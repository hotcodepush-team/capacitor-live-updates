import Capacitor
import Foundation
import UIKit
#if canImport(HotCodePushCore)
import HotCodePushCore
#endif

@objc(HotCodePushPlugin)
public class HotCodePushPlugin: CAPPlugin, CAPBridgedPlugin {
    public static let sdkVersion = "0.0.0"

    public let identifier = "HotCodePushPlugin"
    public let jsName = "HotCodePush"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "apply", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "check", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getChannel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDevice", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "notifyRendered", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "ready", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "reset", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "rollback", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setAttributes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setChannel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setRestartAllowed", returnType: CAPPluginReturnPromise),
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        Task { await core.handleAppStart() }
    }

    @objc private func handleWillEnterForeground() {
        Task { await core?.handleAppResume() }
    }

    // MARK: Methods

    @objc func apply(_ call: CAPPluginCall) {
        runVoid(call) { core in await core.apply() }
    }

    @objc func check(_ call: CAPPluginCall) {
        run(call) { core in await core.check() }
    }

    @objc func getChannel(_ call: CAPPluginCall) {
        run(call) { core in await core.channel() }
    }

    @objc func getDevice(_ call: CAPPluginCall) {
        run(call) { core in await core.deviceResult() }
    }

    @objc func getStatus(_ call: CAPPluginCall) {
        run(call) { core in await core.status() }
    }

    @objc func notifyRendered(_ call: CAPPluginCall) {
        runVoid(call) { core in await core.handleRendered() }
    }

    @objc func ready(_ call: CAPPluginCall) {
        run(call) { core in await core.ready() }
    }

    @objc func reset(_ call: CAPPluginCall) {
        runVoid(call) { core in await core.reset() }
    }

    @objc func rollback(_ call: CAPPluginCall) {
        let reason = call.getString("reason")
        runVoid(call) { core in await core.rollback(reason: reason) }
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

    @objc func sync(_ call: CAPPluginCall) {
        let installStrategy = call.getString("installStrategy").flatMap(InstallStrategy.init(rawValue:))
        let network = call.getString("network").flatMap(NetworkPolicy.init(rawValue:))
        run(call) { core in await core.sync(trigger: .call, installStrategy: installStrategy, network: network) }
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
    public func syncStarted(trigger: SyncTrigger) {
        notifyListeners("syncStarted", data: ["trigger": trigger.rawValue])
    }

    public func synced(result: SyncResult, trigger: SyncTrigger) {
        guard let js = try? HotCodePushPlugin.jsObject(result) else { return }
        notifyListeners("synced", data: ["result": js, "trigger": trigger.rawValue])
    }

    public func downloadProgress(releaseId: String, downloadedBytes: Int, totalBytes: Int) {
        let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0
        notifyListeners("downloadProgress", data: ["releaseId": releaseId, "downloadedBytes": downloadedBytes, "totalBytes": totalBytes, "progress": progress])
    }

    public func rolledBack(_ event: RolledBackEvent) {
        guard let js = try? HotCodePushPlugin.jsObject(event) else { return }
        notifyListeners("rolledBack", data: js, retainUntilConsumed: true)
    }
}
