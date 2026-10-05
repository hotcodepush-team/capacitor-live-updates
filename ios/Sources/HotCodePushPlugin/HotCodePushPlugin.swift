#if canImport(Capacitor)
import Capacitor
import Foundation
import HotCodePushProtocol
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

    private static let notConfiguredMessage = "HotCodePush is not configured: hotcodepush.json is missing from the app's resources. Run `npx hotcodepush init` and build the app once."

    private var core: Core?
    private var loader: CapacitorBundleLoader?

    override public func load() {
        guard let configuration = HotCodePushPlugin.readConfiguration() else {
            CAPLog.print("[HotCodePush] ", HotCodePushPlugin.notConfiguredMessage)
            return
        }
        let loader = CapacitorBundleLoader(plugin: self)
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        Task { await core.handleAppStart() }
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
        run(call) { core in await core.checkForUpdate() }
    }

    @objc func clearUpdates(_ call: CAPPluginCall) {
        runVoid(call) { core in await core.clearUpdates() }
    }

    @objc func downloadUpdate(_ call: CAPPluginCall) {
        run(call) { core in await core.downloadUpdate() }
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
        runVoid(call) { core in await core.setChannel(choice) }
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
            call.reject(HotCodePushPlugin.notConfiguredMessage)
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
            run(call) { core in await core.sync(trigger: .manual, options: options) }
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
            call.reject(HotCodePushPlugin.notConfiguredMessage)
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
            call.reject(HotCodePushPlugin.notConfiguredMessage)
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

    static func readConfiguration() -> Configuration? {
        guard let url = Bundle.main.url(forResource: "hotcodepush", withExtension: "json"), let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            return try Configuration.decode(data)
        } catch {
            CAPLog.print("[HotCodePush] hotcodepush.json could not be read: \(error)")
            return nil
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
        notify("updateAvailable", event)
    }

    public func updateDownloaded(_ event: UpdateDownloadedEvent) {
        notify("updateDownloaded", event)
    }

    public func updateFailed(_ event: UpdateFailedEvent) {
        notify("updateFailed", event)
    }

    public func downloadProgress(releaseId: String, downloadedBytes: Int, totalBytes: Int) {
        let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0
        notifyListeners("downloadProgress", data: ["releaseId": releaseId, "downloadedBytes": downloadedBytes, "totalBytes": totalBytes, "progress": progress])
    }

    /// Retained until the reloaded web layer listens: the event belongs to the start that follows the rollback.
    public func rolledBack(_ event: RolledBackEvent) {
        guard let js = try? HotCodePushPlugin.jsObject(event) else { return }
        notifyListeners("rolledBack", data: js, retainUntilConsumed: true)
    }

    private func notify<T: Encodable>(_ eventName: String, _ event: T) {
        guard let js = try? HotCodePushPlugin.jsObject(event) else { return }
        notifyListeners(eventName, data: js)
    }
}
#endif
