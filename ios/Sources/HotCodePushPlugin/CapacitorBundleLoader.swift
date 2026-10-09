#if canImport(Capacitor)
import Capacitor
import Foundation
import HotCodePushCore
import Network

/// Capacitor serves the WebView from its bridge's base path, at launch the path persisted under `serverBasePath`, resolved inside
/// `Library/NoCloud/ionic_built_snapshots/<last path component>`; a bundle is laid out there by path. Until the start has decided,
/// a switch only changes what the first load serves; from then on it reloads the WebView.
final class CapacitorBundleLoader: BundleLoader {
    private static let serverBasePathKey = "serverBasePath"
    private static let snapshotsDirectory = "NoCloud/ionic_built_snapshots"

    private weak var bridge: CAPBridgeProtocol?
    private let willLoadPage: () -> Void
    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private var isMetered = false
    /// The bundle the WebView serves, or serves at its first load while the start decides; `nil` is the embedded bundle.
    private var servedBundle: String?
    /// The WebView loads: a switch reloads it from here on.
    private var isServing = false

    /// `willLoadPage` runs on the main thread before every load the SDK starts, the first one included.
    init(bridge: CAPBridgeProtocol, willLoadPage: @escaping () -> Void) {
        self.bridge = bridge
        self.willLoadPage = willLoadPage
        servedBundle = CapacitorBundleLoader.resolveBundleId(path: bridge.config.appLocation.path)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isMetered = path.isExpensive || path.isConstrained
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
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

    func isConnectionMetered() -> Bool {
        return isMetered
    }

    /// The start has decided: the bridge serves its bundle from the first load on, before Capacitor checks that the path exists,
    /// and a switch reloads the WebView from here on. Main thread, before the WebView loads.
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
        return bundleId.map { projectionDirectory(bundleId: $0).path } ?? Bundle.main.bundleURL.appendingPathComponent("public").path
    }

    /// The bundle a base path names as Capacitor resolves it, by its last component under the snapshots directory, while that tree is
    /// on disk; a tree a restore from backup did not bring back, or any other path, is the embedded bundle.
    private static func resolveBundleId(path: String?) -> String? {
        guard let path = path, path.contains(snapshotsDirectory) else { return nil }
        let bundleId = URL(fileURLWithPath: path).lastPathComponent
        return FileManager.default.fileExists(atPath: projectionDirectory(bundleId: bundleId).path) ? bundleId : nil
    }
}

/// The files compiled into the binary, `public/` in the app bundle, addressed by the embedded manifest's hashes; none without a manifest.
final class AppBundleEmbeddedBundle: EmbeddedBundle {
    private let pathsBySha256: [String: String]
    private let publicDirectory = Bundle.main.bundleURL.appendingPathComponent("public", isDirectory: true)

    init(manifest: EmbeddedBundleManifest?) {
        var paths: [String: String] = [:]
        for file in manifest?.files ?? [] {
            paths[file.sha256] = file.path
        }
        pathsBySha256 = paths
    }

    func has(sha256: String) -> Bool {
        guard let path = pathsBySha256[sha256] else { return false }
        return FileManager.default.fileExists(atPath: publicDirectory.appendingPathComponent(path).path)
    }

    func copyFile(sha256: String, to destination: URL) throws {
        guard let path = pathsBySha256[sha256] else { throw PlainError("No embedded file with hash \(sha256)") }
        try FileManager.default.copyItem(at: publicDirectory.appendingPathComponent(path), to: destination)
    }
}
#endif
