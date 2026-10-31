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
import com.hotcodepush.core.PlainException
import com.hotcodepush.core.Release
import com.hotcodepush.core.RollbackReason
import com.hotcodepush.core.UpdateRolledBackEvent
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyString
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockConstruction
import org.mockito.Mockito.never
import org.mockito.Mockito.timeout
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoMoreInteractions
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HotCodePushPluginTest {
    private val context = contextWithResourceFile()
    private val appPage: android.webkit.WebView = mock(android.webkit.WebView::class.java).also { `when`(it.url).thenReturn("$LOCAL_URL/") }
    private val bridge: Bridge = mock(Bridge::class.java).also {
        `when`(it.context).thenReturn(context)
        `when`(it.localUrl).thenReturn(LOCAL_URL)
    }
    private val plugin = HotCodePushPlugin().also { it.bridge = bridge }

    @Test
    fun shouldRejectTheDownloadWhenItsApplyStrategyIsNotOneOfItsChoices() {
        mockConstruction(Core::class.java).use {
            loadPlugin()
            val call = mock(PluginCall::class.java)
            `when`(call.getString("applyStrategy")).thenReturn("later")

            plugin.downloadUpdate(call)

            verify(call, timeout(CALL_TIMEOUT_MILLIS)).reject(eq("applyStrategy is not one of its choices: later"), any(PlainException::class.java))
        }
    }

    @Test
    fun shouldResolveWithNoDataWhenTheMethodReturnsNothing() {
        mockConstruction(Core::class.java).use {
            loadPlugin()
            val call = mock(PluginCall::class.java)

            plugin.clearUpdates(call)

            verify(call, timeout(CALL_TIMEOUT_MILLIS)).resolve()
            verify(call, never()).resolve(any(JSObject::class.java))
        }
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

    private fun loadPlugin(): WebViewListener {
        plugin.load()
        // The start's events and the page listener are posted to the main thread.
        shadowOf(Looper.getMainLooper()).idle()
        val pageStartListener = ArgumentCaptor.forClass(WebViewListener::class.java)
        verify(bridge).addWebViewListener(pageStartListener.capture())
        return pageStartListener.value
    }

    // The bridge drops the plugin listeners before it tells the WebView listeners.
    private fun beginPage(pageStartListener: WebViewListener) {
        plugin.removeAllListeners()
        pageStartListener.onPageStarted(appPage)
    }

    private fun listen(eventName: String): PluginCall {
        val call = mock(PluginCall::class.java)
        `when`(call.getString("eventName")).thenReturn(eventName)
        plugin.addListener(call)
        return call
    }

    private fun persistDownloadedBundle(bundleId: String) {
        val loader = CapacitorBundleLoader(context, bridge) {}
        loader.projectionDirectory(bundleId).mkdirs()
        loader.persistServedBundle(bundleId)
    }

    private fun contextWithResourceFile(): Context {
        val resourceAssets = mock(AssetManager::class.java)
        `when`(resourceAssets.open("hotcodepush.json")).thenAnswer { RESOURCE_FILE.byteInputStream() }
        return object : ContextWrapper(RuntimeEnvironment.getApplication()) {
            override fun getAssets(): AssetManager = resourceAssets
        }
    }

    companion object {
        const val LOCAL_URL = "https://localhost"
        const val RESOURCE_FILE =
            """{"appId":"0b6d5c1e-2f3a-4b5c-8d9e-0f1a2b3c4d5e","channelId":null,"checkIntervalSeconds":60,"builtAt":"2026-10-08T00:00:00.000Z","fingerprint":null,"embeddedBundleManifest":null}"""

        // Calls run in a coroutine on the IO dispatcher.
        const val CALL_TIMEOUT_MILLIS = 5_000L

        val ROLLBACK = UpdateRolledBackEvent(Release("r2", 2, "b2", "1.0.1", false), Release("r1", 1, "b1", "1.0.0", false), RollbackReason.APP_CRASHED)
    }
}
