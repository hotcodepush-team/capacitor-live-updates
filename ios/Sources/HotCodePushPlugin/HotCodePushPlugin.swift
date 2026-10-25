import Capacitor
import Foundation
import HotCodePushCore

@objc(HotCodePushPlugin)
public class HotCodePushPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HotCodePushPlugin"
    public let jsName = "HotCodePush"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "applyUpdate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkForUpdate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearUpdates", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "downloadUpdate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getChannel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDevice", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "notifyReady", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "notifyRendered", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "rollbackUpdate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setAttributes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setChannel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setRestartAllowed", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showDebugScreen", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sync", returnType: CAPPluginReturnPromise)
    ]

    private var core: Core?
    /// Why every method rejects while the core is absent: the resource file is missing, or the core's reader refused it.
    private var notConfiguredMessage = Configuration.missingMessage
    private lazy var pageEvents = PageEvents(plugin: self)

    /// Runs inside Capacitor's bridge, before its view controller loads the WebView: the start decides the bundle the first load
    /// serves, waiting for the core at most its bound, so the WebView never loads a bundle the start replaces.
    override public func load() {
        let configuration: Configuration?
        do {
            configuration = try Configuration.read()
        } catch {
            notConfiguredMessage = Configuration.resolveRefusedMessage(error)
            configuration = nil
        }
        guard let configuration = configuration, let bridge = bridge else {
            CAPLog.print("[HotCodePush] ", notConfiguredMessage)
            return
        }
        let loader = CapacitorBundleLoader(bridge: bridge) { [weak self] in
            self?.pageEvents.holdUntilNextPage()
        }
        let core = Core(
            configuration: configuration,
            device: DeviceFacts.current(sdkVersion: sdkVersion),
            embedded: AppBundleEmbeddedBundle(manifest: configuration.embeddedBundleManifest, rootDirectory: CapacitorBundleLoader.embeddedDirectory),
            loader: loader,
            listener: self)
        self.core = core
        _ = core.handleAppStartBlocking()
        loader.beginServing()
        if let webView = bridge.webView {
            PageStartListener.attach(to: webView) { [weak self] url in
                self?.handlePageStart(url: url)
            }
        }
        core.observeAppLifecycle()
    }

    /// A page of the app began: the events held for it go out, retained until a page listens. A page start the SDK did not request
    /// is never interpreted, a `location.reload()` or a restarted WebContent process among them: the page serves the bundle of this
    /// run, a `next_start` release waits for the next process start, and the readiness gate runs from the start.
    private func handlePageStart(url: URL) {
        guard let serverURL = bridge?.config.serverURL, url.absoluteString.hasPrefix(serverURL.absoluteString) else { return }
        pageEvents.releaseToPage()
    }

    // MARK: Methods

    @objc func applyUpdate(_ call: CAPPluginCall) {
        run(call) { core in try HotCodePushPlugin.jsObject(await core.applyUpdate()) }
    }

    @objc func checkForUpdate(_ call: CAPPluginCall) {
        run(call) { core in try HotCodePushPlugin.jsObject(await core.checkForUpdate()) }
    }

    @objc func clearUpdates(_ call: CAPPluginCall) {
        run(call) { core in
            await core.clearUpdates()
            return nil
        }
    }

    @objc func downloadUpdate(_ call: CAPPluginCall) {
        run(call) { core in try HotCodePushPlugin.jsObject(await core.downloadUpdate(options: HotCodePushPlugin.downloadUpdateOptions(from: call))) }
    }

    @objc func getChannel(_ call: CAPPluginCall) {
        run(call) { core in try HotCodePushPlugin.jsObject(await core.channel()) }
    }

    @objc func getDevice(_ call: CAPPluginCall) {
        run(call) { core in try HotCodePushPlugin.jsObject(await core.deviceResult()) }
    }

    @objc func getState(_ call: CAPPluginCall) {
        run(call) { core in try HotCodePushPlugin.jsObject(await core.getState()) }
    }

    @objc func notifyReady(_ call: CAPPluginCall) {
        run(call) { core in try HotCodePushPlugin.jsObject(await core.notifyReady()) }
    }

    @objc func notifyRendered(_ call: CAPPluginCall) {
        run(call) { core in
            await core.handleRendered()
            return nil
        }
    }

    @objc func rollbackUpdate(_ call: CAPPluginCall) {
        let reason = call.getString("reason")
        run(call) { core in
            try await core.rollbackUpdate(detail: reason)
            return nil
        }
    }

    @objc func setAttributes(_ call: CAPPluginCall) {
        var changes: [String: String?] = [:]
        for (key, value) in call.options ?? [:] {
            guard let key = key as? String else { continue }
            if value is NSNull {
                changes[key] = .some(nil)
            } else if let value = value as? String {
                changes[key] = value
            } else {
                call.reject("An attribute value is a string or null: \(key)")
                return
            }
        }
        run(call) { core in
            try await core.setAttributes(changes)
            return nil
        }
    }

    @objc func setChannel(_ call: CAPPluginCall) {
        let choice: ChannelChoice?
        if let id = call.getString("id") {
            choice = .id(id)
        } else if let name = call.getString("name") {
            choice = .name(name)
        } else {
            choice = nil
        }
        run(call) { core in
            try await core.setChannel(choice)
            return nil
        }
    }

    @objc func setRestartAllowed(_ call: CAPPluginCall) {
        run(call) { core in
            guard let isAllowed = call.getBool("isAllowed") else { throw PlainError("isAllowed must be a boolean") }
            await core.setRestartAllowed(isAllowed)
            return nil
        }
    }

    /// The shared core's debug screen, presented over the bridge's view controller.
    @objc func showDebugScreen(_ call: CAPPluginCall) {
        guard let core = core else {
            call.reject(notConfiguredMessage)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let presenter = self?.bridge?.viewController else {
                call.reject("The debug screen has no view controller to open over")
                return
            }
            DebugScreenViewController.present(core: core, from: presenter)
            call.resolve()
        }
    }

    @objc func sync(_ call: CAPPluginCall) {
        run(call) { core in try HotCodePushPlugin.jsObject(await core.sync(trigger: .manual, options: HotCodePushPlugin.syncOptions(from: call))) }
    }

    /// Each stage's strategy for this call; a value outside its choices is a programming mistake and rejects the call.
    static func syncOptions(from call: CAPPluginCall) throws -> SyncOptions {
        return SyncOptions(
            applyStrategy: try option("applyStrategy", call.getString("applyStrategy"), ApplyStrategy.init(rawValue:)),
            downloadStrategy: try option("downloadStrategy", call.getString("downloadStrategy"), DownloadStrategy.init(rawValue:)),
            mandatoryApplyStrategy: try option("mandatoryApplyStrategy", call.getString("mandatoryApplyStrategy"), MandatoryApplyStrategy.init(rawValue:)))
    }

    /// The apply strategies for this call, the download pinned to `auto`; a value outside its choices rejects the call.
    static func downloadUpdateOptions(from call: CAPPluginCall) throws -> DownloadUpdateOptions {
        return DownloadUpdateOptions(
            applyStrategy: try option("applyStrategy", call.getString("applyStrategy"), ApplyStrategy.init(rawValue:)),
            mandatoryApplyStrategy: try option("mandatoryApplyStrategy", call.getString("mandatoryApplyStrategy"), MandatoryApplyStrategy.init(rawValue:)))
    }

    private static func option<T>(_ name: String, _ raw: String?, _ parse: (String) -> T?) throws -> T? {
        guard let raw = raw else { return nil }
        guard let value = parse(raw) else { throw PlainError("\(name) is not one of its choices: \(raw)") }
        return value
    }

    /// Resolves with the body's result, or with no data when a method that returns nothing ends its body in `nil`.
    private func run(_ call: CAPPluginCall, _ body: @escaping (Core) async throws -> JSObject?) {
        guard let core = core else {
            call.reject(notConfiguredMessage)
            return
        }
        Task {
            do {
                if let result = try await body(core) {
                    call.resolve(result)
                } else {
                    call.resolve()
                }
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    static func jsObject<T: Encodable>(_ value: T) throws -> JSObject {
        guard let js = JSTypes.coerceDictionaryToJSObject(try Json.encodeObject(value)) else {
            throw PlainError("The result could not be encoded")
        }
        return js
    }
}

extension HotCodePushPlugin: CoreListener {
    public func updateAvailable(_ event: UpdateAvailableEvent) {
        deliver("updateAvailable", event)
    }

    public func updateDownloaded(_ event: UpdateDownloadedEvent) {
        deliver("updateDownloaded", event)
    }

    public func updateFailed(_ event: UpdateFailedEvent) {
        deliver("updateFailed", event)
    }

    public func downloadProgress(_ event: DownloadProgressEvent) {
        deliver("downloadProgress", event)
    }

    /// Retained until the page listens: the event belongs to the page the rollback reloads into.
    public func updateRolledBack(_ event: UpdateRolledBackEvent) {
        deliver("updateRolledBack", event, retainUntilConsumed: true)
    }

    /// On the main thread, in order behind the reload the loader starts there, so an event that follows a reload waits for its page.
    private func deliver<T: Encodable>(_ eventName: String, _ event: T, retainUntilConsumed: Bool = false) {
        guard let data = try? HotCodePushPlugin.jsObject(event) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.pageEvents.deliver(eventName, data: data, retainUntilConsumed: retainUntilConsumed)
        }
    }
}
