import Foundation

public enum FrontmatterError: Error, Equatable {
    /// Line 1 is not `---`, or the block never closes: there are no fields to edit.
    case noFrontMatter
    /// The key appears more than once, so there is no single line to edit.
    case duplicateKey(String)
}

/// The YAML block at the top of an effort file, read and edited one line at a time.
///
/// Only `key: value` lines are understood (plus `|` / `>` block scalars, read as text). Everything else
/// (lists under a key, comments, keys Obsidian adds) is carried along untouched, because the file is
/// edited line by line, never re-serialised.
public enum Frontmatter {
    public struct Parsed: Equatable {
        /// Decoded values; a key with an empty value is absent. A repeated key keeps its first value.
        public var values: [String: String]
        /// Index of the first line after the closing `---` (0 when the file has no front matter).
        public var bodyStart: Int
        /// Keys that appear more than once.
        public var duplicateKeys: Set<String>
        /// False when the file has no fields block ParkBar can read.
        public var exists: Bool { bodyStart > 0 }
    }

    /// Front matter exists only when line 1 is `---` (a byte-order mark may precede it) and it closes at
    /// the next line that is `---` from column 0. Trailing spaces, tabs and `\r` are allowed on both.
    static func fences(_ lines: [String]) -> (Int, Int)? {
        guard let first = lines.first else { return nil }
        guard isFence(first.hasPrefix("\u{FEFF}") ? String(first.dropFirst()) : first) else { return nil }
        guard let close = lines.indices.dropFirst().first(where: { isFence(lines[$0]) }) else { return nil }
        return (0, close)
    }

    static func isFence(_ line: String) -> Bool {
        line.hasPrefix("---") && line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
    }

    /// The line without its `\r`, if it has one.
    static func bare(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }

    public static func parse(_ text: String) -> Parsed {
        let lines = text.components(separatedBy: "\n")
        guard let (open, close) = fences(lines) else { return Parsed(values: [:], bodyStart: 0, duplicateKeys: []) }
        var values: [String: String] = [:]
        var seen = Set<String>(), duplicates = Set<String>()
        var i = open + 1
        while i < close {
            defer { i += 1 }
            guard let (key, raw) = keyLine(lines[i]) else { continue }
            if !seen.insert(key).inserted { duplicates.insert(key); continue }
            let end = valueEnd(lines, after: i, close: close, raw: raw)
            let value = BlockScalar(indicator: raw).map { $0.text(of: Array(lines[(i + 1)..<end])) } ?? YAMLScalar.decode(raw)
            if let value { values[key] = value }
            i = end - 1
        }
        return Parsed(values: values, bodyStart: close + 1, duplicateKeys: duplicates)
    }

    /// Returns `text` with `key`'s value set to `key: <encoded>` (or `key:` when nil). The key's old line
    /// and any lines that belonged to its value (a `|`/`>` block, or a list under an empty key) become that
    /// one line; comment lines among a list's items stay, just below it. A missing key is added just before
    /// the closing fence, with the file's own line ending.
    public static func setting(_ key: String, to encoded: String?, in text: String) throws -> String {
        var lines = text.components(separatedBy: "\n")
        guard let (open, close) = fences(lines) else { throw FrontmatterError.noFrontMatter }
        let newLine = encoded.map { "\(key): \($0)" } ?? "\(key):"
        let matches = ((open + 1)..<close).filter { keyLine(lines[$0])?.0 == key }
        guard matches.count <= 1 else { throw FrontmatterError.duplicateKey(key) }
        guard let index = matches.first else {
            lines.insert(newLine + (lines[close].hasSuffix("\r") ? "\r" : ""), at: close)
            return lines.joined(separator: "\n")
        }
        let raw = keyLine(lines[index])?.1 ?? ""
        let end = valueEnd(lines, after: index, close: close, raw: raw)
        // Inside a block scalar a `#` line is text; among a list's items it is a comment, and comments stay.
        let comments = BlockScalar(indicator: raw) != nil ? [] : lines[(index + 1)..<end].filter(isComment)
        lines.replaceSubrange(index..<end, with: [newLine + (lines[index].hasSuffix("\r") ? "\r" : "")] + comments)
        return lines.joined(separator: "\n")
    }

    /// The index just past the lines that belong to the value on line `index`. A scalar on the key's own
    /// line owns nothing below it: indented lines there are comments or someone else's, and stay. A `|`/`>`
    /// block owns its indented lines; an empty value owns the list (or nested block) under it. Blank lines
    /// count only when more of the value follows them.
    static func valueEnd(_ lines: [String], after index: Int, close: Int, raw: String) -> Int {
        let isBlock = BlockScalar(indicator: raw) != nil
        guard isBlock || YAMLScalar.decode(raw) == nil else { return index + 1 }
        func continues(_ line: String) -> Bool {
            line.first == " " || line.first == "\t" || (!isBlock && (line.hasPrefix("- ") || bare(line) == "-"))
        }
        var end = index + 1, lastContent = index + 1
        while end < close {
            let line = lines[end]
            if bare(line).trimmingCharacters(in: .whitespaces).isEmpty {
                end += 1
            } else if continues(line) {
                end += 1
                lastContent = end
            } else {
                break
            }
        }
        return lastContent
    }

    static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    /// `key: rest` at the top level (no indentation), or nil.
    static func keyLine(_ line: String) -> (String, String)? {
        guard let first = line.first, first != " ", first != "\t", first != "#", first != "-",
              let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colon])
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return (key, String(line[line.index(after: colon)...]))
    }
}

/// A `|` (literal) or `>` (folded) value whose text is on the indented lines below the key.
struct BlockScalar {
    let folded: Bool

    init?(indicator raw: String) {
        let text = YAMLScalar.withoutComment(Frontmatter.bare(raw)).trimmingCharacters(in: .whitespaces)
        guard let mark = text.first, mark == "|" || mark == ">",
              text.dropFirst().allSatisfy({ $0 == "-" || $0 == "+" || $0.isNumber }) else { return nil }
        folded = mark == ">"
    }

    /// The block's lines with their common indentation removed: joined by spaces when folded (a blank
    /// line stays a line break), by line breaks when literal. Nil when the block is empty.
    func text(of lines: [String]) -> String? {
        let rows = lines.map(Frontmatter.bare)
        let indent = rows.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        let stripped = rows.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "" : String($0.dropFirst(indent)) }
        let joined: String
        if folded {
            joined = stripped.split(separator: "", omittingEmptySubsequences: false)
                .map { $0.joined(separator: " ") }
                .joined(separator: "\n")
        } else {
            joined = stripped.joined(separator: "\n")
        }
        let result = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

/// Decoding and encoding of single YAML scalars, the subset the notes use.
public enum YAMLScalar {
    /// `"…"` (JSON-style escapes), `'…'` (`''` = `'`), or plain text, each with any trailing ` # comment`
    /// cut off. Empty values, a lone comment and `null`/`~` decode to nil. Flow collections (`[a, b]`)
    /// come back as written.
    public static func decode(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\"") {
            let quoted = closingQuote(in: text).map { String(text[...$0]) } ?? text
            if let s = try? JSONDecoder().decode(String.self, from: Data(quoted.utf8)) { return s }
            return String(quoted.dropFirst().dropLast(quoted.count > 1 && quoted.hasSuffix("\"") ? 1 : 0))
        }
        if text.hasPrefix("'") {
            let quoted = closingQuote(in: text).map { String(text[...$0]) } ?? text
            let inner = quoted.dropFirst().dropLast(quoted.count > 1 && quoted.hasSuffix("'") ? 1 : 0)
            return inner.replacingOccurrences(of: "''", with: "'")
        }
        let plain = withoutComment(text).trimmingCharacters(in: .whitespaces)
        return plain.isEmpty || plain == "~" || plain == "null" ? nil : plain
    }

    /// The closing quote of a quoted scalar that opens `text`, when only a comment (or nothing) follows it.
    static func closingQuote(in text: String) -> String.Index? {
        guard let quote = text.first, quote == "\"" || quote == "'" else { return nil }
        var i = text.index(after: text.startIndex)
        while i < text.endIndex {
            let c = text[i]
            let next = text.index(after: i)
            if quote == "\"" && c == "\\" {
                i = next < text.endIndex ? text.index(after: next) : next
                continue
            }
            if c == quote {
                if quote == "'" && next < text.endIndex && text[next] == "'" {
                    i = text.index(after: next)
                    continue
                }
                let rest = text[next...]
                let isComment = rest.first.map { $0 == " " || $0 == "\t" } == true
                    && rest.trimmingCharacters(in: .whitespaces).hasPrefix("#")
                return rest.trimmingCharacters(in: .whitespaces).isEmpty || isComment ? i : nil
            }
            i = next
        }
        return nil
    }

    /// Plain text before a comment: `#` at the start, or after a space or tab.
    static func withoutComment(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return "" }
        guard let hash = text.range(of: #"[ \t]#"#, options: .regularExpression) else { return text }
        return String(text[..<hash.lowerBound])
    }

    /// A double-quoted scalar, escaped the way JSON does it (which YAML accepts).
    public static func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) else {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return s
    }
}
