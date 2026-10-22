import AppKit
import ParkBarCore
import SwiftUI
import WidgetKit

/// The vault as last read, what the panel is showing, and every action a click can take.
@MainActor
final class AppModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case efforts = "Efforts"
        case people = "People"
        case archived = "Archived"
    }

    static let shared = AppModel(live: !CommandLine.arguments.contains("--snapshot"))

    /// Which notes folder and settings are showing: the user's, or the example notes.
    @Published private(set) var setup: NotesSetup
    /// The snapshot mode's `--notes`, which wins over the setup's folder.
    private let explicitRoot: URL?
    var root: URL { explicitRoot ?? setup.folder }
    var config: ParkBarConfig { setup.config }
    /// Whether the notes folder is in an Obsidian vault: notes then open in Obsidian.
    @Published private(set) var opensInObsidian = false
    @Published private(set) var vault: Vault
    @Published private(set) var today: Day
    @Published var tab: Tab = .efforts
    /// The effort whose detail view is open, if any.
    @Published var openEffort: String?
    /// The person whose page is open in the People tab, if any.
    @Published var openPerson: String?
    /// The last write that did not go through, shown until the next successful one.
    @Published var problem: String?
    @Published private(set) var toast: String?
    /// What the last start found left by an interrupted save, until dismissed.
    @Published var recoveryNotice: String?
    private(set) var recoveredFiles: [URL] = []

    private var watcher: FolderWatcher?
    private var clock: Timer?
    /// While the notes folder has no efforts/ yet: looks every few seconds, so the first /park shows up.
    private var waitingForFolder: Timer?
    private let live: Bool
    private var lastSnapshot: WidgetSnapshot?

    /// `root` defaults to the notes folder the config names (`$PARKBAR_NOTES` first).
    init(root: URL? = nil, live: Bool, today: Day = .today()) {
        let setup = NotesSetup(configURL: ParkBarConfig.url(environment: ProcessInfo.processInfo.environment))
        let folder = root ?? setup.folder
        self.setup = setup
        explicitRoot = root
        self.live = live
        self.today = today
        vault = Vault.load(from: folder, config: setup.config)
        opensInObsidian = Vault.obsidianVault(containing: folder) != nil
        guard live else { return }
        noteRecovery(SafeStorage.standard.reconcile())
        watch()
        // Cold, due and late all move at midnight; a few minutes late is fine.
        clock = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshToday() }
        }
        publishWidget()
        waitForFolderIfMissing()
    }

    func reload() {
        vault = Vault.load(from: root, config: config)
        opensInObsidian = Vault.obsidianVault(containing: root) != nil
        if live { today = .today() }
        publishWidget()
        if live { waitForFolderIfMissing() }
    }

    private func waitForFolderIfMissing() {
        guard !vault.hasEffortsFolder else {
            waitingForFolder?.invalidate()
            waitingForFolder = nil
            return
        }
        guard waitingForFolder == nil else { return }
        let efforts = root.appendingPathComponent(Vault.effortsFolder).path
        waitingForFolder = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard FileManager.default.fileExists(atPath: efforts) else { return }
            Task { @MainActor in
                self?.watch()
                self?.reload()
            }
        }
    }

    private func refreshToday() {
        let now = Day.today()
        if now != today { today = now; publishWidget() }
    }

    private func watch() {
        watcher = FolderWatcher(url: root) { [weak self] in self?.reload() }
    }

    // MARK: - Notes folder

    /// The example notes next to the app or in the repo it was built from, if any.
    lazy var examples: ExampleNotes? = ExampleNotes.locate(in: ExampleNotes.places())

    /// Asks for the notes folder and remembers it in `config.json`, leaving the examples. Says why instead
    /// when `$PARKBAR_NOTES` decides the folder or the config file cannot be read.
    func chooseFolder() {
        if let blocker = setup.choiceBlocker() {
            problem = blocker.description
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder that holds \(Vault.effortsFolder)/ and \(Vault.todoFile)"
        panel.directoryURL = root
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try setup.choose(folder)
            problem = nil
        } catch {
            problem = (error as? NotesSetup.ChoiceError)?.description ?? "Could not save the folder: \(error.localizedDescription)"
            return
        }
        showCurrentFolder()
    }

    /// Shows a fresh copy of the example notes, dated today, with the examples' own settings. Your own
    /// config is untouched; "Back to my notes" or choosing a folder returns to it.
    func tryExamples() {
        guard let examples else { return }
        do {
            try setup.tryExamples(examples, storage: .standard, today: .today())
            problem = nil
        } catch {
            problem = "Could not copy the example notes: \(error.localizedDescription)"
            return
        }
        showCurrentFolder()
    }

    func leaveExamples() {
        setup.leaveExamples()
        problem = nil
        showCurrentFolder()
    }

    private func showCurrentFolder() {
        waitingForFolder?.invalidate()
        waitingForFolder = nil
        openEffort = nil
        openPerson = nil
        if live { watch() }
        reload()
    }

    // MARK: - Edits

    /// Runs one edit against the vault as currently shown, then reloads whatever happened.
    /// Shows the editor's notices (skipped files, "moved to Cold") or its error; returns the error.
    @discardableResult
    func edit(_ change: (NotesEditor) throws -> [String]) -> WriteError? {
        var failure: WriteError?
        do {
            let notices = try change(NotesEditor(vault: vault))
            problem = notices.isEmpty ? nil : notices.joined(separator: " · ")
        } catch {
            failure = error as? WriteError
            problem = failure?.description ?? "Could not save; nothing was changed"
        }
        reload()
        return failure
    }

    /// Drops the dragged effort just before `before` (nil = end) within one visible list; a drop from the
    /// other list (main ↔ cold) does nothing.
    func drop(_ dragged: DraggedEffort, before: String?, within list: [String]) {
        guard dragged.name != before, list.contains(dragged.name) else { return }
        edit { try $0.drop(dragged, before: before, within: list) }
    }

    func activate(_ name: String) {
        edit { try $0.activate(name, today: today) }
    }

    // MARK: - Recovery

    /// One line naming the note an interrupted save left a version of; Show reveals the files.
    func noteRecovery(_ result: SafeStorage.Reconciled) {
        recoveredFiles = result.recovered + result.stuck
        guard let first = recoveredFiles.first else { return }
        let more = recoveredFiles.count > 1 ? " and \(recoveredFiles.count - 1) more" : ""
        let place = result.recovered.isEmpty ? " (still in pending)" : ""
        recoveryNotice = "Kept from an interrupted save: \(Self.noteName(of: first))\(more)\(place)"
    }

    /// "2026-10-22T155103-Garden shed-qj7qln.md" → "Garden shed"; a pending file keeps its name.
    static func noteName(of file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        guard let match = name.firstMatch(of: #/^\d{4}-\d{2}-\d{2}T\d{6}-(.+)-[a-z0-9]{6}$/#) else { return name }
        return String(match.1)
    }

    func revealRecovered() {
        NSWorkspace.shared.activateFileViewerSelecting(recoveredFiles)
    }

    // MARK: - Outside the app

    func copyResume(_ effort: Effort) {
        guard let command = effort.resume else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        show(toast: "Copied — paste in Terminal")
    }

    /// In Obsidian when the notes folder is in an Obsidian vault and Obsidian opens the link; otherwise
    /// in the default app for `.md` files.
    func openNote(_ effort: Effort) {
        if opensInObsidian, let url = Vault.obsidianLink(for: effort.fileURL), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(effort.fileURL)
    }

    func open(effortNamed name: String) {
        guard vault.effort(named: name) != nil else { return }
        tab = .efforts
        openEffort = name
    }

    private func show(toast text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }

    /// Writes the widget's snapshot and asks WidgetKit to redraw, but only when what it shows changed.
    /// The example notes never reach the widget, and with `$PARKBAR_SUPPORT` set the snapshot goes there.
    private func publishWidget() {
        guard live, !setup.isShowingExamples else { return }
        let destination = WidgetSnapshotStore.destination()
        let snapshot = WidgetSnapshot.make(from: vault, today: today, at: Date())
        guard snapshot.items != lastSnapshot?.items else { return }
        do {
            try WidgetSnapshotStore.write(snapshot, to: destination)
            lastSnapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            NSLog("ParkBar: widget snapshot not written: \(error)")
        }
    }
}
