import Foundation
import Testing
@testable import ParkBarCore

@Suite struct EffortBodyTests {
    let shed: Effort

    init() throws {
        shed = try #require(Fixture.vault().effort(named: "Garden shed"))
    }

    @Test func latestWhereIAmAndThenWin() {
        #expect(shed.body.latestWhereIAm?.label == "Where I am (21 Oct)")
        #expect(shed.body.latestWhereIAm?.text == "panels chosen, delivery not booked yet.")
        #expect(shed.body.latestThen?.text == "1. Book the delivery for Friday.\n2. Tell Bob the date.")
    }

    @Test func nothingIsDropped() throws {
        let text = try Fixture.effortText("Garden shed")
        let body = text.components(separatedBy: "\n").dropFirst(9).joined(separator: "\n")
        #expect(shed.body.text == body.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(shed.body.text.hasPrefix("Some opening words"))
        #expect(shed.body.refs == "[plan](docs/shed/PLAN.md) · SHED-12")
    }

    @Test func questionsWithPeopleAndContinuationLines() {
        let q = shed.body.questions
        #expect(q.count == 4)
        #expect(q[0].people == ["Alice", "Bob"])
        #expect(q[0].text == "Which panel colour matches the house, and who signs off on the delivery date?")
        #expect(!q[0].isChecked)
        #expect(q[1].isChecked)
        #expect(q[2].text == "Does the permit cover the bigger window?")
        #expect(q[3].people == ["Me"])
        #expect(q[3].text == "Paint now or in spring")
    }

    @Test func questionLinesPointIntoTheFile() throws {
        let lines = try Fixture.effortText("Garden shed").components(separatedBy: "\n")
        for q in shed.body.questions {
            #expect(lines[q.line] == q.rawLine)
        }
    }

    @Test func thenListsAreNotQuestions() {
        #expect(!shed.body.questions.contains { $0.text.contains("Book the delivery") })
    }

    @Test func peopleSeparators() {
        #expect(EffortBody.people(in: "Erin / Alice") == ["Erin", "Alice"])
        #expect(EffortBody.people(in: "Bob, Carol and Alice") == ["Bob", "Carol", "Alice"])
        #expect(EffortBody.people(in: "Bob + Bob") == ["Bob"])
    }

    @Test func labelKinds() {
        #expect(EffortBody.kind(of: "Then (after lunch)") == .then)
        #expect(EffortBody.kind(of: "Where I am (Friday evening)") == .whereIAm)
        #expect(EffortBody.kind(of: "Update 2026-09-01 (shipped)") == .other)
        #expect(EffortBody.label(in: "  **Indented:** no") == nil)
        #expect(EffortBody.label(in: "**bold** then: text") == nil)
    }

    @Test func checkboxShapes() {
        #expect(EffortBody.checkbox(in: "- [ ] open")?.0 == false)
        #expect(EffortBody.checkbox(in: "- [X] done")?.0 == true)
        #expect(EffortBody.checkbox(in: "- [ ]")?.1 == "")
        #expect(EffortBody.checkbox(in: "  - [ ] indented") == nil)
        #expect(EffortBody.checkbox(in: "- [link](x)") == nil)
    }

    /// Real notes put blank lines, tables and code fences between a label's checkboxes.
    @Test func blankLinesDoNotEndTheQuestionList() {
        let body = EffortBody(lines: [
            "**Clarify with Bob:**",
            "",
            "- [ ] first",
            "",
            "- [ ] after a gap, still a question",
        ], firstLine: 0)
        #expect(body.questions.map(\.text) == ["first", "after a gap, still a question"])
    }
}
