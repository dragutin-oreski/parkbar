import Foundation

public indirect enum WriteError: Error, Equatable, CustomStringConvertible {
    case unknownEffort(String)
    case changedOnDisk(String)
    case notTickable
    case noFrontMatter(String)
    case duplicateKey(file: String, key: String)
    case saveFailed(String)
    /// `cause` stopped an edit, and these files, already written, could not be put back (each with why).
    case partiallySaved(cause: WriteError, leftChanged: [String])
    /// A save slipped in while writing; a version that could not be proven redundant is kept at `path`.
    case keptInRecovery(file: String, path: String)
    /// The file's disk cannot swap files atomically, so it is never written.
    case swapUnsupported(String)
    /// ParkBar's pending folder is on another disk than the note, so it is never written.
    case otherVolume(file: String, pending: String)
    /// The effort's entry is a link to a file that is not an effort file (`target`: where it points).
    case notAnEffortFile(file: String, target: String)
    /// The effort file is also `todo.md` or an agenda list (one links to the other), which are never written.
    case sharesAReadOnlyFile(file: String, other: String)

    public var description: String {
        switch self {
        case .unknownEffort(let name): return "No effort named \(name)"
        case .changedOnDisk(let file): return "\(file) changed on disk, try again"
        case .notTickable: return "That item has no checkbox to tick"
        case .noFrontMatter(let file): return "\(file): no fields block at the top — fix it in your editor"
        case .duplicateKey(let file, let key): return "\(file): '\(key)' appears twice — fix it in your editor"
        case .saveFailed(let file): return "Could not save \(file); nothing was changed"
        case .partiallySaved(let cause, let files):
            return "Could not finish saving: \(cause.reason). Could not put back: \(files.joined(separator: ", ")) — check those files"
        case .keptInRecovery(let file, let path): return "\(file) changed on disk while saving; the other version is kept at \(path) — compare the two"
        case .swapUnsupported(let file): return "Can't save \(file) safely: its disk can't swap files atomically; nothing was changed"
        case .otherVolume(let file, let pending):
            return "Can't save \(file) safely: ParkBar's pending folder (\(pending)) is on a different disk; nothing was changed"
        case .notAnEffortFile(let file, let target):
            return "\(file) is a link to \(target), outside efforts/; ParkBar only writes effort files, so nothing was changed"
        case .sharesAReadOnlyFile(let file, let other):
            return "\(file) is the same file as \(other), which ParkBar never writes, so nothing was changed"
        }
    }

    /// What went wrong, without what it means for the rest of the edit.
    var reason: String {
        switch self {
        case .changedOnDisk(let file): return "\(file) changed on disk"
        case .saveFailed(let file): return "could not save \(file)"
        case .swapUnsupported(let file): return "\(file)'s disk can't swap files atomically"
        case .otherVolume(let file, _): return "\(file) is on a different disk from ParkBar's pending folder"
        case .notAnEffortFile(let file, _): return "\(file) links outside efforts/"
        case .sharesAReadOnlyFile(let file, let other): return "\(file) is the same file as \(other)"
        default: return description
        }
    }
}

/// What `parkbar-cli show` prints for a question and `tick` must be given back: the start of the file's
/// hash and the question's line, as `3fa2c1d94b7e:14`. A tick goes ahead only while the file still has
/// that hash, so it can never land on a question that replaced the one shown.
public struct QuestionToken: Equatable, Sendable {
    public static let hashLength = 12

    public let hashPrefix: String
    public let line: Int

    public init(fileHash: String, line: Int) {
        hashPrefix = String(fileHash.prefix(Self.hashLength))
        self.line = line
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[0].count == Self.hashLength, parts[0].allSatisfy(\.isHexDigit),
              let line = Int(parts[1]), line >= 0 else { return nil }
        hashPrefix = parts[0].lowercased()
        self.line = line
    }

    public var text: String { "\(hashPrefix):\(line)" }
}

/// The only writes ParkBar makes: a few fields per effort file and one checkbox at a time.
///
/// Each edit names the hash the file must still have: the vault's, or the one the panel showed (a popover
/// when it opened, a checkbox or a dragged row when it was drawn). Every file is checked and every new
/// text worked out before anything is written; each file is written by `NoteFile.replace`, which checks it
/// once more; any failure puts back the files already written, where they still hold what this edit wrote.
/// Methods return notices: files a renumbering had to skip, or where a reactivated effort landed.
public struct NotesEditor {
    public static let coldNotice = "moved to Cold — set a target to keep it on top"

    public let vault: Vault
    /// Test hook: called with the real file's URL just before it is checked and written.
    var beforeWrite: ((URL) -> Void)?
    /// Test hook: called at each step of writing a file (not of putting one back).
    var duringWrite: ((URL, NoteFile.ReplaceStep) -> Void)?
    /// Where a write keeps its pending files, and any version it displaced but could not prove redundant.
    public var storage = SafeStorage.standard

    public init(vault: Vault) {
        self.vault = vault
    }

    @discardableResult
    public func setTarget(_ day: Day?, on name: String, expectedHash: String? = nil) throws -> [String] {
        try run([fieldEdit(name, [.target(day)], expectedHash: expectedHash)])
    }

    @discardableResult
    public func setNext(_ text: String?, on name: String, expectedHash: String? = nil) throws -> [String] {
        try run([fieldEdit(name, [.next(text)], expectedHash: expectedHash)])
    }

    /// The visible list (the main list, or the cold one) in its new order.
    @discardableResult
    public func reorder(subset: [String]) throws -> [String] {
        try apply(order: Ordering.merge(full: vault.activeOrder.map(\.name), reorderedSubset: subset))
    }

    /// A row dropped just before `before` (nil = end) within one visible list. A row from another
    /// list (main ↔ cold) is ignored: dropping it changes nothing. The dragged file must still hash as it
    /// did when the drag started, so a rename or edit meanwhile refuses instead of moving another effort.
    @discardableResult
    public func drop(_ dragged: DraggedEffort, before: String?, within list: [String]) throws -> [String] {
        guard list.contains(dragged.name) else { return [] }
        guard let effort = vault.effort(named: dragged.name) else { throw WriteError.unknownEffort(dragged.name) }
        guard effort.contentHash == dragged.hash, (try? NoteFile.read(effort.fileURL))?.hash == dragged.hash else {
            throw WriteError.changedOnDisk(effort.fileURL.lastPathComponent)
        }
        return try reorder(subset: Ordering.moving(dragged.name, before: before, in: list))
    }

    /// Drops `name` just before `before` in the drag order (at the end when nil).
    @discardableResult
    public func move(_ name: String, before: String?) throws -> [String] {
        try apply(order: Ordering.moving(name, before: before, in: vault.activeOrder.map(\.name)))
    }

    /// Moves `name` to 1-based `position` in the drag order.
    @discardableResult
    public func move(_ name: String, toPosition position: Int) throws -> [String] {
        try apply(order: Ordering.moving(name, toPosition: position, in: vault.activeOrder.map(\.name)))
    }

    /// Archived efforts leave the drag order; the rest close up.
    @discardableResult
    public func archive(_ name: String) throws -> [String] {
        guard vault.effort(named: name) != nil else { throw WriteError.unknownEffort(name) }
        let order = vault.activeOrder.map(\.name).filter { $0 != name }
        return try apply(order: order, also: [name: [.status(.archived), .priority(nil)]])
    }

    /// A reactivated effort joins at the bottom of the drag order. Says so when it lands in Cold.
    @discardableResult
    public func activate(_ name: String, today: Day = .today()) throws -> [String] {
        guard let effort = vault.effort(named: name) else { throw WriteError.unknownEffort(name) }
        let order = vault.activeOrder.map(\.name).filter { $0 != name } + [name]
        let notices = try apply(order: order, also: [name: [.status(.active)]])
        return notices + (effort.wouldBeCold(today: today, coldAfterDays: vault.config.coldAfterDays) ? [Self.coldNotice] : [])
    }

    /// Ticks or unticks the question as the panel showed it: `expectedHash` is the hash of the file it was
    /// read from, and its line must still read exactly `question.rawLine`. Anything else is "changed on disk".
    @discardableResult
    public func setQuestion(_ question: EffortBody.Question, in name: String, expectedHash: String, checked: Bool) throws -> [String] {
        guard let effort = vault.effort(named: name) else { throw WriteError.unknownEffort(name) }
        guard question.isTickable else { throw WriteError.notTickable }
        let file = effort.fileURL.lastPathComponent
        return try run([FileEdit(effort: effort, expectedHash: expectedHash, skippable: false) { text in
            guard Frontmatter.parse(text).exists else { throw FrontmatterError.noFrontMatter }
            var lines = text.components(separatedBy: "\n")
            guard question.line < lines.count, lines[question.line] == question.rawLine else {
                throw WriteError.changedOnDisk(file)
            }
            lines[question.line] = Self.withCheckbox(question.rawLine, checked: checked)
            return lines.joined(separator: "\n")
        }])
    }

    /// The CLI's tick: the question on the token's line, only while the file still has the token's hash.
    @discardableResult
    public func setQuestion(token: QuestionToken, in name: String, checked: Bool) throws -> [String] {
        guard let effort = vault.effort(named: name) else { throw WriteError.unknownEffort(name) }
        guard effort.contentHash.hasPrefix(token.hashPrefix),
              let question = effort.body.questions.first(where: { $0.line == token.line }) else {
            throw WriteError.changedOnDisk(effort.fileURL.lastPathComponent)
        }
        return try setQuestion(question, in: name, expectedHash: effort.contentHash, checked: checked)
    }

    // MARK: - Mechanics

    struct FileEdit {
        let effort: Effort
        let expectedHash: String
        /// A renumbering side effect: if the file can't take it, skip it with a notice instead of failing.
        let skippable: Bool
        let transform: (String) throws -> String

        var fileName: String { effort.fileURL.lastPathComponent }
    }

    /// Writes priorities 1…n for `order` (only where they differ) plus any extra fields per effort.
    /// Only active efforts get numbers, so files with another status are never touched by a renumbering.
    func apply(order: [String], also extra: [String: [EffortField]] = [:]) throws -> [String] {
        let numbers = Ordering.priorities(for: order)
        var edits: [FileEdit] = []
        for effort in vault.efforts {
            let required = extra[effort.name] ?? []
            var fields = required
            if let p = numbers[effort.name], p != effort.priority { fields.append(.priority(p)) }
            if !fields.isEmpty { edits.append(try fieldEdit(effort.name, fields, skippable: required.isEmpty)) }
        }
        return try run(edits)
    }

    func fieldEdit(_ name: String, _ fields: [EffortField], expectedHash: String? = nil, skippable: Bool = false) throws -> FileEdit {
        guard let effort = vault.effort(named: name) else { throw WriteError.unknownEffort(name) }
        return FileEdit(effort: effort, expectedHash: expectedHash ?? effort.contentHash, skippable: skippable) { text in
            try fields.reduce(text) { try Frontmatter.setting($1.key, to: $1.encoded, in: $0) }
        }
    }

    func run(_ edits: [FileEdit]) throws -> [String] {
        var notices: [String] = []
        var plans: [(edit: FileEdit, file: NoteFile, bytes: Data)] = []
        let efforts = vault.root.appendingPathComponent(Vault.effortsFolder, isDirectory: true)
        let readOnly = ([Vault.todoFile] + vault.config.agendaLists.map(\.file)).compactMap { name in
            FileIdentity(vault.root.appendingPathComponent(name)).map { (name, $0) }
        }
        for edit in edits {
            guard let file = try? NoteFile.read(edit.effort.fileURL), file.hash == edit.expectedHash else {
                throw WriteError.changedOnDisk(edit.fileName)
            }
            var refusal: WriteError?
            if !Self.isEffortFile(file.url, efforts: efforts) {
                refusal = .notAnEffortFile(file: edit.fileName, target: Self.shortPath(file.url, under: vault.root))
            } else if let identity = FileIdentity(file.url), let match = readOnly.first(where: { $0.1 == identity }) {
                refusal = .sharesAReadOnlyFile(file: edit.fileName, other: match.0)
            }
            if let refusal {
                guard edit.skippable else { throw refusal }
                notices.append(refusal.description)
                continue
            }
            let text: String
            do {
                text = try edit.transform(file.text)
            } catch let error as FrontmatterError {
                let problem: WriteError
                switch error {
                case .noFrontMatter: problem = .noFrontMatter(edit.fileName)
                case .duplicateKey(let key): problem = .duplicateKey(file: edit.fileName, key: key)
                }
                guard edit.skippable else { throw problem }
                notices.append(problem.description)
                continue
            }
            if text != file.text { plans.append((edit, file, file.bytes(for: text))) }
        }

        // What this edit put where: the path and the hash of our bytes, so a rollback only ever replaces
        // exactly what we wrote, never a newer save or another note renamed onto the path.
        var written: [(url: URL, original: Data, ours: String, name: String)] = []
        for plan in plans {
            beforeWrite?(plan.file.url)
            do {
                let original = try NoteFile.replace(plan.file.url, expecting: plan.edit.expectedHash, with: plan.bytes,
                                                    storage: storage) { duringWrite?(plan.file.url, $0) }
                written.append((plan.file.url, original, NoteFile.hash(plan.bytes), plan.edit.fileName))
            } catch {
                // The same write protocol puts each back, so a newer save there is never overwritten or deleted.
                var leftChanged: [String] = []
                for w in written.reversed() {
                    do {
                        try NoteFile.replace(w.url, expecting: w.ours, with: w.original, storage: storage)
                    } catch {
                        leftChanged.insert("\(w.name) (\(Self.whyNotPutBack(error)))", at: 0)
                    }
                }
                let failure = Self.writeError(error, file: plan.edit.fileName, storage: storage)
                guard leftChanged.isEmpty else { throw WriteError.partiallySaved(cause: failure, leftChanged: leftChanged) }
                throw failure
            }
        }
        return notices
    }

    static func writeError(_ error: Error, file: String, storage: SafeStorage) -> WriteError {
        switch error as? NoteFile.ReplaceError {
        case .changed(nil): return .changedOnDisk(file)
        case .changed(let kept?): return .keptInRecovery(file: file, path: kept.path)
        case .swapUnsupported: return .swapUnsupported(file)
        case .otherVolume: return .otherVolume(file: file, pending: storage.pending.path)
        case .failed, nil: return (error as? WriteError) ?? .saveFailed(file)
        }
    }

    /// Where a write may land: a regular `.md` file directly inside the efforts folder, both with symlinks
    /// resolved. An effort entry that links anywhere else (the todo file, an agenda list, another folder)
    /// is shown but never written.
    static func isEffortFile(_ url: URL, efforts: URL) -> Bool {
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        let folder = efforts.resolvingSymlinksInPath().standardizedFileURL
        guard file.pathExtension == "md", file.deletingLastPathComponent().path == folder.path else { return false }
        return (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    /// Device and inode, after symlinks: two paths with the same identity are one file (a link or a hard link).
    struct FileIdentity: Equatable {
        let device: Int32
        let inode: UInt64

        init?(_ url: URL) {
            var info = stat()
            guard stat(url.path, &info) == 0 else { return nil }
            device = info.st_dev
            inode = info.st_ino
        }
    }

    /// `todo.md` for a file in the notes folder, else the full path with `~`.
    static func shortPath(_ file: URL, under root: URL) -> String {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let path = file.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : (path as NSString).abbreviatingWithTildeInPath
    }

    /// Why a file this edit wrote could not be put back, for the message.
    static func whyNotPutBack(_ error: Error) -> String {
        switch error as? NoteFile.ReplaceError {
        case .changed(nil): return "changed since"
        case .changed(let kept?): return "changed since; the other version is kept at \(kept.path)"
        case .swapUnsupported, .otherVolume: return "could not be written safely"
        case .failed, nil: return "could not write"
        }
    }

    static func withCheckbox(_ line: String, checked: Bool) -> String {
        guard line.hasPrefix("- ["), line.count >= 5 else { return line }
        var chars = Array(line)
        chars[3] = checked ? "x" : " "
        return String(chars)
    }
}

/// What a dragged row carries: the effort's name (its file) and the hash the file had when the drag
/// started. As drag-and-drop text: `parkbar-effort:<hash>:<name>`.
public struct DraggedEffort: Equatable, Sendable {
    static let prefix = "parkbar-effort:"

    public let name: String
    public let hash: String

    public init(name: String, hash: String) {
        self.name = name
        self.hash = hash
    }

    public init(_ effort: Effort) {
        self.init(name: effort.name, hash: effort.contentHash)
    }

    public var payload: String { "\(Self.prefix)\(hash):\(name)" }

    /// Nil for anything else dropped on the list, such as text from another app.
    public init?(payload: String) {
        guard payload.hasPrefix(Self.prefix) else { return nil }
        let rest = payload.dropFirst(Self.prefix.count)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let hash = String(rest[..<colon]), name = String(rest[rest.index(after: colon)...])
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit), !name.isEmpty else { return nil }
        self.init(name: name, hash: hash)
    }
}
