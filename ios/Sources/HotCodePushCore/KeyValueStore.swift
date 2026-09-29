import Foundation

/// The platform's key-value store, one string per key; `UserDefaults` on iOS, an in-memory map in tests.
public protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

public final class UserDefaultsStore: KeyValueStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? {
        return defaults.string(forKey: key)
    }

    public func set(_ value: String?, forKey key: String) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public final class InMemoryStore: KeyValueStore {
    public private(set) var values: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        return values[key]
    }

    public func set(_ value: String?, forKey key: String) {
        values[key] = value
    }
}
