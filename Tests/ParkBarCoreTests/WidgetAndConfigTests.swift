import Foundation
import Testing
@testable import ParkBarCore

@Suite struct WidgetSnapshotTests {
    @Test func topActiveNonColdEfforts() {
        let snapshot = WidgetSnapshot.make(from: Fixture.vault(), today: Fixture.today, at: Date(timeIntervalSince1970: 0))
        #expect(snapshot.items.map(\.name) == ["Garden shed", "Bike repair", "New idea"])
        #expect(snapshot.items[1].target == Day(year: 2026, month: 10, day: 18))
    }

    @Test(arguments: ["Search v2 rollout", "PROJ-160 & co", "Café #1"])
    func effortLinkRoundTrips(_ name: String) throws {
        let url = try #require(WidgetSnapshot.url(for: name))
        #expect(WidgetSnapshot.effortName(in: url) == name)
    }

    @Test func otherLinksAreIgnored() {
        #expect(WidgetSnapshot.effortName(in: URL(string: "https://example.com/effort/x")!) == nil)
        #expect(WidgetSnapshot.effortName(in: URL(string: "parkbar://effort/")!) == nil)
    }

    @Test func storeRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)/snapshot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = WidgetSnapshot.make(from: Fixture.vault(), today: Fixture.today, at: Date(timeIntervalSince1970: 1_000))
        try WidgetSnapshotStore.write(snapshot, to: url)
        #expect(WidgetSnapshotStore.read(from: url) == snapshot)
    }
}

@Suite struct ConfigTests {
    func tempFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func environmentWinsThenConfigThenDefault() throws {
        let dir = try tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data(#"{"notesFolder": "/from/config"}"#.utf8).write(to: url)
        let config = ParkBarConfig.load(from: url).config

        #expect(config.notesURL(environment: ["PARKBAR_NOTES": "/from/env"]).path == "/from/env")
        #expect(config.notesURL(environment: [:]).path == "/from/config")
        #expect(config.notesURL(environment: ["PARKBAR_NOTES": ""]).path == "/from/config", "an empty variable is no setting")
        let missing = ParkBarConfig.load(from: dir.appendingPathComponent("missing.json"))
        #expect(missing.config == .default && missing.problems.isEmpty && missing.file == .missing)
        #expect(missing.config.notesURL(environment: [:]).path == NSHomeDirectory() + "/Documents/ParkBar")
    }

    @Test func everyKeyIsOptionalAndDefaultsFillTheRest() throws {
        let dir = try tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data("""
        {"agendaLists": [{"file": "TEAM-SYNC.md", "person": "Carol"}], "meName": "Dana", "coldAfterDays": 30}
        """.utf8).write(to: url)
        let loaded = ParkBarConfig.load(from: url)
        #expect(loaded.problems.isEmpty)
        let config = loaded.config
        #expect(config.agendaLists == [.init(file: "TEAM-SYNC.md", person: "Carol")])
        #expect(config.meName == "Dana")
        #expect(config.meLabels == ["Decide myself"])
        #expect(config.coldAfterDays == 30)
        #expect(config.notesFolder == nil)
    }

    @Test func unreadableConfigFallsBackToDefaultsAndSaysSo() throws {
        let dir = try tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data("{ not json".utf8).write(to: url)
        let loaded = ParkBarConfig.load(from: url)
        #expect(loaded.config == .default)
        #expect(loaded.problems == ["config.json is not valid JSON; using the defaults"])
        #expect(loaded.file == .unreadable("not valid JSON"))
    }

    @Test func savingTheFolderKeepsTheOtherKeys() throws {
        let dir = try tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sub/config.json")
        try ParkBarConfig.saveNotesFolder(URL(fileURLWithPath: "/first"), to: url)
        #expect(ParkBarConfig.load(from: url).config.notesFolder == "/first")

        try Data(#"{"meName": "Dana", "notesFolder": "/first", "someFutureKey": [1, 2]}"#.utf8).write(to: url)
        let remaining = try ParkBarConfig.saveNotesFolder(URL(fileURLWithPath: "/second"), to: url)
        #expect(remaining == [#"config.json: unknown key "someFutureKey"; ignored"#], "kept, and still reported")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["notesFolder"] as? String == "/second")
        #expect(object["meName"] as? String == "Dana")
        #expect(object["someFutureKey"] as? [Int] == [1, 2])
    }

    @Test func savingRefusesToOverwriteAFileItCannotRead() throws {
        let dir = try tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data("[1, 2]".utf8).write(to: url)
        #expect(throws: ParkBarConfig.SaveError.unreadable("not one JSON object")) {
            try ParkBarConfig.saveNotesFolder(URL(fileURLWithPath: "/x"), to: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "[1, 2]")
    }

    @Test func configShapesTheVault() throws {
        let config = ParkBarConfig(meName: "Dana", coldAfterDays: 100)
        let vault = Vault.load(from: Fixture.notes, config: config)
        #expect(vault.agendas.isEmpty, "no agenda lists unless the config names them")
        #expect(vault.cold(today: Fixture.today).isEmpty, "Old plan is 82 days quiet, under 100")
        let people = vault.people()
        #expect(people.first?.name == "Dana")
        #expect(!people.contains { $0.name == "Me" })
    }
}

@Suite struct ExampleNotesTests {
    @Test func locatesTheFirstPlaceWithExamplesAndReadsTheirConfig() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let empty = base.appendingPathComponent("empty")
        let repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("examples/notes/efforts"), withIntermediateDirectories: true)
        try Data(#"{"meName": "Dana"}"#.utf8).write(to: repo.appendingPathComponent("examples/config.json"))

        let found = try #require(ExampleNotes.locate(in: [empty, repo]))
        #expect(found.notes.path == repo.appendingPathComponent("examples/notes").path)
        #expect(found.config.meName == "Dana")
        #expect(ExampleNotes.locate(in: [empty]) == nil)
    }

    @Test func everyTryMakesAFreshCopy() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = base.appendingPathComponent("repo")
        let efforts = repo.appendingPathComponent("examples/notes/efforts")
        try FileManager.default.createDirectory(at: efforts, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: efforts.appendingPathComponent("A.md"))
        let examples = try #require(ExampleNotes.locate(in: [repo]))
        let storage = SafeStorage(root: base.appendingPathComponent("support"))

        let copy = try examples.copy(into: storage, today: ExampleNotes.writtenFor)
        #expect(try String(contentsOf: copy.appendingPathComponent("efforts/A.md"), encoding: .utf8) == "first")
        try Data("edited".utf8).write(to: copy.appendingPathComponent("efforts/A.md"))
        try Data("stray".utf8).write(to: copy.appendingPathComponent("efforts/B.md"))
        #expect(try examples.copy(into: storage, today: ExampleNotes.writtenFor) == copy)
        #expect(try String(contentsOf: copy.appendingPathComponent("efforts/A.md"), encoding: .utf8) == "first", "each try starts fresh")
        #expect(!FileManager.default.fileExists(atPath: copy.appendingPathComponent("efforts/B.md").path))
        #expect(try String(contentsOf: efforts.appendingPathComponent("A.md"), encoding: .utf8) == "first", "the original is never touched")
    }

    @Test func aCopyMovesEveryDateToToday() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let efforts = base.appendingPathComponent("repo/examples/notes/efforts")
        try FileManager.default.createDirectory(at: efforts, withIntermediateDirectories: true)
        try Data("target: 2026-10-22\nupdated: 2026-09-30\nnot a day: 2026-02-30 · PROJ-2026-10-22x".utf8)
            .write(to: efforts.appendingPathComponent("A.md"))
        let examples = try #require(ExampleNotes.locate(in: [base.appendingPathComponent("repo")]))
        let copy = try examples.copy(into: SafeStorage(root: base.appendingPathComponent("support")),
                                     today: Day(year: 2027, month: 1, day: 5))
        #expect(try String(contentsOf: copy.appendingPathComponent("efforts/A.md"), encoding: .utf8)
            == "target: 2027-01-05\nupdated: 2026-12-14\nnot a day: 2026-02-30 · PROJ-2026-10-22x")
    }

    @Test func theRepoExamplesLoadCleanly() throws {
        // Tests run from the package folder; the examples live next to Package.swift.
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let examples = try #require(ExampleNotes.locate(in: [package]))
        let vault = Vault.load(from: examples.notes, config: examples.config)
        #expect(vault.problems.isEmpty)
        #expect(vault.efforts.count >= 5)
        #expect(!vault.agendas.isEmpty, "examples/config.json wires up the example agenda list")
        #expect(vault.efforts.allSatisfy { $0.status != .unreadable })
    }
}
