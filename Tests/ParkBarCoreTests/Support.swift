import Foundation
@testable import ParkBarCore

enum Fixture {
    /// The day the fixtures are written against.
    static let today = Day(year: 2026, month: 10, day: 22)

    static var notes: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures/notes", isDirectory: true)
    }

    /// The fixtures' settings: two agenda lists, everything else the defaults.
    static let config = ParkBarConfig(agendaLists: [.init(file: "BOB-TOPICS.md", person: "Bob"),
                                                    .init(file: "MY-TOPICS.md", person: "Me")])

    static func vault() -> Vault { Vault.load(from: notes, config: config) }

    static func effortText(_ name: String) throws -> String {
        try String(contentsOf: notes.appendingPathComponent("efforts/\(name).md"), encoding: .utf8)
    }

    /// A throwaway copy of the fixture notes, for tests that write.
    static func scratchCopy() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: notes, to: dir)
        return dir
    }
}

/// A throwaway notes folder holding just the given effort files (name → full text) and an empty todo file.
final class TempNotes {
    let root: URL

    init(_ efforts: [String: String]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("todo.md"))
        for (name, text) in efforts { try Data(text.utf8).write(to: url(name)) }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var folder: URL { root.appendingPathComponent("efforts", isDirectory: true) }
    /// This folder's own pending/ and recovery/ (never the user's real ones), on the same volume.
    var storage: SafeStorage { SafeStorage(root: root.appendingPathComponent("support", isDirectory: true)) }
    var recovery: URL { storage.recovery }
    /// Read with the fixtures' settings, so `BOB-TOPICS.md` and `MY-TOPICS.md` are agenda lists.
    var vault: Vault { Vault.load(from: root, config: Fixture.config) }
    var editor: NotesEditor {
        var editor = NotesEditor(vault: vault)
        editor.storage = storage
        return editor
    }

    func url(_ name: String) -> URL { folder.appendingPathComponent("\(name).md") }
    func bytes(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
    func text(_ name: String) throws -> String { String(decoding: try bytes(name), as: UTF8.self) }
}

/// A plain effort file with the usual fields.
func effortFile(priority: String = "1", status: String = "active", next: String = "\"Do it\"",
                target: String = "", updated: String = "2026-10-20", extra: String = "", body: String = "**Where I am:** here.\n") -> String {
    "---\nabout: \"a thing\"\nstatus: \(status)\npriority: \(priority)\ntarget: \(target)\nnext: \(next)\nupdated: \(updated)\n\(extra)resume: \"cmd\"\n---\n\(body)"
}

/// Lines that differ between two texts of the same length, as (index, old, new).
func changedLines(_ old: String, _ new: String) -> [(Int, String, String)] {
    let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
    precondition(a.count == b.count, "line count changed: \(a.count) → \(b.count)")
    return zip(a, b).enumerated().compactMap { i, pair in pair.0 == pair.1 ? nil : (i, pair.0, pair.1) }
}
