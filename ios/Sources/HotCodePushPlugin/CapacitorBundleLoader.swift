import Capacitor
import Foundation
import Network
#if canImport(HotCodePushCore)
import HotCodePushCore
#endif

/// Capacitor loads the WebView from the path it persisted under `serverBasePath`, resolved inside
/// `Library/NoCloud/ionic_built_snapshots/<last path component>`; a bundle is laid out there by path.
final class CapacitorBundleLoader: BundleLoader {
    private static let serverBasePathKey = "serverBasePath"
    private static let snapshotsDirectory = "NoCloud/ionic_built_snapshots"

    private weak var plugin: CAPPlugin?
    private let monitor = NWPathMonitor()
    private var isMetered = false

    init(plugin: CAPPlugin) {
        self.plugin = plugin
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isMetered = path.isExpensive || path.isConstrained
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func projectionDirectory(bundleId: String) -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library.appendingPathComponent(CapacitorBundleLoader.snapshotsDirectory, isDirectory: true).appendingPathComponent(bundleId, isDirectory: true)
    }

    func persistServedBundle(bundleId: String?) {
        if let bundleId = bundleId {
            KeyValueStore.standard[CapacitorBundleLoader.serverBasePathKey] = projectionDirectory(bundleId: bundleId).path
        } else {
            KeyValueStore.standard[CapacitorBundleLoader.serverBasePathKey] = ""
        }
    }

    func loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId: bundleId)
        DispatchQueue.main.async { [weak self] in
            guard let viewController = self?.plugin?.bridge?.viewController as? CAPBridgeViewController else { return }
            let path = bundleId.map { self!.projectionDirectory(bundleId: $0).path } ?? Bundle.main.bundleURL.appendingPathComponent("public").path
            viewController.setServerBasePath(path: path)
        }
    }

    func servedBundleId() -> String? {
        guard let viewController = plugin?.bridge?.viewController as? CAPBridgeViewController else {
            return nil
        }
        let url = URL(fileURLWithPath: viewController.getServerBasePath())
        return url.path.contains(CapacitorBundleLoader.snapshotsDirectory) ? url.lastPathComponent : nil
    }

    func isConnectionMetered() -> Bool {
        return isMetered
    }
}

/// The files compiled into the binary, `public/` in the app bundle, addressed by the embedded manifest's hashes.
final class AppBundleEmbeddedBundle: EmbeddedBundle {
    private let pathsBySha256: [String: String]
    private let publicDirectory = Bundle.main.bundleURL.appendingPathComponent("public", isDirectory: true)

    init(manifest: BundleManifest) {
        var paths: [String: String] = [:]
        for file in manifest.files {
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
