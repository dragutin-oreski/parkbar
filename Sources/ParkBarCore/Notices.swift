import Foundation

/// A short notice another program left for you, such as a hook saying which session is about to ask for a
/// keychain secret and why. Programs append one JSON object per line to `alerts.jsonl` in ParkBar's
/// support folder; the panel lists the recent ones at the top until they age out or you clear them.
///
///     {"at":"2026-11-06T14:32:05Z","title":"signing key 'Dev'","source":"Release build session",
///      "detail":"Package a release build","symbol":"key.fill","copy":"claude --resume 1234"}
///
/// `at` and `title` are required; the rest (`source`, `detail`, `symbol`, `copy`, `action`) is optional. Lines that do not parse are skipped.
public struct Notice: Equatable, Identifiable, Sendable {
    public static let fileName = "alerts.jsonl"
    /// How long an alert stays listed.
    public static let shownFor: TimeInterval = 30 * 60

    public let at: Date
    /// What it is about, in a few words.
    public let title: String
    /// Who raised it.
    public let source: String?
    /// Why, in one line.
    public let detail: String?
    /// An SF Symbol name.
    public let symbol: String?
    /// Text a click copies, such as a command that reopens the source.
    public let copy: String?
    /// What you need to do about it, if anything.
    public let action: String?

    public var id: String { "\(at.timeIntervalSince1970)|\(title)|\(source ?? "")" }

    public init(at: Date, title: String, source: String? = nil, detail: String? = nil, symbol: String? = nil, copy: String? = nil,
                action: String? = nil) {
        self.at = at
        self.title = title
        self.source = source
        self.detail = detail
        self.symbol = symbol
        self.copy = copy
        self.action = action
    }

    public static func url(in storage: SafeStorage = .standard) -> URL {
        storage.root.appendingPathComponent(fileName)
    }

    public static func parse(_ text: String) -> [Notice] {
        text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stamp = object["at"] as? String, let at = ISO8601DateFormatter().date(from: stamp),
                  let title = nonBlank(object["title"]) else { return nil }
            return Notice(at: at, title: title, source: nonBlank(object["source"]), detail: nonBlank(object["detail"]),
                         symbol: nonBlank(object["symbol"]), copy: nonBlank(object["copy"]),
                          action: nonBlank(object["action"]))
        }
    }

    /// Alerts from the last `shownFor` and after `clearedAt`, newest first. One from the future (a clock
    /// set wrong) counts as now.
    public static func recent(_ alerts: [Notice], now: Date, clearedAt: Date? = nil) -> [Notice] {
        alerts.filter { now.timeIntervalSince($0.at) < shownFor && $0.at > (clearedAt ?? .distantPast) }
            .sorted { $0.at > $1.at }
    }

    public static func load(from url: URL) -> [Notice] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(String(decoding: data, as: UTF8.self))
    }

    private static func nonBlank(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
