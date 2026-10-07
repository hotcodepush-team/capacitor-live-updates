package com.hotcodepush.capacitor

import android.content.Context
import android.os.Looper
import com.getcapacitor.Bridge
import com.getcapacitor.plugin.WebView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File

/** The loader over Capacitor's preferences and a bridge that records its calls: what the first load serves and when a switch reloads. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CapacitorBundleLoaderTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val bridge: Bridge = mock(Bridge::class.java)
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
        assertEquals(1, pageLoads)
        verifyNoInteractions(bridge)
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

        verifyNoInteractions(bridge)
        assertEquals(1, pageLoads)
    }

    private fun projectionsDirectory() = File(File(context.filesDir, "hotcodepush"), "www")

    private fun layOutBundle(bundleId: String) = File(projectionsDirectory(), bundleId).apply { mkdirs() }

    private fun preferences() = context.getSharedPreferences(WebView.WEBVIEW_PREFS_NAME, Context.MODE_PRIVATE)

    private fun persist(path: String) = preferences().edit().putString(WebView.CAP_SERVER_PATH, path).commit()

    private fun persisted() = preferences().getString(WebView.CAP_SERVER_PATH, null)
}
