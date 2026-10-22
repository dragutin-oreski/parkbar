import Foundation

/// The example notes that ship in the repo (`examples/notes`) and inside the bundled app, with the
/// settings they are meant to be read with (`examples/config.json`).
public struct ExampleNotes: Equatable, Sendable {
    /// The day the example notes are written against. Each copy moves every date by the days since, so the
    /// examples look the same whenever they are tried: one effort due today, one late, one cold.
    public static let writtenFor = Day(year: 2026, month: 10, day: 22)

    /// The `examples` folder itself.
    public let folder: URL
    public var notes: URL { folder.appendingPathComponent("notes", isDirectory: true) }
    /// `examples/config.json`, or the defaults when it is missing or unreadable.
    public let config: ParkBarConfig

    /// The first of `places` that holds `examples/notes/efforts`.
    public static func locate(in places: [URL], fileManager: FileManager = .default) -> ExampleNotes? {
        for place in places {
            let folder = place.appendingPathComponent("examples", isDirectory: true)
            let efforts = folder.appendingPathComponent("notes/\(Vault.effortsFolder)", isDirectory: true)
            guard fileManager.fileExists(atPath: efforts.path) else { continue }
            let config = ParkBarConfig.load(from: folder.appendingPathComponent(ParkBarConfig.fileName)).config
            return ExampleNotes(folder: folder, config: config)
        }
        return nil
    }

    /// Where to look from a running app: its Resources folder, then each folder above the app or binary
    /// (a build inside the repo), then the current folder.
    public static func places(bundle: Bundle = .main, currentFolder: String = FileManager.default.currentDirectoryPath) -> [URL] {
        var places: [URL] = []
        if let resources = bundle.resourceURL { places.append(resources) }
        var folder = bundle.bundleURL
        for _ in 0..<6 {
            folder.deleteLastPathComponent()
            places.append(folder)
        }
        places.append(URL(fileURLWithPath: currentFolder, isDirectory: true))
        return places
    }

    /// A fresh copy of the notes in `storage`, its dates moved to `today`, replacing any earlier copy, so
    /// trying them never changes the repo or the app. Returns the copy's folder.
    public func copy(into storage: SafeStorage, today: Day = .today(), fileManager: FileManager = .default) throws -> URL {
        let target = storage.root.appendingPathComponent("Example notes", isDirectory: true)
        try fileManager.createDirectory(at: storage.root, withIntermediateDirectories: true)
        let staging = storage.root.appendingPathComponent(".Example notes-\(UUID().uuidString)", isDirectory: true)
        try fileManager.copyItem(at: notes, to: staging)
        let offset = Self.writtenFor.days(until: today)
        let files = fileManager.enumerator(at: staging, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "md" } ?? []
        for file in files where offset != 0 {
            let text = try String(contentsOf: file, encoding: .utf8)
            try Data(Self.shiftingDates(in: text, by: offset).utf8).write(to: file)
        }
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.moveItem(at: staging, to: target)
        return target
    }

    /// Every `YYYY-MM-DD` that is a real day, moved by `days`; anything else as it was.
    static func shiftingDates(in text: String, by days: Int) -> String {
        text.replacing(#/\b\d{4}-\d{2}-\d{2}\b/#) { match in
            Day(String(match.output)).map { $0.adding(days: days).description } ?? String(match.output)
        }
    }
}
