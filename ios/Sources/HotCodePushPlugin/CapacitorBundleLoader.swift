import Capacitor
import Foundation
import HotCodePushCore

// At launch, Capacitor resolves the persisted `serverBasePath` inside `Library/NoCloud/ionic_built_snapshots/<last path component>`.
// So each bundle is laid out there.
final class CapacitorBundleLoader: BundleLoader {
    static let embeddedDirectory = Bundle.main.bundleURL.appendingPathComponent("public", isDirectory: true)
    private static let serverBasePathKey = "serverBasePath"
    private static let snapshotsDirectory = "NoCloud/ionic_built_snapshots"

    private weak var bridge: CAPBridgeProtocol?
    private let willLoadPage: () -> Void
    private let lock = NSLock()
    // Until the first load, this is the bundle that load will serve. `nil` means the embedded bundle.
    private var servedBundle: String?
    // Until the start has decided, a switch only changes what the first load serves. After that, a switch reloads the WebView.
    private var isServing = false

    // `willLoadPage` runs on the main thread before every load the SDK starts, including the first one.
    init(bridge: CAPBridgeProtocol, willLoadPage: @escaping () -> Void) {
        self.bridge = bridge
        self.willLoadPage = willLoadPage
        servedBundle = CapacitorBundleLoader.resolveBundleId(path: bridge.config.appLocation.path)
    }

    func projectionDirectory(bundleId: String) -> URL {
        return CapacitorBundleLoader.projectionDirectory(bundleId: bundleId)
    }

    func deleteProjection(bundleId: String) {
        try? FileManager.default.removeItem(at: projectionDirectory(bundleId: bundleId))
    }

    func persistServedBundle(bundleId: String?) {
        KeyValueStore.standard[CapacitorBundleLoader.serverBasePathKey] = bundleId.map { projectionDirectory(bundleId: $0).path } ?? ""
    }

    func loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId: bundleId)
        let isReload = locked { () -> Bool in
            servedBundle = bundleId
            return isServing
        }
        if isReload {
            DispatchQueue.main.async { [weak self] in
                self?.reloadWebView(bundleId: bundleId)
            }
        }
    }

    func servedBundleId() -> String? {
        return locked { servedBundle }
    }

    // Runs on the main thread once the start has decided and before the WebView loads.
    // The base path is set here, before Capacitor checks that the path exists.
    func beginServing() {
        let bundleId = locked { () -> String? in
            isServing = true
            return servedBundle
        }
        willLoadPage()
        bridge?.setServerBasePath(CapacitorBundleLoader.basePath(bundleId: bundleId))
    }

    private func reloadWebView(bundleId: String?) {
        guard let bridge = bridge else { return }
        willLoadPage()
        bridge.setServerBasePath(CapacitorBundleLoader.basePath(bundleId: bundleId))
        _ = bridge.webView?.load(URLRequest(url: bridge.config.serverURL))
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func projectionDirectory(bundleId: String) -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library.appendingPathComponent(snapshotsDirectory, isDirectory: true).appendingPathComponent(bundleId, isDirectory: true)
    }

    private static func basePath(bundleId: String?) -> String {
        return bundleId.map { projectionDirectory(bundleId: $0).path } ?? embeddedDirectory.path
    }

    // Capacitor resolves a base path by its last component under the snapshots directory.
    // A tree that a restore from backup did not bring back, or any other path, means the embedded bundle.
    private static func resolveBundleId(path: String?) -> String? {
        guard let path = path, path.contains(snapshotsDirectory) else { return nil }
        let bundleId = URL(fileURLWithPath: path).lastPathComponent
        return FileManager.default.fileExists(atPath: projectionDirectory(bundleId: bundleId).path) ? bundleId : nil
    }
}
