import Foundation

/// Where an effort's target date stands today.
public enum TargetState: String, Codable, Sendable {
    case none
    case upcoming
    case due
    case late
}

public extension Effort {
    func targetState(today: Day) -> TargetState {
        guard let target else { return .none }
        if target == today { return .due }
        return target < today ? .late : .upcoming
    }

    /// Active, no target, and `updated` more than `coldAfterDays` days ago (the config's, 14 by default).
    /// An effort with no `updated` date is never cold: there is nothing to measure.
    func isCold(today: Day, coldAfterDays: Int = ParkBarConfig.default.coldAfterDays) -> Bool {
        status == .active && wouldBeCold(today: today, coldAfterDays: coldAfterDays)
    }

    /// Cold if it were active: no target and quiet for too long. Used to warn when reactivating.
    func wouldBeCold(today: Day, coldAfterDays: Int = ParkBarConfig.default.coldAfterDays) -> Bool {
        guard target == nil, let updated else { return false }
        return updated.days(until: today) > coldAfterDays
    }
}

/// The short texts the panel and widget show.
public enum Labels {
    /// "—", "today", "1 day late", "3 days late", "Fri 24 Oct".
    public static func target(_ target: Day?, today: Day) -> String {
        guard let target else { return "—" }
        let late = target.days(until: today)
        if late == 0 { return "today" }
        if late > 0 { return late == 1 ? "1 day late" : "\(late) days late" }
        return dayFormatter.string(from: target.date() ?? Date())
    }

    /// "today", "yesterday", "8 days ago".
    public static func updated(_ updated: Day?, today: Day) -> String {
        guard let updated else { return "never updated" }
        let ago = updated.days(until: today)
        if ago <= 0 { return "today" }
        return ago == 1 ? "yesterday" : "\(ago) days ago"
    }

    /// "Fri 24 Oct".
    public static func day(_ day: Day) -> String {
        dayFormatter.string(from: day.date() ?? Date())
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE d MMM"
        return f
    }()
}
