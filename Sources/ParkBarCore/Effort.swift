import Foundation

/// One effort file: its fields and its prose. A value read from disk at one moment.
public struct Effort: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case active
        case archived
        case other(String)
        /// The file has no readable fields block.
        case unreadable

        /// No status means active (a fresh /park file has none). Anything other than active or
        /// archived is kept as written and stays out of the drag order.
        public init(text: String?) {
            guard let text, !text.isEmpty else { self = .active; return }
            switch text.lowercased() {
            case "active": self = .active
            case "archived": self = .archived
            default: self = .other(text)
            }
        }

        public var text: String {
            switch self {
            case .active: return "active"
            case .archived: return "archived"
            case .other(let s): return s
            case .unreadable: return "fields unreadable — fix them in your editor"
            }
        }
    }

    /// The file name without `.md`.
    public let name: String
    public let fileURL: URL
    public let about: String?
    public let status: Status
    public let priority: Int?
    public let target: Day?
    public let next: String?
    public let updated: Day?
    public let resume: String?
    public let body: EffortBody
    /// SHA-256 of the file's bytes as read; a write goes ahead only while the file still has it.
    public let contentHash: String

    public var id: String { name }

    /// `fileURL` is the entry in the efforts folder (it names the effort, even when it is a symlink).
    public init(fileURL: URL, file: NoteFile, config: ParkBarConfig = .default) {
        self.init(fileURL: fileURL, text: file.text, contentHash: file.hash, config: config)
    }

    public init(fileURL: URL, text: String, contentHash: String? = nil, config: ParkBarConfig = .default) {
        let fields = Frontmatter.parse(text)
        let lines = text.components(separatedBy: "\n")
        let v = fields.values

        name = fileURL.deletingPathExtension().lastPathComponent
        self.fileURL = fileURL
        about = v["about"]
        status = fields.exists ? Status(text: v["status"]) : .unreadable
        priority = v["priority"].flatMap { Int($0) }
        target = v["target"].flatMap(Day.init)
        next = v["next"]
        updated = v["updated"].flatMap(Day.init)
        resume = v["resume"]
        body = EffortBody(lines: Array(lines[min(fields.bodyStart, lines.count)...]), firstLine: fields.bodyStart, config: config)
        self.contentHash = contentHash ?? Self.hash(text)
    }

    public static func hash(_ text: String) -> String {
        NoteFile.hash(Data(text.utf8))
    }
}

/// The fields the app is allowed to change, and how each is written.
public enum EffortField: Sendable, Equatable {
    case priority(Int?)
    case target(Day?)
    case next(String?)
    case status(Effort.Status)

    public var key: String {
        switch self {
        case .priority: return "priority"
        case .target: return "target"
        case .next: return "next"
        case .status: return "status"
        }
    }

    /// The YAML text after `key: `, or nil to leave the value empty.
    public var encoded: String? {
        switch self {
        case .priority(let p): return p.map(String.init)
        case .target(let d): return d?.description
        case .next(let s):
            guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return YAMLScalar.quoted(s.trimmingCharacters(in: .whitespaces))
        case .status(let s): return s.text
        }
    }
}
