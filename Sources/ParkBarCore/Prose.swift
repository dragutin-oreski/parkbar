import Foundation

/// Display helpers for the notes' markdown prose.
public enum Prose {
    /// Joins hard-wrapped lines into paragraphs the way markdown reads them, keeping blank lines,
    /// list items (`- `, `* `, `1. `) and their indented continuations on their own lines.
    public static func reflow(_ text: String) -> String {
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let startsBlock = trimmed.isEmpty || isListItem(trimmed) || trimmed.hasPrefix("**") || trimmed.hasPrefix("#")
            if let last = out.last, !startsBlock, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                out[out.count - 1] = last + " " + trimmed
            } else {
                out.append(trimmed.isEmpty ? "" : (isListItem(trimmed) ? trimmed : line))
            }
        }
        return out.joined(separator: "\n")
    }

    /// The prose as the panel shows it: hard-wrapped lines joined back into paragraphs, then inline
    /// markdown (bold, links, code) parsed. Nil when the parser cannot read it.
    public static func markdown(_ text: String) -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return try? AttributedString(markdown: reflow(text), options: options)
    }

    static func isListItem(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return true }
        let digits = trimmed.prefix { $0.isNumber }
        return !digits.isEmpty && trimmed.dropFirst(digits.count).hasPrefix(". ")
    }
}
