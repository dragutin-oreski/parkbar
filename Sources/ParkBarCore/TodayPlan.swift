import Foundation

/// The day's plan: a few things you mean to do today, kept in `today.md` under a heading per day.
///
///     # Today
///
///     ## 2026-11-06
///     - [ ] Review the graph pull request
///     - [x] Answer the design question
///
///     ## 2026-11-05
///     - [ ] Book the room
///
/// Items under today's date are today's plan. Open items under an earlier date (or under any other
/// heading) are left over: the panel offers to keep them for today or drop them. Ticked items from an
/// earlier day are gone from the panel, and from the file at its next write. ParkBar owns this file:
/// every write lays it out again, keeping only the checkbox lines.
public struct TodayPlan: Equatable, Sendable {
    public static let heading = "# Today"
    /// Where open items without a date go when the file is written again.
    static let undatedHeading = "Earlier"

    public struct Item: Equatable, Identifiable, Sendable {
        public let text: String
        public let isChecked: Bool
        /// The date heading above it; nil under any other heading or none.
        public let day: Day?
        /// The line index in the file, valid for the version hashed `TodayPlan.hash`.
        public let line: Int

        public var id: Int { line }
    }

    public let items: [Item]
    /// SHA-256 of the file as read; nil when there is no file yet.
    public let hash: String?

    public init(items: [Item] = [], hash: String? = nil) {
        self.items = items
        self.hash = hash
    }

    public static func parse(_ text: String, hash: String?) -> TodayPlan {
        var day: Day?
        var items: [Item] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            if line.hasPrefix("## ") {
                day = Day(String(line.dropFirst(3)))
                continue
            }
            guard let (checked, rest) = EffortBody.checkbox(in: line) else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            items.append(Item(text: text, isChecked: checked, day: day, line: i))
        }
        return TodayPlan(items: items, hash: hash)
    }

    /// Today's items, ticked or not, in file order.
    public func items(on today: Day) -> [Item] { items.filter { $0.day == today } }

    /// Open items from any other day, newest day first, undated last.
    public func leftovers(on today: Day) -> [Item] {
        let open = items.filter { $0.day != today && !$0.isChecked }
        return open.enumerated().sorted { a, b in
            switch (a.element.day, b.element.day) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// How many of today's items are ticked, and how many there are.
    public func progress(on today: Day) -> (done: Int, total: Int) {
        let mine = items(on: today)
        return (mine.filter(\.isChecked).count, mine.count)
    }

    // MARK: - Changes, as the file's new text

    /// One line of text for a new item: line breaks become spaces, ends trimmed. Nil when nothing is left.
    public static func cleaned(_ text: String) -> String? {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? nil : flat
    }

    func adding(_ text: String, today: Day) -> String {
        rendered(today: today) { current, _ in
            if let line = Self.cleaned(text) { current.append(Entry(text: line, checked: false, line: nil)) }
        }
    }

    func setting(_ item: Item, checked: Bool, today: Day) -> String {
        rendered(today: today) { current, leftovers in
            if let i = current.firstIndex(where: { $0.line == item.line }) {
                current[i].checked = checked
            } else if checked, let i = leftovers.firstIndex(where: { $0.line == item.line }) {
                // Ticking a leftover means it got done today.
                current.append(Entry(text: leftovers.remove(at: i).text, checked: true, line: nil))
            }
        }
    }

    func removing(_ item: Item, today: Day) -> String {
        rendered(today: today) { current, leftovers in
            current.removeAll { $0.line == item.line }
            leftovers.removeAll { $0.line == item.line }
        }
    }

    func keeping(_ item: Item, today: Day) -> String {
        rendered(today: today) { current, leftovers in
            guard let i = leftovers.firstIndex(where: { $0.line == item.line }) else { return }
            current.append(Entry(text: leftovers.remove(at: i).text, checked: false, line: nil))
        }
    }

    /// One of today's items while a change is worked out; `line` is nil for one the change added.
    struct Entry {
        var text: String
        var checked: Bool
        var line: Int?
    }

    /// The file laid out again after `change`: today's items first, then the open leftovers by day.
    private func rendered(today: Day, _ change: (inout [Entry], inout [Item]) -> Void) -> String {
        var current = items(on: today).map { Entry(text: $0.text, checked: $0.isChecked, line: $0.line) }
        var leftovers = leftovers(on: today)
        change(&current, &leftovers)

        var out = [Self.heading, "", "## \(today)"]
        out += current.map { "- [\($0.checked ? "x" : " ")] \($0.text)" }
        var lastGroup: String?
        for item in leftovers {
            let group = item.day?.description ?? Self.undatedHeading
            if group != lastGroup {
                out += ["", "## \(group)"]
                lastGroup = group
            }
            out.append("- [ ] \(item.text)")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
