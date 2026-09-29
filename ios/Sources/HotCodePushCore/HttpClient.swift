import Foundation

public struct HttpResponse {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        return headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// The two HTTP shapes the core needs: a small GET and a large download that resumes.
public protocol HttpClient {
    func get(_ url: URL, headers: [String: String]) async throws -> HttpResponse
    /// Downloads to the file, appending from its current size with a `Range` request when it exists.
    func download(_ url: URL, to file: URL, progress: @escaping (Int, Int) -> Void) async throws
}

public final class UrlSessionHttpClient: HttpClient {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HttpResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        return HttpResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, headers: UrlSessionHttpClient.headers(of: response), body: data)
    }

    public func download(_ url: URL, to file: URL, progress: @escaping (Int, Int) -> Void) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let existing = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 206 else { throw DownloadFailure.downloadFailed("HTTP \(status) for \(url.lastPathComponent)") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if status == 206, existing > 0, let handle = try? FileHandle(forWritingTo: file) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(contentsOf: temporary))
            try handle.close()
        } else {
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: temporary, to: file)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        progress(size, size)
    }

    private static func headers(of response: URLResponse) -> [String: String] {
        guard let http = response as? HTTPURLResponse else { return [:] }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String {
                headers[name] = value
            }
        }
        return headers
    }
}
