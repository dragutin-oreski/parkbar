import ParkBarCore
import SwiftUI

/// What a popover saw when it opened. Saves go against this hash, not the vault at Save time, so a
/// change made meanwhile (Obsidian, /park) is never overwritten with stale values.
struct OpenedFrom {
    var hash: String

    /// Message shown when the file changed while the popover was open.
    static let reopened = "changed on disk — reopened with the new value"
}

/// Popover for an effort's target date.
struct TargetEditor: View {
    @ObservedObject var model: AppModel
    let effort: Effort
    let done: () -> Void
    @State private var date: Date
    @State private var opened: OpenedFrom
    /// The last save's error, shown in the popover (which stays open).
    @State private var error: String?

    init(model: AppModel, effort: Effort, done: @escaping () -> Void) {
        self.model = model
        self.effort = effort
        self.done = done
        _date = State(initialValue: (effort.target ?? model.today).localDate)
        _opened = State(initialValue: OpenedFrom(hash: effort.contentHash))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target for \(effort.name)").font(.headline)
            Text("The day you aim to have the next step done.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("Target", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            EditorError(text: error)
            HStack {
                Button("Clear") { save(nil) }
                    .disabled(effort.target == nil)
                Spacer()
                Button("Cancel", action: done)
                    .keyboardShortcut(.cancelAction)
                Button("Set") { save(Day(date)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    /// Closes only on success. Changed on disk: shows the new value. Any other error: keeps what was picked.
    private func save(_ day: Day?) {
        let hash = opened.hash
        switch model.edit({ try $0.setTarget(day, on: effort.name, expectedHash: hash) }) {
        case nil:
            done()
        case .changedOnDisk?:
            if let fresh = model.vault.effort(named: effort.name) {
                date = (fresh.target ?? model.today).localDate
                opened = OpenedFrom(hash: fresh.contentHash)
            }
            error = OpenedFrom.reopened
            model.problem = OpenedFrom.reopened
        case let failure?:
            error = failure.description
        }
    }
}

/// Popover for an effort's one-line next step.
struct NextEditor: View {
    @ObservedObject var model: AppModel
    let effort: Effort
    let done: () -> Void
    @State private var text: String
    @State private var opened: OpenedFrom
    /// The last save's error, shown in the popover (which stays open).
    @State private var error: String?

    init(model: AppModel, effort: Effort, done: @escaping () -> Void) {
        self.model = model
        self.effort = effort
        self.done = done
        _text = State(initialValue: effort.next ?? "")
        _opened = State(initialValue: OpenedFrom(hash: effort.contentHash))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next step for \(effort.name)").font(.headline)
            TextField("What to do next", text: $text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            EditorError(text: error)
            HStack {
                Spacer()
                Button("Cancel", action: done)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    /// Closes only on success. Changed on disk: shows the new value. Any other error: keeps what was typed.
    private func save() {
        let hash = opened.hash, value = text
        switch model.edit({ try $0.setNext(value, on: effort.name, expectedHash: hash) }) {
        case nil:
            done()
        case .changedOnDisk?:
            if let fresh = model.vault.effort(named: effort.name) {
                text = fresh.next ?? ""
                opened = OpenedFrom(hash: fresh.contentHash)
            }
            error = OpenedFrom.reopened
            model.problem = OpenedFrom.reopened
        case let failure?:
            error = failure.description
        }
    }
}

/// A save's error inside its popover, so it is seen where the input is.
private struct EditorError: View {
    let text: String?

    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.late)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension Day {
    /// Local midnight of this day, for date pickers.
    var localDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}
