import Foundation

/// The drag order of active efforts, and how a drag turns into priority numbers.
public enum Ordering {
    /// Active efforts, top first: by priority, those without one at the bottom, then by name.
    public static func activeOrder(_ efforts: [Effort]) -> [Effort] {
        efforts.filter { $0.status == .active }.sorted { a, b in
            let pa = a.priority ?? Int.max, pb = b.priority ?? Int.max
            if pa != pb { return pa < pb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Puts a reordered visible subset back into the full order. The slots the subset occupied are
    /// refilled in its new order; everything else (the cold efforts) keeps its place.
    public static func merge(full: [String], reorderedSubset subset: [String]) -> [String] {
        let members = Set(subset)
        var queue = subset[...]
        return full.map { name in
            guard members.contains(name), let next = queue.popFirst() else { return name }
            return next
        }
    }

    /// `name` moved to just before `before` (or to the end when nil) within `list`.
    public static func moving(_ name: String, before: String?, in list: [String]) -> [String] {
        guard name != before, list.contains(name) else { return list }
        var result = list.filter { $0 != name }
        let index = before.flatMap { result.firstIndex(of: $0) } ?? result.endIndex
        result.insert(name, at: index)
        return result
    }

    /// `name` moved to 1-based `position` within `list` (clamped).
    public static func moving(_ name: String, toPosition position: Int, in list: [String]) -> [String] {
        guard list.contains(name) else { return list }
        var result = list.filter { $0 != name }
        result.insert(name, at: min(max(position - 1, 0), result.count))
        return result
    }

    /// 1…n in the given order.
    public static func priorities(for order: [String]) -> [String: Int] {
        Dictionary(order.enumerated().map { ($1, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    }
}
