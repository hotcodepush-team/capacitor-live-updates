import XCTest
@testable import HotCodePushCore

final class DownloaderTests: XCTestCase {
    func testShouldRefuseAManifestUrlOffTheConfiguredHosts() async {
        let harness = DownloaderHarness()
        let release = harness.publish(DownloaderHarness.manifest(files: ["index.html": Data("v2".utf8)]), manifestUrl: "https://elsewhere.test/manifest.json")
        let failure = await harness.downloadFailure(release)
        XCTAssertEqual(failure?.reason, .verificationFailed)
        XCTAssertTrue(harness.http.requests.isEmpty)
    }

    func testShouldRefuseAPackUrlOffTheConfiguredHosts() async {
        let harness = DownloaderHarness()
        let manifest = DownloaderHarness.manifest(files: ["index.html": Data("v2".utf8), "app.js": Data("js".utf8)], packUrl: "https://elsewhere.test/pack")
        let failure = await harness.downloadFailure(harness.publish(manifest))
        XCTAssertEqual(failure?.reason, .verificationFailed)
        XCTAssertEqual(harness.http.requests.map { $0.url.host }, ["files.test"])
    }

    func testShouldRefuseAManifestPathThatClimbsOutOfTheServedTree() async {
        let harness = DownloaderHarness()
        let failure = await harness.downloadFailure(harness.publish(DownloaderHarness.manifest(files: ["../../escape.html": Data("v2".utf8)])))
        XCTAssertEqual(failure?.reason, .verificationFailed)
        XCTAssertTrue(harness.files.bundleIds().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.root.appendingPathComponent("escape.html").path))
    }
}

/// A downloader over fakes, in a fresh temporary directory.
final class DownloaderHarness {
    static let bundleId = "b2"

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("hotcodepush-tests-\(UUID().uuidString)")
    let http = FakeHttpClient()
    let files: FileStore
    let downloader: Downloader

    init() {
        files = FileStore(rootDirectory: root.appendingPathComponent("store"))
        downloader = Downloader(configuration: Fixture.configuration(), files: files, embedded: InMemoryEmbeddedBundle(), http: http, temporaryDirectory: root.appendingPathComponent("tmp"))
    }

    static func manifest(files: [String: Data], packUrl: String = "\(Fixture.filesBaseUrl)/apps/\(Fixture.appId)/bundles/\(bundleId)/pack", packSizeBytes: Int = 0) -> BundleManifest {
        let entries = files.sorted { $0.key < $1.key }.map { BundleManifest.File(path: $0.key, sha256: Hashing.sha256Hex($0.value), sizeBytes: $0.value.count) }
        return BundleManifest(bundleId: bundleId, appId: Fixture.appId, version: "1.2.0", createdAt: Fixture.builtAt, files: entries, pack: .init(url: packUrl, sizeBytes: packSizeBytes))
    }

    /// Serves the manifest where the index entry says it is and returns that entry.
    func publish(_ manifest: BundleManifest, manifestUrl: String = "\(Fixture.filesBaseUrl)/apps/\(Fixture.appId)/bundles/\(bundleId)/manifest.json") -> IndexRelease {
        let json = String(bytes: try! Json.encoder.encode(manifest), encoding: .utf8) ?? ""
        http.stubJson(manifestUrl, ManifestEnvelope(manifest: json))
        return IndexRelease(id: "r2", number: 2, createdAt: manifest.createdAt, bundleId: manifest.bundleId, bundleVersion: manifest.version, manifestUrl: manifestUrl, manifestSha256: Hashing.sha256Hex(json), sizeBytes: 0)
    }

    func downloadFailure(_ release: IndexRelease) async -> DownloadFailure? {
        do {
            _ = try await downloader.downloadRelease(release, currentBundleId: nil) { _, _ in }
            return nil
        } catch {
            return error as? DownloadFailure
        }
    }
}
