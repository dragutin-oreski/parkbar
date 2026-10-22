import Foundation
import Testing
@testable import ParkBarCore

// Where a write may land, what a field write replaces, and how labels and defaults are read.

// MARK: Symlinked effort files

@Suite struct SymlinkBoundaryTests {
    let fields = "---\nstatus: active\npriority: 1\nnext: old\n---\nPROSE\n"

    @Test func aLinkToTheTodoFileIsNeverWritten() throws {
        let notes = try TempNotes([:])
        let todo = notes.root.appendingPathComponent("todo.md")
        try Data(fields.utf8).write(to: todo)
        try FileManager.default.createSymbolicLink(at: notes.url("A"), withDestinationURL: todo)

        #expect(throws: WriteError.notAnEffortFile(file: "A.md", target: "todo.md")) {
            try notes.editor.setTarget(Day(year: 2026, month: 11, day: 1), on: "A")
        }
        #expect(try String(contentsOf: todo, encoding: .utf8) == fields)
        #expect(WriteError.notAnEffortFile(file: "A.md", target: "todo.md").description
            == "A.md is a link to todo.md, outside efforts/; ParkBar only writes effort files, so nothing was changed")
    }

    @Test func linksToAgendaListsAndFilesOutsideTheNotesAreNeverWritten() throws {
        let notes = try TempNotes([:])
        let agenda = notes.root.appendingPathComponent("BOB-TOPICS.md")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-outside-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: outside) }
        for target in [agenda, outside] { try Data(fields.utf8).write(to: target) }
        try FileManager.default.createSymbolicLink(at: notes.url("Agenda"), withDestinationURL: agenda)
        try FileManager.default.createSymbolicLink(at: notes.url("Outside"), withDestinationURL: outside)

        for name in ["Agenda", "Outside"] {
            #expect(throws: WriteError.self) { try notes.editor.setNext("new", on: name) }
            #expect(throws: WriteError.self) { try notes.editor.archive(name) }
        }
        #expect(try String(contentsOf: agenda, encoding: .utf8) == fields)
        #expect(try String(contentsOf: outside, encoding: .utf8) == fields)
    }

    @Test func aLinkToAnotherEffortFileIsWritten() throws {
        let notes = try TempNotes(["Real": fields])
        try FileManager.default.createSymbolicLink(at: notes.url("Alias"), withDestinationURL: notes.url("Real"))
        try notes.editor.setNext("through the link", on: "Alias")
        #expect(try notes.text("Real").contains(#"next: "through the link""#))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: notes.url("Alias").path).hasSuffix("Real.md"))
    }

    @Test func aRenumberingSkipsALinkedFileWithANotice() throws {
        let notes = try TempNotes(["B": effortFile(priority: "2")])
        let todo = notes.root.appendingPathComponent("todo.md")
        try Data(effortFile(priority: "1").utf8).write(to: todo)
        try FileManager.default.createSymbolicLink(at: notes.url("A"), withDestinationURL: todo)
        let before = try Data(contentsOf: todo)

        let notices = try notes.editor.move("B", toPosition: 1)
        #expect(notices == [WriteError.notAnEffortFile(file: "A.md", target: "todo.md").description])
        #expect(try notes.text("B").contains("priority: 1\n"))
        #expect(try Data(contentsOf: todo) == before)
    }

    @Test(arguments: ["todo.md", "BOB-TOPICS.md"])
    func aReadOnlyFileLinkedToAnEffortKeepsTheEffortReadOnly(_ readOnly: String) throws {
        let notes = try TempNotes(["A": fields])
        let other = notes.root.appendingPathComponent(readOnly)
        try? FileManager.default.removeItem(at: other)
        try FileManager.default.createSymbolicLink(at: other, withDestinationURL: notes.url("A"))
        #expect(throws: WriteError.sharesAReadOnlyFile(file: "A.md", other: readOnly)) {
            try notes.editor.setNext("new", on: "A")
        }
        #expect(try notes.text("A") == fields)
        #expect(WriteError.sharesAReadOnlyFile(file: "A.md", other: "todo.md").description
            == "A.md is the same file as todo.md, which ParkBar never writes, so nothing was changed")
    }

    @Test func aHardLinkedTodoFileIsCaughtToo() throws {
        let notes = try TempNotes(["A": fields])
        let todo = notes.root.appendingPathComponent("todo.md")
        try FileManager.default.removeItem(at: todo)
        try FileManager.default.linkItem(at: notes.url("A"), to: todo)
        #expect(throws: WriteError.sharesAReadOnlyFile(file: "A.md", other: "todo.md")) { try notes.editor.archive("A") }
        #expect(try notes.text("A") == fields)
    }

    @Test func onlyRegularMarkdownFilesDirectlyInsideEffortsQualify() throws {
        let notes = try TempNotes(["A": fields])
        let efforts = notes.folder
        #expect(NotesEditor.isEffortFile(notes.url("A"), efforts: efforts))
        let nested = efforts.appendingPathComponent("sub/C.md")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(fields.utf8).write(to: nested)
        #expect(!NotesEditor.isEffortFile(nested, efforts: efforts))
        let text = efforts.appendingPathComponent("D.txt")
        try Data(fields.utf8).write(to: text)
        #expect(!NotesEditor.isEffortFile(text, efforts: efforts))
        #expect(!NotesEditor.isEffortFile(efforts.appendingPathComponent("sub"), efforts: efforts))
    }
}

// MARK: A field write replaces the whole value

@Suite struct WholeValueTests {
    @Test func aBlockValueBecomesOneQuotedLineAndEverythingElseStays() throws {
        let before = """
        ---
        status: active
        priority: 1
        next: |
          Call Bob
          # Keep this context
          Bring the paper draft
        custom:
          - preserve this
        ---
        PROSE MUST STAY

        """
        let notes = try TempNotes(["A": before])
        try notes.editor.setNext("Email", on: "A")
        #expect(try notes.text("A") == """
        ---
        status: active
        priority: 1
        next: "Email"
        custom:
          - preserve this
        ---
        PROSE MUST STAY

        """)
    }
}

// MARK: Clarify labels with notes after the names

@Suite struct ClarifyAnnotationTests {
    @Test(arguments: [
        ("Clarify with Bob (by Friday)", ["Bob"]),
        ("Clarify with Alice and Bob (22 Oct)", ["Alice", "Bob"]),
        ("Clarify with Alice + Bob [design]", ["Alice", "Bob"]),
        ("Clarify with Bob 22 Oct", ["Bob"]),
        ("Clarify with Bob on Oct 22", ["Bob"]),
        ("Clarify with Carol, 2026-10-22", ["Carol"]),
        ("Clarify with Team 2", ["Team 2"]),
        ("Clarify with Team 2 and Bob (by Friday)", ["Team 2", "Bob"]),
        ("Clarify with Floor 3 — before the move", ["Floor 3"]),
        ("Clarify with Sam Lee — before the release", ["Sam Lee"]),
        ("Clarify with Erin / Alice", ["Erin", "Alice"]),
    ])
    func namesStopAtTheAnnotation(_ label: String, _ people: [String]) {
        #expect(EffortBody.kind(of: label) == .clarify(people: people))
    }

    @Test func aDatedLabelGivesTheQuestionToThePerson() {
        let body = EffortBody(lines: ["**Clarify with Bob (22 Oct):**", "- [ ] Question"], firstLine: 0)
        #expect(body.questions.map(\.people) == [["Bob"]])
    }
}

// MARK: A new effort written with only about, next, updated and resume

@Suite struct MinimalEffortTests {
    let minimal = """
    ---
    about: "fresh from /park"
    next: "Write the first page"
    updated: 2026-10-21
    resume: "claude --resume new-thing"
    ---
    **Where I am:** started.
    """

    @Test func missingFieldsMeanActiveBottomAndNoTarget() throws {
        let notes = try TempNotes(["Ranked": effortFile(priority: "1"), "Zed new": minimal, "Another": effortFile(priority: "2")])
        let effort = try #require(notes.vault.effort(named: "Zed new"))
        #expect(effort.status == .active)
        #expect(effort.priority == nil)
        #expect(effort.target == nil && effort.targetState(today: Fixture.today) == .none)
        #expect(notes.vault.activeOrder.map(\.name) == ["Ranked", "Another", "Zed new"])
        #expect(!notes.vault.isCold(effort, today: Fixture.today))
    }

    @Test func theAppAddsAMissingFieldAsOneLineBeforeTheClosingFence() throws {
        let notes = try TempNotes(["Ranked": effortFile(priority: "1"), "New": minimal])
        try notes.editor.move("New", toPosition: 1)
        try notes.editor.setTarget(Day(year: 2026, month: 10, day: 30), on: "New")
        #expect(try notes.text("New") == """
        ---
        about: "fresh from /park"
        next: "Write the first page"
        updated: 2026-10-21
        resume: "claude --resume new-thing"
        priority: 1
        target: 2026-10-30
        ---
        **Where I am:** started.
        """)
    }
}

// MARK: Opening notes

@Suite struct ObsidianVaultTests {
    @Test func aVaultIsFoundInTheFolderOrAnyFolderAbove() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let notes = base.appendingPathComponent("vault/work/notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        #expect(Vault.obsidianVault(containing: notes) == nil)

        try FileManager.default.createDirectory(at: base.appendingPathComponent("vault/.obsidian"), withIntermediateDirectories: true)
        #expect(Vault.obsidianVault(containing: notes)?.lastPathComponent == "vault")
        try FileManager.default.createDirectory(at: notes.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        #expect(Vault.obsidianVault(containing: notes)?.lastPathComponent == "notes")
    }

    @Test func aSymlinkedNotesFolderIsFollowedToItsVault() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("vault/notes")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("efforts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("vault/.obsidian"), withIntermediateDirectories: true)
        let link = base.appendingPathComponent("elsewhere/notes")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(Vault.obsidianVault(containing: link) != nil)
        let file = link.appendingPathComponent("efforts/A.md")
        try Data("x".utf8).write(to: file)
        let url = try #require(Vault.obsidianLink(for: file)).absoluteString
        #expect(url.hasSuffix("/vault/notes/efforts/A.md"), "the link names the file where the vault holds it: \(url)")
        #expect(Vault.obsidianLink(for: base.appendingPathComponent("elsewhere")) == nil)
    }

    @Test func messagesNameNoParticularEditor() {
        let errors: [WriteError] = [
            .noFrontMatter("A.md"), .duplicateKey(file: "A.md", key: "next"),
            .partiallySaved(cause: .saveFailed("B.md"), leftChanged: ["A.md (could not write)"]),
            .keptInRecovery(file: "A.md", path: "/r/A.md"),
        ]
        #expect(errors.allSatisfy { !$0.description.contains("Obsidian") })
        #expect(!Effort.Status.unreadable.text.contains("Obsidian"))
    }
}
