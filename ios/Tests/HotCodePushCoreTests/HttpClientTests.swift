import XCTest
@testable import HotCodePushCore

final class HttpClientTests: XCTestCase {
    private let url = URL(string: "https://files.test/apps/a/bundles/b2/pack")!
    private var file: URL!

    override func setUp() {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("hotcodepush-tests-\(UUID().uuidString)").appendingPathComponent("b2.pack")
    }

    func testShouldStopADownloadPastItsMaximumAndDeleteTheFile() async {
        let client = StubUrlProtocol.client { _ in .init(status: 200, body: Data(count: 200_000)) }
        do {
            try await client.download(url, to: file, maximumBytes: 100_000) { _, _ in }
            XCTFail("The download should stop past its maximum")
        } catch {
            XCTAssertEqual((error as? DownloadFailure)?.reason, .downloadFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}

/// Answers the real `URLSession` client's requests from a closure, so it runs without a network.
final class StubUrlProtocol: URLProtocol {
    struct Reply {
        let status: Int
        let body: Data
        var isInterrupted = false
    }

    static var reply: (URLRequest) -> Reply = { _ in Reply(status: 404, body: Data()) }

    static func client(_ reply: @escaping (URLRequest) -> Reply) -> UrlSessionHttpClient {
        StubUrlProtocol.reply = reply
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubUrlProtocol.self]
        return UrlSessionHttpClient(session: URLSession(configuration: configuration))
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = StubUrlProtocol.reply(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        if reply.isInterrupted {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
