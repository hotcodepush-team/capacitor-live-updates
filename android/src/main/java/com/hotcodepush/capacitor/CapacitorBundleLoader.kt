package com.hotcodepush.capacitor

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.getcapacitor.Bridge
import com.getcapacitor.plugin.WebView
import com.hotcodepush.core.BundleLoader
import com.hotcodepush.core.FileStore
import com.hotcodepush.core.NetworkMonitor
import com.hotcodepush.core.ServedBundle
import java.io.File

/**
 * Capacitor serves the WebView from the directory it persisted under `serverBasePath` in its `CapWebViewSettings` preferences,
 * read when the bridge loads the WebView right after the plugins load; a bundle is laid out there by path. Until the start has
 * decided, a switch only changes what that first load serves; from then on it reloads the WebView.
 *
 * `willLoadPage` runs on the main thread before every load the SDK starts, the first one included.
 */
class CapacitorBundleLoader(private val context: Context, private val bridge: Bridge, private val willLoadPage: () -> Unit) : BundleLoader {
    private val projectionsDirectory = File(FileStore.defaultRootDirectory(context), "www")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val networkMonitor = NetworkMonitor(context)

    /** The bundle the WebView serves, or serves at its first load while the start decides; `null` is the embedded bundle. */
    private var servedBundle: String? = resolvePersistedBundleId()

    /** The WebView loads: a switch reloads it from here on. */
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

    override fun isConnectionMetered(): Boolean = networkMonitor.isConnectionMetered()

    /** The start has decided: the bridge's first load reads its bundle from the preferences, and a switch reloads the WebView from here on. Main thread, in `load()`. */
    fun beginServing() {
        val bundleId = synchronized(this) {
            isServing = true
            servedBundle
        }
        persistServedBundle(bundleId)
        willLoadPage()
    }

    /** The activity is gone: a reload still waiting for the main thread has no WebView to go to. */
    fun close() = mainHandler.removeCallbacksAndMessages(null)

    private fun reloadWebView(bundleId: String?) {
        willLoadPage()
        if (bundleId == null) bridge.setServerAssetPath(EMBEDDED_ASSET_PATH) else bridge.setServerBasePath(projectionDirectory(bundleId).path)
    }

    /** A persisted tree that is no longer on disk is the embedded bundle, which is what Capacitor loads for it too. */
    private fun resolvePersistedBundleId(): String? = ServedBundle.resolveBundleId(preferences().getString(WebView.CAP_SERVER_PATH, null), projectionsDirectory)

    private fun preferences() = context.getSharedPreferences(WebView.WEBVIEW_PREFS_NAME, Activity.MODE_PRIVATE)

    companion object {
        const val EMBEDDED_ASSET_PATH = "public"
    }
}
