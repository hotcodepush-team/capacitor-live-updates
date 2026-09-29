import Foundation

public enum DownloadFailure: Error, Equatable {
    case invalidSignature(String)
    case verificationFailed(String)
    case downloadFailed(String)

    public var reason: FailedReason {
        switch self {
        case .invalidSignature: return .invalidSignature
        case .verificationFailed: return .verificationFailed
        case .downloadFailed: return .downloadFailed
        }
    }

    public var message: String {
        switch self {
        case .invalidSignature(let message), .verificationFailed(let message), .downloadFailed(let message): return message
        }
    }
}

public struct DownloadOutcome: Equatable {
    public let manifest: BundleManifest
    public let bytes: Int
    public let packKind: PackKind
}

/// Manifest, signature, missing files, pack, verification, files to disk — each step one function.
public final class Downloader {
    private let configuration: Configuration
    private let embedded: EmbeddedBundle
    private let files: FileStore
    private let http: HttpClient
    private let temporaryDirectory: URL

    public init(configuration: Configuration, files: FileStore, embedded: EmbeddedBundle, http: HttpClient, temporaryDirectory: URL) {
        self.configuration = configuration
        self.files = files
        self.embedded = embedded
        self.http = http
        self.temporaryDirectory = temporaryDirectory
    }

    public func downloadRelease(_ target: IndexRelease, currentBundleId: String?, progress: @escaping (Int, Int) -> Void) async throws -> DownloadOutcome {
        let manifest = try await fetchBundleManifest(target)
        let missing = resolveMissingFiles(manifest)
        var bytes = 0
        var packKind = PackKind.files
        if !missing.isEmpty, let pack = resolvePack(manifest, currentBundleId: currentBundleId, missing: missing) {
            bytes += try await downloadPack(pack.url, bundleId: manifest.bundleId, wanted: Set(missing.map { $0.sha256 }), progress: progress)
            packKind = pack.kind
        }
        for file in resolveMissingFiles(manifest) {
            bytes += try await downloadFile(file)
        }
        try files.writeManifest(manifest)
        return DownloadOutcome(manifest: manifest, bytes: bytes, packKind: packKind)
    }

    func fetchBundleManifest(_ target: IndexRelease) async throws -> BundleManifest {
        guard let url = URL(string: target.manifestUrl) else { throw DownloadFailure.downloadFailed("Invalid manifest URL") }
        let response: HttpResponse
        do {
            response = try await http.get(url, headers: [:])
        } catch {
            throw DownloadFailure.downloadFailed("The manifest could not be fetched: \(error.localizedDescription)")
        }
        guard response.status == 200 else { throw DownloadFailure.downloadFailed("HTTP \(response.status) for the manifest") }
        guard let envelope = try? Json.decoder.decode(ManifestEnvelope.self, from: response.body), let manifest = try? envelope.decodeManifest() else {
            throw DownloadFailure.verificationFailed("The manifest could not be parsed")
        }
        try verifyManifestSignature(envelope, expectedSha256: target.manifestSha256)
        guard manifest.bundleId == target.bundleId else { throw DownloadFailure.verificationFailed("The manifest names another bundle") }
        return manifest
    }

    func verifyManifestSignature(_ envelope: ManifestEnvelope, expectedSha256: String) throws {
        let actual = Hashing.sha256Hex(envelope.manifest)
        guard actual == expectedSha256 else { throw DownloadFailure.verificationFailed("The manifest's hash does not match the index") }
        if !configuration.publicKeys.isEmpty {
            // TODO(milestone 3, code signing): verify the ed25519 signature over the manifest bytes against `publicKeys`.
            throw DownloadFailure.invalidSignature("Signature verification is not available in this SDK version")
        }
    }

    func resolveMissingFiles(_ manifest: BundleManifest) -> [BundleManifest.File] {
        return manifest.files.filter { !files.hasFile(sha256: $0.sha256) && !embedded.has(sha256: $0.sha256) }
    }

    /// The delta pack against the running bundle where one exists, the full pack otherwise; nothing when the pack would cost more than the files.
    func resolvePack(_ manifest: BundleManifest, currentBundleId: String?, missing: [BundleManifest.File]) -> (url: String, kind: PackKind)? {
        if let currentBundleId = currentBundleId, let delta = manifest.deltas.first(where: { $0.baseBundleId == currentBundleId }) {
            return (delta.url, .delta)
        }
        if let pack = manifest.pack, missing.count > 1 {
            return (pack.url, .full)
        }
        return nil
    }

    func downloadPack(_ urlString: String, bundleId: String, wanted: Set<String>, progress: @escaping (Int, Int) -> Void) async throws -> Int {
        guard let url = URL(string: urlString) else { throw DownloadFailure.downloadFailed("Invalid pack URL") }
        let file = temporaryDirectory.appendingPathComponent("\(bundleId)-\(Hashing.sha256Hex(urlString).prefix(16)).pack")
        do {
            try await http.download(url, to: file, progress: progress)
        } catch let failure as DownloadFailure {
            throw failure
        } catch {
            throw DownloadFailure.downloadFailed("The pack could not be downloaded: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { throw DownloadFailure.downloadFailed("The pack could not be read") }
        do {
            try PackReader.forEachEntry(in: data) { entry in
                guard wanted.contains(entry.sha256) else { return }
                try files.writeFile(try Gzip.decompress(entry.body), sha256: entry.sha256)
            }
        } catch let failure as DownloadFailure {
            throw failure
        } catch {
            throw DownloadFailure.verificationFailed("The pack did not verify: \(error)")
        }
        return data.count
    }

    func downloadFile(_ file: BundleManifest.File) async throws -> Int {
        guard let url = URL(string: "\(configuration.filesBaseUrl)/apps/\(configuration.appId)/files/\(file.sha256)") else { throw DownloadFailure.downloadFailed("Invalid file URL") }
        let response: HttpResponse
        do {
            response = try await http.get(url, headers: [:])
        } catch {
            throw DownloadFailure.downloadFailed("The file \(file.path) could not be downloaded: \(error.localizedDescription)")
        }
        guard response.status == 200 else { throw DownloadFailure.downloadFailed("HTTP \(response.status) for \(file.path)") }
        let content = (try? Gzip.decompress(response.body)) ?? response.body
        do {
            try files.writeFile(content, sha256: file.sha256)
        } catch {
            throw DownloadFailure.verificationFailed("The file \(file.path) did not match its hash")
        }
        return response.body.count
    }
}
