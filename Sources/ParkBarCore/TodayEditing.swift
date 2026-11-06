import Foundation

/// Writes to `today.md`, the one file outside `efforts/` that ParkBar writes. Each change is made against
/// the plan as the vault read it: if the file changed since, nothing is written ("changed on disk").
extension NotesEditor {
    @discardableResult
    public func addToday(_ text: String, today: Day = .today()) throws -> [String] {
        guard TodayPlan.cleaned(text) != nil else { return [] }
        return try writeToday(vault.todayPlan.adding(text, today: today))
    }

    @discardableResult
    public func setToday(_ item: TodayPlan.Item, checked: Bool, today: Day = .today()) throws -> [String] {
        try writeToday(vault.todayPlan.setting(item, checked: checked, today: today))
    }

    @discardableResult
    public func removeToday(_ item: TodayPlan.Item, today: Day = .today()) throws -> [String] {
        try writeToday(vault.todayPlan.removing(item, today: today))
    }

    /// Moves an open item from an earlier day into today's plan.
    @discardableResult
    public func keepForToday(_ item: TodayPlan.Item, today: Day = .today()) throws -> [String] {
        try writeToday(vault.todayPlan.keeping(item, today: today))
    }

    private func writeToday(_ text: String) throws -> [String] {
        let name = Vault.todayFile
        let url = vault.root.appendingPathComponent(name)
        let readOnly = ([Vault.todoFile] + vault.config.agendaLists.map(\.file)).compactMap { other in
            FileIdentity(vault.root.appendingPathComponent(other)).map { (other, $0) }
        }

        guard let expected = vault.todayPlan.hash else {
            // No file when the vault was read: create it, but never over one that appeared since.
            guard !FileManager.default.fileExists(atPath: url.path),
                  (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else {
                throw WriteError.changedOnDisk(name)
            }
            do {
                try Data(text.utf8).write(to: url, options: .withoutOverwriting)
            } catch {
                throw FileManager.default.fileExists(atPath: url.path) ? WriteError.changedOnDisk(name) : WriteError.saveFailed(name)
            }
            return []
        }

        guard let file = try? NoteFile.read(url), file.hash == expected else { throw WriteError.changedOnDisk(name) }
        if let identity = FileIdentity(file.url), let match = readOnly.first(where: { $0.1 == identity }) {
            throw WriteError.sharesAReadOnlyFile(file: name, other: match.0)
        }
        let efforts = vault.root.appendingPathComponent(Vault.effortsFolder, isDirectory: true)
        guard (try? file.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              !Self.isEffortFile(file.url, efforts: efforts) else {
            throw WriteError.notAnEffortFile(file: name, target: Self.shortPath(file.url, under: vault.root))
        }
        guard text != file.text else { return [] }
        do {
            try NoteFile.replace(file.url, expecting: expected, with: file.bytes(for: text), storage: storage)
        } catch {
            throw Self.writeError(error, file: name, storage: storage)
        }
        return []
    }
}
