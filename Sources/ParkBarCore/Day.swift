import Foundation

/// A calendar day with no time or time zone, as written in the notes: `2026-10-24`.
public struct Day: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`; nil for anything else, including impossible dates like `2026-02-30`.
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let candidate = Day(year: y, month: m, day: d)
        guard let date = candidate.date(), Day(date, calendar: Self.utc) == candidate else { return nil }
        self = candidate
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public static func today(now: Date = Date(), calendar: Calendar = .current) -> Day {
        Day(now, calendar: calendar)
    }

    /// Whole days from `self` to `other`: positive when `other` is later.
    public func days(until other: Day) -> Int {
        guard let a = date(), let b = other.date() else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    public func adding(days: Int) -> Day {
        guard let d = date() else { return self }
        return Day(d.addingTimeInterval(Double(days) * 86_400), calendar: Self.utc)
    }

    /// Noon UTC on this day: a stable anchor for arithmetic and formatting.
    public func date() -> Date? {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a YYYY-MM-DD day: \(text)"))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
