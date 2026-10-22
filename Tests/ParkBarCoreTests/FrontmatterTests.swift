import Foundation
import Testing
@testable import ParkBarCore

@Suite struct FrontmatterTests {
    let sample = """
    ---
    about: "replacing the \\"old\\" oven: phase 2"
    single: 'it''s fine'
    plain: Buy a tube # a comment
    tags:
      - home
    empty:
    nulled: null
    ---
    **Where I am:** body
    """

    @Test func decodesTheScalarStyles() {
        let parsed = Frontmatter.parse(sample)
        let v = parsed.values
        #expect(v["about"] == "replacing the \"old\" oven: phase 2")
        #expect(v["single"] == "it's fine")
        #expect(v["plain"] == "Buy a tube")
        #expect(v["empty"] == nil)
        #expect(v["nulled"] == nil)
        #expect(v["tags"] == nil, "a block list has no scalar value")
        #expect(parsed.bodyStart == 9)
    }

    @Test func noFrontMatter() {
        let parsed = Frontmatter.parse("**Where I am:** no fields\n")
        #expect(parsed.values == [:])
        #expect(parsed.bodyStart == 0)
    }

    @Test func settingAnExistingKeyChangesOnlyThatLine() throws {
        let out = try Frontmatter.setting("plain", to: "\"Buy two tubes\"", in: sample)
        #expect(changedLines(sample, out).map { $0.2 } == ["plain: \"Buy two tubes\""])
    }

    @Test func clearingWritesAnEmptyValue() throws {
        let out = try Frontmatter.setting("about", to: nil, in: sample)
        #expect(changedLines(sample, out).map { $0.2 } == ["about:"])
    }

    @Test func missingKeyGoesBeforeTheClosingFence() throws {
        let out = try Frontmatter.setting("priority", to: "4", in: sample)
        let lines = out.components(separatedBy: "\n")
        #expect(lines[8] == "priority: 4")
        #expect(lines[9] == "---")
        #expect(Frontmatter.parse(out).values["priority"] == "4")
    }

    @Test func replacingAListValueDropsItsItems() throws {
        let out = try Frontmatter.setting("tags", to: "\"none\"", in: sample)
        #expect(!out.contains("  - home"))
        #expect(Frontmatter.parse(out).values["tags"] == "none")
        #expect(out.contains("empty:\n"))
    }

    @Test func fileWithoutFrontMatterIsRefused() {
        #expect(throws: FrontmatterError.noFrontMatter) {
            try Frontmatter.setting("status", to: "archived", in: "body line\n")
        }
    }

    @Test func windowsLineEndingsSurvive() throws {
        let crlf = "---\r\nnext: \"a\"\r\nstatus: active\r\n---\r\nbody\r\n"
        let out = try Frontmatter.setting("next", to: "\"b\"", in: crlf)
        #expect(out == "---\r\nnext: \"b\"\r\nstatus: active\r\n---\r\nbody\r\n")
        #expect(Frontmatter.parse(out).values["next"] == "b")
    }

    @Test(arguments: ["plain", "with \"quotes\" and \\ backslash", "colon: hash # emoji 🚲", "Ć Š Ž — dash"])
    func quotingRoundTrips(_ value: String) {
        #expect(YAMLScalar.decode(YAMLScalar.quoted(value)) == value)
    }
}
