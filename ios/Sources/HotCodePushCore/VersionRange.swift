import Foundation

/// The range subset the three evaluators share, over dotted numeric versions: comparators `>=`, `>`, `<=`, `<`, `=`,
/// a bare version as equality, `x` or `*` wildcards and partial versions as intervals, alternatives joined by `||`.
/// Anything else does not parse, and a condition that does not parse is not satisfied.
public enum VersionRange {
    private struct Comparator {
        let op: String
        let version: [Int]
    }

    /// A version's numeric components; `nil` when the string is not a dotted number.
    public static func parseVersion(_ value: String) -> [Int]? {
        let components = value.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        var parsed: [Int] = []
        for component in components {
            guard !component.isEmpty, component.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(component) else { return nil }
            parsed.append(number)
        }
        return parsed.isEmpty ? nil : parsed
    }

    /// Whether the version satisfies the range: `nil` when the range does not parse.
    /// A comparator compares only as many components as it names, so `2.4.1` matches `2.4.1.57`.
    public static func isVersionInRange(_ version: [Int], _ range: String) -> Bool? {
        var alternatives: [[Comparator]] = []
        for alternative in range.components(separatedBy: "||") {
            guard let comparators = parseAlternative(alternative) else { return nil }
            alternatives.append(comparators)
        }
        return alternatives.contains { $0.allSatisfy { isSatisfied(version, $0) } }
    }

    private static func compare(_ left: [Int], _ right: [Int], length: Int) -> Int {
        for index in 0..<length {
            let difference = (index < left.count ? left[index] : 0) - (index < right.count ? right[index] : 0)
            if difference != 0 { return difference }
        }
        return 0
    }

    private static func isSatisfied(_ version: [Int], _ comparator: Comparator) -> Bool {
        let order = compare(version, comparator.version, length: comparator.version.count)
        switch comparator.op {
        case "<": return order < 0
        case "<=": return order <= 0
        case "=": return order == 0
        case ">": return order > 0
        default: return order >= 0
        }
    }

    private static func parseAlternative(_ alternative: String) -> [Comparator]? {
        let parts = alternative.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !parts.isEmpty else { return nil }
        var comparators: [Comparator] = []
        for part in parts {
            guard let parsed = parseComparator(part) else { return nil }
            comparators.append(contentsOf: parsed)
        }
        return comparators
    }

    private static func parseComparator(_ part: String) -> [Comparator]? {
        var op: String?
        var rest = Substring(part)
        for candidate in [">=", "<=", ">", "<", "="] where rest.hasPrefix(candidate) {
            op = candidate
            rest = rest.dropFirst(candidate.count)
            break
        }
        let components = rest.drop(while: { $0.isWhitespace }).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "x" || $0 == "X" || $0 == "*" } }) else { return nil }
        let wildcardIndex = components.firstIndex { $0.allSatisfy { $0 == "x" || $0 == "X" || $0 == "*" } }
        if wildcardIndex != nil && op != nil { return nil }
        if wildcardIndex == nil && (op != nil || components.count >= 3) {
            return [Comparator(op: op ?? "=", version: components.compactMap(Int.init))]
        }
        let fixed = components.prefix(wildcardIndex ?? components.count).compactMap(Int.init)
        return intervalComparators(fixed)
    }

    /// A partial or wildcard version as the interval it names: `1.2` and `1.2.x` are `>=1.2 <1.3`, `x` is everything.
    private static func intervalComparators(_ fixed: [Int]) -> [Comparator] {
        guard !fixed.isEmpty else { return [] }
        var upper = fixed
        upper[upper.count - 1] += 1
        return [Comparator(op: ">=", version: fixed), Comparator(op: "<", version: upper)]
    }
}
