import Foundation
import Testing
@testable import ParkBarCore

// Safety probes: each test sets up one way a read or write could go wrong and asserts what should happen.

// MARK: Rollback never destroys someone else's text

@Suite struct RollbackSafetyTests {
    @Test func rollbackLeavesANewerExternalSaveAlone() throws {
        let notes = try TempNotes(["A": effortFile(priority: "1"), "B": effortFile(priority: "2"), "C": effortFile(priority: "3")])
        var editor = notes.editor
        editor.beforeWrite = { url in
            guard url.lastPathComponent == "B.md" else { return }
            // A was already written by ParkBar; Obsidian now saves A and B.
            try! Data((try! notes.text("A") + "\nNEW PRIVATE PROSE SAVED BY OBSIDIAN\n").utf8).write(to: notes.url("A"))
            try! Data((try! notes.text("B") + "\nEXTERNAL SAVE ON B\n").utf8).write(to: notes.url("B"))
        }
        #expect(throws: WriteError.partiallySaved(cause: .changedOnDisk("B.md"), leftChanged: ["A.md (changed since)"])) {
            try editor.reorder(subset: ["B", "C", "A"])
        }
        #expect(try notes.text("A").contains("NEW PRIVATE PROSE"))
        #expect(try notes.text("B").contains("EXTERNAL SAVE ON B"))
    }

    @Test func rollbackNeverRestoresOverAnotherNote() throws {
        let notes = try TempNotes(["A": effortFile(priority: "1", body: "A ORIGINAL BODY\n"),
                                   "B": effortFile(priority: "2", body: "B IRREPLACEABLE PRIVATE BODY\n")])
        var editor = notes.editor
        editor.beforeWrite = { url in
            guard url.lastPathComponent == "B.md" else { return }
            try! FileManager.default.moveItem(at: notes.url("A"), to: notes.url("Renamed A"))
            try! FileManager.default.moveItem(at: notes.url("B"), to: notes.url("A"))
        }
        #expect(throws: WriteError.partiallySaved(cause: .changedOnDisk("B.md"), leftChanged: ["A.md (changed since)"])) {
            try editor.reorder(subset: ["B", "A"])
        }
        #expect(try notes.text("A").contains("B IRREPLACEABLE PRIVATE BODY"), "the note now named A is untouched")
        #expect(try notes.text("Renamed A").contains("A ORIGINAL BODY"))
    }
}

// MARK: Fields: only the value's own lines are replaced

@Suite struct FieldLinesTests {
    @Test func commentsUnderAScalarSurvive() throws {
        let text = "---\nstatus: active\nnext: \"Call Bob\"\n  # private explanation: keep this\nupdated: 2026-10-22\n---\nBODY MUST SURVIVE\n"
        let notes = try TempNotes(["A": text])
        try notes.editor.setNext("Call Alice", on: "A")
        #expect(try notes.text("A") == text.replacingOccurrences(of: "next: \"Call Bob\"", with: "next: \"Call Alice\""))
    }

    @Test func trailingCommentsDoNotBreakDecoding() {
        let e = Effort(fileURL: URL(fileURLWithPath: "/A.md"),
                       text: "---\nstatus: \"active\" # keep open\ntarget: '2026-10-22' # today\nnext: >- # fold this\n  actual next step\npriority: 2 # mine\nabout: # nothing yet\n---\n")
        #expect(e.status == .active)
        #expect(e.target == Day(year: 2026, month: 10, day: 22))
        #expect(e.next == "actual next step")
        #expect(e.priority == 2)
        #expect(e.about == nil)
    }
}

// MARK: Body: fences, tables, label shapes

@Suite struct BodyScopeTests {
    func body(_ text: String) -> EffortBody { EffortBody(lines: text.components(separatedBy: "\n"), firstLine: 0) }

    @Test func aTableDoesNotEndTheQuestionList() {
        let b = body("**Clarify with Bob:**\n- [ ] first\n\n| Decision | Owner |\n| --- | --- |\n| A | Bob |\n\n- [ ] second")
        #expect(b.questions.map(\.text) == ["first", "second"])
    }

    @Test func aDashLabelWithoutColonHoldsInlineItems() {
        let b = body("**Clarify with Carol** — first · second")
        #expect(b.questions.map(\.text) == ["first", "second"])
        #expect(b.questions.allSatisfy { $0.people == ["Carol"] && !$0.isTickable })
    }

    @Test func nothingInsideACodeFenceIsALabelOrQuestion() {
        let b = body("**Where I am:**\n```markdown\n**Clarify with Bob:**\n- [ ] CODE EXAMPLE ONLY\n**Then:** not a then\n```\nafter")
        #expect(b.questions.isEmpty)
        #expect(b.sections.map(\.label) == ["Where I am"])
        #expect(b.latestThen == nil)
        #expect(b.latestWhereIAm?.text.contains("CODE EXAMPLE ONLY") == true)
    }

    @Test func aFencedExampleCannotBeTicked() throws {
        let notes = try TempNotes(["A": effortFile(body: "**Where I am:**\n```markdown\n**Clarify with Bob:**\n- [ ] CODE EXAMPLE ONLY\n```\n")])
        #expect(notes.vault.effort(named: "A")?.body.questions.isEmpty == true)
    }
}

// MARK: Checkbox writes

@Suite struct CheckboxSafetyTests {
    @Test func aFileWithoutFieldsIsNotTicked() throws {
        let notes = try TempNotes(["A": "**Clarify with Bob:**\n- [ ] question\n"])
        let before = try notes.bytes("A")
        let a = try #require(notes.vault.effort(named: "A"))
        let q = try #require(a.body.questions.first)
        #expect(throws: WriteError.noFrontMatter("A.md")) {
            try notes.editor.setQuestion(q, in: "A", expectedHash: a.contentHash, checked: true)
        }
        #expect(try notes.bytes("A") == before)
    }
}

// MARK: Reading: problems are visible

@Suite struct ReadProblemTests {
    @Test func invalidUTF8AndAMissingFolderAreReported() throws {
        let notes = try TempNotes([:])
        try Data([0xFF, 0xFE, 0x00]).write(to: notes.url("Bad"))
        #expect(notes.vault.efforts.isEmpty)
        #expect(notes.vault.problems == ["Could not read Bad.md"])
        #expect(!Vault.load(from: notes.root.appendingPathComponent("missing")).problems.isEmpty)
    }

    @Test func anUnreadableEffortsFolderIsReported() throws {
        let notes = try TempNotes(["A": effortFile()])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: notes.folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notes.folder.path) }
        #expect(notes.vault.efforts.isEmpty)
        #expect(notes.vault.problems == ["Could not read the \(Vault.effortsFolder)/ folder"])
    }

    @Test func anUnreadableTodoOrAgendaIsReported() throws {
        let notes = try TempNotes([:])
        try Data([0xFF, 0xFE]).write(to: notes.root.appendingPathComponent("todo.md"))
        try Data([0xC3, 0x28]).write(to: notes.root.appendingPathComponent("BOB-TOPICS.md"))
        #expect(notes.vault.todos.isEmpty)
        #expect(notes.vault.problems == ["Could not read todo.md", "Could not read BOB-TOPICS.md"])
    }

    @Test func aMissingTodoOrAgendaIsNotAProblem() throws {
        let notes = try TempNotes([:])
        try FileManager.default.removeItem(at: notes.root.appendingPathComponent("todo.md"))
        #expect(notes.vault.problems.isEmpty)
    }
}

// MARK: Widget links and snapshots

@Suite struct WidgetRobustnessTests {
    @Test(arguments: ["100% done", "literal%2Fescape", "A#B?C", "A & B + C", "café 🦊", "ends in slash%2F", "dots..", "colon: thing"])
    func oddNamesRoundTrip(_ name: String) throws {
        let url = try #require(WidgetSnapshot.url(for: name))
        #expect(WidgetSnapshot.effortName(in: url) == name)
    }

    @Test func damagedSnapshotsAndUnknownURLsAreIgnored() throws {
        let notes = try TempNotes([:])
        let snapshot = notes.root.appendingPathComponent("snapshot.json")
        for bytes in [Data(), Data([0xFF]), Data("{\"items\": [".utf8), Data("null".utf8)] {
            try bytes.write(to: snapshot)
            #expect(WidgetSnapshotStore.read(from: snapshot) == nil)
        }
        for text in ["https://effort/A", "parkbar://other/A", "parkbar://effort/"] {
            #expect(WidgetSnapshot.effortName(in: URL(string: text)!) == nil)
        }
    }
}

// MARK: The write protocol: the note path never goes missing, and no version is ever lost

/// How another program saves while ParkBar is writing the same file.
enum ExternalSave: CaseIterable, Sendable {
    /// `>>`: opens the path with O_APPEND|O_CREAT and adds a line.
    case appending
    /// Writes its full version (the original plus its edit) to a new file and renames it over the path.
    case rewritingByRename
    /// Truncates the path and writes its full version (O_TRUNC|O_CREAT).
    case rewritingInPlace
    /// Appends through a handle it opened before ParkBar started.
    case appendingThroughAnOpenHandle
}

/// One note being written while external saves are injected at chosen steps.
final class Race {
    let original = effortFile(body: "**Where I am:** ORIGINAL PROSE, first line.\nSecond line of prose.\n")
    let notes: TempNotes
    let url: URL
    let handle: FileHandle
    var markers: [String] = []
    var pathWentMissing = false

    init() throws {
        notes = try TempNotes(["A": original])
        url = notes.url("A")
        handle = try FileHandle(forWritingTo: url)
    }

    deinit { try? handle.close() }

    var recovered: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: notes.recovery, includingPropertiesForKeys: nil)) ?? []
    }

    /// Every version left: the note itself, then whatever went to recovery.
    var versions: [String] {
        ([url] + recovered).compactMap { try? String(decoding: Data(contentsOf: $0), as: UTF8.self) }
    }

    func save(_ kind: ExternalSave) {
        let marker = "EXTERNAL SAVE \(markers.count + 1) (\(kind))"
        markers.append(marker)
        let line = Data("\n\(marker)\n".utf8)
        let full = Data(original.utf8) + line
        switch kind {
        case .appending:
            let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            _ = line.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, line.count) }
            close(fd)
        case .rewritingByRename:
            try! full.write(to: url, options: .atomic)
        case .rewritingInPlace:
            let fd = open(url.path, O_WRONLY | O_TRUNC | O_CREAT, 0o644)
            _ = full.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, full.count) }
            close(fd)
        case .appendingThroughAnOpenHandle:
            _ = try! handle.seekToEnd()
            try! handle.write(contentsOf: line)
        }
    }

    /// Runs one edit, injecting `plan[step]` saves at each step, and checking at every step that the
    /// note's path exists.
    func write(_ plan: [NoteFile.ReplaceStep: [ExternalSave]]) -> WriteError? {
        var editor = notes.editor
        editor.duringWrite = { [self] _, step in
            if !FileManager.default.fileExists(atPath: url.path) { pathWentMissing = true }
            plan[step]?.forEach(save)
        }
        do {
            try editor.setNext("ParkBar's next", on: "A")
            return nil
        } catch {
            return error as? WriteError ?? .saveFailed("not a WriteError: \(error)")
        }
    }

    /// The original note (all of its fields and prose; only `next:` may differ) or a newer full version of
    /// it is somewhere: at the path or in recovery.
    var originalSurvives: Bool {
        let mustKeep = original.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("next:") }
        return versions.contains { text in
            var rest = text.components(separatedBy: "\n")[...]
            for line in mustKeep {
                guard let i = rest.firstIndex(of: line) else { return false }
                rest = rest[(i + 1)...]
            }
            return true
        }
    }

    func markerSurvives(_ marker: String) -> Bool { versions.contains { $0.contains(marker) } }
}

@Suite struct WriteProtocolTests {
    static let forwardSteps: [NoteFile.ReplaceStep] = [.checked, .prepared, .swapped, .verified]

    @Test(arguments: forwardSteps, ExternalSave.allCases)
    func anExternalSaveAtAnyStepLosesNothing(at step: NoteFile.ReplaceStep, by save: ExternalSave) throws {
        let race = try Race()
        let error = race.write([step: [save]])
        try #require(race.markers.count == 1, "the save was injected")
        #expect(!race.pathWentMissing)
        #expect(race.originalSurvives, "the original note, or a newer full version, is at the path or in recovery")
        #expect(race.markerSurvives(race.markers[0]))
        #expect(error == nil || error == .changedOnDisk("A.md"), "\(String(describing: error))")
        #expect(try FileManager.default.contentsOfDirectory(atPath: race.notes.folder.path) == ["A.md"])
    }

    /// A save before the swap makes ParkBar swap back; a second save lands while it does.
    @Test(arguments: ExternalSave.allCases)
    func aSecondSaveWhileSwappingBackLosesNothing(_ save: ExternalSave) throws {
        let race = try Race()
        let error = race.write([.prepared: [.appendingThroughAnOpenHandle], .swappedBack: [save]])
        try #require(race.markers.count == 2, "ParkBar swapped back, and the second save was injected")
        #expect(!race.pathWentMissing)
        #expect(race.originalSurvives)
        #expect(race.markerSurvives(race.markers[1]))
        if save != .rewritingByRename && save != .rewritingInPlace {
            #expect(race.markerSurvives(race.markers[0]), "a full rewrite replaces the first save by its own choice")
        }
        #expect(error == .changedOnDisk("A.md"))
    }

    /// A save into the old file makes ParkBar swap back, but our file was appended to in between: it is
    /// no longer just ours, so it goes to recovery instead of being deleted.
    @Test func aWriteBetweenTheSwapsGoesToRecovery() throws {
        let race = try Race()
        let error = race.write([.swapped: [.appendingThroughAnOpenHandle, .appending]])
        try #require(race.markers.count == 2)
        #expect(!race.pathWentMissing)
        let kept = try #require(race.recovered.first)
        guard case .keptInRecovery("A.md", let path) = error else { Issue.record("got \(String(describing: error))"); return }
        #expect(URL(fileURLWithPath: path).resolvingSymlinksInPath() == kept.resolvingSymlinksInPath())
        #expect(try race.notes.text("A").contains(race.markers[0]))
        #expect(String(decoding: try Data(contentsOf: kept), as: UTF8.self).contains(race.markers[1]))
        #expect(kept.lastPathComponent.range(of: #"-A-[a-z0-9]{6}\.md$"#, options: .regularExpression) != nil)
        #expect(race.originalSurvives)
    }

    @Test func withoutInterferenceTheWriteGoesThroughAndNothingIsKept() throws {
        let race = try Race()
        var steps: [NoteFile.ReplaceStep] = []
        var editor = race.notes.editor
        editor.duringWrite = { _, step in steps.append(step) }
        try editor.setNext("new", on: "A")
        #expect(steps == Self.forwardSteps)
        #expect(try race.notes.text("A") == race.original.replacingOccurrences(of: "next: \"Do it\"", with: "next: \"new\""))
        #expect(race.recovered.isEmpty)
    }

    @Test func aDiskWithoutAtomicSwapsIsRefused() throws {
        let notes = try TempNotes(["A": effortFile()])
        let before = try notes.bytes("A")
        #expect(throws: NoteFile.ReplaceError.swapUnsupported) {
            try NoteFile.replace(notes.url("A"), expecting: NoteFile.hash(before), with: Data("new".utf8),
                                 storage: notes.storage, exchange: { _, _ in ENOTSUP })
        }
        #expect(try notes.bytes("A") == before)
        #expect(NotesEditor.writeError(NoteFile.ReplaceError.swapUnsupported, file: "A.md", storage: notes.storage) == .swapUnsupported("A.md"))
    }

    @Test func aNoteDeletedBeforeTheSwapStaysDeleted() throws {
        let race = try Race()
        var editor = race.notes.editor
        editor.duringWrite = { [url = race.url] _, step in
            if step == .prepared { try! FileManager.default.removeItem(at: url) }
        }
        #expect(throws: WriteError.changedOnDisk("A.md")) { try editor.setNext("x", on: "A") }
        #expect(!FileManager.default.fileExists(atPath: race.url.path))
        #expect(race.recovered.isEmpty)
    }
}

// MARK: Stale clicks and drags

@Suite struct StaleActionTests {
    @Test func aStaleCheckboxClickIsRefused() throws {
        let notes = try TempNotes(["A": effortFile(body: "**Clarify with Bob:**\n- [ ] OLD QUESTION SHOWN TO USER\n")])
        let shown = try #require(notes.vault.effort(named: "A"))
        let question = try #require(shown.body.questions.first)
        let replaced = try notes.text("A").replacingOccurrences(of: "OLD QUESTION SHOWN TO USER", with: "NEW QUESTION FROM OBSIDIAN")
        try Data(replaced.utf8).write(to: notes.url("A"))
        // The watcher has reloaded the vault, but the click comes from the row drawn before.
        #expect(throws: WriteError.changedOnDisk("A.md")) {
            try notes.editor.setQuestion(question, in: "A", expectedHash: shown.contentHash, checked: true)
        }
        #expect(try notes.text("A") == replaced)
    }

    @Test func aDragAfterTheFilesWereSwappedIsRefused() throws {
        let notes = try TempNotes(["A": effortFile(priority: "1", body: "ORIGINAL A"), "B": effortFile(priority: "2", body: "ORIGINAL B"),
                                   "C": effortFile(priority: "3")])
        let dragged = DraggedEffort(try #require(notes.vault.effort(named: "A")))
        let fm = FileManager.default
        try fm.moveItem(at: notes.url("A"), to: notes.url("Swap"))
        try fm.moveItem(at: notes.url("B"), to: notes.url("A"))
        try fm.moveItem(at: notes.url("Swap"), to: notes.url("B"))
        let before = try ["A", "B", "C"].map(notes.bytes)
        let fresh = notes.vault
        #expect(throws: WriteError.changedOnDisk("A.md")) {
            var editor = NotesEditor(vault: fresh)
            editor.storage = notes.storage
            try editor.drop(dragged, before: nil, within: fresh.activeOrder.map(\.name))
        }
        #expect(try ["A", "B", "C"].map(notes.bytes) == before)
    }

    @Test func dragPayloadsRoundTripAndForeignTextIsIgnored() {
        let token = DraggedEffort(name: "Odd: name", hash: String(repeating: "ab", count: 32))
        #expect(DraggedEffort(payload: token.payload) == token)
        #expect(DraggedEffort(payload: "Laptop handover") == nil)
        #expect(DraggedEffort(payload: "parkbar-effort:nothex:A") == nil)
    }
}

// MARK: Comments among list items, text inside blocks

@Suite struct ValueLinesTests {
    @Test func commentsAmongAListsItemsStayButTheItemsGo() throws {
        let text = "---\nnext:\n  - old one\n  # keep this\n  - old two\nstatus: active\n---\nbody\n"
        #expect(try Frontmatter.setting("next", to: "\"new\"", in: text)
            == "---\nnext: \"new\"\n  # keep this\nstatus: active\n---\nbody\n")
    }

    @Test func aHashLineInsideABlockIsTextAndGoesWithIt() throws {
        let text = "---\nnext: |\n  # a heading in the text\n  more\nstatus: active\n---\n"
        #expect(try Frontmatter.setting("next", to: "\"new\"", in: text) == "---\nnext: \"new\"\nstatus: active\n---\n")
    }

    @Test func aScalarOwnsOnlyItsLine() throws {
        let text = "---\npriority: 3\n  # why 3\n- stray\nstatus: active\n---\n"
        #expect(try Frontmatter.setting("priority", to: "1", in: text) == text.replacingOccurrences(of: "priority: 3", with: "priority: 1"))
    }
}
