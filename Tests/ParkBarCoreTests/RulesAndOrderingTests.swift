import Foundation
import Testing
@testable import ParkBarCore

@Suite struct RulesTests {
    let today = Fixture.today

    func effort(_ fields: String) -> Effort {
        Effort(fileURL: URL(fileURLWithPath: "/x/e.md"), text: "---\n\(fields)\n---\n")
    }

    @Test func coldOnlyWhenNoTargetAndQuietForTwoWeeks() throws {
        let v = Fixture.vault()
        #expect(try #require(v.effort(named: "Old plan")).isCold(today: today))
        #expect(!(try #require(v.effort(named: "Garden shed")).isCold(today: today)))
        #expect(!(try #require(v.effort(named: "Tax return")).isCold(today: today)), "archived is never cold")
    }

    @Test func coldBoundaryIsMoreThanFourteenDays() {
        #expect(!effort("updated: 2026-10-08").isCold(today: today))
        #expect(effort("updated: 2026-10-07").isCold(today: today))
        #expect(!effort("updated: 2026-01-01\ntarget: 2026-12-01").isCold(today: today), "a target keeps it warm")
        #expect(!Effort(fileURL: URL(fileURLWithPath: "/x/e.md"), text: "no fields").isCold(today: today))
    }

    @Test func targetStates() throws {
        let v = Fixture.vault()
        #expect(try #require(v.effort(named: "Bike repair")).targetState(today: today) == .late)
        #expect(try #require(v.effort(named: "Garden shed")).targetState(today: today) == TargetState.none)
        #expect(effort("target: 2026-10-22").targetState(today: today) == .due)
        #expect(effort("target: 2026-10-24").targetState(today: today) == .upcoming)
    }

    @Test func labels() {
        #expect(Labels.target(nil, today: today) == "—")
        #expect(Labels.target(today, today: today) == "today")
        #expect(Labels.target(today.adding(days: -1), today: today) == "1 day late")
        #expect(Labels.target(today.adding(days: -4), today: today) == "4 days late")
        #expect(Labels.target(Day(year: 2026, month: 10, day: 24), today: today) == "Sat 24 Oct")
        #expect(Labels.updated(today, today: today) == "today")
        #expect(Labels.updated(today.adding(days: -1), today: today) == "yesterday")
        #expect(Labels.updated(today.adding(days: -8), today: today) == "8 days ago")
        #expect(Labels.updated(nil, today: today) == "never updated")
    }
}

@Suite struct OrderingTests {
    @Test func activeOrderPutsMissingPrioritiesLast() {
        #expect(Fixture.vault().activeOrder.map(\.name) == ["Garden shed", "Bike repair", "Old plan", "New idea"])
    }

    @Test func mergeKeepsHiddenItemsInTheirSlots() {
        // "c" is cold and sits between visible ones; the visible ones swap around it.
        let full = ["a", "b", "c", "d"]
        #expect(Ordering.merge(full: full, reorderedSubset: ["d", "a", "b"]) == ["d", "a", "c", "b"])
        #expect(Ordering.merge(full: full, reorderedSubset: ["c"]) == full)
    }

    @Test func movingBeforeAndToPosition() {
        let list = ["a", "b", "c", "d"]
        #expect(Ordering.moving("d", before: "b", in: list) == ["a", "d", "b", "c"])
        #expect(Ordering.moving("a", before: nil, in: list) == ["b", "c", "d", "a"])
        #expect(Ordering.moving("b", before: "b", in: list) == list)
        #expect(Ordering.moving("x", before: "a", in: list) == list)
        #expect(Ordering.moving("d", toPosition: 1, in: list) == ["d", "a", "b", "c"])
        #expect(Ordering.moving("a", toPosition: 99, in: list) == ["b", "c", "d", "a"])
    }

    @Test func priorities() {
        #expect(Ordering.priorities(for: ["x", "y"]) == ["x": 1, "y": 2])
    }
}
