import Foundation

/// The prose under an effort's fields, split at its bold labels (`**Where I am:**`, `**Then:**`, …).
/// Nothing is dropped: `text` is the whole body as written, and the sections only point into it.
public struct EffortBody: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case whereIAm
        case clarify(people: [String])
        /// A label from the config's `meLabels` ("Decide myself" by default): items that are yours.
        case decideMyself
        case then
        case other
    }

    public struct Section: Equatable, Sendable {
        public let kind: Kind
        /// The label as written, without the asterisks and colon: "Where I am (22 Oct)".
        public let label: String
        /// Text after the label on its line plus the lines up to the next label, trimmed.
        public let text: String
    }

    /// Something to ask a person (or to decide myself): a checkbox, or an inline "a · b" item.
    public struct Question: Equatable, Identifiable, Sendable {
        /// The line index in the whole file; stable for one read of the file.
        public let line: Int
        public let people: [String]
        /// The text: a checkbox's first paragraph with its continuation lines joined, or one inline item.
        public let text: String
        public let isChecked: Bool
        /// The line exactly as read, so a write can confirm it is still there.
        public let rawLine: String
        /// False for inline items ("a · b" after a label): there is no checkbox to flip.
        public var isTickable: Bool = true
        /// The inline item's place on its line (0 for a checkbox).
        public var item: Int = 0
        public var id: String { "\(line)#\(item)" }
    }

    public let text: String
    public let sections: [Section]
    public let questions: [Question]
    public let refs: String?

    public var latestWhereIAm: Section? { sections.last { $0.kind == .whereIAm } }
    public var latestThen: Section? { sections.last { $0.kind == .then } }

    /// Parses `lines` (the body only); `firstLine` is the index of `lines[0]` in the whole file. `config`
    /// says whose "Decide myself" items are and which labels mean that.
    ///
    /// Code fences are found first, across the whole body: nothing inside one is a label, `refs:` line or
    /// question (it stays in its section's text). An unclosed fence runs to the end, as Obsidian shows it.
    /// Under a question label the list runs while the next non-blank line is a checkbox, a fenced block,
    /// a column-0 table row or an indented line belonging to the item above. Other column-0 prose or any
    /// bold-led line ends it. Text right after the label, up to the first blank line, holds inline items
    /// split on " · ", unless it ends with a colon (then it only introduces the list).
    public init(lines: [String], firstLine: Int, config: ParkBarConfig = .default) {
        text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [Section] = []
        var questions: [Question] = []
        var refs: String?

        var current: (kind: Kind, label: String, lines: [String], line: Int, raw: String)?
        var inline: [String]?
        var pending: (index: Int, checked: Bool, parts: [String], raw: String)?
        var collecting = false
        var listOpen = false
        let fenced = Self.fencedLines(lines)

        func people(_ kind: Kind?) -> [String]? {
            switch kind {
            case .clarify(let names): return names
            case .decideMyself: return [config.meName]
            default: return nil
            }
        }

        func flushQuestion() {
            if let p = pending, let who = people(current?.kind) {
                questions.append(Question(line: firstLine + p.index, people: who,
                                          text: p.parts.joined(separator: " "), isChecked: p.checked, rawLine: p.raw))
            }
            pending = nil
            collecting = false
        }

        func finishInline() {
            defer { inline = nil }
            guard let paragraph = inline, let c = current, let who = people(c.kind) else { return }
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !joined.hasSuffix(":") else { return }
            let items = joined.components(separatedBy: " · ")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "·").union(.whitespaces)) }
                .filter { !$0.isEmpty }
            for (k, item) in items.enumerated() {
                questions.append(Question(line: firstLine + c.line, people: who, text: item, isChecked: false,
                                          rawLine: c.raw, isTickable: false, item: k))
            }
        }

        func closeSection() {
            finishInline()
            flushQuestion()
            if let c = current {
                let body = c.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                sections.append(Section(kind: c.kind, label: c.label, text: body))
            }
            current = nil
        }

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if fenced[i] {
                // Code: part of the section's text, never read. It ends the item above, not the list.
                current?.lines.append(line)
                finishInline()
                flushQuestion()
                continue
            }
            if line.hasPrefix("refs:") {
                closeSection()
                refs = String(trimmed.dropFirst("refs:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if let (label, rest) = Self.label(in: line, meLabels: config.meLabels) {
                closeSection()
                current = (Self.kind(of: label, meLabels: config.meLabels), label, rest.isEmpty ? [] : [rest], i, line)
                listOpen = people(current?.kind) != nil
                if listOpen, !rest.isEmpty { inline = [rest] }
                continue
            }
            guard current != nil else { continue }
            current?.lines.append(line)
            guard people(current?.kind) != nil else { continue }

            if inline != nil {
                if trimmed.isEmpty || Self.checkbox(in: line) != nil {
                    finishInline()
                } else {
                    inline?.append(trimmed)
                    continue
                }
            }
            guard listOpen else { continue }
            if trimmed.isEmpty {
                collecting = false
            } else if let (checked, rest) = Self.checkbox(in: line) {
                flushQuestion()
                pending = (i, checked, [rest], line)
                collecting = true
            } else if line.first == " " || line.first == "\t" {
                // Part of the item above; its text is the first paragraph only, never code.
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { collecting = false }
                if collecting { pending?.parts.append(trimmed) }
            } else if line.hasPrefix("|") {
                // A table between the items: shown in the notes, not part of any question.
                flushQuestion()
            } else {
                flushQuestion()
                listOpen = false
            }
        }
        closeSection()

        self.sections = sections
        self.questions = questions
        self.refs = refs
    }

    /// A label at the start of a line: `**Label:** rest`, or `**Label** — rest` / `**Label**: rest`
    /// when the label is one ParkBar knows (so bold-led prose is not mistaken for a label).
    static func label(in line: String, meLabels: [String] = ParkBarConfig.default.meLabels) -> (String, String)? {
        guard line.hasPrefix("**") else { return nil }
        let inner = line.index(line.startIndex, offsetBy: 2)
        guard let close = line.range(of: "**", range: inner..<line.endIndex) else { return nil }
        let bold = String(line[inner..<close.lowerBound])
        guard !bold.isEmpty else { return nil }
        let after = String(line[close.upperBound...])
        if bold.hasSuffix(":") {
            return (String(bold.dropLast()), after.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Otherwise a known label followed by a colon ("**Then**: …") or a dash ("**Clarify with Bob** — …").
        let label = bold.trimmingCharacters(in: .whitespaces)
        let tail = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = tail.hasPrefix(":") || tail.first.map { "—–-".contains($0) } == true
        guard joined, kind(of: label, meLabels: meLabels) != .other else { return nil }
        // Drop the joiner before the description ("— notes:", ": a · b"), keep its own trailing colon.
        let rest = after.drop { ":—–- \t".contains($0) }.trimmingCharacters(in: .whitespacesAndNewlines)
        return (label, rest)
    }

    static func kind(of label: String, meLabels: [String] = ParkBarConfig.default.meLabels) -> Kind {
        let lower = label.lowercased()
        if lower.hasPrefix("where i am") { return .whereIAm }
        if lower.hasPrefix("then") { return .then }
        if meLabels.contains(where: { !$0.isEmpty && lower.hasPrefix($0.lowercased()) }) { return .decideMyself }
        if lower.hasPrefix("clarify with ") {
            return .clarify(people: people(in: names(in: String(label.dropFirst("clarify with ".count)))))
        }
        return .other
    }

    /// The names in a Clarify label: everything before a bracket or a dash, without a date at the end.
    /// "Bob (by Friday)" → "Bob", "Alice and Bob 22 Oct" → "Alice and Bob", "Team 2" stays "Team 2".
    static func names(in text: String) -> String {
        var cut = text
        for stop in ["(", "[", " — ", " – ", " - "] {
            if let range = cut.range(of: stop) { cut = String(cut[..<range.lowerBound]) }
        }
        if let date = cut.range(of: trailingDate, options: [.regularExpression, .caseInsensitive]) {
            cut = String(cut[..<date.lowerBound])
        }
        return cut
    }

    /// ", 2026-10-22", " 22 Oct", " on Oct 22" at the end of the names.
    static let trailingDate: String = {
        let month = #"(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sep(t(ember)?)?|oct(ober)?|nov(ember)?|dec(ember)?)\.?"#
        return #"[\s,]+(on\s+)?(\d{4}-\d{2}-\d{2}|\d{1,2}\s+"# + month + #"|"# + month + #"\s+\d{1,2})\s*$"#
    }()

    /// "Alice + Bob", "Erin / Alice", "Bob, Carol and Alice" → each name once, in order.
    static func people(in text: String) -> [String] {
        var parts = [text]
        for separator in [" + ", " / ", ",", " and ", " & "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        var seen = Set<String>()
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// For each line, whether it is a code fence or inside one. A fence opens with three or more ``` ` ```
    /// or `~` indented by at most three spaces (a backtick fence's info text has no backticks), and closes
    /// with at least as many of the same character and nothing after them.
    static func fencedLines(_ lines: [String]) -> [Bool] {
        var fenced = [Bool](repeating: false, count: lines.count)
        var open: (mark: Character, count: Int)?
        for (i, line) in lines.enumerated() {
            let indent = line.prefix { $0 == " " }.count
            let rest = line.dropFirst(indent)
            let mark = rest.first ?? " "
            let run = mark == "`" || mark == "~" ? rest.prefix { $0 == mark }.count : 0
            let info = rest.dropFirst(run)
            if let o = open {
                fenced[i] = true
                if indent <= 3, mark == o.mark, run >= o.count, info.allSatisfy(\.isWhitespace) { open = nil }
            } else if indent <= 3, run >= 3, !(mark == "`" && info.contains("`")) {
                fenced[i] = true
                open = (mark, run)
            }
        }
        return fenced
    }

    /// `- [ ] text` / `- [x] text` at the start of a line (no indentation).
    static func checkbox(in line: String) -> (Bool, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("- ["), trimmed.count >= 5 else { return nil }
        let chars = Array(trimmed)
        guard chars[4] == "]", chars.count == 5 || chars[5] == " " else { return nil }
        let mark = chars[3]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        let rest = String(chars.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        return (mark != " ", rest)
    }
}
