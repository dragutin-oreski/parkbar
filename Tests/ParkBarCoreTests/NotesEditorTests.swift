import Foundation
import Testing
@testable import ParkBarCore

/// Every write test runs on its own throwaway copy and checks that only the intended lines changed.
@Suite final class NotesEditorTests {
    let root: URL

    init() throws {
        root = try Fixture.scratchCopy()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var vault: Vault { Vault.load(from: root, config: Fixture.config) }
    var editor: NotesEditor {
        var editor = NotesEditor(vault: vault)
        editor.storage = SafeStorage(root: root.appendingPathComponent(".support", isDirectory: true))
        return editor
    }

    func text(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("efforts/\(name).md"), encoding: .utf8)
    }

    @Test func setTargetChangesOneLine() throws {
        let before = try text("Garden shed")
        try editor.setTarget(Day(year: 2026, month: 10, day: 24), on: "Garden shed")
        #expect(changedLines(before, try text("Garden shed")).map { $0.2 } == ["target: 2026-10-24"])
        try editor.setTarget(nil, on: "Garden shed")
        #expect(try text("Garden shed") == before)
    }

    @Test func setNextQuotesAndKeepsObsidianLayout() throws {
        let before = try text("Bike repair")
        try editor.setNext("Ask \"Erin\": which shop?", on: "Bike repair")
        let after = try text("Bike repair")
        #expect(changedLines(before, after).map { $0.2 } == ["next: \"Ask \\\"Erin\\\": which shop?\""])
        #expect(vault.effort(named: "Bike repair")?.next == "Ask \"Erin\": which shop?")
        #expect(after.hasPrefix("---\ntags:\n  - home\n  - weekend\n"), "unknown keys stay as written")
    }

    @Test func reorderWritesOnlyFilesWhoseNumberChanged() throws {
        let names = ["Garden shed", "Bike repair", "Old plan", "New idea"]
        let before = try names.map(text)
        // The visible list is shed, bike, new idea (old plan is cold). Drag "New idea" to the top.
        try editor.reorder(subset: ["New idea", "Garden shed", "Bike repair"])
        #expect(vault.activeOrder.map(\.name) == ["New idea", "Garden shed", "Old plan", "Bike repair"])
        let after = try names.map(text)
        #expect(changedLines(before[0], after[0]).map { $0.2 } == ["priority: 2"])
        #expect(changedLines(before[1], after[1]).map { $0.2 } == ["priority: 4"])
        #expect(before[2] == after[2], "the cold effort kept its slot and number")
        // "New idea" had no priority line, so one is added before the closing fence.
        #expect(after[3].contains("--resume new-idea\"\npriority: 1\n---"))
    }

    @Test func moveToPositionAndBefore() throws {
        try editor.move("Old plan", toPosition: 1)
        #expect(vault.activeOrder.first?.name == "Old plan")
        try editor.move("Old plan", before: nil)
        #expect(vault.activeOrder.last?.name == "Old plan")
    }

    @Test func archiveClosesTheGapAndActivateGoesToTheBottom() throws {
        try editor.archive("Garden shed")
        var v = vault
        #expect(v.effort(named: "Garden shed")?.status == .archived)
        #expect(v.effort(named: "Garden shed")?.priority == nil)
        #expect(v.activeOrder.compactMap(\.priority) == [1, 2, 3])

        try editor.activate("Garden shed")
        v = vault
        #expect(v.effort(named: "Garden shed")?.status == .active)
        #expect(v.activeOrder.last?.name == "Garden shed")
        #expect(v.activeOrder.compactMap(\.priority) == [1, 2, 3, 4])
    }

    @Test func tickAndUntickAQuestion() throws {
        let before = try text("Garden shed")
        let shed = try #require(vault.effort(named: "Garden shed"))
        let question = try #require(shed.body.questions.first)
        try editor.setQuestion(question, in: "Garden shed", expectedHash: shed.contentHash, checked: true)
        #expect(changedLines(before, try text("Garden shed")).map { $0.2 }
            == ["- [x] Which panel colour matches the house, and who signs off"])
        let ticked = try #require(vault.effort(named: "Garden shed"))
        try editor.setQuestion(try #require(ticked.body.questions.first), in: "Garden shed", expectedHash: ticked.contentHash, checked: false)
        #expect(try text("Garden shed") == before)
    }

    @Test func refusesWhenTheFileChangedSinceItWasRead() throws {
        let stale = editor
        let url = root.appendingPathComponent("efforts/Garden shed.md")
        try (try text("Garden shed") + "\nAdded in Obsidian.").write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: WriteError.changedOnDisk("Garden shed.md")) {
            try stale.setTarget(Fixture.today, on: "Garden shed")
        }
        #expect(try text("Garden shed").hasSuffix("Added in Obsidian."))
    }

    @Test func noFileIsWrittenWhenAnyOfThemChanged() throws {
        let stale = editor
        let bike = root.appendingPathComponent("efforts/Bike repair.md")
        try (try text("Bike repair") + "\n").write(to: bike, atomically: true, encoding: .utf8)
        let shedBefore = try text("Garden shed")
        #expect(throws: WriteError.self) { try stale.reorder(subset: ["Bike repair", "Garden shed", "New idea"]) }
        #expect(try text("Garden shed") == shedBefore)
    }

    @Test func unknownEffort() {
        #expect(throws: WriteError.unknownEffort("Nope")) { try self.editor.setNext("x", on: "Nope") }
    }

    @Test func aQuestionNotOnItsLineIsRefused() throws {
        let shed = try #require(vault.effort(named: "Garden shed"))
        let question = try #require(shed.body.questions.first)
        let elsewhere = EffortBody.Question(line: 0, people: question.people, text: question.text,
                                            isChecked: false, rawLine: question.rawLine)
        #expect(throws: WriteError.changedOnDisk("Garden shed.md")) {
            try self.editor.setQuestion(elsewhere, in: "Garden shed", expectedHash: shed.contentHash, checked: true)
        }
    }

    @Test func todoFileAndAgendaListsAreNeverTouched() throws {
        let files = ["todo.md", "BOB-TOPICS.md", "MY-TOPICS.md"].map { root.appendingPathComponent($0) }
        let before = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        try editor.archive("Bike repair")
        try editor.setNext("x", on: "Garden shed")
        #expect(try files.map { try String(contentsOf: $0, encoding: .utf8) } == before)
    }
}
