import Foundation

public enum SyncTrigger: String, Codable {
    case start, resume, interval, call
}

public enum SyncStatus: String, Codable {
    case upToDate = "UP_TO_DATE"
    case available = "AVAILABLE"
    case updated = "UPDATED"
    case skipped = "SKIPPED"
    case failed = "FAILED"
}

public enum SkippedReason: String, Codable {
    case incompatible = "INCOMPATIBLE"
    case notTargeted = "NOT_TARGETED"
    case notInRollout = "NOT_IN_ROLLOUT"
    case unsupportedCondition = "UNSUPPORTED_CONDITION"
    case olderThanBinary = "OLDER_THAN_BINARY"
    case channelPaused = "CHANNEL_PAUSED"
    case spendingCapReached = "SPENDING_CAP_REACHED"
    case releaseRevoked = "RELEASE_REVOKED"
    case failedBefore = "FAILED_BEFORE"
    case debugBuild = "DEBUG_BUILD"
    case meteredConnection = "METERED_CONNECTION"
}

public enum FailedReason: String, Codable {
    case offline = "OFFLINE"
    case unknownChannel = "UNKNOWN_CHANNEL"
    case invalidIndex = "INVALID_INDEX"
    case invalidSignature = "INVALID_SIGNATURE"
    case downloadFailed = "DOWNLOAD_FAILED"
    case verificationFailed = "VERIFICATION_FAILED"
}

public enum RollbackReason: String, Codable {
    case readyTimeout = "READY_TIMEOUT"
    case crashed = "CRASHED"
    case reportedByApp = "REPORTED_BY_APP"
}

public enum InstallMoment: String, Codable {
    case now
    case nextStart = "next-start"
    case onResume = "on-resume"
    case manual
}

/// One shape for `SyncResult` and `CheckResult`: the status says which fields are set.
public struct SyncResult: Codable, Equatable {
    public let status: SyncStatus
    public let release: Release?
    public let reason: String?
    public let condition: ConditionType?
    public let notes: String?
    public let installAt: InstallMoment?
    public let downloadBytes: Int?
    public let message: String?

    private init(status: SyncStatus, release: Release?, reason: String? = nil, condition: ConditionType? = nil, notes: String? = nil, installAt: InstallMoment? = nil, downloadBytes: Int? = nil, message: String? = nil) {
        self.status = status
        self.release = release
        self.reason = reason
        self.condition = condition
        self.notes = notes
        self.installAt = installAt
        self.downloadBytes = downloadBytes
        self.message = message
    }

    public static func upToDate(_ release: Release?) -> SyncResult {
        return SyncResult(status: .upToDate, release: release)
    }

    public static func available(_ release: Release, notes: String?, downloadBytes: Int?) -> SyncResult {
        return SyncResult(status: .available, release: release, notes: notes, downloadBytes: downloadBytes)
    }

    public static func updated(_ release: Release, notes: String?, installAt: InstallMoment) -> SyncResult {
        return SyncResult(status: .updated, release: release, notes: notes, installAt: installAt)
    }

    public static func skipped(_ release: Release?, reason: SkippedReason, condition: ConditionType? = nil) -> SyncResult {
        return SyncResult(status: .skipped, release: release, reason: reason.rawValue, condition: condition)
    }

    public static func failed(_ release: Release?, reason: FailedReason, message: String) -> SyncResult {
        return SyncResult(status: .failed, release: release, reason: reason.rawValue, message: message)
    }
}

public struct ReadyResult: Codable, Equatable {
    public let currentRelease: Release?
    public let previousRelease: Release?
    public let isRolledBack: Bool
    public let rollbackReason: RollbackReason?
}

public struct LastCheck: Codable, Equatable {
    public let at: Date
    public let trigger: SyncTrigger
    public let result: SyncResult
}

public struct IndexState: Codable, Equatable {
    public let sequence: Int
    public let fetchedAt: Date
}

public struct StatusResult: Codable, Equatable {
    public let currentRelease: Release?
    public let nextRelease: Release?
    public let fallbackRelease: Release?
    public let embeddedBundleId: String?
    public let lastCheck: LastCheck?
    public let index: IndexState?
    public let failedBundleIds: [String]
    public let lastReportAt: Date?
}

public enum ChannelSource: String, Codable {
    case runtime, config
}

public struct ChannelResult: Codable, Equatable {
    public let id: String
    public let name: String?
    public let source: ChannelSource
}

public struct DeviceResult: Codable, Equatable {
    public let id: String
    public let platform: String
    public let binaryVersion: String
    public let binaryBuild: String
    public let osVersion: String
    public let sdkVersion: String
    public let fingerprint: String?
    public let channel: ChannelResult
    public let attributes: [String: String]
}

public struct RolledBackEvent: Codable, Equatable {
    public let from: Release
    public let to: Release?
    public let reason: RollbackReason
}
