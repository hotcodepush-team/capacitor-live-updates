import Foundation

/// The facts a device evaluates an index against.
public struct DeviceInfo: Equatable {
    public let deviceId: String
    public let binaryVersion: String
    public let binaryBuild: String
    public let osVersion: String
    public let fingerprint: String?
    public let attributes: [String: String]
    public let builtAt: Date
    public let reportedAt: Date?
    public let failedBundleIds: [String]
    public let currentRelease: Release?

    public init(deviceId: String, binaryVersion: String, binaryBuild: String, osVersion: String, fingerprint: String?, attributes: [String: String], builtAt: Date, reportedAt: Date?, failedBundleIds: [String], currentRelease: Release?) {
        self.deviceId = deviceId
        self.binaryVersion = binaryVersion
        self.binaryBuild = binaryBuild
        self.osVersion = osVersion
        self.fingerprint = fingerprint
        self.attributes = attributes
        self.builtAt = builtAt
        self.reportedAt = reportedAt
        self.failedBundleIds = failedBundleIds
        self.currentRelease = currentRelease
    }
}

public struct Skip: Equatable {
    public let reason: SkippedReason
    public let condition: ConditionType?

    public init(reason: SkippedReason, condition: ConditionType? = nil) {
        self.reason = reason
        self.condition = condition
    }
}

/// What the device should do with an index.
public enum Evaluation: Equatable {
    /// Nothing newer than what runs.
    case upToDate
    /// Take this release: newer and eligible, or the eligible release below a revoked one.
    case update(IndexRelease)
    /// Return to the embedded bundle: the running release is revoked or the directive says so.
    case revert(reason: SkippedReason)
    /// A newer release exists and this device will not take it now.
    case skipped(newest: IndexRelease, skip: Skip)
    /// The whole index is off for this device: paused or beyond the cap.
    case unavailable(reason: SkippedReason)
}

/// The shared evaluator: the same rules in TypeScript, Swift and Kotlin, proven equal by the fixture suite.
public enum Evaluator {
    public static func evaluate(_ index: ChannelIndex, device: DeviceInfo) -> Evaluation {
        if index.isPaused {
            return .unavailable(reason: .channelPaused)
        }
        if let cappedAt = index.cappedAt, device.reportedAt.map({ $0 > cappedAt }) ?? true {
            return .unavailable(reason: .spendingCapReached)
        }
        let current = device.currentRelease
        if let current = current, let directive = index.rollBackToEmbedded, current.number <= directive.aboveNumber {
            return .revert(reason: .releaseRevoked)
        }
        let releases = index.releases.sorted { $0.number > $1.number }
        if let current = current, index.revokedReleaseIds.contains(current.id) {
            let older = releases.filter { $0.number < current.number }
            for candidate in older where eligibility(of: candidate, in: index, device: device) == nil {
                return .update(candidate)
            }
            return .revert(reason: .releaseRevoked)
        }
        let newer = releases.filter { candidate in current.map { candidate.number > $0.number } ?? true }
        var firstSkip: (IndexRelease, Skip)?
        for candidate in newer {
            if let skip = eligibility(of: candidate, in: index, device: device) {
                if firstSkip == nil { firstSkip = (candidate, skip) }
                continue
            }
            return .update(candidate)
        }
        if let (newest, skip) = firstSkip {
            return .skipped(newest: newest, skip: skip)
        }
        return .upToDate
    }

    /// `nil` when the device may take the release, else why not.
    public static func eligibility(of release: IndexRelease, in index: ChannelIndex, device: DeviceInfo) -> Skip? {
        if index.revokedReleaseIds.contains(release.id) {
            return Skip(reason: .releaseRevoked)
        }
        if release.createdAt < device.builtAt {
            return Skip(reason: .olderThanBinary)
        }
        if device.failedBundleIds.contains(release.bundleId) {
            return Skip(reason: .failedBefore)
        }
        for condition in release.conditions {
            if let skip = evaluate(condition, device: device) {
                return skip
            }
        }
        if Hashing.rolloutBucket(deviceId: device.deviceId, releaseId: release.id) >= release.rollout {
            return Skip(reason: .notInRollout)
        }
        return nil
    }

    static func evaluate(_ condition: Condition, device: DeviceInfo) -> Skip? {
        switch condition {
        case .binary(let range):
            return VersionRange(range)?.contains(device.binaryVersion) == true ? nil : Skip(reason: .incompatible, condition: .binary)
        case .os(let range):
            return VersionRange(range)?.contains(device.osVersion) == true ? nil : Skip(reason: .incompatible, condition: .os)
        case .runtime:
            return Skip(reason: .incompatible, condition: .runtime)
        case .fingerprint(let hash):
            return device.fingerprint == hash ? nil : Skip(reason: .incompatible, condition: .fingerprint)
        case .device(let hashedIds):
            return hashedIds.contains(Hashing.sha256Hex(device.deviceId)) ? nil : Skip(reason: .notTargeted, condition: .device)
        case .attribute(let key, let valueSha256):
            let matches = device.attributes[key].map { Hashing.attributeHash(key: key, value: $0) == valueSha256 } ?? false
            return matches ? nil : Skip(reason: .notTargeted, condition: .attribute)
        case .unknown:
            return Skip(reason: .unsupportedCondition)
        }
    }
}
