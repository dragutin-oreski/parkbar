import Foundation

/// What the widget shows, written by the app after every reload; the widget only reads it.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public let name: String
        public let next: String?
        public let target: Day?
        public var id: String { name }

        public init(name: String, next: String?, target: Day?) {
            self.name = name
            self.next = next
            self.target = target
        }
    }

    public static let itemCount = 4

    public let updatedAt: Date
    public let items: [Item]

    public init(updatedAt: Date, items: [Item]) {
        self.updatedAt = updatedAt
        self.items = items
    }

    /// The top active, non-cold efforts. Target labels are worked out when drawn, so they stay right
    /// across midnight without a new snapshot.
    public static func make(from vault: Vault, today: Day, at now: Date) -> WidgetSnapshot {
        WidgetSnapshot(updatedAt: now, items: vault.current(today: today).prefix(itemCount).map {
            Item(name: $0.name, next: $0.next, target: $0.target)
        })
    }

    /// The link that opens the panel on one effort.
    public static func url(for name: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return name.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: "parkbar://effort/\($0)") }
    }

    /// The effort name in a `parkbar://effort/<name>` link.
    public static func effortName(in url: URL) -> String? {
        guard url.scheme == "parkbar", url.host == "effort" else { return nil }
        let name = String(url.path.dropFirst())
        return name.isEmpty ? nil : name
    }
}

/// Where the snapshot lives. The widget is sandboxed; the app writes straight into the widget's own
/// container, which the sandbox lets the widget read as its Application Support.
public enum WidgetSnapshotStore {
    public static let widgetBundleID = "dev.parkbar.ParkBar.Widget"
    public static let fileName = "snapshot.json"

    /// Path as seen by the (unsandboxed) app.
    public static func appSideURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support/ParkBar", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Where the app writes the snapshot: the widget's container, unless `$PARKBAR_SUPPORT` is set (a test
    /// or development run), when it goes to `widget/snapshot.json` in that folder instead.
    public static func destination(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   home: String = NSHomeDirectory()) -> URL {
        if let support = environment[SafeStorage.environmentKey], !support.isEmpty {
            return URL(fileURLWithPath: support, isDirectory: true).appendingPathComponent("widget/\(fileName)")
        }
        return appSideURL(home: home)
    }

    /// Path as seen from inside the widget's sandbox.
    public static func widgetSideURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ParkBar", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    public static func write(_ snapshot: WidgetSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
