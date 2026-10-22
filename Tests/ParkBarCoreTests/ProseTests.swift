import Testing
@testable import ParkBarCore

@Suite struct ProseTests {
    @Test func joinsHardWrappedLines() {
        #expect(Prose.reflow("the two price-\nlist drafts,\nsamples.") == "the two price- list drafts, samples.")
    }

    @Test func keepsParagraphsAndLists() {
        let text = """
        First paragraph
        continues here.

        1. Book the delivery
           for Friday.
        2. Tell Bob.
        - [ ] a checkbox
        **Then:** next
        """
        #expect(Prose.reflow(text) == """
        First paragraph continues here.

        1. Book the delivery for Friday.
        2. Tell Bob.
        - [ ] a checkbox
        **Then:** next
        """)
    }

    @Test func listDetection() {
        #expect(Prose.isListItem("12. twelve"))
        #expect(!Prose.isListItem("12 apples"))
        #expect(!Prose.isListItem("-not a list"))
    }
}
