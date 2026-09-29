import Foundation

/// A dotted numeric version; missing components are zero, pre-release and build metadata are ignored.
public struct Version: Comparable, Equatable {
    public let components: [Int]

    public init?(_ text: String) {
        let core = text.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? text
        var parsed: [Int] = []
        for part in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(part) else { return nil }
            parsed.append(number)
        }
        guard !parsed.isEmpty, parsed.count <= 3 else { return nil }
        components = parsed + Array(repeating: 0, count: 3 - parsed.count)
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        return lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

/// The subset of npm's range syntax the three evaluators share: comparators, `x` wildcards, `||`.
public struct VersionRange {
    private enum Comparator {
        case greaterOrEqual(Version)
        case greater(Version)
        case lessOrEqual(Version)
        case less(Version)
        case equal(Version)

        func matches(_ version: Version) -> Bool {
            switch self {
            case .greaterOrEqual(let bound): return version >= bound
            case .greater(let bound): return version > bound
            case .lessOrEqual(let bound): return version <= bound
            case .less(let bound): return version < bound
            case .equal(let bound): return version == bound
            }
        }
    }

    private let alternatives: [[Comparator]]

    public init?(_ text: String) {
        var alternatives: [[Comparator]] = []
        for alternative in text.components(separatedBy: "||") {
            var comparators: [Comparator] = []
            for token in alternative.split(separator: " ") {
                guard let parsed = VersionRange.parse(String(token)) else { return nil }
                comparators.append(contentsOf: parsed)
            }
            alternatives.append(comparators)
        }
        self.alternatives = alternatives
    }

    public func contains(_ version: Version) -> Bool {
        return alternatives.contains { comparators in comparators.allSatisfy { $0.matches(version) } }
    }

    public func contains(_ text: String) -> Bool {
        guard let version = Version(text) else { return false }
        return contains(version)
    }

    private static func parse(_ token: String) -> [Comparator]? {
        let operators: [(String, (Version) -> Comparator)] = [(">=", { .greaterOrEqual($0) }), ("<=", { .lessOrEqual($0) }), (">", { .greater($0) }), ("<", { .less($0) }), ("=", { .equal($0) })]
        for (op, make) in operators where token.hasPrefix(op) {
            guard let version = Version(String(token.dropFirst(op.count))) else { return nil }
            return [make(version)]
        }
        return wildcard(token)
    }

    /// `2`, `2.x`, `2.*`, `2.4.x`: the range of every version with that prefix; `1.2.3` alone is exact.
    private static func wildcard(_ token: String) -> [Comparator]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let fixed = parts.prefix { $0 != "x" && $0 != "X" && $0 != "*" }
        guard fixed.count > 0, fixed.count <= 3, fixed.allSatisfy({ Int($0) != nil }) else { return nil }
        let numbers = fixed.compactMap(Int.init)
        if numbers.count == 3 && parts.count == 3 {
            guard let version = Version(token) else { return nil }
            return [.equal(version)]
        }
        let lower = numbers + Array(repeating: 0, count: 3 - numbers.count)
        var upper = lower
        upper[numbers.count - 1] += 1
        for index in numbers.count..<3 { upper[index] = 0 }
        guard let lowerVersion = Version(lower.map(String.init).joined(separator: ".")), let upperVersion = Version(upper.map(String.init).joined(separator: ".")) else { return nil }
        return [.greaterOrEqual(lowerVersion), .less(upperVersion)]
    }
}
