import Foundation

public enum InstallStrategy: String, Codable {
    case nextStart = "next-start"
    case immediate
    case onResume = "on-resume"
    case manual
}

public enum ReadySignal: String, Codable {
    case render
    case call
}

public enum NetworkPolicy: String, Codable {
    case any
    case unmetered
}

/// The resource file: the project's `hotcodepush.json` plus what only the embed step knows.
public struct Configuration: Codable, Equatable {
    public static let defaultFilesBaseUrl = "https://files.hotcodepush.com"
    public static let defaultUpdatesBaseUrl = "https://updates.hotcodepush.com"

    public var appId: String
    public var channelId: String
    public var autoSync: Bool
    public var syncInterval: Double
    public var installStrategy: InstallStrategy
    public var minimumBackgroundDuration: Double
    public var readySignal: ReadySignal
    public var readyTimeout: Double
    public var network: NetworkPolicy
    public var enabledInDebugBuilds: Bool
    public var publicKeys: [String]
    public var builtAt: Date
    public var fingerprint: String?
    public var embeddedBundleManifest: BundleManifest
    public var embeddedBundleId: String?
    public var filesBaseUrl: String
    public var updatesBaseUrl: String

    enum CodingKeys: String, CodingKey {
        case appId, channelId, autoSync, syncInterval, installStrategy, minimumBackgroundDuration
        case readySignal, readyTimeout, network, enabledInDebugBuilds, publicKeys, builtAt
        case fingerprint, embeddedBundleManifest, embeddedBundleId, filesBaseUrl, updatesBaseUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decode(String.self, forKey: .appId)
        channelId = try container.decode(String.self, forKey: .channelId)
        autoSync = try container.decodeIfPresent(Bool.self, forKey: .autoSync) ?? true
        syncInterval = try container.decodeIfPresent(Double.self, forKey: .syncInterval) ?? 900
        installStrategy = try container.decodeIfPresent(InstallStrategy.self, forKey: .installStrategy) ?? .nextStart
        minimumBackgroundDuration = try container.decodeIfPresent(Double.self, forKey: .minimumBackgroundDuration) ?? 300
        readySignal = try container.decodeIfPresent(ReadySignal.self, forKey: .readySignal) ?? .render
        readyTimeout = max(1, try container.decodeIfPresent(Double.self, forKey: .readyTimeout) ?? 10)
        network = try container.decodeIfPresent(NetworkPolicy.self, forKey: .network) ?? .any
        enabledInDebugBuilds = try container.decodeIfPresent(Bool.self, forKey: .enabledInDebugBuilds) ?? true
        publicKeys = try container.decodeIfPresent([String].self, forKey: .publicKeys) ?? []
        builtAt = try container.decode(Date.self, forKey: .builtAt)
        fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
        embeddedBundleManifest = try container.decode(BundleManifest.self, forKey: .embeddedBundleManifest)
        embeddedBundleId = try container.decodeIfPresent(String.self, forKey: .embeddedBundleId)
        filesBaseUrl = try container.decodeIfPresent(String.self, forKey: .filesBaseUrl) ?? Configuration.defaultFilesBaseUrl
        updatesBaseUrl = try container.decodeIfPresent(String.self, forKey: .updatesBaseUrl) ?? Configuration.defaultUpdatesBaseUrl
    }

    public static func decode(_ data: Data) throws -> Configuration {
        return try Json.decoder.decode(Configuration.self, from: data)
    }
}
