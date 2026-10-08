package com.hotcodepush.capacitor

import android.content.Context
import android.content.res.AssetManager
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** The resource file as the plugin reads it from the app's assets: missing, refused by the core's reader, or read. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HotCodePushPluginTest {
    @Test
    fun shouldReadNoConfigurationWhenTheAssetsLackTheResourceFile() {
        assertNull(HotCodePushPlugin.readConfiguration(RuntimeEnvironment.getApplication()))
    }

    @Test
    fun shouldThrowTheReadersErrorWhenTheCoreRefusesTheResourceFile() {
        val context = contextWithResourceFile(resourceFile(checkInterval = 30))

        val exception = assertThrows(JSONException::class.java) { HotCodePushPlugin.readConfiguration(context) }

        assertEquals("checkInterval is below its floor of 60.0 seconds: 30.0", exception.message)
    }

    @Test
    fun shouldReadTheConfigurationWhenTheResourceFileIsValid() {
        val context = contextWithResourceFile(resourceFile(checkInterval = 60))

        assertEquals(60.0, HotCodePushPlugin.readConfiguration(context)?.checkInterval)
    }

    private fun contextWithResourceFile(text: String): Context {
        val assets = mock(AssetManager::class.java)
        `when`(assets.open("hotcodepush.json")).thenReturn(text.byteInputStream())
        val context = mock(Context::class.java)
        `when`(context.assets).thenReturn(assets)
        return context
    }

    private fun resourceFile(checkInterval: Int) =
        """{"appId":"0b6d5c1e-2f3a-4b5c-8d9e-0f1a2b3c4d5e","channelId":null,"checkInterval":$checkInterval,"builtAt":"2026-10-08T00:00:00.000Z","fingerprint":null,"embeddedBundleManifest":null}"""
}
