package com.hotcodepush.capacitor

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import com.getcapacitor.Bridge
import com.getcapacitor.plugin.WebView
import com.hotcodepush.core.BundleLoader
import com.hotcodepush.core.BundleManifest
import com.hotcodepush.core.EmbeddedBundle
import com.hotcodepush.core.PlainException
import com.hotcodepush.core.ServedBundle
import com.hotcodepush.core.WebViewGate
import java.io.File

/**
 * Capacitor loads the WebView from the directory it persisted under `serverBasePath` in its
 * `CapWebViewSettings` preferences when that directory exists; a bundle is laid out there by path.
 * The bridge's local server exists only once the WebView has loaded, so a switch waits for it.
 */
class CapacitorBundleLoader(private val context: Context, private val bridge: () -> Bridge?) : BundleLoader {
    private val projectionsDirectory = File(File(context.filesDir, "hotcodepush"), "www")
    private val gate = WebViewGate()

    override fun projectionDirectory(bundleId: String): File = File(projectionsDirectory, bundleId)

    override fun deleteProjection(bundleId: String) {
        projectionDirectory(bundleId).deleteRecursively()
    }

    override fun persistServedBundle(bundleId: String?) {
        preferences().edit().putString(WebView.CAP_SERVER_PATH, bundleId?.let { projectionDirectory(it).path } ?: "").apply()
    }

    override fun loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId)
        gate.runWhenLoaded {
            val bridge = bridge() ?: return@runWhenLoaded
            bridge.activity.runOnUiThread {
                if (bundleId == null) bridge.setServerAssetPath(EMBEDDED_ASSET_PATH) else bridge.setServerBasePath(projectionDirectory(bundleId).path)
            }
        }
    }

    /** The persisted path is what the framework loads at start; the bridge itself is not asked, since it may not exist yet. */
    override fun servedBundleId(): String? = ServedBundle.resolveBundleId(preferences().getString(WebView.CAP_SERVER_PATH, null), projectionsDirectory)

    override fun isConnectionMetered(): Boolean =
        (context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager)?.isActiveNetworkMetered ?: false

    fun handleWebViewLoaded() = gate.markLoaded()

    private fun preferences() = context.getSharedPreferences(WebView.WEBVIEW_PREFS_NAME, Activity.MODE_PRIVATE)

    companion object {
        const val EMBEDDED_ASSET_PATH = "public"
    }
}

/** The files compiled into the binary, `assets/public/` in the APK, addressed by the embedded manifest's hashes. */
class AssetsEmbeddedBundle(private val context: Context, manifest: BundleManifest) : EmbeddedBundle {
    private val pathsBySha256 = manifest.files.associate { it.sha256 to it.path }

    override fun has(sha256: String): Boolean {
        val path = pathsBySha256[sha256] ?: return false
        return runCatching { context.assets.open("${CapacitorBundleLoader.EMBEDDED_ASSET_PATH}/$path").close(); true }.getOrDefault(false)
    }

    override fun copyFile(sha256: String, destination: File) {
        val path = pathsBySha256[sha256] ?: throw PlainException("No embedded file with hash $sha256")
        context.assets.open("${CapacitorBundleLoader.EMBEDDED_ASSET_PATH}/$path").use { input -> destination.outputStream().use { input.copyTo(it) } }
    }
}
