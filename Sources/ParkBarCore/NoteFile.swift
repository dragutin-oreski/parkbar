import CryptoKit
import Darwin
import Foundation

/// One notes file as bytes on disk: its text (without a byte-order mark), and how to write it back
/// without disturbing anything else about the file.
public struct NoteFile: Equatable, Sendable {
    static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// The real file, symlinks resolved.
    public let url: URL
    public let text: String
    public let hasBOM: Bool
    /// SHA-256 of the bytes on disk.
    public let hash: String

    public static func read(_ url: URL) throws -> NoteFile {
        let real = url.resolvingSymlinksInPath()
        let data = try Data(contentsOf: real)
        let hasBOM = data.starts(with: bom)
        guard let text = String(data: hasBOM ? data.dropFirst(bom.count) : data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return NoteFile(url: real, text: text, hasBOM: hasBOM, hash: hash(data))
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The bytes `text` becomes in this file: the byte-order mark comes back if it was there.
    public func bytes(for text: String) -> Data {
        (hasBOM ? Data(Self.bom) : Data()) + Data(text.utf8)
    }

    /// Why a replace did not go through.
    public enum ReplaceError: Error, Equatable {
        /// The file is not (or stopped being) the version the edit was made against. The path holds the
        /// newer version; a version that could not be proven redundant was kept at `kept`.
        case changed(kept: URL?)
        /// The write failed before anything was swapped; the file is as it was.
        case failed
        /// The volume cannot swap two files atomically, and there is no safe way without that.
        case swapUnsupported
        /// ParkBar's pending folder is not on the note's volume, so the two can't be swapped.
        case otherVolume
    }

    /// The points in `replace` where a test can inject an external save (or stop, as a crash would).
    public enum ReplaceStep: CaseIterable, Sendable {
        /// The file still had the expected hash.
        case checked
        /// The new bytes are in the pending file, with the original's permissions and attributes.
        case prepared
        /// Ours is at the path; what was there is at the pending name, not checked yet.
        case swapped
        /// What came out was the expected version; it is about to be hashed once more and deleted.
        case verified
        /// A save had slipped in, so the two were swapped back; what came out is not checked yet.
        case swappedBack
    }

    /// Puts `data` at `url` (the real file, symlinks already resolved) only while the file there is the
    /// version hashed `expected`, and returns the bytes it replaced. `data` already carries the file's
    /// byte-order mark and line endings.
    ///
    /// The path never goes missing, so an appender cannot re-create it and editors and sync tools never see
    /// a delete. Nothing is deleted unless its hash proves it redundant: the expected version this write
    /// supersedes, or our own bytes. Anything else goes to `storage.recovery`. The temporary and displaced
    /// files live in `storage.pending`, which must be on the note's volume; a crash leaves them there for
    /// the next start to move into recovery.
    /// 1. Hash the file; anything else is `.changed`, and nothing has been touched.
    /// 2. Write the new bytes to a pending file (permissions and extended attributes copied onto it).
    /// 3. Swap it with the file (`RENAME_SWAP`): ours is at the path, and the pending name now holds
    ///    whatever was at the path at that instant. No swap support: `.swapUnsupported`, nothing written.
    /// 4. Hash what came out. The expected version (still, when hashed again right before the delete):
    ///    delete it. Done.
    /// 5. Anything else is a save that slipped in: swap back, so theirs is at the path again, and hash what
    ///    came out. Exactly ours: delete it. Otherwise someone wrote to ours between the swaps: keep it.
    ///
    /// Accepted limits, not chased:
    /// - A writer holding a handle open on the old file across the swap, writing after step 4's last hash,
    ///   writes into a file that is then deleted. Any save that replaces a file by renaming has this,
    ///   Obsidian's own included.
    /// - Two external saves that bracket ours (one before step 3, one between steps 3 and 5): both are kept,
    ///   the earlier one at the path and the later one in recovery, and the error names where.
    @discardableResult
    static func replace(_ url: URL, expecting expected: String, with data: Data, storage: SafeStorage,
                        step: (ReplaceStep) throws -> Void = { _ in },
                        exchange: (URL, URL) -> Int32 = NoteFile.exchange,
                        sameVolume: (URL, URL) -> Bool = NoteFile.sameVolume) throws -> Data {
        let fm = FileManager.default
        guard let current = try? Data(contentsOf: url) else {
            throw fm.fileExists(atPath: url.path) ? ReplaceError.failed : .changed(kept: nil)
        }
        guard hash(current) == expected else { throw ReplaceError.changed(kept: nil) }
        try step(.checked)

        guard let folder = try? storage.newWriteFolder() else { throw ReplaceError.failed }
        // Only an empty folder goes: whatever is left in it was not proven redundant.
        defer { rmdir(folder.path) }
        guard sameVolume(url, folder) else { throw ReplaceError.otherVolume }
        let temp = folder.appendingPathComponent(url.lastPathComponent)
        let ours = hash(data)
        func settle(redundant: Set<String>) -> URL? {
            keepUnlessRedundant(temp, redundant: redundant, name: url.lastPathComponent, recovery: storage.recovery)
        }
        guard fm.createFile(atPath: temp.path, contents: data) else {
            _ = settle(redundant: [ours])
            throw ReplaceError.failed
        }
        do {
            if let permissions = try fm.attributesOfItem(atPath: url.path)[.posixPermissions] {
                try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
            }
        } catch {
            _ = settle(redundant: [ours])
            throw ReplaceError.failed
        }
        copyExtendedAttributes(from: url.path, to: temp.path)
        try step(.prepared)

        switch exchange(url, temp) {
        case 0: break
        case ENOTSUP:
            _ = settle(redundant: [ours])
            throw ReplaceError.swapUnsupported
        case ENOENT:
            // The note was deleted or renamed meanwhile: it stays that way.
            _ = settle(redundant: [ours])
            throw ReplaceError.changed(kept: nil)
        default:
            _ = settle(redundant: [ours])
            throw ReplaceError.failed
        }
        try step(.swapped)

        if let previous = try? Data(contentsOf: temp), hash(previous) == expected {
            try step(.verified)
            if let again = try? Data(contentsOf: temp), hash(again) == expected, unlink(temp.path) == 0 { return previous }
        }
        // A save slipped in (before the swap, or into the old file since): theirs goes back to the path.
        guard exchange(url, temp) == 0 else { throw ReplaceError.changed(kept: settle(redundant: [])) }
        try step(.swappedBack)
        throw ReplaceError.changed(kept: settle(redundant: [ours]))
    }

    /// Swaps two files atomically; 0, or the `errno` of the failure.
    static func exchange(_ a: URL, _ b: URL) -> Int32 {
        renamex_np(a.path, b.path, UInt32(RENAME_SWAP)) == 0 ? 0 : errno
    }

    /// Deletes `file` when its bytes hash to one of `redundant` (hashed right before the delete); otherwise
    /// keeps it in `recovery` and returns where it is. Nil when it was deleted or is already gone.
    static func keepUnlessRedundant(_ file: URL, redundant: Set<String>, name: String, recovery: URL) -> URL? {
        guard let bytes = try? Data(contentsOf: file) else {
            return FileManager.default.fileExists(atPath: file.path) ? keep(file, name: name, in: recovery) : nil
        }
        if redundant.contains(hash(bytes)), unlink(file.path) == 0 { return nil }
        return keep(file, name: name, in: recovery)
    }

    /// Best effort: attributes the system refuses to set (provenance, quarantine) are left to it.
    static func copyExtendedAttributes(from source: String, to target: String) {
        let size = listxattr(source, nil, 0, 0)
        guard size > 0 else { return }
        var names = [CChar](repeating: 0, count: size)
        guard listxattr(source, &names, size, 0) == size else { return }
        let all = names.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        for name in all {
            let length = getxattr(source, name, nil, 0, 0, 0)
            guard length >= 0 else { continue }
            var value = [UInt8](repeating: 0, count: length)
            guard getxattr(source, name, &value, length, 0, 0) == length else { continue }
            _ = setxattr(target, name, value, length, 0, 0)
        }
    }
}
