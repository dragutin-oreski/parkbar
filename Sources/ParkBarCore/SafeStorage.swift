import Darwin
import Foundation

/// ParkBar's own folders, outside the notes: `pending/` holds a write's temporary file and the version it
/// displaces while the write runs (durable, unlike the system's temporary items, so a crash strands
/// nothing where macOS may purge it); `recovery/` keeps any version a write displaced but could not prove
/// redundant. Nothing in either is ever deleted by ParkBar.
public struct SafeStorage: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static let environmentKey = "PARKBAR_SUPPORT"

    /// `~/Library/Application Support/ParkBar`, or `$PARKBAR_SUPPORT` (tests and development).
    public static var standard: SafeStorage { standard(environment: ProcessInfo.processInfo.environment) }

    public static func standard(environment: [String: String]) -> SafeStorage {
        if let custom = environment[environmentKey], !custom.isEmpty {
            return SafeStorage(root: URL(fileURLWithPath: custom, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return SafeStorage(root: support.appendingPathComponent("ParkBar", isDirectory: true))
    }

    public var pending: URL { root.appendingPathComponent("pending", isDirectory: true) }
    public var recovery: URL { root.appendingPathComponent("recovery", isDirectory: true) }

    /// A fresh folder in `pending/` for one write, named `<pid>.<random>` so `reconcile` can tell a write
    /// still running in another process from one a dead process left behind.
    func newWriteFolder() throws -> URL {
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        for _ in 0..<8 {
            let folder = pending.appendingPathComponent("\(getpid()).\(Self.randomSuffix())", isDirectory: true)
            if mkdir(folder.path, 0o700) == 0 { return folder }
            guard errno == EEXIST else { break }
        }
        throw CocoaError(.fileWriteUnknown)
    }

    public struct Reconciled: Equatable, Sendable {
        /// Versions moved into `recovery/`.
        public var recovered: [URL] = []
        /// Versions that could not be moved; they stay in `pending/`, where nothing deletes them.
        public var stuck: [URL] = []
    }

    /// Run at app and CLI start: moves into `recovery/` everything a write left in `pending/` when its
    /// process died. Folders of a process that is still running are left alone.
    public func reconcile() -> Reconciled {
        let fm = FileManager.default
        var result = Reconciled()
        let entries = (try? fm.contentsOfDirectory(at: pending, includingPropertiesForKeys: nil)) ?? []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isFolder: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isFolder) else { continue }
            guard isFolder.boolValue else {
                settle(entry, name: entry.lastPathComponent, into: &result)
                continue
            }
            if let pid = Int32(entry.lastPathComponent.prefix { $0 != "." }), pid != getpid(), Self.isRunning(pid) { continue }
            let files = (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                settle(file, name: file.lastPathComponent, into: &result)
            }
            rmdir(entry.path)
        }
        return result
    }

    private func settle(_ file: URL, name: String, into result: inout Reconciled) {
        let kept = NoteFile.keep(file, name: name, in: recovery)
        if kept == file { result.stuck.append(file) } else { result.recovered.append(kept) }
    }

    static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func randomSuffix() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}

extension NoteFile {
    /// Moves `file` to `<recovery>/<timestamp>-<name>-<random>.md` without ever replacing anything there:
    /// the move is `RENAME_EXCL`, and a taken name is retried with a new random suffix. Across volumes it
    /// copies into a newly created file instead, letting the original go only once the copy is identical.
    /// If nothing works the file stays where it is. Returns where it is.
    static func keep(_ file: URL, name: String, in recovery: URL) -> URL {
        guard (try? FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)) != nil else { return file }
        let base = "\(stampFormatter.string(from: Date()))-\((name as NSString).deletingPathExtension)"
        for _ in 0..<16 {
            let target = recovery.appendingPathComponent("\(base)-\(SafeStorage.randomSuffix()).md")
            if renamex_np(file.path, target.path, UInt32(RENAME_EXCL)) == 0 { return target }
            switch errno {
            case EEXIST: continue
            case EXDEV: return copyExclusively(file, to: target) ? target : file
            default: return file
            }
        }
        return file
    }

    /// Copies into a file this call creates (`O_EXCL`), then removes the source once the copy reads back
    /// identical. False, with the source untouched, on any failure.
    static func copyExclusively(_ file: URL, to target: URL) -> Bool {
        guard let bytes = try? Data(contentsOf: file) else { return false }
        let fd = open(target.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return false }
        let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, bytes.count) }
        let synced = fsync(fd) == 0
        close(fd)
        guard written == bytes.count, synced, (try? Data(contentsOf: target)) == bytes else { return false }
        unlink(file.path)
        return true
    }

    /// Both on one volume, so a rename (and a swap) between them works: same volume identifier and device.
    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let va = try? a.resourceValues(forKeys: keys).volumeIdentifier,
              let vb = try? b.resourceValues(forKeys: keys).volumeIdentifier, va.isEqual(vb) else { return false }
        var sa = stat(), sb = stat()
        return stat(a.path, &sa) == 0 && stat(b.path, &sb) == 0 && sa.st_dev == sb.st_dev
    }

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return f
    }()
}
