#if canImport(Capacitor)
import Capacitor
import Foundation
import HotCodePushCore
import UIKit

@objc(HotCodePushPlugin)
public class HotCodePushPlugin: CAPPlugin, CAPBridgedPlugin {
    public static let sdkVersion = "0.0.0"

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

    private static let missingConfigurationMessage = "HotCodePush is not configured: hotcodepush.json is missing from the app's resources. Run `npx hotcodepush init` and build the app once."

    private var core: Core?
    private var loader: CapacitorBundleLoader?
    /// Why every method rejects while the core is absent: the resource file is missing, or the core's reader refused it.
    private var notConfiguredMessage = HotCodePushPlugin.missingConfigurationMessage
    private lazy var pageEvents = PageEvents(plugin: self)

    /// Runs inside Capacitor's bridge, before its view controller loads the WebView: the start decides the bundle the first load
    /// serves, waiting for the core at most its bound, so the WebView never loads a bundle the start replaces.
    override public func load() {
        let configuration: Configuration?
        do {
            configuration = try HotCodePushPlugin.readConfiguration()
        } catch {
            notConfiguredMessage = "HotCodePush is not configured: the app's hotcodepush.json was refused: \(HotCodePushPlugin.describeRefusal(error)). Check the project's hotcodepush.json and build the app again."
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
            device: HotCodePushPlugin.deviceFacts(),
            store: UserDefaultsStore(),
            files: FileStore(rootDirectory: HotCodePushPlugin.storeDirectory()),
            embedded: AppBundleEmbeddedBundle(manifest: configuration.embeddedBundleManifest),
            http: UrlSessionHttpClient(),
            loader: loader,
            listener: self)
        self.loader = loader
        self.core = core
        _ = core.handleAppStartBlocking()
        loader.beginServing()
        if let webView = bridge.webView {
            PageStartListener.attach(to: webView) { [weak self] url in
                self?.handlePageStart(url: url)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// A page of the app began: the events held for it go out, and one the SDK did not load is the app reloading on its own, a
    /// `location.reload()` among them, which serves the bundle a start would and goes through the gate as a start does.
    private func handlePageStart(url: URL) {
        guard let serverURL = bridge?.config.serverURL, url.absoluteString.hasPrefix(serverURL.absoluteString) else { return }
        let isLoadedBySdk = pageEvents.isPageLoadPending
        pageEvents.releaseToPage()
        guard !isLoadedBySdk, let core = core, let loader = loader else { return }
        loader.reloadPersistedBundle()
        Task { await core.handleAppReload() }
    }

    @objc private func handleDidEnterBackground() {
        Task { await core?.handleAppPause() }
    }

    @objc private func handleWillEnterForeground() {
        Task { await core?.handleAppResume() }
    }

    // MARK: Methods

    @objc func applyUpdate(_ call: CAPPluginCall) {
        run(call) { core in await core.applyUpdate() }
    }

    @objc func checkForUpdate(_ call: CAPPluginCall) {
        run(call) { core in try await core.checkForUpdate() }
    }

    @objc func clearUpdates(_ call: CAPPluginCall) {
        runVoid(call) { core in await core.clearUpdates() }
    }

    @objc func downloadUpdate(_ call: CAPPluginCall) {
        run(call) { core in try await core.downloadUpdate() }
    }

    @objc func getChannel(_ call: CAPPluginCall) {
        run(call) { core in await core.channel() }
    }

    @objc func getDevice(_ call: CAPPluginCall) {
        run(call) { core in await core.deviceResult() }
    }

    @objc func getState(_ call: CAPPluginCall) {
        run(call) { core in await core.getState() }
    }

    @objc func notifyReady(_ call: CAPPluginCall) {
        run(call) { core in await core.notifyReady() }
    }

    @objc func notifyRendered(_ call: CAPPluginCall) {
        runVoid(call) { core in await core.handleRendered() }
    }

    @objc func rollbackUpdate(_ call: CAPPluginCall) {
        let reason = call.getString("reason")
        runVoid(call) { core in try await core.rollbackUpdate(detail: reason) }
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
        runVoid(call) { core in try await core.setAttributes(changes) }
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
        runVoid(call) { core in try await core.setChannel(choice) }
    }

    @objc func setRestartAllowed(_ call: CAPPluginCall) {
        guard let allowed = call.getBool("allowed") else {
            call.reject("allowed must be a boolean")
            return
        }
        runVoid(call) { core in await core.setRestartAllowed(allowed) }
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
        do {
            let options = try HotCodePushPlugin.syncOptions(from: call)
            run(call) { core in try await core.sync(trigger: .manual, options: options) }
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    /// Each stage's strategy for this call; a value outside its choices is a programming mistake and rejects the call.
    static func syncOptions(from call: CAPPluginCall) throws -> SyncOptions {
        return SyncOptions(
            downloadStrategy: try option("downloadStrategy", call.getString("downloadStrategy"), DownloadStrategy.init(rawValue:)),
            installStrategy: try option("installStrategy", call.getString("installStrategy"), InstallStrategy.init(rawValue:)),
            mandatoryInstallStrategy: try option("mandatoryInstallStrategy", call.getString("mandatoryInstallStrategy"), MandatoryInstallStrategy.init(rawValue:)))
    }

    private static func option<T>(_ name: String, _ raw: String?, _ parse: (String) -> T?) throws -> T? {
        guard let raw = raw else { return nil }
        guard let value = parse(raw) else { throw PlainError("\(name) is not one of its choices: \(raw)") }
        return value
    }

    private func run<T: Encodable>(_ call: CAPPluginCall, _ body: @escaping (Core) async throws -> T) {
        guard let core = core else {
            call.reject(notConfiguredMessage)
            return
        }
        Task {
            do {
                call.resolve(try HotCodePushPlugin.jsObject(try await body(core)))
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    private func runVoid(_ call: CAPPluginCall, _ body: @escaping (Core) async throws -> Void) {
        guard let core = core else {
            call.reject(notConfiguredMessage)
            return
        }
        Task {
            do {
                try await body(core)
                call.resolve()
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    static func jsObject<T: Encodable>(_ value: T) throws -> JSObject {
        let data = try Json.encoder.encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let js = JSTypes.coerceDictionaryToJSObject(object) else {
            throw PlainError("The result could not be encoded")
        }
        return js
    }

    // MARK: The platform's facts

    /// The resource file the core reads, `nil` when the app's resources lack it; a file the core's reader refuses throws its error.
    static func readConfiguration() throws -> Configuration? {
        guard let url = Bundle.main.url(forResource: "hotcodepush", withExtension: "json") else {
            return nil
        }
        return try Configuration.decode(Data(contentsOf: url))
    }

    /// The reader's own message: a decoding error's `localizedDescription` hides it behind a generic sentence.
    static func describeRefusal(_ error: Error) -> String {
        switch error as? DecodingError {
        case .dataCorrupted(let context)?, .keyNotFound(_, let context)?, .typeMismatch(_, let context)?, .valueNotFound(_, let context)?:
            return context.debugDescription
        default:
            return error.localizedDescription
        }
    }

    static func deviceFacts() -> DeviceFacts {
        let info = Bundle.main.infoDictionary ?? [:]
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return DeviceFacts(
            platform: "ios",
            binaryVersion: info["CFBundleShortVersionString"] as? String ?? "",
            binaryBuild: info["CFBundleVersion"] as? String ?? "",
            osVersion: UIDevice.current.systemVersion,
            sdkVersion: sdkVersion,
            isDebugBuild: isDebugBuild)
    }

    static func storeDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("hotcodepush", isDirectory: true)
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

    public func downloadProgress(releaseId: String, downloadedBytes: Int, totalBytes: Int) {
        let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0
        deliver("downloadProgress", data: ["releaseId": releaseId, "downloadedBytes": downloadedBytes, "totalBytes": totalBytes, "progress": progress])
    }

    /// Retained until the page listens: the event belongs to the page the rollback reloads into.
    public func rolledBack(_ event: RolledBackEvent) {
        deliver("rolledBack", event, retainUntilConsumed: true)
    }

    private func deliver<T: Encodable>(_ eventName: String, _ event: T, retainUntilConsumed: Bool = false) {
        guard let data = try? HotCodePushPlugin.jsObject(event) else { return }
        deliver(eventName, data: data, retainUntilConsumed: retainUntilConsumed)
    }

    /// On the main thread, in order behind the reload the loader starts there, so an event that follows a reload waits for its page.
    private func deliver(_ eventName: String, data: JSObject, retainUntilConsumed: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.pageEvents.deliver(eventName, data: data, retainUntilConsumed: retainUntilConsumed)
        }
    }
}
#endif
