package com.hotcodepush.capacitor

import android.content.Context
import android.content.ContextWrapper
import android.content.res.AssetManager
import android.os.Looper
import com.getcapacitor.Bridge
import com.getcapacitor.JSObject
import com.getcapacitor.PluginCall
import com.getcapacitor.WebViewListener
import com.hotcodepush.core.Core
import com.hotcodepush.core.Release
import com.hotcodepush.core.RollbackReason
import com.hotcodepush.core.UpdateRolledBackEvent
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockConstruction
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoMoreInteractions
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The resource file as the plugin reads it from the app's assets, missing, refused by the core's reader or read, a call's options,
 * and the pages the WebView begins at the start, over a bridge and a core that record their calls.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HotCodePushPluginTest {
    private val context = contextWithResourceFile(resourceFile(checkIntervalSeconds = 60))
    private val appPage: android.webkit.WebView = mock(android.webkit.WebView::class.java).also { `when`(it.url).thenReturn("$LOCAL_URL/") }
    private val bridge: Bridge = mock(Bridge::class.java).also {
        `when`(it.context).thenReturn(context)
        `when`(it.localUrl).thenReturn(LOCAL_URL)
    }
    private val plugin = HotCodePushPlugin().also { it.bridge = bridge }

    @Test
    fun shouldReadNoConfigurationWhenTheAssetsLackTheResourceFile() {
        assertNull(HotCodePushPlugin.readConfiguration(RuntimeEnvironment.getApplication()))
    }

    @Test
    fun shouldThrowTheReadersErrorWhenTheCoreRefusesTheResourceFile() {
        val context = contextWithResourceFile(resourceFile(checkIntervalSeconds = 30))

        val exception = assertThrows(JSONException::class.java) { HotCodePushPlugin.readConfiguration(context) }

        assertEquals("checkIntervalSeconds is below its floor of 60.0 seconds: 30.0", exception.message)
    }

    @Test
    fun shouldReadTheConfigurationWhenTheResourceFileIsValid() {
        assertEquals(60.0, HotCodePushPlugin.readConfiguration(context)?.checkIntervalSeconds)
    }

    @Test
    fun shouldRejectTheDownloadWhenItsApplyStrategyIsNotOneOfItsChoices() {
        val call = mock(PluginCall::class.java)
        `when`(call.getString("applyStrategy")).thenReturn("later")

        HotCodePushPlugin().downloadUpdate(call)

        verify(call).reject("applyStrategy is not one of its choices: later")
    }

    @Test
    fun shouldApplyNothingWhenASecondPageStartsDuringTheStart() {
        persistDownloadedBundle("b1")
        mockConstruction(Core::class.java).use { cores ->
            val pageStartListener = loadPlugin()

            beginPage(pageStartListener)
            persistDownloadedBundle("b2")
            beginPage(pageStartListener)
            shadowOf(Looper.getMainLooper()).idle()

            verify(bridge, never()).setServerBasePath(anyString())
            verify(bridge, never()).setServerAssetPath(anyString())
            val core = cores.constructed().single()
            verify(core).handleAppStartBlocking(false)
            verifyNoMoreInteractions(core)
        }
    }

    @Test
    fun shouldDeliverTheRollbackOnceToThePageOfTheSecondLoadWhenTheFirstPageNeverListened() {
        persistDownloadedBundle("b1")
        mockConstruction(Core::class.java) { core, _ ->
            `when`(core.handleAppStartBlocking(false)).thenAnswer {
                plugin.updateRolledBack(ROLLBACK)
                null
            }
        }.use {
            val pageStartListener = loadPlugin()

            beginPage(pageStartListener)
            beginPage(pageStartListener)
            val listener = listen("updateRolledBack")

            val delivered = ArgumentCaptor.forClass(JSObject::class.java)
            verify(listener).resolve(delivered.capture())
            assertEquals(ROLLBACK.toJson().toString(), delivered.value.toString())
        }
    }

    /** The plugin's load as the bridge runs it, then the main thread's turn, where the start's events and the page listener go. */
    private fun loadPlugin(): WebViewListener {
        plugin.load()
        shadowOf(Looper.getMainLooper()).idle()
        val pageStartListener = ArgumentCaptor.forClass(WebViewListener::class.java)
        verify(bridge).addWebViewListener(pageStartListener.capture())
        return pageStartListener.value
    }

    /** A page of the app begins as the bridge reports it: the plugins' listeners dropped, then the WebView's listeners told. */
    private fun beginPage(pageStartListener: WebViewListener) {
        plugin.removeAllListeners()
        pageStartListener.onPageStarted(appPage)
    }

    /** The page's JavaScript listening for an event, as `addListener()` arrives from the bridge. */
    private fun listen(eventName: String): PluginCall {
        val call = mock(PluginCall::class.java)
        `when`(call.getString("eventName")).thenReturn(eventName)
        plugin.addListener(call)
        return call
    }

    /** A downloaded bundle laid out and persisted for Capacitor's next load, as the core does through the loader. */
    private fun persistDownloadedBundle(bundleId: String) {
        val loader = CapacitorBundleLoader(context, bridge) {}
        loader.projectionDirectory(bundleId).mkdirs()
        loader.persistServedBundle(bundleId)
    }

    private fun contextWithResourceFile(text: String): Context {
        val resourceAssets = mock(AssetManager::class.java)
        `when`(resourceAssets.open("hotcodepush.json")).thenAnswer { text.byteInputStream() }
        return object : ContextWrapper(RuntimeEnvironment.getApplication()) {
            override fun getAssets(): AssetManager = resourceAssets
        }
    }

    private fun resourceFile(checkIntervalSeconds: Int) =
        """{"appId":"0b6d5c1e-2f3a-4b5c-8d9e-0f1a2b3c4d5e","channelId":null,"checkIntervalSeconds":$checkIntervalSeconds,"builtAt":"2026-10-08T00:00:00.000Z","fingerprint":null,"embeddedBundleManifest":null}"""

    companion object {
        const val LOCAL_URL = "https://localhost"
        val ROLLBACK = UpdateRolledBackEvent(Release("r2", 2, "b2", "1.0.1", false), Release("r1", 1, "b1", "1.0.0", false), RollbackReason.APP_CRASHED)
    }
}
