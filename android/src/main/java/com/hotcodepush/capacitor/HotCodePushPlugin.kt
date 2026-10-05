package com.hotcodepush.capacitor

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.WebViewListener
import com.getcapacitor.annotation.CapacitorPlugin
import com.hotcodepush.protocol.ChannelChoice
import com.hotcodepush.protocol.Clock
import com.hotcodepush.protocol.Configuration
import com.hotcodepush.protocol.Core
import com.hotcodepush.protocol.CoreListener
import com.hotcodepush.protocol.DebugScreen
import com.hotcodepush.protocol.DeviceFacts
import com.hotcodepush.protocol.DownloadStrategy
import com.hotcodepush.protocol.FileStore
import com.hotcodepush.protocol.InstallStrategy
import com.hotcodepush.protocol.KeyValueStore
import com.hotcodepush.protocol.MandatoryInstallStrategy
import com.hotcodepush.protocol.OkHttpClientAdapter
import com.hotcodepush.protocol.PlainException
import com.hotcodepush.protocol.RolledBackEvent
import com.hotcodepush.protocol.ScheduledTask
import com.hotcodepush.protocol.Scheduler
import com.hotcodepush.protocol.SyncOptions
import com.hotcodepush.protocol.SyncTrigger
import com.hotcodepush.protocol.UpdateAvailableEvent
import com.hotcodepush.protocol.UpdateDownloadedEvent
import com.hotcodepush.protocol.UpdateFailedEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File

@CapacitorPlugin(name = "HotCodePush")
class HotCodePushPlugin : Plugin(), CoreListener {
    private var core: Core? = null
    private var loader: CapacitorBundleLoader? = null
    private var isWebViewListenerRegistered = false
    private val scheduler = HandlerScheduler()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun load() {
        val configuration = readConfiguration(context)
        if (configuration == null) {
            Logger.error(TAG, NOT_CONFIGURED_MESSAGE, null)
            return
        }
        val loader = CapacitorBundleLoader(context) { bridge }
        val core = Core(
            configuration = configuration,
            device = deviceFacts(context),
            store = SharedPreferencesStore(context.getSharedPreferences(defaultPreferencesName(context), Context.MODE_PRIVATE)),
            files = FileStore(File(context.filesDir, "hotcodepush")),
            embedded = AssetsEmbeddedBundle(context, configuration.embeddedBundleManifest),
            http = OkHttpClientAdapter(),
            loader = loader,
            listener = this,
            scheduler = scheduler,
            clock = Clock { System.currentTimeMillis() },
            scope = scope,
            temporaryDirectory = File(context.cacheDir, "hotcodepush"),
        )
        this.core = core
        this.loader = loader
        scope.launch { core.handleAppStart() }
    }

    override fun handleOnPause() {
        super.handleOnPause()
        val core = core ?: return
        scope.launch { core.handleAppPause() }
    }

    override fun handleOnResume() {
        super.handleOnResume()
        registerWebViewListener()
        val core = core ?: return
        scope.launch { core.handleAppResume() }
    }

    /** The activity took its bridge with it: nothing of this instance may fire again, or two cores would race on one store. */
    override fun handleOnDestroy() {
        super.handleOnDestroy()
        scope.cancel()
        scheduler.cancelAll()
        loader?.close()
        core = null
        loader = null
    }

    /** The bridge accepts a WebView listener only once the activity resumed, never in `load()`. */
    private fun registerWebViewListener() {
        if (isWebViewListenerRegistered) return
        isWebViewListenerRegistered = true
        bridge.addWebViewListener(object : WebViewListener() {
            override fun onPageLoaded(webView: android.webkit.WebView) {
                loader?.handleWebViewLoaded()
            }
        })
    }

    @PluginMethod
    fun applyUpdate(call: PluginCall) = run(call) { it.applyUpdate().toJson() }

    @PluginMethod
    fun checkForUpdate(call: PluginCall) = run(call) { it.checkForUpdate().toJson() }

    @PluginMethod
    fun clearUpdates(call: PluginCall) = runVoid(call) { it.clearUpdates() }

    @PluginMethod
    fun downloadUpdate(call: PluginCall) = run(call) { it.downloadUpdate().toJson() }

    @PluginMethod
    fun getChannel(call: PluginCall) = run(call) { it.channel().toJson() }

    @PluginMethod
    fun getDevice(call: PluginCall) = run(call) { it.deviceResult().toJson() }

    @PluginMethod
    fun getState(call: PluginCall) = run(call) { it.getState().toJson() }

    @PluginMethod
    fun notifyReady(call: PluginCall) = run(call) { it.notifyReady().toJson() }

    @PluginMethod
    fun notifyRendered(call: PluginCall) = runVoid(call) { it.handleRendered() }

    @PluginMethod
    fun rollbackUpdate(call: PluginCall) {
        val reason = call.getString("reason")
        runVoid(call) { it.rollbackUpdate(reason) }
    }

    @PluginMethod
    fun setAttributes(call: PluginCall) {
        val changes = mutableMapOf<String, String?>()
        val data = call.data
        for (key in data.keys()) {
            when {
                data.isNull(key) -> changes[key] = null
                data.get(key) is String -> changes[key] = data.getString(key)
                else -> {
                    call.reject("An attribute value is a string or null: $key")
                    return
                }
            }
        }
        runVoid(call) { it.setAttributes(changes) }
    }

    @PluginMethod
    fun setChannel(call: PluginCall) {
        val choice = call.getString("id")?.let { ChannelChoice.Id(it) } ?: call.getString("name")?.let { ChannelChoice.Name(it) }
        runVoid(call) { it.setChannel(choice) }
    }

    @PluginMethod
    fun setRestartAllowed(call: PluginCall) {
        val allowed = call.getBoolean("allowed")
        if (allowed == null) {
            call.reject("allowed must be a boolean")
            return
        }
        runVoid(call) { it.setRestartAllowed(allowed) }
    }

    /** Opens the shared core's debug screen over the app's activity. */
    @PluginMethod
    fun showDebugScreen(call: PluginCall) {
        val core = core
        if (core == null) {
            call.reject(NOT_CONFIGURED_MESSAGE)
            return
        }
        DebugScreen.show(activity, core)
        call.resolve()
    }

    @PluginMethod
    fun sync(call: PluginCall) {
        val options = try {
            syncOptions(call)
        } catch (exception: PlainException) {
            call.reject(exception.message)
            return
        }
        run(call) { it.sync(SyncTrigger.MANUAL, options).toJson() }
    }

    /** Each stage's strategy for this call; a value outside its choices is a programming mistake and rejects the call. */
    private fun syncOptions(call: PluginCall) = SyncOptions(
        downloadStrategy = option("downloadStrategy", call.getString("downloadStrategy"), DownloadStrategy::fromWire),
        installStrategy = option("installStrategy", call.getString("installStrategy"), InstallStrategy::fromWire),
        mandatoryInstallStrategy = option("mandatoryInstallStrategy", call.getString("mandatoryInstallStrategy"), MandatoryInstallStrategy::fromWire),
    )

    private fun <T> option(name: String, raw: String?, parse: (String?) -> T?): T? {
        if (raw == null) return null
        return parse(raw) ?: throw PlainException("$name is not one of its choices: $raw")
    }

    private fun run(call: PluginCall, body: suspend (Core) -> JSONObject) {
        val core = core
        if (core == null) {
            call.reject(NOT_CONFIGURED_MESSAGE)
            return
        }
        scope.launch {
            try {
                call.resolve(JSObject.fromJSONObject(body(core)))
            } catch (exception: Exception) {
                call.reject(exception.message, exception)
            }
        }
    }

    private fun runVoid(call: PluginCall, body: suspend (Core) -> Unit) {
        val core = core
        if (core == null) {
            call.reject(NOT_CONFIGURED_MESSAGE)
            return
        }
        scope.launch {
            try {
                body(core)
                call.resolve()
            } catch (exception: Exception) {
                call.reject(exception.message, exception)
            }
        }
    }

    // The listener

    override fun updateAvailable(event: UpdateAvailableEvent) {
        notifyListeners("updateAvailable", JSObject.fromJSONObject(event.toJson()))
    }

    override fun updateDownloaded(event: UpdateDownloadedEvent) {
        notifyListeners("updateDownloaded", JSObject.fromJSONObject(event.toJson()))
    }

    override fun updateFailed(event: UpdateFailedEvent) {
        notifyListeners("updateFailed", JSObject.fromJSONObject(event.toJson()))
    }

    override fun downloadProgress(releaseId: String, downloadedBytes: Long, totalBytes: Long) {
        val progress = if (totalBytes > 0) downloadedBytes.toDouble() / totalBytes else 0.0
        notifyListeners("downloadProgress", JSObject().put("releaseId", releaseId).put("downloadedBytes", downloadedBytes).put("totalBytes", totalBytes).put("progress", progress))
    }

    /** Retained until the reloaded web layer listens: the event belongs to the start that follows the rollback. */
    override fun rolledBack(event: RolledBackEvent) {
        notifyListeners("rolledBack", JSObject.fromJSONObject(event.toJson()), true)
    }

    companion object {
        const val TAG = "HotCodePush"
        const val SDK_VERSION = "0.0.0"
        const val NOT_CONFIGURED_MESSAGE = "HotCodePush is not configured: hotcodepush.json is missing from the app's assets. Run `npx hotcodepush init` and build the app once."

        /** The default `SharedPreferences`, the file `PreferenceManager.getDefaultSharedPreferences` names, without the dependency. */
        fun defaultPreferencesName(context: Context) = "${context.packageName}_preferences"

        fun readConfiguration(context: Context): Configuration? = try {
            context.assets.open("hotcodepush.json").bufferedReader().use { Configuration.decode(it.readText()) }
        } catch (exception: Exception) {
            null
        }

        fun deviceFacts(context: Context): DeviceFacts {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
            return DeviceFacts(
                platform = "android",
                binaryVersion = info.versionName ?: "",
                binaryBuild = versionCode.toString(),
                osVersion = Build.VERSION.RELEASE ?: "",
                sdkVersion = SDK_VERSION,
                isDebugBuild = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0,
            )
        }
    }
}

class SharedPreferencesStore(private val preferences: SharedPreferences) : KeyValueStore {
    override fun getString(key: String): String? = preferences.getString(key, null)

    override fun putString(key: String, value: String?) {
        preferences.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }

    override fun getInt(key: String): Int? = if (preferences.contains(key)) runCatching { preferences.getInt(key, 0) }.getOrNull() else null

    override fun putInt(key: String, value: Int?) {
        preferences.edit().apply { if (value == null) remove(key) else putInt(key, value) }.apply()
    }
}

class HandlerScheduler : Scheduler {
    private val handler = Handler(Looper.getMainLooper())

    override fun schedule(afterSeconds: Double, block: () -> Unit): ScheduledTask {
        val runnable = Runnable(block)
        handler.postDelayed(runnable, (afterSeconds * 1000).toLong())
        return ScheduledTask { handler.removeCallbacks(runnable) }
    }

    fun cancelAll() = handler.removeCallbacksAndMessages(null)
}
