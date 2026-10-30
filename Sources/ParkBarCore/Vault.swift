import Foundation

/// Everything ParkBar reads from the notes folder, at one moment.
public struct Vault: Equatable, Sendable {
    public static let effortsFolder = "efforts"
    public static let todoFile = "todo.md"

    public let root: URL
    public let efforts: [Effort]
    public let todos: [Todo]
    public let agendas: [AgendaList]
    /// Files that could not be read, as short messages for the panel.
    public let problems: [String]
    /// False when the notes folder has no `efforts/` folder: the app shows its welcome instead.
    public let hasEffortsFolder: Bool
    public let config: ParkBarConfig

    public init(root: URL, efforts: [Effort], todos: [Todo], agendas: [AgendaList], problems: [String] = [],
                hasEffortsFolder: Bool = true, config: ParkBarConfig = .default) {
        self.root = root
        self.efforts = efforts
        self.todos = todos
        self.agendas = agendas
        self.problems = problems
        self.hasEffortsFolder = hasEffortsFolder
        self.config = config
    }

    /// Reads everything it can; whatever exists but cannot be read (a folder, an effort, the todo file, an
    /// agenda list) becomes a problem the panel shows, so it never just looks empty. A missing todo file or
    /// agenda list is fine.
    public static func load(from root: URL, config: ParkBarConfig = .default, fileManager: FileManager = .default) -> Vault {
        var problems: [String] = []
        let folder = root.appendingPathComponent(effortsFolder, isDirectory: true)
        var files: [URL] = []
        let hasFolder = fileManager.fileExists(atPath: folder.path)
        if !hasFolder {
            problems.append("No \(effortsFolder)/ folder in \(root.path)")
        } else if let listed = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            files = listed
        } else {
            problems.append("Could not read the \(effortsFolder)/ folder")
        }
        func optionalText(_ name: String) -> String? {
            let url = root.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            guard let file = try? NoteFile.read(url) else {
                problems.append("Could not read \(name)")
                return nil
            }
            return file.text
        }
        let efforts: [Effort] = files
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let file = try? NoteFile.read(url) else {
                    problems.append("Could not read \(url.lastPathComponent)")
                    return nil
                }
                return Effort(fileURL: url, file: file, config: config)
            }

        let todoText = optionalText(todoFile) ?? ""
        let agendas = config.agendaLists.compactMap { list -> AgendaList? in
            optionalText(list.file).map { AgendaList(person: list.person, fileName: list.file, text: $0) }
        }
        return Vault(root: root, efforts: efforts, todos: TodoList.parse(todoText), agendas: agendas, problems: problems,
                     hasEffortsFolder: hasFolder, config: config)
    }

    // MARK: - Views over the efforts

    public func effort(named name: String) -> Effort? { efforts.first { $0.name == name } }

    /// All active efforts, top first.
    public var activeOrder: [Effort] { Ordering.activeOrder(efforts) }

    /// Active efforts that are not cold, in drag order: the main list.
    public func current(today: Day) -> [Effort] { activeOrder.filter { !isCold($0, today: today) } }

    /// Active efforts that are cold, in drag order.
    public func cold(today: Day) -> [Effort] { activeOrder.filter { isCold($0, today: today) } }

    /// Whether the effort is cold under this vault's `coldAfterDays`.
    public func isCold(_ effort: Effort, today: Day) -> Bool { effort.isCold(today: today, coldAfterDays: config.coldAfterDays) }

    /// Archived efforts, and those with a status ParkBar doesn't know, most recently updated first.
    public var archived: [Effort] {
        efforts.filter { $0.status != .active }.sorted { ($0.updated ?? Day(year: 1, month: 1, day: 1)) > ($1.updated ?? Day(year: 1, month: 1, day: 1)) }
    }

    /// 1-based place of an active effort in the drag order.
    public func rank(of name: String) -> Int? { activeOrder.firstIndex { $0.name == name }.map { $0 + 1 } }

    /// Active efforts whose target is today or already past: the menu bar number.
    public func dueOrLateCount(today: Day) -> Int {
        activeOrder.filter { [.due, .late].contains($0.targetState(today: today)) }.count
    }

    /// Open todos that link to the effort.
    public func linkedTodos(for name: String) -> [Todo] {
        todos.filter { !$0.isChecked && $0.linkedEfforts.contains(name) }
    }

    /// Open todos under `## Inbox`, in file order: listed at the top of the Efforts tab and counted in
    /// blue in the menu bar.
    public var inbox: [Todo] { todos.filter { $0.isInbox && !$0.isChecked } }

    /// The efforts a todo links to that exist, in order and once each.
    public func linkedEfforts(of todo: Todo) -> [String] {
        todo.linkedEfforts.reduce(into: []) { names, name in
            if effort(named: name) != nil, !names.contains(name) { names.append(name) }
        }
    }

    /// Open todos that link to no effort.
    public var looseTodos: [Todo] {
        let names = Set(efforts.map(\.name))
        return todos.filter { !$0.isChecked && !$0.linkedEfforts.contains(where: names.contains) }
    }

    /// The Obsidian vault the folder belongs to: the nearest folder, itself or above, with a `.obsidian`
    /// folder in it, looking along the path as given and then with symlinks resolved. Notes open in
    /// Obsidian only then; otherwise in the default app for `.md` files.
    public static func obsidianVault(containing folder: URL, fileManager: FileManager = .default) -> URL? {
        vault(above: folder.standardizedFileURL, fileManager: fileManager)
            ?? vault(above: physical(folder), fileManager: fileManager)
    }

    /// The obsidian:// link for a file in a vault, naming it by the path under which the vault holds it (as
    /// given, or with symlinks resolved). Nil when no vault holds it.
    public static func obsidianLink(for file: URL, fileManager: FileManager = .default) -> URL? {
        for path in [file.standardizedFileURL, physical(file)]
        where vault(above: path.deletingLastPathComponent(), fileManager: fileManager) != nil {
            return obsidianURL(for: path)
        }
        return nil
    }

    /// The path with every symlink resolved (`realpath`), or as given when that fails.
    static func physical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    static func vault(above folder: URL, fileManager: FileManager) -> URL? {
        var components = folder.pathComponents
        while !components.isEmpty {
            let candidate = URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true)
            var isFolder: ObjCBool = false
            let marker = candidate.appendingPathComponent(".obsidian").path
            if fileManager.fileExists(atPath: marker, isDirectory: &isFolder), isFolder.boolValue { return candidate }
            components.removeLast()
        }
        return nil
    }

    /// The obsidian:// link that opens a file in Obsidian.
    public static func obsidianURL(for file: URL) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?/")
        allowed.insert("/")
        guard let path = file.path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "obsidian://open?path=\(path)")
    }
}
