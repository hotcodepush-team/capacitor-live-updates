package com.hotcodepush.capacitor

import android.content.Context
import android.content.res.AssetManager
import com.getcapacitor.PluginCall
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** The resource file as the plugin reads it from the app's assets, missing, refused by the core's reader or read, and a call's options. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HotCodePushPluginTest {
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
        val context = contextWithResourceFile(resourceFile(checkIntervalSeconds = 60))

        assertEquals(60.0, HotCodePushPlugin.readConfiguration(context)?.checkIntervalSeconds)
    }

    @Test
    fun shouldRejectTheDownloadWhenItsApplyStrategyIsNotOneOfItsChoices() {
        val call = mock(PluginCall::class.java)
        `when`(call.getString("applyStrategy")).thenReturn("later")

        HotCodePushPlugin().downloadUpdate(call)

        verify(call).reject("applyStrategy is not one of its choices: later")
    }

    private fun contextWithResourceFile(text: String): Context {
        val assets = mock(AssetManager::class.java)
        `when`(assets.open("hotcodepush.json")).thenReturn(text.byteInputStream())
        val context = mock(Context::class.java)
        `when`(context.assets).thenReturn(assets)
        return context
    }

    private fun resourceFile(checkIntervalSeconds: Int) =
        """{"appId":"0b6d5c1e-2f3a-4b5c-8d9e-0f1a2b3c4d5e","channelId":null,"checkIntervalSeconds":$checkIntervalSeconds,"builtAt":"2026-10-08T00:00:00.000Z","fingerprint":null,"embeddedBundleManifest":null}"""
}
