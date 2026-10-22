import Darwin
import Dispatch
import Foundation
import Testing
@testable import ParkBarCore

// Recovery, crashes, CLI tokens and rollback reports: the edges of the write protocol.

/// Stands in for the process dying at a step: the write stops there and nothing settles what it left.
struct SimulatedCrash: Error {}

enum SaveKind: String, CaseIterable, Sendable { case append, rewrite, rename }

func saveAsAnotherApp(_ how: SaveKind, to url: URL, original: String, marker: String) {
    let line = Data("\n\(marker)\n".utf8)
    let full = Data(original.utf8) + line
    switch how {
    case .append:
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        _ = line.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, line.count) }
        close(fd)
    case .rewrite:
        let fd = open(url.path, O_WRONLY | O_TRUNC | O_CREAT, 0o644)
        _ = full.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, full.count) }
        close(fd)
    case .rename:
        try! full.write(to: url, options: .atomic)
    }
}

func recovered(_ notes: TempNotes) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(at: notes.recovery, includingPropertiesForKeys: nil)) ?? [])
        .map { String(decoding: (try? Data(contentsOf: $0)) ?? Data(), as: UTF8.self) }
}

func pendingFiles(_ storage: SafeStorage) -> [URL] {
    let fm = FileManager.default
    guard let walker = fm.enumerator(at: storage.pending, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
    return walker.compactMap { $0 as? URL }
        .filter { (try? $0.resourceValues(forKeys: [URLResourceKey.isRegularFileKey]).isRegularFile) == true }
        .map { $0.resolvingSymlinksInPath() }
}

// MARK: 1. Recovery names never collide

@Suite struct RecoveryNamingTests {
    @Test func concurrentKeepsNeverOverwriteEachOther() throws {
        let notes = try TempNotes([:])
        var lost = 0
        for pair in 0..<64 {
            let recovery = notes.recovery.appendingPathComponent("pair-\(pair)")
            let sources = (0..<2).map { notes.root.appendingPathComponent("source-\(pair)-\($0).md") }
            for (i, source) in sources.enumerated() { try Data("UNIQUE-\(i)".utf8).write(to: source) }
            DispatchQueue.concurrentPerform(iterations: 2) { i in
                _ = NoteFile.keep(sources[i], name: "A.md", in: recovery)
            }
            let survivors = try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
            lost += 2 - Set(try survivors.map { try String(contentsOf: $0, encoding: .utf8) }).count
            #expect(sources.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        }
        #expect(lost == 0)
    }

    @Test func namesCarryATimestampTheNoteAndARandomSuffix() throws {
        let notes = try TempNotes([:])
        let source = notes.root.appendingPathComponent("x")
        try Data("x".utf8).write(to: source)
        let kept = NoteFile.keep(source, name: "Garden shed.md", in: notes.recovery)
        #expect(kept.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}T\d{6}-Garden shed-[a-z0-9]{6}\.md$"#, options: .regularExpression) != nil)
    }
}

// MARK: 2. Pending files live in ParkBar's own folder, and survive a crash

@Suite struct PendingStorageTests {
    @Test(arguments: [NoteFile.ReplaceStep.swapped, .swappedBack])
    func aWriteInterruptedAfterASwapIsRecoveredAtTheNextStart(_ stop: NoteFile.ReplaceStep) throws {
        let original = "---\nnext: old\n---\nORIGINAL PROSE\n"
        let notes = try TempNotes(["A": original])
        let url = notes.url("A")
        do {
            try NoteFile.replace(url, expecting: NoteFile.hash(Data(original.utf8)), with: Data("---\nnext: OURS\n---\nORIGINAL PROSE\n".utf8),
                                 storage: notes.storage, step: { step in
                if step == .prepared { saveAsAnotherApp(.append, to: url, original: "", marker: "EXTERNAL FIRST SAVE") }
                if stop == .swappedBack && step == .swapped { saveAsAnotherApp(.append, to: url, original: "", marker: "EXTERNAL SECOND SAVE") }
                if step == stop { throw SimulatedCrash() }
            })
            Issue.record("expected the simulated crash")
        } catch is SimulatedCrash {}
        let waiting = pendingFiles(notes.storage)
        #expect(waiting.count == 1, "the displaced version waits in pending/, outside the system's temporary items")
        #expect(waiting.allSatisfy { $0.path.hasPrefix(notes.storage.pending.resolvingSymlinksInPath().path) })

        let result = notes.storage.reconcile()
        #expect(result.recovered.count == 1 && result.stuck.isEmpty)
        #expect(pendingFiles(notes.storage).isEmpty)
        let versions = [try notes.text("A")] + recovered(notes)
        #expect(versions.contains { $0.contains("EXTERNAL FIRST SAVE") })
        if stop == .swappedBack { #expect(versions.contains { $0.contains("EXTERNAL SECOND SAVE") }) }
        #expect(versions.allSatisfy { $0.contains("ORIGINAL PROSE") })
    }

    @Test func reconcileLeavesALiveProcessAloneAndTakesADeadOnes() throws {
        let notes = try TempNotes([:])
        let fm = FileManager.default
        let live = notes.storage.pending.appendingPathComponent("1.abcdef")          // launchd: always running
        let dead = notes.storage.pending.appendingPathComponent("99999999.abcdef")   // no such process
        for folder in [live, dead] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("text".utf8).write(to: folder.appendingPathComponent("A.md"))
        }
        let result = notes.storage.reconcile()
        #expect(result.recovered.count == 1)
        #expect(fm.fileExists(atPath: live.appendingPathComponent("A.md").path))
        #expect(!fm.fileExists(atPath: dead.path))
    }

    @Test func aRecoveryThatCannotBeWrittenLeavesItInPending() throws {
        let notes = try TempNotes([:])
        let folder = notes.storage.pending.appendingPathComponent("99999999.abcdef")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("text".utf8).write(to: folder.appendingPathComponent("A.md"))
        try Data("not a folder".utf8).write(to: notes.storage.recovery)
        let result = notes.storage.reconcile()
        #expect(result.recovered.isEmpty)
        #expect(result.stuck.map { $0.resolvingSymlinksInPath() } == [folder.appendingPathComponent("A.md").resolvingSymlinksInPath()])
    }

    @Test func aWriteToANoteOnAnotherVolumeIsRefused() throws {
        let notes = try TempNotes(["A": effortFile()])
        let before = try notes.bytes("A")
        #expect(throws: NoteFile.ReplaceError.otherVolume) {
            try NoteFile.replace(notes.url("A"), expecting: NoteFile.hash(before), with: Data("new".utf8),
                                 storage: notes.storage, sameVolume: { _, _ in false })
        }
        #expect(try notes.bytes("A") == before)
        #expect(pendingFiles(notes.storage).isEmpty)
        let message = NotesEditor.writeError(NoteFile.ReplaceError.otherVolume, file: "A.md", storage: notes.storage).description
        #expect(message.contains("A.md") && message.contains(notes.storage.pending.path) && message.contains("nothing was changed"))
        #expect(NoteFile.sameVolume(notes.url("A"), notes.storage.root))
    }

    /// An error after the swap: deleting the displaced original fails and so does the swap back.
    @Test func anErrorAfterTheSwapKeepsBothVersions() throws {
        let notes = try TempNotes(["A": effortFile()])
        let original = try notes.bytes("A")
        let ours = Data(effortFile(next: "\"OURS\"").utf8)
        var temp: URL?
        defer { if let temp { chmod(temp.deletingLastPathComponent().path, 0o700) } }
        do {
            try NoteFile.replace(notes.url("A"), expecting: NoteFile.hash(original), with: ours, storage: notes.storage,
                                 step: { step in if step == .verified { chmod(temp!.deletingLastPathComponent().path, 0o500) } },
                                 exchange: { a, b in temp = b; return NoteFile.exchange(a, b) })
            Issue.record("expected a conflict")
        } catch NoteFile.ReplaceError.changed(let kept) {
            let kept = try #require(kept)
            #expect(try Data(contentsOf: kept) == original)
            #expect(kept.path.hasPrefix(notes.storage.root.path), "kept in ParkBar's own folders, never system temporary items")
            #expect(try notes.bytes("A") == ours)
        }
    }

    @Test(arguments: [EIO, ENOTSUP, ENOENT])
    func aFailedFirstSwapLeavesTheNoteAndNoFiles(_ failure: Int32) throws {
        let notes = try TempNotes(["A": effortFile()])
        let original = try notes.bytes("A")
        #expect(throws: NoteFile.ReplaceError.self) {
            try NoteFile.replace(notes.url("A"), expecting: NoteFile.hash(original), with: Data("OURS".utf8),
                                 storage: notes.storage, exchange: { _, _ in failure })
        }
        #expect(try notes.bytes("A") == original)
        #expect(pendingFiles(notes.storage).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: notes.recovery.path))
    }

    @Test func anUnreadableDisplacedFileIsSwappedBackNotDeleted() throws {
        let notes = try TempNotes(["A": effortFile()])
        let original = try notes.bytes("A")
        var temp: URL?
        defer { chmod(notes.url("A").path, 0o644) }
        #expect(throws: NoteFile.ReplaceError.changed(kept: nil)) {
            try NoteFile.replace(notes.url("A"), expecting: NoteFile.hash(original), with: Data("OURS".utf8), storage: notes.storage,
                                 step: { step in if step == .swapped { chmod(temp!.path, 0o000) } },
                                 exchange: { a, b in temp = b; return NoteFile.exchange(a, b) })
        }
        chmod(notes.url("A").path, 0o644)
        #expect(try notes.bytes("A") == original)
        #expect(pendingFiles(notes.storage).isEmpty)
    }

    @Test func whenRecoveryIsUnavailableTheVersionStaysInPendingAndIsNamed() throws {
        let notes = try TempNotes(["A": effortFile()])
        let original = try notes.bytes("A")
        try FileManager.default.createDirectory(at: notes.storage.root, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: notes.recovery)
        let url = notes.url("A")
        do {
            try NoteFile.replace(url, expecting: NoteFile.hash(original), with: Data(effortFile(next: "\"OURS\"").utf8), storage: notes.storage,
                                 step: { step in
                if step == .prepared { saveAsAnotherApp(.append, to: url, original: "", marker: "FIRST") }
                if step == .swapped { saveAsAnotherApp(.append, to: url, original: "", marker: "UNIQUE LATEST") }
            })
            Issue.record("expected a conflict")
        } catch NoteFile.ReplaceError.changed(let kept) {
            let kept = try #require(kept)
            #expect(kept.path.hasPrefix(notes.storage.pending.path))
            #expect(try String(contentsOf: kept, encoding: .utf8).contains("UNIQUE LATEST"))
            #expect(try notes.text("A").contains("FIRST"))
            #expect(NotesEditor.writeError(NoteFile.ReplaceError.changed(kept: kept), file: "A.md", storage: notes.storage).description.contains(kept.path))
        }
    }
}

// MARK: One external save at every step, and the accepted limits

@Suite struct ExternalSaveMatrixTests {
    @Test(arguments: NoteFile.ReplaceStep.allCases, SaveKind.allCases)
    func aSingleSaveAtAnyStepSurvives(_ point: NoteFile.ReplaceStep, _ kind: SaveKind) throws {
        let original = effortFile(body: "BASE PROSE\n")
        let notes = try TempNotes(["A": original])
        var editor = notes.editor
        var saw = false, pathPresent = true
        editor.duringWrite = { url, step in
            pathPresent = pathPresent && FileManager.default.fileExists(atPath: url.path)
            if point == .swappedBack && step == .prepared { saveAsAnotherApp(.append, to: url, original: original, marker: "FIRST") }
            if step == point {
                saw = true
                saveAsAnotherApp(kind, to: url, original: original, marker: "EXTERNAL")
            }
        }
        _ = try? editor.setNext("OURS", on: "A")
        #expect(saw && pathPresent)
        #expect(([try notes.text("A")] + recovered(notes)).contains { $0.contains("EXTERNAL") })
    }

    /// Accepted: two external saves bracket ours. Both versions are kept, one at the path and one in
    /// recovery, and the message names where.
    @Test(arguments: SaveKind.allCases)
    func twoSavesAroundOursAreBothKeptAndNamed(_ kind: SaveKind) throws {
        let original = effortFile(body: "BASE PROSE\n")
        let notes = try TempNotes(["A": original])
        var editor = notes.editor
        editor.duringWrite = { url, step in
            if step == .prepared { saveAsAnotherApp(.append, to: url, original: original, marker: "FIRST") }
            if step == .swapped { saveAsAnotherApp(kind, to: url, original: original, marker: "LATEST") }
        }
        do {
            try editor.setNext("OURS", on: "A")
            Issue.record("expected a conflict")
        } catch {
            guard case .keptInRecovery("A.md", let path) = error as? WriteError else { Issue.record("\(error)"); return }
            #expect(try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8).contains("LATEST"))
        }
        #expect(try notes.text("A").contains("FIRST"))
        #expect(recovered(notes).contains { $0.contains("LATEST") })
    }

    /// Accepted: an append through a handle opened on the old file, written after the swap, goes into a
    /// file that is then deleted. Any save that replaces a file by renaming (Obsidian's own) has this.
    @Test func anAppendThroughAHandleHeldAcrossTheSwapIsTheAcceptedLimit() throws {
        let notes = try TempNotes(["A": effortFile()])
        var editor = notes.editor
        var fd: Int32 = -1
        defer { if fd >= 0 { close(fd) } }
        editor.duringWrite = { url, step in if step == .prepared { fd = open(url.path, O_WRONLY | O_APPEND) } }
        try editor.setNext("OURS", on: "A")
        let appended = Data("\nLATE APPEND\n".utf8)
        _ = appended.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, appended.count) }
        let versions = [try notes.text("A")] + recovered(notes)
        withKnownIssue("accepted limit, documented on NoteFile.replace") {
            #expect(versions.contains { $0.contains("LATE APPEND") })
        }
    }
}

// MARK: 3. The CLI ticks only what `show` showed

@Suite struct QuestionTokenTests {
    let original = effortFile(body: "**Clarify with Bob:**\n- [ ] ORIGINAL QUESTION\n")

    @Test func aTokenTicksTheQuestionItWasShownFor() throws {
        let notes = try TempNotes(["A": original])
        let a = try #require(notes.vault.effort(named: "A"))
        let token = QuestionToken(fileHash: a.contentHash, line: try #require(a.body.questions.first).line)
        #expect(QuestionToken(token.text) == token)
        try notes.editor.setQuestion(token: token, in: "A", checked: true)
        #expect(try notes.text("A").contains("- [x] ORIGINAL QUESTION"))
    }

    @Test func aTokenFromBeforeAnEditIsRefused() throws {
        let notes = try TempNotes(["A": original])
        let a = try #require(notes.vault.effort(named: "A"))
        let token = QuestionToken(fileHash: a.contentHash, line: try #require(a.body.questions.first).line)
        let replaced = original.replacingOccurrences(of: "ORIGINAL QUESTION", with: "REPLACEMENT QUESTION")
        try Data(replaced.utf8).write(to: notes.url("A"))
        #expect(throws: WriteError.changedOnDisk("A.md")) { try notes.editor.setQuestion(token: token, in: "A", checked: true) }
        #expect(try notes.text("A") == replaced)
    }

    @Test func badTokensAreNotTokens() {
        #expect(QuestionToken("1") == nil)
        #expect(QuestionToken("zzzzzzzzzzzz:3") == nil)
        #expect(QuestionToken("0123456789ab:x") == nil)
    }

    @Test func theCLIRefusesATickAfterTheQuestionWasReplaced() throws {
        let notes = try TempNotes(["A": original])
        let cliURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/debug/parkbar-cli")
        try #require(FileManager.default.isExecutableFile(atPath: cliURL.path), "build the CLI first")
        func cli(_ args: [String]) throws -> (Int32, String) {
            let p = Process()
            p.executableURL = cliURL
            p.arguments = ["--notes", notes.root.path] + args
            p.environment = ["PARKBAR_SUPPORT": notes.storage.root.path]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try p.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: output, as: UTF8.self))
        }
        let (_, shown) = try cli(["show", "A"])
        let token = try #require(shown.firstMatch(of: #/token ([0-9a-f]{12}:\d+)/#)?.1).description
        #expect(shown.contains("ORIGINAL QUESTION"))
        try Data(original.replacingOccurrences(of: "ORIGINAL QUESTION", with: "REPLACEMENT QUESTION").utf8).write(to: notes.url("A"))
        let (status, output) = try cli(["tick", "A", token])
        #expect(status != 0 && output.contains("changed on disk"))
        #expect(try notes.text("A").contains("- [ ] REPLACEMENT QUESTION"))
        let (_, again) = try cli(["show", "A"])
        let fresh = try #require(again.firstMatch(of: #/token ([0-9a-f]{12}:\d+)/#)?.1).description
        #expect(try cli(["tick", "A", fresh]).0 == 0)
        #expect(try notes.text("A").contains("- [x] REPLACEMENT QUESTION"))
    }

    /// `--config $EMPTY` from a script leaves a bare `--config`; it must stop the run, not be skipped.
    @Test(arguments: [["set-next", "A", "new", "--config"], ["set-next", "A", "new", "--config", "--notes", "/x"],
                      ["set-next", "A", "new", "--notes"]])
    func anOptionWithoutItsValueStopsTheRun(_ args: [String]) throws {
        let notes = try TempNotes(["A": original])
        let cliURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/debug/parkbar-cli")
        try #require(FileManager.default.isExecutableFile(atPath: cliURL.path), "build the CLI first")
        let p = Process()
        p.executableURL = cliURL
        p.arguments = args
        p.environment = ["PARKBAR_SUPPORT": notes.storage.root.path, "PARKBAR_NOTES": notes.root.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        #expect(p.terminationStatus != 0)
        #expect(output.contains("needs a value"))
        #expect(try notes.text("A") == original)
    }
}

// MARK: 4. A failed rollback names the cause and every file it could not put back

@Suite struct RollbackReportTests {
    @Test func theCauseAndEachRollbackFailureAreReported() throws {
        let notes = try TempNotes(["A": effortFile(priority: "1"), "B": effortFile(priority: "2"), "C": effortFile(priority: "3")])
        var editor = notes.editor
        editor.beforeWrite = { url in
            guard url.lastPathComponent == "C.md" else { return }
            // Obsidian edits A and B after ParkBar wrote them, then saves C.
            for name in ["A", "B", "C"] { try! Data((try! notes.text(name) + "\nedited\n").utf8).write(to: notes.url(name)) }
        }
        // All three numbers change (C 3→1, A 1→2, B 2→3); files are written A, B, C.
        do {
            try editor.reorder(subset: ["C", "A", "B"])
            Issue.record("expected a failure")
        } catch let error as WriteError {
            #expect(error == .partiallySaved(cause: .changedOnDisk("C.md"), leftChanged: ["A.md (changed since)", "B.md (changed since)"]))
            let text = error.description
            #expect(text.contains("C.md changed on disk") && text.contains("A.md") && text.contains("B.md"))
            #expect(!text.contains("nothing was changed"))
        }
    }
}
