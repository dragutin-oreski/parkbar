import Darwin
import Foundation
import Testing
@testable import ParkBarCore

/// A throwaway folder with a config file in it, removed afterwards.
final class TempConfig {
    let dir: URL
    var url: URL { dir.appendingPathComponent("config.json") }

    init(_ text: String? = nil) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let text { try write(text) }
    }

    deinit {
        chmod(url.path, 0o600)
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ text: String) throws { try Data(text.utf8).write(to: url) }
    func text() throws -> String { try String(contentsOf: url, encoding: .utf8) }
}

// MARK: Reading the config, key by key

@Suite struct ConfigLoadingTests {
    @Test func aWrongTypedKeyIsIgnoredByNameAndTheRestStillApplies() throws {
        let file = try TempConfig(#"{"notesFolder": "/chosen", "coldAfterDays": "14"}"#)
        let loaded = ParkBarConfig.load(from: file.url)
        #expect(loaded.config.notesFolder == "/chosen")
        #expect(loaded.config.coldAfterDays == 14)
        #expect(loaded.file == .read)
        #expect(loaded.problems == [#"config.json: "coldAfterDays" must be a whole number; ignored"#])
    }

    @Test func unknownKeysAndBadValuesAreEachNamed() throws {
        let file = try TempConfig("""
        {"meName": "", "meLabels": "Decide myself", "coldAfterDays": true, "theme": "dark",
         "agendaLists": [{"file": "WITH-BOB.md", "person": "Bob"}, {"file": "X.md"}], "notesFolder": 3}
        """)
        let loaded = ParkBarConfig.load(from: file.url)
        #expect(loaded.config.agendaLists == [.init(file: "WITH-BOB.md", person: "Bob")])
        #expect(loaded.config.meName == "Me" && loaded.config.meLabels == ["Decide myself"] && loaded.config.coldAfterDays == 14)
        #expect(loaded.config.notesFolder == nil)
        #expect(loaded.problems == [
            #"config.json: "agendaLists" item 2 needs a "file" and a "person"; ignored"#,
            #"config.json: "coldAfterDays" must be a whole number; ignored"#,
            #"config.json: "meLabels" must be a list of labels; ignored"#,
            #"config.json: "meName" must be a name; ignored"#,
            #"config.json: "notesFolder" must be a folder path; ignored"#,
            #"config.json: unknown key "theme"; ignored"#,
        ])
    }

    @Test func aFileThatCannotBeReadIsAProblemNotAMissingFile() throws {
        let file = try TempConfig(#"{"notesFolder": "/chosen", "meName": "Dana", "someFutureKey": [1, 2]}"#)
        let before = try file.text()
        chmod(file.url.path, 0o000)
        let loaded = ParkBarConfig.load(from: file.url)
        #expect(loaded.config == .default)
        #expect(loaded.file == .unreadable("Permission denied"))
        #expect(loaded.problems == ["Could not read config.json (Permission denied); using the defaults"])

        #expect(throws: ParkBarConfig.SaveError.unreadable("Permission denied")) {
            try ParkBarConfig.saveNotesFolder(URL(fileURLWithPath: "/other"), to: file.url)
        }
        chmod(file.url.path, 0o600)
        #expect(try file.text() == before)
        #expect(ParkBarConfig.SaveError.unreadable("Permission denied").description
            == "config.json could not be read (Permission denied), so ParkBar did not change it. Fix or remove it, then choose the folder again.")
    }

    @Test func savingTheFolderMakesItApplyEvenNextToABrokenKey() throws {
        let file = try TempConfig(#"{"notesFolder": "/chosen", "coldAfterDays": "14"}"#)
        let remaining = try ParkBarConfig.saveNotesFolder(URL(fileURLWithPath: "/second"), to: file.url)
        #expect(remaining == [#"config.json: "coldAfterDays" must be a whole number; ignored"#])
        let again = ParkBarConfig.load(from: file.url)
        #expect(again.config.notesFolder == "/second")
        #expect(try file.text().contains(#""coldAfterDays" : "14""#), "the broken key is kept as written, and reported")
    }

    @Test func theSupportFolderVariableMovesTheConfigFile() {
        let url = ParkBarConfig.url(environment: ["PARKBAR_SUPPORT": "/scratch/support"])
        #expect(url.path == "/scratch/support/config.json")
        #expect(ParkBarConfig.url(environment: [:]).path.hasSuffix("Library/Application Support/ParkBar/config.json"))
    }
}

// MARK: Which folder and settings the app shows

@Suite struct NotesSetupTests {
    func examples(in base: URL) throws -> ExampleNotes {
        let efforts = base.appendingPathComponent("repo/examples/notes/efforts")
        try FileManager.default.createDirectory(at: efforts, withIntermediateDirectories: true)
        try Data("---\ntarget: 2026-10-22\n---\n".utf8).write(to: efforts.appendingPathComponent("A.md"))
        try Data(#"{"meName": "Example me", "coldAfterDays": 3}"#.utf8).write(to: base.appendingPathComponent("repo/examples/config.json"))
        return try #require(ExampleNotes.locate(in: [base.appendingPathComponent("repo")]))
    }

    @Test func theFolderComesFromTheEnvironmentThenTheConfigThenTheDefault() throws {
        let file = try TempConfig(#"{"notesFolder": "/from/config", "meName": "Dana"}"#)
        let env = NotesSetup(configURL: file.url, environment: ["PARKBAR_NOTES": "/from/env"])
        #expect(env.folder.path == "/from/env" && env.folderIsFromEnvironment)
        let config = NotesSetup(configURL: file.url, environment: [:])
        #expect(config.folder.path == "/from/config" && !config.folderIsFromEnvironment)
        #expect(config.config.meName == "Dana")
        let none = NotesSetup(configURL: file.dir.appendingPathComponent("missing.json"), environment: [:])
        #expect(none.folder.path == NSHomeDirectory() + "/Documents/ParkBar")
    }

    @Test func choosingAFolderIsRefusedWhileTheEnvironmentDecides() throws {
        let file = try TempConfig()
        var setup = NotesSetup(configURL: file.url, environment: ["PARKBAR_NOTES": "/from/env"])
        #expect(throws: NotesSetup.ChoiceError.environmentInCharge) { try setup.choose(URL(fileURLWithPath: "/picked")) }
        #expect(setup.folder.path == "/from/env")
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        #expect(NotesSetup.ChoiceError.environmentInCharge.description
            == "PARKBAR_NOTES is set, so it decides the notes folder (for /park too). Unset it to choose a folder here.")
    }

    @Test func checkingWhetherAChoiceIsAllowedChangesNothing() throws {
        let file = try TempConfig(#"{"notesFolder": "/mine", "meName": "Dana"}"#)
        var setup = NotesSetup(configURL: file.url, environment: [:])
        let before = setup
        try file.write("{ broken")
        #expect(setup.choiceBlocker() == .config(.unreadable("not valid JSON")))
        #expect(setup == before)
        #expect(setup.folder.path == "/mine" && setup.config.meName == "Dana")
        #expect(throws: NotesSetup.ChoiceError.config(.unreadable("not valid JSON"))) { try setup.choose(URL(fileURLWithPath: "/picked")) }
        #expect(setup == before, "a refused choice changes nothing either")
    }

    @Test func choosingAFolderIsRefusedWhileTheConfigCannotBeRead() throws {
        let file = try TempConfig("{ not json")
        var setup = NotesSetup(configURL: file.url, environment: [:])
        #expect(setup.problems == ["config.json is not valid JSON; using the defaults"])
        #expect(throws: NotesSetup.ChoiceError.config(.unreadable("not valid JSON"))) { try setup.choose(URL(fileURLWithPath: "/picked")) }
        #expect(try file.text() == "{ not json")
        #expect(setup.folder.path == NSHomeDirectory() + "/Documents/ParkBar")
    }

    @Test func choosingAFolderSavesItAndReportsWhatIsStillBroken() throws {
        let file = try TempConfig(#"{"coldAfterDays": "14", "meName": "Dana"}"#)
        var setup = NotesSetup(configURL: file.url, environment: [:])
        try setup.choose(URL(fileURLWithPath: "/picked"))
        #expect(setup.folder.path == "/picked")
        #expect(ParkBarConfig.load(from: file.url).config.notesFolder == "/picked")
        #expect(setup.config.meName == "Dana")
        #expect(setup.problems == [#"config.json: "coldAfterDays" must be a whole number; ignored"#])
    }

    @Test func examplesUseTheirOwnSettingsUntilYouLeaveThem() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let file = try TempConfig(#"{"notesFolder": "/mine", "meName": "Dana"}"#)
        let storage = SafeStorage(root: base.appendingPathComponent("support"))
        var setup = NotesSetup(configURL: file.url, environment: [:])

        try setup.tryExamples(examples(in: base), storage: storage, today: Day(year: 2026, month: 10, day: 22))
        #expect(setup.isShowingExamples)
        #expect(setup.config.meName == "Example me" && setup.config.coldAfterDays == 3)
        #expect(setup.folder.path.hasPrefix(storage.root.path))

        setup.leaveExamples()
        #expect(!setup.isShowingExamples)
        #expect(setup.folder.path == "/mine" && setup.config.meName == "Dana")
        #expect(try file.text() == #"{"notesFolder": "/mine", "meName": "Dana"}"#, "trying the examples never touches the config")
    }

    @Test func eachTryStartsFromAFreshCopyDatedThatDay() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let file = try TempConfig()
        let storage = SafeStorage(root: base.appendingPathComponent("support"))
        let source = try examples(in: base)
        var setup = NotesSetup(configURL: file.url, environment: [:])

        try setup.tryExamples(source, storage: storage, today: Day(year: 2026, month: 10, day: 22))
        try Data("---\ntarget: 2000-01-01\n---\n".utf8).write(to: setup.folder.appendingPathComponent("efforts/A.md"))
        setup.leaveExamples()
        try setup.tryExamples(source, storage: storage, today: Day(year: 2026, month: 11, day: 22))
        let text = try String(contentsOf: setup.folder.appendingPathComponent("efforts/A.md"), encoding: .utf8)
        #expect(text == "---\ntarget: 2026-11-22\n---\n")
    }

    @Test func choosingAFolderLeavesTheExamples() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parkbar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let file = try TempConfig(#"{"meName": "Dana"}"#)
        var setup = NotesSetup(configURL: file.url, environment: [:])
        try setup.tryExamples(examples(in: base), storage: SafeStorage(root: base.appendingPathComponent("support")),
                              today: Day(year: 2026, month: 10, day: 22))
        try setup.choose(URL(fileURLWithPath: "/picked"))
        #expect(!setup.isShowingExamples)
        #expect(setup.config.meName == "Dana" && setup.config.coldAfterDays == 14)
        #expect(setup.folder.path == "/picked")
    }
}

// MARK: Keeping test runs away from the real widget

@Suite struct WidgetDestinationTests {
    @Test func onlyASupportFolderOverrideKeepsTheRealWidgetAlone() {
        let home = "/home/someone"
        #expect(WidgetSnapshotStore.destination(environment: [:], home: home) == WidgetSnapshotStore.appSideURL(home: home))
        #expect(WidgetSnapshotStore.destination(environment: ["PARKBAR_SUPPORT": "/scratch"], home: home).path
            == "/scratch/widget/snapshot.json")
        #expect(WidgetSnapshotStore.destination(environment: ["PARKBAR_NOTES": "/notes"], home: home)
            == WidgetSnapshotStore.appSideURL(home: home), "a notes folder from the environment is still your own")
        #expect(WidgetSnapshotStore.destination(environment: ["PARKBAR_NOTES": "/notes", "PARKBAR_SUPPORT": "/scratch"], home: home).path
            == "/scratch/widget/snapshot.json")
    }
}

// MARK: The CLI reads another config file on request

@Suite struct CLIConfigOptionTests {
    /// Runs the built CLI with only the given environment; returns the exit code and all output.
    func cli(_ args: [String], environment: [String: String]) throws -> (Int32, String) {
        let cliURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/debug/parkbar-cli")
        try #require(FileManager.default.isExecutableFile(atPath: cliURL.path), "build the CLI first")
        let p = Process()
        p.executableURL = cliURL
        p.arguments = args
        p.environment = environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return (p.terminationStatus, output)
    }

    @Test func theConfigOptionReplacesTheStandardFile() throws {
        let support = try TempConfig(#"{"meName": "From support"}"#)
        let other = try TempConfig(#"{"meName": "From option", "agendaLists": [{"file": "WITH-BOB.md", "person": "Bob"}]}"#)
        let (status, output) = try cli(["--config", other.url.path, "config"], environment: ["PARKBAR_SUPPORT": support.dir.path])
        #expect(status == 0)
        #expect(output.contains("config file: \(other.url.path)"))
        #expect(output.contains("me: From option"))
        #expect(output.contains("WITH-BOB.md → Bob"))
    }

    /// The notes the fallback would reach (here through PARKBAR_NOTES, standing in for the default folder).
    @Test(arguments: ["missing", "malformed", "unreadable", "bad notesFolder"])
    func anUnusableConfigOptionNeverRedirectsAWrite(_ kind: String) throws {
        let notes = try TempNotes(["A": effortFile()])
        let support = try TempConfig()
        let other = try TempConfig()
        switch kind {
        case "missing": break
        case "malformed": try other.write("{ broken")
        case "unreadable":
            try other.write(#"{"notesFolder": "/somewhere"}"#)
            chmod(other.url.path, 0o000)
        default: try other.write(#"{"notesFolder": 42}"#)
        }
        let env = ["PARKBAR_SUPPORT": support.dir.path, "PARKBAR_NOTES": notes.root.path]
        let before = try notes.bytes("A")

        let (status, output) = try cli(["--config", other.url.path, "set-next", "A", "not for this folder"], environment: env)
        #expect(status != 0)
        #expect(output.contains("--config"), "says which option is the problem: \(output)")
        #expect(try notes.bytes("A") == before)

        let (readStatus, listing) = try cli(["--config", other.url.path, "list"], environment: env)
        #expect(readStatus == 0 && listing.contains("! ") && listing.contains("A"), "reading goes on, with a warning")

        let (namedStatus, _) = try cli(["--config", other.url.path, "--notes", notes.root.path, "set-next", "A", "named"], environment: env)
        #expect(namedStatus == 0, "an explicit --notes says where to write")
        #expect(try notes.text("A").contains(#"next: "named""#))
    }
}
