import Foundation
import Testing
@testable import ParkBarCore

@Suite struct TodayPlanTests {
    let today = Day(year: 2026, month: 11, day: 6)

    let sample = """
    # Today

    ## 2026-11-06
    - [ ] Review the pull request
    - [x] Answer the design question

    ## 2026-11-05
    - [ ] Book the room
    - [x] Water the plants

    ## 2026-11-04
    - [ ] Call the bank
    """

    @Test func splitsTodayFromLeftovers() {
        let plan = TodayPlan.parse(sample, hash: "h")
        #expect(plan.items(on: today).map(\.text) == ["Review the pull request", "Answer the design question"])
        #expect(plan.leftovers(on: today).map(\.text) == ["Book the room", "Call the bank"])
        #expect(plan.progress(on: today) == (1, 2))
    }

    @Test func nextDayEverythingOpenIsALeftover() {
        let plan = TodayPlan.parse(sample, hash: "h")
        let tomorrow = today.adding(days: 1)
        #expect(plan.items(on: tomorrow).isEmpty)
        #expect(plan.leftovers(on: tomorrow).map(\.text) == ["Review the pull request", "Book the room", "Call the bank"])
    }

    @Test func undatedItemsAreLeftoversListedLast() {
        let plan = TodayPlan.parse("- [ ] Loose one\n## 2026-11-05\n- [ ] Dated\n## Notes\n- [ ] Under notes\n", hash: nil)
        #expect(plan.leftovers(on: today).map(\.text) == ["Dated", "Loose one", "Under notes"])
    }

    @Test func addingOnANewDayStartsCleanAndCarriesOpenItems() {
        let plan = TodayPlan.parse(sample, hash: "h")
        let text = plan.adding("  Plan the week\n", today: today.adding(days: 1))
        #expect(text == """
        # Today

        ## 2026-11-07
        - [ ] Plan the week

        ## 2026-11-06
        - [ ] Review the pull request

        ## 2026-11-05
        - [ ] Book the room

        ## 2026-11-04
        - [ ] Call the bank

        """)
    }

    @Test func tickingAndRemovingToday() throws {
        let plan = TodayPlan.parse(sample, hash: "h")
        let review = try #require(plan.items(on: today).first)
        let ticked = TodayPlan.parse(plan.setting(review, checked: true, today: today), hash: nil)
        #expect(ticked.progress(on: today) == (2, 2))
        let removed = TodayPlan.parse(plan.removing(review, today: today), hash: nil)
        #expect(removed.items(on: today).map(\.text) == ["Answer the design question"])
    }

    @Test func keepingOrTickingALeftoverMovesItToToday() throws {
        let plan = TodayPlan.parse(sample, hash: "h")
        let room = try #require(plan.leftovers(on: today).first)
        let kept = TodayPlan.parse(plan.keeping(room, today: today), hash: nil)
        #expect(kept.items(on: today).map(\.text).last == "Book the room")
        #expect(kept.leftovers(on: today).map(\.text) == ["Call the bank"])

        let done = TodayPlan.parse(plan.setting(room, checked: true, today: today), hash: nil)
        #expect(done.items(on: today).last == TodayPlan.Item(text: "Book the room", isChecked: true, day: today,
                                                             line: done.items(on: today).last!.line))
    }

    @Test func blankTextIsNotAnItem() {
        #expect(TodayPlan.cleaned(" \n ") == nil)
        #expect(TodayPlan.cleaned("a\nb") == "a b")
    }

    // MARK: - Writing the file

    @Test func firstAddCreatesTheFile() throws {
        let notes = try TempNotes([:])
        try notes.editor.addToday("First thing", today: today)
        let text = try String(contentsOf: notes.root.appendingPathComponent("today.md"), encoding: .utf8)
        #expect(text == "# Today\n\n## 2026-11-06\n- [ ] First thing\n")
        #expect(notes.vault.todayPlan.items(on: today).map(\.text) == ["First thing"])
    }

    @Test func refusesWhenTheFileChangedSinceItWasRead() throws {
        let notes = try TempNotes([:])
        let url = notes.root.appendingPathComponent("today.md")
        try Data(sample.utf8).write(to: url)
        let editor = notes.editor
        try Data((sample + "\n- [ ] Added in Obsidian\n").utf8).write(to: url)
        #expect(throws: WriteError.changedOnDisk("today.md")) { try editor.addToday("Mine", today: today) }
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Added in Obsidian"))
    }

    @Test func refusesToCreateOverAFileThatAppeared() throws {
        let notes = try TempNotes([:])
        let editor = notes.editor
        let url = notes.root.appendingPathComponent("today.md")
        try Data("- [ ] theirs\n".utf8).write(to: url)
        #expect(throws: WriteError.changedOnDisk("today.md")) { try editor.addToday("Mine", today: today) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "- [ ] theirs\n")
    }

    @Test func neverWritesTodoThroughALink() throws {
        let notes = try TempNotes([:])
        try Data("## Inbox\n- [ ] keep me\n".utf8).write(to: notes.root.appendingPathComponent("todo.md"))
        try FileManager.default.createSymbolicLink(at: notes.root.appendingPathComponent("today.md"),
                                                   withDestinationURL: notes.root.appendingPathComponent("todo.md"))
        #expect(throws: WriteError.sharesAReadOnlyFile(file: "today.md", other: "todo.md")) {
            try notes.editor.addToday("Mine", today: today)
        }
        #expect(try String(contentsOf: notes.root.appendingPathComponent("todo.md"), encoding: .utf8) == "## Inbox\n- [ ] keep me\n")
    }
}
