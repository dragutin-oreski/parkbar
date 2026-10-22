import Foundation

/// Which notes folder and settings the app shows, and what choosing a folder or trying the example notes
/// does to them. `$PARKBAR_NOTES` decides the folder when set; the examples never change the user's config.
public struct NotesSetup: Equatable, Sendable {
    public enum ChoiceError: Error, Equatable, CustomStringConvertible {
        /// `$PARKBAR_NOTES` is set, so a folder chosen here would not be the one `/park` writes to.
        case environmentInCharge
        case config(ParkBarConfig.SaveError)

        public var description: String {
            switch self {
            case .environmentInCharge:
                return "\(ParkBarConfig.environmentKey) is set, so it decides the notes folder (for /park too). Unset it to choose a folder here."
            case .config(let error): return error.description
            }
        }
    }

    /// The example notes being shown: a fresh copy, read with the examples' own settings.
    public struct Trial: Equatable, Sendable {
        public let folder: URL
        public let config: ParkBarConfig
    }

    public let configURL: URL
    let environment: [String: String]
    /// The user's own config, as last read.
    public private(set) var own: ParkBarConfig.Loaded
    public private(set) var trial: Trial?

    public init(configURL: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.configURL = configURL
        self.environment = environment
        own = ParkBarConfig.load(from: configURL)
    }

    public var isShowingExamples: Bool { trial != nil }

    /// True when `$PARKBAR_NOTES` picks the folder (and the examples are not showing).
    public var folderIsFromEnvironment: Bool {
        trial == nil && !(environment[ParkBarConfig.environmentKey] ?? "").isEmpty
    }

    public var folder: URL { trial?.folder ?? own.config.notesURL(environment: environment) }
    public var config: ParkBarConfig { trial?.config ?? own.config }
    /// What is wrong with the user's config file, while their notes are showing.
    public var problems: [String] { trial == nil ? own.problems : [] }

    /// Why choosing a folder would be refused, from the config file as it is now. Changes nothing.
    public func choiceBlocker() -> ChoiceError? {
        if !(environment[ParkBarConfig.environmentKey] ?? "").isEmpty { return .environmentInCharge }
        if case .unreadable(let reason) = ParkBarConfig.load(from: configURL).file { return .config(.unreadable(reason)) }
        return nil
    }

    /// Makes `folder` the notes folder and remembers it in the config, leaving the examples. Refused while
    /// `$PARKBAR_NOTES` is set or the config file cannot be read.
    public mutating func choose(_ folder: URL) throws {
        if !(environment[ParkBarConfig.environmentKey] ?? "").isEmpty { throw ChoiceError.environmentInCharge }
        do {
            try ParkBarConfig.saveNotesFolder(folder, to: configURL)
        } catch let error as ParkBarConfig.SaveError {
            throw ChoiceError.config(error)
        }
        trial = nil
        own = ParkBarConfig.load(from: configURL)
    }

    /// Shows a fresh copy of the example notes, dated `today`, with the examples' settings.
    public mutating func tryExamples(_ examples: ExampleNotes, storage: SafeStorage, today: Day = .today()) throws {
        let copy = try examples.copy(into: storage, today: today)
        trial = Trial(folder: copy, config: examples.config)
    }

    /// Back to the user's own notes and settings, read again.
    public mutating func leaveExamples() {
        trial = nil
        own = ParkBarConfig.load(from: configURL)
    }
}
