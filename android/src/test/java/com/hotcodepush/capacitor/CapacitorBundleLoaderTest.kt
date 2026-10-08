package com.hotcodepush.capacitor

import android.content.Context
import android.os.Looper
import com.getcapacitor.Bridge
import com.getcapacitor.plugin.WebView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File

/**
 * The loader over Capacitor's preferences and a bridge that records its calls: what the first load serves, when a switch reloads
 * and which loads' pages the SDK prepares. The WebView keeps its posts in order until the test runs them, as a WebView not yet
 * attached does.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CapacitorBundleLoaderTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val webViewPosts = mutableListOf<Runnable>()
    private val webView: android.webkit.WebView = mock(android.webkit.WebView::class.java).also { webView ->
        doAnswer { webViewPosts.add(it.getArgument(0)) }.`when`(webView).post(any())
    }
    private val bridge: Bridge = mock(Bridge::class.java).also { `when`(it.webView).thenReturn(webView) }
    private var pageLoads = 0
    private val loader by lazy { CapacitorBundleLoader(context, bridge) { pageLoads++ } }

    @Test
    fun shouldServeThePersistedBundleAtTheStartWhenItsTreeIsOnDisk() {
        persist(layOutBundle("b1").path)

        assertEquals("b1", loader.servedBundleId())
    }

    @Test
    fun shouldServeTheEmbeddedBundleAtTheStartWhenThePersistedTreeIsGone() {
        persist(File(projectionsDirectory(), "b1").path)

        assertNull(loader.servedBundleId())
    }

    @Test
    fun shouldServeTheBundleTheStartSwitchedToFromTheFirstLoadWithoutReloading() {
        persist(layOutBundle("b1").path)
        val switched = layOutBundle("b2")

        loader.loadServedBundle("b2")
        loader.beginServing()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(switched.path, persisted())
        assertEquals("b2", loader.servedBundleId())
        verifyNoReload()
    }

    @Test
    fun shouldPrepareThePageOfTheLoadCapacitorPostsWhenTheStartServesADownloadedBundle() {
        persist(layOutBundle("b1").path)
        val loads = mutableListOf<String>()
        val loader = CapacitorBundleLoader(context, bridge) { loads += "willLoadPage" }

        loader.beginServing()
        webView.post { loads += "posted load" } // the bridge's setServerBasePath() as it loads the WebView
        shadowOf(Looper.getMainLooper()).idle()
        runWebViewPosts()

        assertEquals(listOf("willLoadPage", "posted load", "willLoadPage"), loads)
    }

    @Test
    fun shouldPrepareOnlyTheFirstLoadWhenTheStartServesTheEmbeddedBundle() {
        loader.beginServing()
        shadowOf(Looper.getMainLooper()).idle()
        runWebViewPosts()

        assertEquals(1, pageLoads)
    }

    @Test
    fun shouldHoldThePageOfTheLoadCapacitorPostsWhenThePageOfTheFirstLoadBeganBeforeIt() {
        persist(layOutBundle("b1").path)
        val pageEvents = PageEvents { _, _, _ -> }
        val loader = CapacitorBundleLoader(context, bridge) { pageEvents.holdUntilNextPage() }

        loader.beginServing()
        webView.post {} // the bridge's setServerBasePath() as it loads the WebView
        shadowOf(Looper.getMainLooper()).idle()
        pageEvents.releaseToPage()
        runWebViewPosts()

        assertTrue(pageEvents.isPageLoadPending)
    }

    @Test
    fun shouldReloadTheWebViewWhenTheBundleSwitchesAfterTheStart() {
        val switched = layOutBundle("b2")
        loader.beginServing()

        loader.loadServedBundle("b2")
        shadowOf(Looper.getMainLooper()).idle()

        verify(bridge).setServerBasePath(switched.path)
        assertEquals(2, pageLoads)
    }

    @Test
    fun shouldReloadIntoTheEmbeddedBundleWhenTheSwitchAfterTheStartIsToIt() {
        persist(layOutBundle("b1").path)
        loader.beginServing()

        loader.loadServedBundle(null)
        shadowOf(Looper.getMainLooper()).idle()

        verify(bridge).setServerAssetPath(CapacitorBundleLoader.EMBEDDED_ASSET_PATH)
        assertEquals("", persisted())
    }

    @Test
    fun shouldReloadIntoThePersistedBundleWhenTheAppReloadsOnItsOwn() {
        persist(layOutBundle("b1").path)
        loader.beginServing()
        val held = layOutBundle("b2")
        loader.persistServedBundle("b2")

        loader.reloadPersistedBundle()
        shadowOf(Looper.getMainLooper()).idle()

        verify(bridge).setServerBasePath(held.path)
        assertEquals("b2", loader.servedBundleId())
    }

    @Test
    fun shouldKeepTheServedBundleWhenTheAppReloadsOnItsOwnAndItIsThePersistedOne() {
        persist(layOutBundle("b1").path)
        loader.beginServing()

        loader.reloadPersistedBundle()
        shadowOf(Looper.getMainLooper()).idle()

        verifyNoReload()
    }

    /** The posts reach the main thread in order once the WebView is attached, and a post they run joins the end. */
    private fun runWebViewPosts() {
        while (webViewPosts.isNotEmpty()) webViewPosts.removeAt(0).run()
    }

    private fun verifyNoReload() {
        verify(bridge, never()).setServerBasePath(anyString())
        verify(bridge, never()).setServerAssetPath(anyString())
    }

    private fun projectionsDirectory() = File(File(context.filesDir, "hotcodepush"), "www")

    private fun layOutBundle(bundleId: String) = File(projectionsDirectory(), bundleId).apply { mkdirs() }

    private fun preferences() = context.getSharedPreferences(WebView.WEBVIEW_PREFS_NAME, Context.MODE_PRIVATE)

    private fun persist(path: String) = preferences().edit().putString(WebView.CAP_SERVER_PATH, path).commit()

    private fun persisted() = preferences().getString(WebView.CAP_SERVER_PATH, null)
}
