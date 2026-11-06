import Foundation
import Testing
@testable import ParkBarCore

@Suite struct NoticeTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-06T14:40:00Z")!

    @Test func parsesLinesAndSkipsBrokenOnes() {
        let text = """
        {"at":"2026-11-06T14:32:05Z","title":"signing key 'Dev'","source":"Release build","detail":"Package the app","symbol":"key.fill","copy":"claude --resume 1"}
        not json
        {"at":"yesterday","title":"bad date"}
        {"at":"2026-11-06T14:35:00Z","title":"  "}
        {"at":"2026-11-06T14:36:00Z","title":"read 'token'","action":"Click Allow"}
        """
        let notices = Notice.parse(text)
        #expect(notices.map(\.title) == ["signing key 'Dev'", "read 'token'"])
        #expect(notices[0].source == "Release build" && notices[0].copy == "claude --resume 1")
        #expect(notices[1].source == nil && notices[1].symbol == nil && notices[1].action == "Click Allow")
        #expect(notices[0].action == nil)
    }

    @Test func recentIsNewestFirstWithinHalfAnHourAndAfterClearing() {
        let at = { (minutesAgo: Double) in Notice(at: self.now.addingTimeInterval(-minutesAgo * 60), title: "\(Int(minutesAgo))") }
        let all = [at(45), at(5), at(29), at(1)]
        #expect(Notice.recent(all, now: now).map(\.title) == ["1", "5", "29"])
        #expect(Notice.recent(all, now: now, clearedAt: now.addingTimeInterval(-3 * 60)).map(\.title) == ["1"])
    }
}
