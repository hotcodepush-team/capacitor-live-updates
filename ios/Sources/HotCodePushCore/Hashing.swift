import CryptoKit
import Foundation

public enum Hashing {
    public static func sha256Hex(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(_ string: String) -> String {
        return sha256Hex(Data(string.utf8))
    }

    /// `sha256(key + '\0' + value)`, the form an attribute condition carries.
    public static func attributeHash(key: String, value: String) -> String {
        return sha256Hex(key + "\u{0}" + value)
    }

    /// The rollout bucket: a stable hash of the device id and the release id into a hundred buckets.
    public static func rolloutBucket(deviceId: String, releaseId: String) -> Int {
        let digest = SHA256.hash(data: Data((deviceId + "\u{0}" + releaseId).utf8))
        let bytes = Array(digest.prefix(4))
        let value = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        return Int(value % 100)
    }
}
