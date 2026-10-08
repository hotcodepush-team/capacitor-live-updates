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
import com.hotcodepush.core.ApplyStrategy
import com.hotcodepush.core.ChannelChoice
import com.hotcodepush.core.Clock
import com.hotcodepush.core.Configuration
import com.hotcodepush.core.Core
import com.hotcodepush.core.CoreListener
import com.hotcodepush.core.DebugScreen
import com.hotcodepush.core.DeviceFacts
import com.hotcodepush.core.DownloadStrategy
import com.hotcodepush.core.DownloadUpdateOptions
import com.hotcodepush.core.FileStore
import com.hotcodepush.core.KeyValueStore
import com.hotcodepush.core.MandatoryApplyStrategy
import com.hotcodepush.core.OkHttpClientAdapter
import com.hotcodepush.core.PlainException
import com.hotcodepush.core.ScheduledTask
import com.hotcodepush.core.Scheduler
import com.hotcodepush.core.SyncOptions
import com.hotcodepush.core.SyncTrigger
import com.hotcodepush.core.UpdateAvailableEvent
import com.hotcodepush.core.UpdateDownloadedEvent
import com.hotcodepush.core.UpdateFailedEvent
import com.hotcodepush.core.UpdateRolledBackEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

@CapacitorPlugin(name = "HotCodePush")
class HotCodePushPlugin : Plugin(), CoreListener {
    private var core: Core? = null
    private var loader: CapacitorBundleLoader? = null
    private val scheduler = HandlerScheduler()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pageEvents = PageEvents { eventName, data, retainUntilConsumed -> notifyListeners(eventName, data, retainUntilConsumed) }

    /** Why every method rejects while the core is absent: the resource file is missing, or the core's reader refused it. */
    private var notConfiguredMessage = MISSING_CONFIGURATION_MESSAGE

    /** Hears each page the WebView begins in its main frame, after the bridge dropped the listeners of the one before. */
    private val pageStartListener = object : WebViewListener() {
        override fun onPageStarted(webView: android.webkit.WebView) {
            if (webView.url?.startsWith(bridge.localUrl) == true) handlePageStart()
        }
    }

    /**
     * Runs while Capacitor builds its bridge, before the bridge loads the WebView: the start decides the bundle the first load
     * serves, waiting for the core at most its bound, so the WebView never loads a bundle the start replaces.
     */
    override fun load() {
        val configuration = try {
            readConfiguration(context)
        } catch (exception: Exception) {
            notConfiguredMessage = "HotCodePush is not configured: the app's hotcodepush.json was refused: ${exception.message}. Check the project's hotcodepush.json and build the app again."
            null
        }
        if (configuration == null) {
            Logger.error(TAG, notConfiguredMessage, null)
            return
        }
        val loader = CapacitorBundleLoader(context, bridge) { pageEvents.holdUntilNextPage() }
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
        core.handleAppStartBlocking()
        loader.beginServing()
        // The bridge takes its WebView listeners from its builder once it is built, which replaces any added while it builds.
        mainHandler.post { bridge.addWebViewListener(pageStartListener) }
    }

    /**
     * A page of the app began: the events held for it go out, and one the SDK did not load is the app reloading on its own, a
     * `location.reload()` among them, which serves the bundle a start would and goes through the gate as a start does.
     */
    private fun handlePageStart() {
        val isLoadedBySdk = pageEvents.isPageLoadPending
        pageEvents.releaseToPage()
        if (isLoadedBySdk) return
        val core = core ?: return
        loader?.reloadPersistedBundle()
        scope.launch { core.handleAppReload() }
    }

    override fun handleOnPause() {
        super.handleOnPause()
        val core = core ?: return
        scope.launch { core.handleAppPause() }
    }

    override fun handleOnResume() {
        super.handleOnResume()
        val core = core ?: return
        scope.launch { core.handleAppResume() }
    }

    /** The activity took its bridge with it: nothing of this instance may fire again, or two cores would race on one store. */
    override fun handleOnDestroy() {
        super.handleOnDestroy()
        scope.cancel()
        scheduler.cancelAll()
        mainHandler.removeCallbacksAndMessages(null)
        loader?.close()
        core = null
        loader = null
    }

    @PluginMethod
    fun applyUpdate(call: PluginCall) = run(call) { it.applyUpdate().toJson() }

    @PluginMethod
    fun checkForUpdate(call: PluginCall) = run(call) { it.checkForUpdate().toJson() }

    @PluginMethod
    fun clearUpdates(call: PluginCall) = runVoid(call) { it.clearUpdates() }

    @PluginMethod
    fun downloadUpdate(call: PluginCall) {
        val options = try {
            downloadUpdateOptions(call)
        } catch (exception: PlainException) {
            call.reject(exception.message)
            return
        }
        run(call) { it.downloadUpdate(options).toJson() }
    }

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
            call.reject(notConfiguredMessage)
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
        applyStrategy = option("applyStrategy", call.getString("applyStrategy"), ApplyStrategy::fromWire),
        downloadStrategy = option("downloadStrategy", call.getString("downloadStrategy"), DownloadStrategy::fromWire),
        mandatoryApplyStrategy = option("mandatoryApplyStrategy", call.getString("mandatoryApplyStrategy"), MandatoryApplyStrategy::fromWire),
    )

    /** The apply strategies for this call, the download pinned to `auto`; a value outside its choices rejects the call. */
    private fun downloadUpdateOptions(call: PluginCall) = DownloadUpdateOptions(
        applyStrategy = option("applyStrategy", call.getString("applyStrategy"), ApplyStrategy::fromWire),
        mandatoryApplyStrategy = option("mandatoryApplyStrategy", call.getString("mandatoryApplyStrategy"), MandatoryApplyStrategy::fromWire),
    )

    private fun <T> option(name: String, raw: String?, parse: (String?) -> T?): T? {
        if (raw == null) return null
        return parse(raw) ?: throw PlainException("$name is not one of its choices: $raw")
    }

    private fun run(call: PluginCall, body: suspend (Core) -> JSONObject) {
        val core = core
        if (core == null) {
            call.reject(notConfiguredMessage)
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
            call.reject(notConfiguredMessage)
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

    override fun updateAvailable(event: UpdateAvailableEvent) = deliver("updateAvailable", JSObject.fromJSONObject(event.toJson()))

    override fun updateDownloaded(event: UpdateDownloadedEvent) = deliver("updateDownloaded", JSObject.fromJSONObject(event.toJson()))

    override fun updateFailed(event: UpdateFailedEvent) = deliver("updateFailed", JSObject.fromJSONObject(event.toJson()))

    override fun downloadProgress(releaseId: String, downloadedBytes: Long, totalBytes: Long) {
        val progress = if (totalBytes > 0) downloadedBytes.toDouble() / totalBytes else 0.0
        deliver("downloadProgress", JSObject().put("releaseId", releaseId).put("downloadedBytes", downloadedBytes).put("totalBytes", totalBytes).put("progress", progress))
    }

    /** Retained until the page listens: the event belongs to the page the rollback reloads into. */
    override fun updateRolledBack(event: UpdateRolledBackEvent) = deliver("updateRolledBack", JSObject.fromJSONObject(event.toJson()), retainUntilConsumed = true)

    /** On the main thread, in order behind the reload the loader starts there, so an event that follows a reload waits for its page. */
    private fun deliver(eventName: String, data: JSObject, retainUntilConsumed: Boolean = false) {
        mainHandler.post { pageEvents.deliver(eventName, data, retainUntilConsumed) }
    }

    companion object {
        const val TAG = "HotCodePush"
        const val SDK_VERSION = "0.0.0"
        const val MISSING_CONFIGURATION_MESSAGE = "HotCodePush is not configured: hotcodepush.json is missing from the app's assets. Run `npx hotcodepush init` and build the app once."

        /** The default `SharedPreferences`, the file `PreferenceManager.getDefaultSharedPreferences` names, without the dependency. */
        fun defaultPreferencesName(context: Context) = "${context.packageName}_preferences"

        /** The resource file the core reads, null when the app's assets lack it; a file the core's reader refuses throws its error. */
        fun readConfiguration(context: Context): Configuration? {
            val text = try {
                context.assets.open("hotcodepush.json").bufferedReader().use { it.readText() }
            } catch (exception: FileNotFoundException) {
                return null
            }
            return Configuration.decode(text)
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
