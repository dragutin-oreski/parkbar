import Foundation
import Testing
@testable import ParkBarCore

@Suite struct EffortTests {
    @Test func readsQuotedFields() throws {
        let e = try #require(Fixture.vault().effort(named: "Garden shed"))
        #expect(e.about == "rebuilding the shed roof (with Bob)")
        #expect(e.status == .active)
        #expect(e.priority == 1)
        #expect(e.target == nil)
        #expect(e.next == "Order the \"blue\" panels, then call Alice")
        #expect(e.updated == Day(year: 2026, month: 10, day: 20))
        #expect(e.resume == "claude --resume garden-shed")
    }

    @Test func readsObsidianStyleFields() throws {
        let e = try #require(Fixture.vault().effort(named: "Bike repair"))
        #expect(e.about == "fixing the back wheel")
        #expect(e.priority == 2)
        #expect(e.target == Day(year: 2026, month: 10, day: 18))
        #expect(e.next == "Buy a new inner tube")
        #expect(e.resume == nil, "an empty resume line means there is nothing to copy")
    }

    @Test func missingStatusMeansActiveAndMissingPriorityIsNil() throws {
        let e = try #require(Fixture.vault().effort(named: "New idea"))
        #expect(e.status == .active)
        #expect(e.priority == nil)
    }

    @Test func hashFollowsTheText() {
        #expect(Effort.hash("a") == Effort.hash("a"))
        #expect(Effort.hash("a") != Effort.hash("a\n"))
    }

    @Test func fieldEncoding() {
        #expect(EffortField.priority(3).encoded == "3")
        #expect(EffortField.priority(nil).encoded == nil)
        #expect(EffortField.target(Day(year: 2026, month: 10, day: 24)).encoded == "2026-10-24")
        #expect(EffortField.next("Say \"go\"").encoded == "\"Say \\\"go\\\"\"")
        #expect(EffortField.next("   ").encoded == nil)
        #expect(EffortField.status(.archived).encoded == "archived")
    }
}
