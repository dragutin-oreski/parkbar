import Darwin
import Foundation
import Testing
@testable import ParkBarCore

/// Edge cases of the parser and the editor, one suite each.

// MARK: 1. Labels the parser missed

@Suite struct LabelShapeTests {
    func body(_ lines: [String]) -> EffortBody { EffortBody(lines: lines, firstLine: 10) }

    @Test func nameInsideTheBoldAndColonLater() {
        let b = body([
            "**Where I am:** working on it.",
            "\t",
            "**Clarify with Dan** — for Thursday's tasting:",
            "",
            "- [ ] **Croissants.** How many sell on a weekday (counting only the",
            "      *plain* ones):",
            "",
            "      | day | dozens |",
            "- [ ] Taste the rye starter",
            "```",
            "- [ ] inside a code fence, not a question",
            "```",
            "- [x] Pick the menu font",
            "",
            "**Clarify with Carol** — before the new oven arrives:",
            "",
            "- [ ] Measure the kitchen door",
        ])
        #expect(b.latestWhereIAm?.text == "working on it.", "the label must not be swallowed into Where I am")
        #expect(b.questions.map(\.people) == [["Dan"], ["Dan"], ["Dan"], ["Carol"]])
        #expect(b.questions.map(\.text) == [
            "**Croissants.** How many sell on a weekday (counting only the *plain* ones):",
            "Taste the rye starter", "Pick the menu font", "Measure the kitchen door",
        ])
        #expect(b.questions.allSatisfy { $0.isTickable })
        #expect(b.questions.map(\.line) == [14, 18, 22, 26])
    }

    @Test func inlineItemsAreShownButNotTickable() {
        let b = body([
            "**Clarify with Erin / Alice:** who bakes on Sundays; who opens the shop at six",
            "",
            "**Decide myself:** a new loaf on the menu? (reply:",
            "`try the seeded rye`) · the two price changes · ",
            "",
            "**Then:** next.",
        ])
        #expect(b.questions.map(\.people) == [["Erin", "Alice"], ["Me"], ["Me"]])
        #expect(b.questions.map(\.text) == [
            "who bakes on Sundays; who opens the shop at six",
            "a new loaf on the menu? (reply: `try the seeded rye`)", "the two price changes",
        ])
        #expect(b.questions.allSatisfy { !$0.isTickable })
        #expect(Set(b.questions.map(\.id)).count == 3, "ids stay unique on one line")
        #expect(b.latestThen?.text == "next.")
    }

    @Test func configuredLabelsBelongToConfiguredName() {
        let lines = ["**Up to me (this week):**", "- [x] done one", "- [ ] open one"]
        let config = ParkBarConfig(meName: "Sam", meLabels: ["Decide myself", "Up to me"])
        let b = EffortBody(lines: lines, firstLine: 10, config: config)
        #expect(b.questions.map(\.people) == [["Sam"], ["Sam"]])
        #expect(b.questions.map(\.isChecked) == [true, false])
        #expect(b.questions.allSatisfy { $0.isTickable })
        #expect(body(lines).questions.isEmpty, "not one of the default labels")
        #expect(EffortBody(lines: ["**Decide myself:** a"], firstLine: 0, config: config).questions.map(\.people) == [["Sam"]])
    }

    @Test func peopleTabPicksUpAllShapes() {
        let text = effortFile(body: """
        **Clarify with Erin / Alice:** who orders the flour
        **Decide myself:** a · b
        **Decide myself (later):**
        - [ ] c
        """)
        let e = Effort(fileURL: URL(fileURLWithPath: "/n/efforts/X.md"), text: text)
        let people = Vault(root: URL(fileURLWithPath: "/n"), efforts: [e], todos: [], agendas: []).people()
        #expect(Set(people.map(\.name)) == ["Erin", "Alice", "Me"])
        #expect(people.first { $0.name == "Me" }?.questions.map(\.question.text) == ["a", "b", "c"])
    }

    @Test func inlineItemsCannotBeTicked() throws {
        let notes = try TempNotes(["X": effortFile(body: "**Decide myself:** a · b\n")])
        let x = try #require(notes.vault.effort(named: "X"))
        let q = try #require(x.body.questions.first)
        #expect(throws: WriteError.notTickable) { try notes.editor.setQuestion(q, in: "X", expectedHash: x.contentHash, checked: true) }
    }
}

// MARK: 2. Front matter recognition, unknown status

@Suite struct FrontMatterShapeTests {
    @Test func fencesMustBeExact() {
        #expect(Frontmatter.parse("---\nnext: a\n---\nbody").values["next"] == "a")
        #expect(Frontmatter.parse("\u{FEFF}---\nnext: a\n---\nbody").values["next"] == "a")
        #expect(Frontmatter.parse("---\r\nnext: a\r\n---\r\nbody").values["next"] == "a")
        #expect(Frontmatter.parse(" ---\nnext: a\n---\n").values.isEmpty)
        #expect(Frontmatter.parse("----\nnext: a\n---\n").values.isEmpty, "four dashes are not a fence")
        #expect(Frontmatter.parse("---\nnext: a\n  ---\nbody").values.isEmpty, "an indented fence does not close")
    }

    @Test func writingAFileWithoutFieldsIsRefused() throws {
        let notes = try TempNotes(["Plain": "**Where I am:** no fields here\n"])
        let before = try notes.bytes("Plain")
        #expect(throws: WriteError.noFrontMatter("Plain.md")) { try notes.editor.setTarget(Fixture.today, on: "Plain") }
        #expect(try notes.bytes("Plain") == before)
        #expect(WriteError.noFrontMatter("Plain.md").description.contains("Plain.md"))
    }

    @Test func unknownStatusIsKeptOutOfTheDragOrder() throws {
        let notes = try TempNotes([
            "A": effortFile(priority: "1"),
            "Paused": effortFile(priority: "2", status: "paused"),
            "B": effortFile(priority: "3"),
            "Capital": effortFile(priority: "4", status: "Active"),
        ])
        let v = notes.vault
        #expect(v.effort(named: "Paused")?.status == .other("paused"))
        #expect(v.effort(named: "Paused")?.status.text == "paused")
        #expect(v.effort(named: "Capital")?.status == .active)
        #expect(v.activeOrder.map(\.name) == ["A", "B", "Capital"])
        #expect(v.archived.map(\.name) == ["Paused"])
        let paused = try notes.bytes("Paused")
        try notes.editor.reorder(subset: ["B", "A", "Capital"])
        #expect(try notes.bytes("Paused") == paused, "renumbering never writes an unknown-status file")
        #expect(notes.vault.activeOrder.map(\.priority) == [1, 2, 3])
    }
}

// MARK: 3. Duplicate keys

@Suite struct DuplicateKeyTests {
    @Test func writingADuplicatedKeyIsRefused() throws {
        let notes = try TempNotes(["Dup": effortFile(extra: "next: \"again\"\n")])
        let before = try notes.bytes("Dup")
        #expect(throws: WriteError.duplicateKey(file: "Dup.md", key: "next")) { try notes.editor.setNext("x", on: "Dup") }
        #expect(try notes.bytes("Dup") == before)
        #expect(WriteError.duplicateKey(file: "Dup.md", key: "next").description == "Dup.md: 'next' appears twice — fix it in your editor")
    }

    @Test func renumberingSkipsTheFileAndSaysSo() throws {
        let notes = try TempNotes([
            "A": effortFile(priority: "1"),
            "Dup": effortFile(priority: "2", extra: "priority: 9\n"),
            "C": effortFile(priority: "3"),
        ])
        let dup = try notes.bytes("Dup")
        let notices = try notes.editor.reorder(subset: ["C", "A", "Dup"])
        #expect(notices == ["Dup.md: 'priority' appears twice — fix it in your editor"])
        #expect(try notes.bytes("Dup") == dup)
        #expect(notes.vault.effort(named: "C")?.priority == 1)
        #expect(notes.vault.effort(named: "A")?.priority == 2)
    }
}

// MARK: 4. All-or-nothing renumbering

@Suite struct AllOrNothingTests {
    @Test func aFileChangingMidWayRestoresTheOnesAlreadyWritten() throws {
        let notes = try TempNotes(["A": effortFile(priority: "1"), "B": effortFile(priority: "2"), "C": effortFile(priority: "3")])
        let before = try ["A", "B", "C"].map(notes.bytes)
        var editor = notes.editor
        var written = 0
        editor.beforeWrite = { url in
            written += 1
            // Obsidian saves the second file just before ParkBar gets to it.
            if written == 2 { try? Data((String(decoding: try! Data(contentsOf: url), as: UTF8.self) + "\nedited").utf8).write(to: url) }
        }
        // All three numbers change (B 2→1, C 3→2, A 1→3); files are written A, B, C.
        #expect(throws: WriteError.changedOnDisk("B.md")) { try editor.reorder(subset: ["B", "C", "A"]) }
        let after = try ["A", "B", "C"].map(notes.bytes)
        #expect(after[0] == before[0], "the file ParkBar already wrote is put back")
        #expect(String(decoding: after[1], as: UTF8.self).hasSuffix("edited"), "Obsidian's change survives")
        #expect(after[2] == before[2], "the rest is never written")
    }

    @Test func aFailedSaveIsOneReadableSentence() throws {
        let notes = try TempNotes(["A": effortFile(priority: "1"), "B": effortFile(priority: "2")])
        let editor = notes.editor
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: notes.folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notes.folder.path) }
        do {
            try editor.reorder(subset: ["B", "A"])
            Issue.record("expected the save to fail")
        } catch {
            let text = "\(error)"
            #expect(error as? WriteError == .saveFailed("A.md") || error as? WriteError == .saveFailed("B.md"))
            #expect(!text.contains("Domain=") && !text.contains("NSError") && text.contains("nothing was changed"))
        }
    }
}

// MARK: 5. Stale editors

@Suite struct StaleEditorTests {
    @Test func aPopoverSavesAgainstTheHashItOpenedWith() throws {
        let notes = try TempNotes(["A": effortFile()])
        let openedWith = try #require(notes.vault.effort(named: "A")?.contentHash)
        try notes.editor.setNext("changed elsewhere", on: "A")          // e.g. Obsidian, or /park
        let fresh = notes.editor                                        // the vault has reloaded since
        #expect(throws: WriteError.changedOnDisk("A.md")) {
            try fresh.setTarget(Fixture.today, on: "A", expectedHash: openedWith)
        }
        #expect(throws: WriteError.changedOnDisk("A.md")) {
            try fresh.setNext("mine", on: "A", expectedHash: openedWith)
        }
        #expect(notes.vault.effort(named: "A")?.next == "changed elsewhere")
    }
}

// MARK: 6. Cold rows

@Suite struct ColdListTests {
    @Test func aDropBetweenListsDoesNothing() throws {
        let notes = try TempNotes([
            "Warm": effortFile(priority: "1"),
            "Cold": effortFile(priority: "2", updated: "2026-08-01"),
            "Warm2": effortFile(priority: "3"),
        ])
        let before = try ["Warm", "Cold", "Warm2"].map(notes.bytes)
        let v = notes.vault
        try notes.editor.drop(DraggedEffort(try #require(v.effort(named: "Cold"))), before: "Warm", within: ["Warm", "Warm2"])
        #expect(try ["Warm", "Cold", "Warm2"].map(notes.bytes) == before)
        try notes.editor.drop(DraggedEffort(try #require(v.effort(named: "Warm2"))), before: "Warm", within: ["Warm", "Warm2"])
        #expect(notes.vault.activeOrder.map(\.name) == ["Warm2", "Cold", "Warm"], "within a list the cold slot is kept")
    }

    @Test func reactivatingIntoColdSaysSo() throws {
        let notes = try TempNotes([
            "Old": effortFile(priority: "", status: "archived", updated: "2026-08-01"),
            "Recent": effortFile(priority: "", status: "archived", updated: "2026-10-21"),
        ])
        #expect(try notes.editor.activate("Old", today: Fixture.today) == [NotesEditor.coldNotice])
        #expect(try notes.editor.activate("Recent", today: Fixture.today) == [])
        #expect(NotesEditor.coldNotice == "moved to Cold — set a target to keep it on top")
    }
}

// MARK: 7. Bytes on disk

@Suite struct ByteLevelTests {
    @Test func addedLinesUseTheFilesLineEnding() throws {
        let crlf = "---\r\nnext: \"a\"\r\n---\r\nbody\r\n"
        #expect(try Frontmatter.setting("priority", to: "2", in: crlf) == "---\r\nnext: \"a\"\r\npriority: 2\r\n---\r\nbody\r\n")
    }

    @Test func byteOrderMarkIsKept() throws {
        let notes = try TempNotes([:])
        try (Data([0xEF, 0xBB, 0xBF]) + Data(effortFile().utf8)).write(to: notes.url("Bom"))
        #expect(notes.vault.effort(named: "Bom")?.next == "Do it")
        try notes.editor.setNext("new", on: "Bom")
        let bytes = try notes.bytes("Bom")
        #expect(Array(bytes.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: bytes.dropFirst(3), as: UTF8.self) == effortFile(next: "\"new\""))
    }

    /// A link to another effort file is followed and kept; a link anywhere else is refused (BoundaryTests).
    @Test func symlinksAreFollowedAndKept() throws {
        let notes = try TempNotes(["Real": effortFile()])
        let real = notes.url("Real")
        try FileManager.default.createSymbolicLink(at: notes.url("Linked"), withDestinationURL: real)
        try notes.editor.setNext("through the link", on: "Linked")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: notes.url("Linked").path) == real.path)
        #expect(String(decoding: try Data(contentsOf: real), as: UTF8.self).contains("next: \"through the link\""))

        let elsewhere = notes.root.appendingPathComponent("elsewhere.md")
        try Data(effortFile().utf8).write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: notes.url("Outside"), withDestinationURL: elsewhere)
        #expect(throws: WriteError.notAnEffortFile(file: "Outside.md", target: "elsewhere.md")) {
            try notes.editor.setNext("through the link", on: "Outside")
        }
        #expect(String(decoding: try Data(contentsOf: elsewhere), as: UTF8.self) == effortFile())
    }

    @Test func extendedAttributesAndPermissionsAreKept() throws {
        let notes = try TempNotes(["Tagged": effortFile()])
        let path = notes.url("Tagged").path
        let value = Data("keep me".utf8)
        let set = value.withUnsafeBytes { setxattr(path, "dev.parkbar.test", $0.baseAddress, value.count, 0, 0) }
        try #require(set == 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: path)
        try notes.editor.setNext("tagged", on: "Tagged")
        var buffer = [UInt8](repeating: 0, count: 64)
        let size = getxattr(path, "dev.parkbar.test", &buffer, buffer.count, 0, 0)
        #expect(size == value.count && Data(buffer.prefix(max(size, 0))) == value)
        #expect((try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int) == 0o640)
    }
}

// MARK: 8. Block scalars and todo pointers

@Suite struct DisplayShapeTests {
    let blocks = """
    ---
    next: >-
      first part
      second part
    about: |
      line one
      line two
    status: active
    ---
    body
    """

    @Test func blockScalarsAreReadAsText() {
        let v = Frontmatter.parse(blocks).values
        #expect(v["next"] == "first part second part")
        #expect(v["about"] == "line one\nline two")
        #expect(v["status"] == "active")
    }

    @Test func writingABlockScalarReplacesItWithOneLine() throws {
        let out = try Frontmatter.setting("next", to: "\"one line\"", in: blocks)
        #expect(out == blocks.replacingOccurrences(of: "next: >-\n  first part\n  second part", with: "next: \"one line\""))
        #expect(Frontmatter.parse(out).values["about"] == "line one\nline two")
    }

    @Test func trailingPointersOfAnyWordingAreStripped() {
        #expect(TodoList.displayText("Send Dan the price list → details in [[Shop website]]") == "Send Dan the price list")
        #expect(TodoList.displayText("Call Bob → ask about the flour order, say \"batch 4\" → [[Oven upgrade]]")
            == "Call Bob → ask about the flour order, say \"batch 4\"")
        #expect(TodoList.displayText("Ask → context in [[X|x]]") == "Ask")
        #expect(TodoList.displayText("Plan → then build") == "Plan → then build")
    }
}

// MARK: - Where a question list ends, fences, label colons, unreadable fields

@Suite struct LabelScopeTests {
    func body(_ text: String) -> EffortBody { EffortBody(lines: text.components(separatedBy: "\n"), firstLine: 0) }

    @Test func plainProseEndsTheQuestionList() {
        let b = body("""
        **Clarify with Bob:**
        - [ ] one
              continued

              | an indented table inside the item |
        - [ ] two
        My own reminders:
        - [ ] not for Bob
        """)
        #expect(b.questions.map(\.text) == ["one continued", "two"])
    }

    @Test func anyBoldLedLineEndsTheQuestionList() {
        let b = body("""
        **Clarify with Bob:**
        - [ ] one
        **Baked 06:30** — all trays out
        - [ ] not a question
        """)
        #expect(b.questions.map(\.text) == ["one"])
    }

    @Test func aCodeFenceBetweenCheckboxesKeepsTheListOpen() {
        let b = body("""
        **Clarify with Dan:**
        - [ ] one
        ```
        preheat 220
        ```
        - [ ] two
        """)
        #expect(b.questions.map(\.text) == ["one", "two"])
    }
}

@Suite struct FenceTests {
    func body(_ text: String) -> EffortBody { EffortBody(lines: text.components(separatedBy: "\n"), firstLine: 0) }

    @Test func tildeFencesHideTheirContent() {
        let b = body("**Clarify with Bob:**\n- [ ] one\n~~~\n- [ ] hidden\n~~~\n- [ ] two")
        #expect(b.questions.map(\.text) == ["one", "two"])
    }

    @Test func onlyColumnsZeroToThreeOpenAFence() {
        let b = body("**Clarify with Bob:**\n- [ ] one\n      ```\n- [ ] two\n   ```\n- [ ] hidden\n```\n- [ ] three")
        #expect(b.questions.map(\.text) == ["one", "two", "three"])
    }

    /// Obsidian shows everything after an unclosed fence as code, so nothing there is a label or question.
    @Test func anUnclosedFenceRunsToTheEnd() {
        let b = body("**Clarify with Bob:**\n- [ ] one\n```\nnever closed\n**Clarify with Carol:**\n- [ ] for Carol")
        #expect(b.questions.map(\.text) == ["one"])
        #expect(b.sections.count == 1)
    }
}

@Suite struct LabelColonTests {
    @Test func aLabelNeedsItsColon() {
        #expect(EffortBody.label(in: "**Then:** go")?.0 == "Then")
        #expect(EffortBody.label(in: "**Then (me):** go")?.0 == "Then (me)")
        #expect(EffortBody.label(in: "**Then**: go")?.0 == "Then")
        #expect(EffortBody.label(in: "**Clarify with Carol** — before the new oven arrives:")?.0 == "Clarify with Carol")
        #expect(EffortBody.label(in: "**Then** I go home.") == nil)
        #expect(EffortBody.label(in: "**Where I am** is a nice phrase") == nil)
    }
}

@Suite struct UnreadableFieldsTests {
    @Test func trailingWhitespaceOnFencesIsFine() {
        #expect(Frontmatter.parse("--- \nnext: a\n---\t\nbody").values["next"] == "a")
        #expect(Frontmatter.parse(" ---\nnext: a\n---\n").values.isEmpty, "leading space still disqualifies")
    }

    @Test func aFileWhoseFieldsCantBeReadIsNotActive() throws {
        let notes = try TempNotes([
            "Good": effortFile(priority: "1"),
            "Broken": "---\nabout: \"never closed\"\nstatus: active\npriority: 2\n**Where I am:** oops\n",
            "Plain": "**Where I am:** no fields at all\n",
        ])
        let v = notes.vault
        #expect(v.activeOrder.map(\.name) == ["Good"])
        #expect(v.archived.map(\.name).sorted() == ["Broken", "Plain"])
        #expect(v.effort(named: "Broken")?.status == .unreadable)
        #expect(Effort.Status.unreadable.text == "fields unreadable — fix them in your editor")
        let broken = try notes.bytes("Broken")
        try notes.editor.reorder(subset: ["Good"])
        #expect(try notes.bytes("Broken") == broken)
    }
}

@Suite struct TemporaryFileTests {
    @Test func pendingFilesLiveOutsideTheNotesFolder() throws {
        let notes = try TempNotes(["A": effortFile()])
        let folder = try notes.storage.newWriteFolder()
        defer { rmdir(folder.path) }
        #expect(!folder.path.hasPrefix(notes.folder.resolvingSymlinksInPath().path))
        #expect(!folder.path.hasPrefix(notes.folder.path))
        #expect(SafeStorage.standard.pending.path.hasSuffix("Library/Application Support/ParkBar/pending")
            || ProcessInfo.processInfo.environment["PARKBAR_SUPPORT"] != nil)
    }

    @Test func aFailedSaveLeavesNoStrayFileInEfforts() throws {
        let notes = try TempNotes(["A": effortFile(priority: "1"), "B": effortFile(priority: "2")])
        let editor = notes.editor
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: notes.folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notes.folder.path) }
        #expect(throws: WriteError.self) { try editor.reorder(subset: ["B", "A"]) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: notes.folder.path).sorted() == ["A.md", "B.md"])
    }
}

@Suite struct FailedRollbackTests {
    @Test func aFailedRestoreNamesTheFilesLeftChanged() throws {
        let notes = try TempNotes(["A": effortFile(priority: "1"), "B": effortFile(priority: "2"), "C": effortFile(priority: "3")])
        var editor = notes.editor
        var calls = 0
        let folder = notes.folder
        editor.beforeWrite = { url in
            calls += 1
            guard calls == 2 else { return }
            // Obsidian saves B, then the folder stops accepting writes, so A cannot be put back.
            try? Data((String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self) + "\nedited").utf8).write(to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        do {
            try editor.reorder(subset: ["B", "C", "A"])
            Issue.record("expected a failure")
        } catch {
            #expect(error as? WriteError == .partiallySaved(cause: .changedOnDisk("B.md"), leftChanged: ["A.md (could not write)"]))
            let text = "\(error)"
            #expect(text.contains("A.md") && !text.contains("nothing was changed"))
        }
    }
}
