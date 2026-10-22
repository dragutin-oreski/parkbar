import Foundation
import ParkBarCore

/// Headless access to the vault: read what the panel would show, and make the same narrow edits.
@main
struct CLI {
    static let usage = """
    parkbar-cli [--notes DIR] [--config FILE] <command>

      list                          efforts in the order the panel shows them (active, cold, archived)
      show <name>                   one effort: fields, where I am, questions, then, linked todos
      people                        everyone with open questions, waiting items or an agenda list
      set-target <name> <YYYY-MM-DD|none>
      set-next <name> <text|none>
      move <name> <position>        1 = top of the drag order
      archive <name>
      activate <name>
      tick <name> <token> / untick <name> <token>   (tokens from `show`; refused once the file changed)
      config                        where the config file is, and the settings in effect

    The notes folder is --notes, else $PARKBAR_NOTES, else notesFolder in the config file, else ~/Documents/ParkBar.
    The config file is --config, else config.json in $PARKBAR_SUPPORT or ~/Library/Application Support/ParkBar.
    If --config cannot be used (missing, unreadable, not valid JSON, or a bad notesFolder), commands that
    change notes refuse to run unless --notes names the folder; the others go on with a warning.
    """

    static let changesNotes: Set = ["set-target", "set-next", "move", "archive", "activate", "tick", "untick"]

    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        /// Takes `--flag VALUE` out of the arguments. A flag without its value stops the run: skipping it
        /// would send a write to whatever folder the defaults name (`--config $EMPTY` in a script).
        func option(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag) else { return nil }
            guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else { fail("\(flag) needs a value.\n\n\(usage)") }
            defer { args.removeSubrange(i...(i + 1)) }
            return args[i + 1]
        }
        let notesOption = option("--notes")
        let configOption = option("--config").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let configURL = configOption ?? ParkBarConfig.url(environment: ProcessInfo.processInfo.environment)
        let loaded = ParkBarConfig.load(from: configURL)
        loaded.problems.forEach { FileHandle.standardError.write(Data("! \($0)\n".utf8)) }
        let config = loaded.config
        let root = notesOption.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? config.notesURL()
        guard let command = args.first else { fail(usage) }
        let rest = Array(args.dropFirst())
        // An explicit --config that can't be used must not send a write to whatever folder the defaults name.
        if let configOption, notesOption == nil, !loaded.isUsable {
            let why: String
            switch loaded.file {
            case .missing: why = "no such file"
            case .unreadable(let reason): why = reason
            case .read: why = "its notesFolder is not a folder path"
            }
            if changesNotes.contains(command) {
                fail("Could not use --config \(configOption.path) (\(why)), so no notes were changed. Fix it, or name the folder with --notes.")
            }
            FileHandle.standardError.write(Data("! could not use --config \(configOption.path) (\(why)); reading \(root.path)\n".utf8))
        }
        if command == "config" { return showConfig(config, at: configURL, root: root) }
        let vault = Vault.load(from: root, config: config)
        let today = Day.today()
        vault.problems.forEach { FileHandle.standardError.write(Data("! \($0)\n".utf8)) }
        let reconciled = SafeStorage.standard.reconcile()
        reconciled.recovered.forEach { FileHandle.standardError.write(Data("! recovered after an interrupted save: \($0.path)\n".utf8)) }
        reconciled.stuck.forEach { FileHandle.standardError.write(Data("! left from an interrupted save (could not move to recovery): \($0.path)\n".utf8)) }

        do {
            var notices: [String] = []
            defer { notices.forEach { print("note: \($0)") } }
            switch command {
            case "list": list(vault, today: today)
            case "show": try show(effort(vault, rest), vault: vault, today: today)
            case "people": people(vault)
            case "set-target":
                let value = try argument(rest, 1)
                let day: Day? = value == "none" ? nil : try Day(value).orThrow("not a YYYY-MM-DD day: \(value)")
                notices = try NotesEditor(vault: vault).setTarget(day, on: effort(vault, rest).name)
            case "set-next":
                let value = try argument(rest, 1)
                notices = try NotesEditor(vault: vault).setNext(value == "none" ? nil : value, on: effort(vault, rest).name)
            case "move":
                let position = try Int(argument(rest, 1)).orThrow("position must be a number")
                notices = try NotesEditor(vault: vault).move(effort(vault, rest).name, toPosition: position)
            case "archive": notices = try NotesEditor(vault: vault).archive(effort(vault, rest).name)
            case "activate": notices = try NotesEditor(vault: vault).activate(effort(vault, rest).name, today: today)
            case "tick", "untick":
                let e = try effort(vault, rest)
                let token = try QuestionToken(argument(rest, 1)).orThrow("give the question's token from `show`, like 3fa2c1d94b7e:14")
                notices = try NotesEditor(vault: vault).setQuestion(token: token, in: e.name, checked: command == "tick")
            default: fail(usage)
            }
        } catch {
            fail("\(error)")
        }
    }

    static func list(_ vault: Vault, today: Day) {
        func row(_ e: Effort, _ rank: String) {
            let target = Labels.target(e.target, today: today).padding(toLength: 13, withPad: " ", startingAt: 0)
            print("\(rank) \(e.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(target) \(e.next ?? "")")
        }
        print("ACTIVE (\(vault.current(today: today).count)) — due or late: \(vault.dueOrLateCount(today: today))")
        vault.current(today: today).forEach { row($0, rank(vault, $0)) }
        print("COLD (\(vault.cold(today: today).count))")
        vault.cold(today: today).forEach { row($0, rank(vault, $0)) }
        print("ARCHIVED (\(vault.archived.count))")
        vault.archived.forEach { row($0, "  ") }
    }

    static func rank(_ vault: Vault, _ e: Effort) -> String {
        String(vault.rank(of: e.name) ?? 0).leftPadded(2)
    }

    static func show(_ e: Effort, vault: Vault, today: Day) {
        print("\(e.name) — \(e.about ?? "")")
        print("status \(e.status.text) · priority \(e.priority.map(String.init) ?? "—") · target \(Labels.target(e.target, today: today)) · updated \(Labels.updated(e.updated, today: today))")
        print("next: \(e.next ?? "—")")
        print("resume: \(e.resume ?? "—")")
        if let w = e.body.latestWhereIAm { print("\n[\(w.label)] \(w.text)") }
        if !e.body.questions.isEmpty { print("\nQuestions:") }
        for (i, q) in e.body.questions.enumerated() {
            let token = q.isTickable ? "  (token \(QuestionToken(fileHash: e.contentHash, line: q.line).text))" : ""
            print("  \(i + 1). \(q.isTickable ? (q.isChecked ? "[x]" : "[ ]") : " • ") \(q.people.joined(separator: " + ")): \(q.text)\(token)")
        }
        if let t = e.body.latestThen { print("\n[\(t.label)] \(t.text)") }
        let todos = vault.linkedTodos(for: e.name)
        if !todos.isEmpty { print("\nTodos:") }
        todos.forEach { print("  - \($0.text)") }
    }

    static func people(_ vault: Vault) {
        for p in vault.people() {
            print("\(p.name) — \(p.questions.count) questions, \(p.waiting.count) waiting, agenda \(p.agenda.map { "\($0.itemCount) items" } ?? "none")")
            for group in p.questionsByEffort {
                print("  \(group.effort)")
                group.questions.forEach { print("    \($0.isTickable ? "☐" : "•") \($0.text)") }
            }
            p.waiting.forEach { print("  ⏳ \($0.text)") }
        }
    }

    static func showConfig(_ config: ParkBarConfig, at url: URL, root: URL) {
        let exists = FileManager.default.fileExists(atPath: url.path)
        print("config file: \(url.path)\(exists ? "" : " (not there; using the defaults)")")
        if !(ProcessInfo.processInfo.environment[ParkBarConfig.environmentKey] ?? "").isEmpty {
            print("(\(ParkBarConfig.environmentKey) is set and decides the notes folder unless --notes is given)")
        }
        print("notes folder: \(root.path)")
        print("me: \(config.meName) · my labels: \(config.meLabels.joined(separator: ", ")) · cold after \(config.coldAfterDays) days")
        print("agenda lists: \(config.agendaLists.isEmpty ? "none" : config.agendaLists.map { "\($0.file) → \($0.person)" }.joined(separator: ", "))")
    }

    static func effort(_ vault: Vault, _ rest: [String]) throws -> Effort {
        let name = try argument(rest, 0)
        return try vault.effort(named: name).orThrow("no effort named \(name)")
    }

    static func argument(_ rest: [String], _ i: Int) throws -> String {
        try rest[safe: i].orThrow(usage)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

extension Optional {
    func orThrow(_ message: String) throws -> Wrapped {
        guard let value = self else { throw CLIError(description: message) }
        return value
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension String {
    func leftPadded(_ width: Int) -> String { String(repeating: " ", count: max(0, width - count)) + self }
}
