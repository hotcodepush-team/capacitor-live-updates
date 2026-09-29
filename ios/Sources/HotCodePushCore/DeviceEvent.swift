import Foundation

/// An outcome event or check event, queued in the outbox until the events endpoint acknowledges it.
public struct DeviceEvent: Codable, Equatable {
    public let type: String
    public let releaseId: String?
    public let bundleId: String?
    public let status: String?
    public let reason: String?
    public let condition: ConditionType?
    public let bytes: Int?
    public let packKind: String?
    public let fromReleaseId: String?
    public let toReleaseId: String?

    private init(type: String, releaseId: String? = nil, bundleId: String? = nil, status: String? = nil, reason: String? = nil, condition: ConditionType? = nil, bytes: Int? = nil, packKind: String? = nil, fromReleaseId: String? = nil, toReleaseId: String? = nil) {
        self.type = type
        self.releaseId = releaseId
        self.bundleId = bundleId
        self.status = status
        self.reason = reason
        self.condition = condition
        self.bytes = bytes
        self.packKind = packKind
        self.fromReleaseId = fromReleaseId
        self.toReleaseId = toReleaseId
    }

    public static func checked(releaseId: String, status: SyncStatus, reason: SkippedReason? = nil, condition: ConditionType? = nil) -> DeviceEvent {
        return DeviceEvent(type: "checked", releaseId: releaseId, status: status.rawValue, reason: reason?.rawValue, condition: condition)
    }

    public static func downloaded(releaseId: String, bundleId: String, bytes: Int, packKind: PackKind) -> DeviceEvent {
        return DeviceEvent(type: "downloaded", releaseId: releaseId, bundleId: bundleId, bytes: bytes, packKind: packKind.rawValue)
    }

    public static func applied(releaseId: String) -> DeviceEvent {
        return DeviceEvent(type: "applied", releaseId: releaseId)
    }

    public static func confirmed(releaseId: String) -> DeviceEvent {
        return DeviceEvent(type: "confirmed", releaseId: releaseId)
    }

    public static func failed(releaseId: String, reason: String) -> DeviceEvent {
        return DeviceEvent(type: "failed", releaseId: releaseId, reason: reason)
    }

    public static func rolledBack(fromReleaseId: String, toReleaseId: String?) -> DeviceEvent {
        return DeviceEvent(type: "rolledBack", fromReleaseId: fromReleaseId, toReleaseId: toReleaseId)
    }
}

public enum PackKind: String, Codable {
    case full, delta, streamed, files
}
