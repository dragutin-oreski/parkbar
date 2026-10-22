import Foundation
import Testing
@testable import ParkBarCore

@Suite struct DayTests {
    @Test func parsesNotesDates() {
        #expect(Day("2026-10-24") == Day(year: 2026, month: 10, day: 24))
        #expect(Day(" 2026-01-05 ") == Day(year: 2026, month: 1, day: 5))
    }

    @Test(arguments: ["", "2026-2-3", "26-10-24", "2026-02-30", "2026-13-01", "tomorrow", "2026/10/24"])
    func rejectsAnythingElse(_ text: String) {
        #expect(Day(text) == nil)
    }

    @Test func dayArithmetic() {
        let d = Day(year: 2026, month: 10, day: 22)
        #expect(d.days(until: Day(year: 2026, month: 10, day: 25)) == 3)
        #expect(d.days(until: Day(year: 2026, month: 9, day: 30)) == -22)
        #expect(d.adding(days: 10) == Day(year: 2026, month: 11, day: 1))
        // Across the end-of-October clock change.
        #expect(Day(year: 2026, month: 10, day: 24).days(until: Day(year: 2026, month: 10, day: 26)) == 2)
    }

    @Test func orderingAndText() {
        #expect(Day(year: 2026, month: 9, day: 30) < Day(year: 2026, month: 10, day: 1))
        #expect(Day(year: 2026, month: 3, day: 7).description == "2026-03-07")
    }

    @Test func codableAsText() throws {
        let data = try JSONEncoder().encode([Day(year: 2026, month: 10, day: 24)])
        #expect(String(data: data, encoding: .utf8) == "[\"2026-10-24\"]")
        #expect(try JSONDecoder().decode([Day].self, from: data) == [Day(year: 2026, month: 10, day: 24)])
    }
}
