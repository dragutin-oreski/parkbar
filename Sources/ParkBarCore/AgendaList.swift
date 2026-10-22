import Foundation

/// A running list of topics to go through with one person (`agendaLists` in the config), shown read-only
/// in the People tab.
public struct AgendaList: Equatable, Sendable {
    public struct Group: Equatable, Sendable {
        public let heading: String
        public let items: [String]
    }

    public let person: String
    public let fileName: String
    public let groups: [Group]

    /// Each top-level `- ` bullet becomes one item: its first bold phrase, else its first line.
    public init(person: String, fileName: String, text: String) {
        self.person = person
        self.fileName = fileName
        var groups: [Group] = []
        var heading = ""
        var items: [String] = []

        func close() {
            if !items.isEmpty { groups.append(Group(heading: heading, items: items)) }
            items = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                close()
                heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("- ") {
                items.append(Self.title(of: String(line.dropFirst(2))))
            }
        }
        close()
        self.groups = groups
    }

    public var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }

    static func title(of text: String) -> String {
        if let open = text.range(of: "**"), let close = text[open.upperBound...].range(of: "**") {
            let bold = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if !bold.isEmpty { return bold }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
