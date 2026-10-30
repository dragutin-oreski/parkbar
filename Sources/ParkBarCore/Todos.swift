import Foundation

/// One line of the todo file.
public struct Todo: Equatable, Identifiable, Sendable {
    /// The `## ` section it sits under: "Inbox", "Next", "Waiting", "Someday".
    public let section: String
    /// The text with the checkbox and any trailing "→ [[link]]" pointers removed.
    public let text: String
    public let isChecked: Bool
    /// Names of efforts it links to with `[[Name]]` or `[[Name|alias]]`.
    public let linkedEfforts: [String]
    /// For an open item under "Waiting": who owes it ("Bob — check the login flow" → "Bob").
    public let waitingOn: String?
    public let line: Int

    public var id: Int { line }
    public var isWaiting: Bool { section.lowercased() == "waiting" && !isChecked }
    /// Whether it sits under a `## Inbox` heading (any case), ticked or not.
    public var isInbox: Bool { section.lowercased() == "inbox" }
    /// What the line shows as code, in order and once each: the commands or replies the Inbox offers to copy.
    public var codeSpans: [String] { TodoList.codeSpans(in: text) }
}

public enum TodoList {
    public static func parse(_ text: String) -> [Todo] {
        var section = ""
        var todos: [Todo] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            if line.hasPrefix("## ") {
                section = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            guard let (checked, rest) = EffortBody.checkbox(in: line) else { continue }
            let links = wikiLinks(in: rest)
            let shown = displayText(rest)
            let isWaiting = section.lowercased() == "waiting" && !checked
            todos.append(Todo(section: section, text: shown, isChecked: checked, linkedEfforts: links,
                              waitingOn: isWaiting ? person(in: shown) : nil, line: i))
        }
        return todos
    }

    /// Targets of `[[Target]]`, `[[Target|alias]]` and `[[Target#heading|alias]]`.
    static func wikiLinks(in text: String) -> [String] {
        var names: [String] = []
        var rest = Substring(text)
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            let inner = rest[open.upperBound..<close.lowerBound]
            let target = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let name = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { names.append(trimmed) }
            rest = rest[close.upperBound...]
        }
        return names
    }

    /// Drops a trailing pointer segment ("→ [[X]]", "→ details in [[X]]", …) so the line reads as a
    /// plain action. Only the last segment goes, and only when it ends in a link.
    static func displayText(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        while t.hasSuffix("]]"), let arrow = t.range(of: " → ", options: .backwards), t[arrow.upperBound...].contains("[[") {
            t = String(t[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    /// The runs the panel's markdown parse marks as code, outside links, in order and once each; blank ones
    /// are left out. Read from the same parse that draws the line, so a copy button never offers text the
    /// line does not show as code (a backtick inside a link's address or title, an unmatched one).
    static func codeSpans(in text: String) -> [String] {
        guard let parsed = Prose.markdown(text) else { return [] }
        var spans: [String] = []
        for run in parsed.runs where run.inlinePresentationIntent?.contains(.code) == true && run.link == nil {
            let span = String(parsed[run.range].characters)
            if !span.trimmingCharacters(in: .whitespaces).isEmpty, !spans.contains(span) { spans.append(span) }
        }
        return spans
    }

    /// "Bob — check …" → "Bob". Only a short, capitalised name counts.
    static func person(in text: String) -> String? {
        guard let dash = text.range(of: " — ") else { return nil }
        let name = text[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
        let words = name.split(separator: " ")
        guard (1...3).contains(words.count), name.first?.isUppercase == true else { return nil }
        return name
    }
}
