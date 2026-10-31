package com.hotcodepush.capacitor

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
import com.hotcodepush.core.AssetsEmbeddedBundle
import com.hotcodepush.core.ChannelChoice
import com.hotcodepush.core.Configuration
import com.hotcodepush.core.Core
import com.hotcodepush.core.CoreListener
import com.hotcodepush.core.DebugScreen
import com.hotcodepush.core.DeviceFacts
import com.hotcodepush.core.DownloadProgressEvent
import com.hotcodepush.core.DownloadStrategy
import com.hotcodepush.core.DownloadUpdateOptions
import com.hotcodepush.core.HandlerScheduler
import com.hotcodepush.core.MandatoryApplyStrategy
import com.hotcodepush.core.PlainException
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

@CapacitorPlugin(name = "HotCodePush")
class HotCodePushPlugin : Plugin(), CoreListener {
    private var core: Core? = null
    private var loader: CapacitorBundleLoader? = null
    private val scheduler = HandlerScheduler()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pageEvents = PageEvents { eventName, data, retainUntilConsumed -> notifyListeners(eventName, data, retainUntilConsumed) }

    // Every method rejects with this while the core is absent: the resource file is missing, or the core refused to read it.
    private var notConfiguredMessage = Configuration.MISSING_MESSAGE

    // A page start arrives after the bridge has dropped the listeners of the previous page.
    private val pageStartListener = object : WebViewListener() {
        override fun onPageStarted(webView: android.webkit.WebView) {
            if (webView.url?.startsWith(bridge.localUrl) == true) handlePageStart()
        }
    }

    // Capacitor calls this while it builds the bridge, before the WebView loads. The start decides the bundle here, with a bounded
    // wait for the core, so the WebView never loads a bundle that the start replaces.
    override fun load() {
        val configuration = try {
            Configuration.read(context)
        } catch (exception: Exception) {
            notConfiguredMessage = Configuration.resolveRefusedMessage(exception)
            null
        }
        if (configuration == null) {
            Logger.error(TAG, notConfiguredMessage, null)
            return
        }
        val loader = CapacitorBundleLoader(context, bridge) { pageEvents.holdUntilNextPage() }
        val core = Core(
            context = context,
            configuration = configuration,
            device = DeviceFacts.current(context, SDK_VERSION),
            embedded = AssetsEmbeddedBundle(context, configuration.embeddedBundleManifest, CapacitorBundleLoader.EMBEDDED_ASSET_PATH),
            loader = loader,
            listener = this,
            scope = scope,
            scheduler = scheduler,
        )
        this.core = core
        this.loader = loader
        core.handleAppStartBlocking()
        loader.beginServing()
        // The bridge takes its WebView listeners from its builder once it is built, which replaces any added while it builds.
        mainHandler.post { bridge.addWebViewListener(pageStartListener) }
    }

    // Held events go out retained, because Capacitor loads a downloaded bundle twice at the start and replaces the first page before it listens.
    // A page start the SDK did not request, such as `location.reload()`, is never interpreted: a `next_start` release waits for the next process start.
    private fun handlePageStart() = pageEvents.releaseToPage()

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

    // The activity took the bridge with it. Nothing of this instance may fire again, or two cores would race on one store.
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
    fun clearUpdates(call: PluginCall) = run(call) {
        it.clearUpdates()
        null
    }

    @PluginMethod
    fun downloadUpdate(call: PluginCall) = run(call) { it.downloadUpdate(downloadUpdateOptions(call)).toJson() }

    @PluginMethod
    fun getChannel(call: PluginCall) = run(call) { it.channel().toJson() }

    @PluginMethod
    fun getDevice(call: PluginCall) = run(call) { it.deviceResult().toJson() }

    @PluginMethod
    fun getState(call: PluginCall) = run(call) { it.getState().toJson() }

    @PluginMethod
    fun notifyReady(call: PluginCall) = run(call) { it.notifyReady().toJson() }

    @PluginMethod
    fun notifyRendered(call: PluginCall) = run(call) {
        it.handleRendered()
        null
    }

    @PluginMethod
    fun rollbackUpdate(call: PluginCall) {
        val reason = call.getString("reason")
        run(call) {
            it.rollbackUpdate(reason)
            null
        }
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
        run(call) {
            it.setAttributes(changes)
            null
        }
    }

    @PluginMethod
    fun setChannel(call: PluginCall) {
        val choice = call.getString("id")?.let { ChannelChoice.Id(it) } ?: call.getString("name")?.let { ChannelChoice.Name(it) }
        run(call) {
            it.setChannel(choice)
            null
        }
    }

    @PluginMethod
    fun setRestartAllowed(call: PluginCall) = run(call) {
        it.setRestartAllowed(call.getBoolean("isAllowed") ?: throw PlainException("isAllowed must be a boolean"))
        null
    }

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
    fun sync(call: PluginCall) = run(call) { it.sync(SyncTrigger.MANUAL, syncOptions(call)).toJson() }

    private fun syncOptions(call: PluginCall) = SyncOptions(
        applyStrategy = option("applyStrategy", call.getString("applyStrategy"), ApplyStrategy::fromWire),
        downloadStrategy = option("downloadStrategy", call.getString("downloadStrategy"), DownloadStrategy::fromWire),
        mandatoryApplyStrategy = option("mandatoryApplyStrategy", call.getString("mandatoryApplyStrategy"), MandatoryApplyStrategy::fromWire),
    )

    private fun downloadUpdateOptions(call: PluginCall) = DownloadUpdateOptions(
        applyStrategy = option("applyStrategy", call.getString("applyStrategy"), ApplyStrategy::fromWire),
        mandatoryApplyStrategy = option("mandatoryApplyStrategy", call.getString("mandatoryApplyStrategy"), MandatoryApplyStrategy::fromWire),
    )

    // A value outside the choices is a programming mistake, so it rejects the call.
    private fun <T> option(name: String, raw: String?, parse: (String?) -> T?): T? {
        if (raw == null) return null
        return parse(raw) ?: throw PlainException("$name is not one of its choices: $raw")
    }

    private fun run(call: PluginCall, body: suspend (Core) -> JSONObject?) {
        val core = core
        if (core == null) {
            call.reject(notConfiguredMessage)
            return
        }
        scope.launch {
            try {
                val result = body(core)
                if (result == null) call.resolve() else call.resolve(JSObject.fromJSONObject(result))
            } catch (exception: Exception) {
                call.reject(exception.message, exception)
            }
        }
    }

    override fun updateAvailable(event: UpdateAvailableEvent) = deliver("updateAvailable", JSObject.fromJSONObject(event.toJson()))

    override fun updateDownloaded(event: UpdateDownloadedEvent) = deliver("updateDownloaded", JSObject.fromJSONObject(event.toJson()))

    override fun updateFailed(event: UpdateFailedEvent) = deliver("updateFailed", JSObject.fromJSONObject(event.toJson()))

    override fun downloadProgress(event: DownloadProgressEvent) = deliver("downloadProgress", JSObject.fromJSONObject(event.toJson()))

    // Retained until a page listens, because the event belongs to the page that the rollback reloads into.
    override fun updateRolledBack(event: UpdateRolledBackEvent) = deliver("updateRolledBack", JSObject.fromJSONObject(event.toJson()), retainUntilConsumed = true)

    // The main thread orders the event behind the reload that the loader starts there. So an event after a reload waits for its page.
    private fun deliver(eventName: String, data: JSObject, retainUntilConsumed: Boolean = false) {
        mainHandler.post { pageEvents.deliver(eventName, data, retainUntilConsumed) }
    }

    companion object {
        const val TAG = "HotCodePush"
    }
}
