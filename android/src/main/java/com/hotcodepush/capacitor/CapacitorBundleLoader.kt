package com.hotcodepush.capacitor

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.getcapacitor.Bridge
import com.getcapacitor.plugin.WebView
import com.hotcodepush.core.BundleLoader
import com.hotcodepush.core.FileStore
import com.hotcodepush.core.ServedBundle
import java.io.File

// Capacitor serves the WebView from the directory persisted under `serverBasePath` in its `CapWebViewSettings` preferences, read when the bridge loads the WebView right after the plugins load.
// `willLoadPage` runs on the main thread before every load the SDK starts, including the first one.
class CapacitorBundleLoader(private val context: Context, private val bridge: Bridge, private val willLoadPage: () -> Unit) : BundleLoader {
    private val projectionsDirectory = File(FileStore.defaultRootDirectory(context), "www")
    private val mainHandler = Handler(Looper.getMainLooper())

    // Until the first load, this is the bundle that load will serve. `null` means the embedded bundle.
    private var servedBundle: String? = resolvePersistedBundleId()

    // Until the start has decided, a switch only changes what the first load serves. After that, a switch reloads the WebView.
    private var isServing = false

    override fun projectionDirectory(bundleId: String): File = File(projectionsDirectory, bundleId)

    override fun deleteProjection(bundleId: String) {
        projectionDirectory(bundleId).deleteRecursively()
    }

    override fun persistServedBundle(bundleId: String?) {
        preferences().edit().putString(WebView.CAP_SERVER_PATH, bundleId?.let { projectionDirectory(it).path } ?: "").apply()
    }

    override fun loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId)
        val isReload = synchronized(this) {
            servedBundle = bundleId
            isServing
        }
        if (isReload) mainHandler.post { reloadWebView(bundleId) }
    }

    override fun servedBundleId(): String? = synchronized(this) { servedBundle }

    // Runs on the main thread in `load()`, once the start has decided. The first load of the bridge reads the bundle from the preferences.
    fun beginServing() {
        val bundleId = synchronized(this) {
            isServing = true
            servedBundle
        }
        persistServedBundle(bundleId)
        willLoadPage()
    }

    // Once the activity is gone, a reload still waiting for the main thread has no WebView to go to.
    fun close() = mainHandler.removeCallbacksAndMessages(null)

    private fun reloadWebView(bundleId: String?) {
        willLoadPage()
        if (bundleId == null) bridge.setServerAssetPath(EMBEDDED_ASSET_PATH) else bridge.setServerBasePath(projectionDirectory(bundleId).path)
    }

    // For a persisted tree that is no longer on disk, Capacitor loads the embedded bundle too.
    private fun resolvePersistedBundleId(): String? = ServedBundle.resolveBundleId(preferences().getString(WebView.CAP_SERVER_PATH, null), projectionsDirectory)

    private fun preferences() = context.getSharedPreferences(WebView.WEBVIEW_PREFS_NAME, Activity.MODE_PRIVATE)

    companion object {
        const val EMBEDDED_ASSET_PATH = "public"
    }
}
