import Foundation

/// The user's settings, from `config.json` in ParkBar's support folder
/// (`~/Library/Application Support/ParkBar/`). Every key is optional; a missing file means the defaults.
///
/// ```json
/// {
///   "notesFolder": "~/Documents/ParkBar",
///   "agendaLists": [{ "file": "TEAM-SYNC.md", "person": "Carol" }],
///   "meName": "Me",
///   "meLabels": ["Decide myself"],
///   "coldAfterDays": 14
/// }
/// ```
///
/// Each key is read on its own: a key with the wrong type, or one ParkBar does not know, is ignored and
/// named in a problem, and every other key still applies.
public struct ParkBarConfig: Equatable, Sendable {
    /// A running list of topics for one person, shown read-only on their page in the People tab.
    public struct AgendaFile: Equatable, Sendable {
        /// File name in the notes folder, such as `TEAM-SYNC.md`.
        public var file: String
        public var person: String

        public init(file: String, person: String) {
            self.file = file
            self.person = person
        }
    }

    public static let environmentKey = "PARKBAR_NOTES"
    public static let defaultNotesFolder = "~/Documents/ParkBar"
    public static let fileName = "config.json"

    /// The notes folder (a `~` is expanded). `$PARKBAR_NOTES` wins over it.
    public var notesFolder: String?
    public var agendaLists: [AgendaFile]
    /// The person your own decisions belong to, listed first in the People tab.
    public var meName: String
    /// Labels whose questions are yours to decide (matched at the start of the label, any case).
    public var meLabels: [String]
    /// An active effort with no target goes cold after this many days without an update.
    public var coldAfterDays: Int

    public static let `default` = ParkBarConfig()

    public init(notesFolder: String? = nil, agendaLists: [AgendaFile] = [], meName: String = "Me",
                meLabels: [String] = ["Decide myself"], coldAfterDays: Int = 14) {
        self.notesFolder = notesFolder
        self.agendaLists = agendaLists
        self.meName = meName
        self.meLabels = meLabels
        self.coldAfterDays = coldAfterDays
    }

    /// The notes folder: `$PARKBAR_NOTES`, else `notesFolder`, else `~/Documents/ParkBar`.
    public func notesURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let path = environment[Self.environmentKey].flatMap { $0.isEmpty ? nil : $0 }
            ?? notesFolder.flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.defaultNotesFolder
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    // MARK: - Reading

    /// What reading `config.json` gave: the settings in effect, and whatever could not be used.
    public struct Loaded: Equatable, Sendable {
        public enum File: Equatable, Sendable {
            case missing
            case read
            /// The file exists but could not be read, or is not one JSON object: why, in a few words.
            case unreadable(String)
        }

        public var config: ParkBarConfig
        public var file: File
        /// One line per thing ignored, for the panel and the CLI.
        public var problems: [String]
        /// Known keys whose value was ignored (wrong type, or a bad list item).
        public var ignoredKeys: [String] = []

        /// Whether the file was read and says where the notes are, if it says so at all.
        public var isUsable: Bool { file == .read && !ignoredKeys.contains("notesFolder") }
    }

    /// `config.json` in the given support folder.
    public static func url(in storage: SafeStorage = .standard) -> URL {
        storage.root.appendingPathComponent(fileName)
    }

    /// `config.json` in `$PARKBAR_SUPPORT`, else in `~/Library/Application Support/ParkBar`.
    public static func url(environment: [String: String]) -> URL {
        url(in: SafeStorage.standard(environment: environment))
    }

    public static func load(from url: URL) -> Loaded {
        switch readObject(at: url) {
        case .missing:
            return Loaded(config: .default, file: .missing, problems: [])
        case .unreadable(let reason):
            let problem: String
            switch reason {
            case notJSON: problem = "\(fileName) is not valid JSON; using the defaults"
            case notObject: problem = "\(fileName) must hold one JSON object; using the defaults"
            default: problem = "Could not read \(fileName) (\(reason)); using the defaults"
            }
            return Loaded(config: .default, file: .unreadable(reason), problems: [problem])
        case .object(let object):
            let (config, problems, ignored) = decode(object)
            return Loaded(config: config, file: .read, problems: problems, ignoredKeys: ignored)
        }
    }

    static let notJSON = "not valid JSON"
    static let notObject = "not one JSON object"

    enum ReadResult {
        case missing
        case unreadable(String)
        case object([String: Any])
    }

    static func readObject(at url: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unreadable(reason(error))
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return .unreadable(notJSON) }
        guard let object = parsed as? [String: Any] else { return .unreadable(notObject) }
        return .object(object)
    }

    /// "Permission denied", from a read or write error, when the system says why.
    static func reason(_ error: Error) -> String {
        if let posix = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain {
            return String(cString: strerror(Int32(posix.code)))
        }
        return error.localizedDescription
    }

    /// The config from a JSON object, key by key (in name order), and one problem per thing it could not use.
    static func decode(_ object: [String: Any]) -> (ParkBarConfig, [String], [String]) {
        var config = ParkBarConfig()
        var problems: [String] = []
        var ignored: [String] = []
        var key = ""
        func ignore(_ what: String) {
            problems.append("\(fileName): \(what); ignored")
            if !ignored.contains(key) { ignored.append(key) }
        }

        for name in object.keys.sorted() {
            key = name
            let value = object[key]!
            switch key {
            case "notesFolder":
                guard let path = value as? String else { ignore(#""notesFolder" must be a folder path"#); continue }
                config.notesFolder = path.isEmpty ? nil : path
            case "agendaLists":
                guard let items = value as? [Any] else { ignore(#""agendaLists" must be a list of {"file", "person"}"#); continue }
                for (i, item) in items.enumerated() {
                    let entry = item as? [String: Any]
                    guard let file = entry?["file"] as? String, let person = entry?["person"] as? String,
                          !file.isEmpty, !person.isEmpty else {
                        ignore(#""agendaLists" item \#(i + 1) needs a "file" and a "person""#)
                        continue
                    }
                    config.agendaLists.append(AgendaFile(file: file, person: person))
                }
            case "meName":
                guard let name = value as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                    ignore(#""meName" must be a name"#)
                    continue
                }
                config.meName = name
            case "meLabels":
                guard let labels = value as? [String] else { ignore(#""meLabels" must be a list of labels"#); continue }
                config.meLabels = labels
            case "coldAfterDays":
                guard let days = wholeNumber(value), days >= 0 else { ignore(#""coldAfterDays" must be a whole number"#); continue }
                config.coldAfterDays = days
            default:
                problems.append("\(fileName): unknown key \"\(key)\"; ignored")
            }
        }
        return (config, problems, ignored)
    }

    /// A JSON number with no fraction; `true` and `false` are not numbers.
    static func wholeNumber(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double == double.rounded(), abs(double) < 1e9 else { return nil }
        return Int(double)
    }

    // MARK: - Saving the folder

    public enum SaveError: Error, Equatable, CustomStringConvertible {
        /// The file exists but could not be read or is not one JSON object, so it is left alone.
        case unreadable(String)
        case writeFailed(String)

        public var description: String {
            switch self {
            case .unreadable(let reason):
                return "\(ParkBarConfig.fileName) could not be read (\(reason)), so ParkBar did not change it. Fix or remove it, then choose the folder again."
            case .writeFailed(let reason):
                return "Could not save the folder in \(ParkBarConfig.fileName): \(reason)"
            }
        }
    }

    /// Writes `notesFolder` into the config file, keeping every other key as it was, and refuses to touch
    /// a file it cannot read. Returns the problems the saved file still has: keys kept but ignored.
    @discardableResult
    public static func saveNotesFolder(_ folder: URL, to url: URL) throws -> [String] {
        var object: [String: Any] = [:]
        switch readObject(at: url) {
        case .missing: break
        case .unreadable(let reason): throw SaveError.unreadable(reason)
        case .object(let existing): object = existing
        }
        object["notesFolder"] = (folder.path as NSString).abbreviatingWithTildeInPath
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
        } catch {
            throw SaveError.writeFailed(reason(error))
        }
        return load(from: url).problems
    }
}
