import ParkBarCore
import SwiftUI

/// One effort read in the panel: where I am, questions, then, todos — and the way back in.
struct EffortDetailView: View {
    @ObservedObject var model: AppModel
    let effort: Effort
    @State private var showAll = false
    @State private var editingTarget = false
    @State private var copiedAt: Date?

    var body: some View {
        VStack(spacing: 0) {
            top
            Divider()
            PanelScroll {
                VStack(alignment: .leading, spacing: 8) {
                    whereIAm
                    questions
                    if let then = effort.body.latestThen, !then.text.isEmpty {
                        section("Then", symbol: "arrow.turn.down.right") { prose(then.text) }
                    }
                    todos
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            Divider()
            buttons
        }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { model.openEffort = nil } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text(model.tab.rawValue)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("updated \(Labels.updated(effort.updated, today: model.today))")
                    .font(.caption)
                    .foregroundStyle(Theme.text3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(effort.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let about = effort.about {
                    Text(about).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            HStack(spacing: 6) {
                if effort.status == .active { priorityChip } else { chip(effort.status.text.capitalized, symbol: "archivebox") }
                Button { editingTarget = true } label: {
                    if let target = effort.target {
                        TargetPill(target: target, today: model.today)
                    } else {
                        chip("Set target", symbol: "calendar.badge.plus")
                    }
                }
                .buttonStyle(.plain)
                .help("Change the target")
                .interactive { button in
                    button.popover(isPresented: $editingTarget, arrowEdge: .bottom) {
                        TargetEditor(model: model, effort: effort) { editingTarget = false }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// "Priority 2": a menu to move it within the main list, the same moves a drag makes. A plain chip
    /// for cold efforts (they reorder only among themselves, by dragging) and in snapshots.
    @ViewBuilder
    private var priorityChip: some View {
        let cold = model.vault.isCold(effort, today: model.today)
        let label = chip("Priority \(model.vault.rank(of: effort.name).map(String.init) ?? "—")\(cold ? " · cold" : "")",
                         symbol: cold ? "snowflake" : "arrow.up.arrow.down")
        if cold {
            label
        } else {
            label.interactive { _ in
                let list = model.vault.current(today: model.today).map(\.name)
                Menu {
                    ForEach(list.filter { $0 != effort.name }, id: \.self) { other in
                        Button("Move above \(other)") { model.drop(DraggedEffort(effort), before: other, within: list) }
                    }
                    Divider()
                    Button("Move to the bottom") { model.drop(DraggedEffort(effort), before: nil, within: list) }
                } label: {
                    label
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    private func chip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.fill, in: Capsule())
    }

    @ViewBuilder
    private var whereIAm: some View {
        if showAll {
            section("All notes", symbol: "doc.text") {
                prose(effort.body.text).textSelection(.enabled)
                moreButton("Show less", symbol: "chevron.up")
            }
        } else if let w = effort.body.latestWhereIAm {
            section(w.label, symbol: "mappin.and.ellipse") {
                prose(w.text).lineLimit(4)
                moreButton("Show all notes", symbol: "chevron.down")
            }
        } else if !effort.body.text.isEmpty {
            section("Notes", symbol: "doc.text") {
                prose(effort.body.text).lineLimit(4)
                moreButton("Show all notes", symbol: "chevron.down")
            }
        }
    }

    private func prose(_ text: String) -> some View {
        Theme.markdown(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func moreButton(_ title: String, symbol: String) -> some View {
        Button { showAll.toggle() } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var questions: some View {
        let groups = Dictionary(grouping: effort.body.questions, by: \.people)
        let order = effort.body.questions.map(\.people).reduce(into: [[String]]()) { if !$0.contains($1) { $0.append($1) } }
        ForEach(order, id: \.self) { people in
            let mine = people == [model.vault.config.meName]
            section(mine ? model.vault.config.meLabels.first ?? "Decide myself" : "Ask " + people.joined(separator: " + "), people: people) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(groups[people] ?? []) { q in
                        QuestionRow(model: model, effort: effort.name, fileHash: effort.contentHash, question: q)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var todos: some View {
        let linked = model.vault.linkedTodos(for: effort.name)
        if !linked.isEmpty {
            section("Todos", symbol: "checklist", count: linked.count) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(linked) { todo in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: "circle").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.text3)
                            prose(todo.text)
                        }
                    }
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if effort.resume != nil {
                let copied = copiedAt != nil
                Button {
                    model.copyResume(effort)
                    let now = Date()
                    copiedAt = now
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        if copiedAt == now { copiedAt = nil }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy resume command", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PanelButtonStyle(prominent: true))
                .help("Copies the command that resumes this effort's session; paste it in Terminal")
            }
            Button { model.openNote(effort) } label: {
                Label(model.opensInObsidian ? "Obsidian" : "Open", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: effort.resume == nil ? .infinity : nil)
            }
            .buttonStyle(PanelButtonStyle(prominent: effort.resume == nil))
            .help(model.opensInObsidian ? "Open this effort's file in Obsidian" : "Open this effort's file in your editor")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// A card with a small-caps title: a glyph, or the avatars of the people it is about.
    private func section<Content: View>(_ title: String, symbol: String? = nil, people: [String] = [], count: Int? = nil,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !people.isEmpty {
                    HStack(spacing: -4) {
                        ForEach(people, id: \.self) { Avatar(name: $0, size: 16, isMe: $0 == model.vault.config.meName) }
                    }
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3)
                }
                Theme.sectionTitle(title)
                if let count { Badge(text: "\(count)") }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// A question with a checkbox that writes straight back to the notes, but only to the file as it was when
/// this row was drawn (`fileHash`): a click that arrives after the note changed is refused.
struct QuestionRow: View {
    @ObservedObject var model: AppModel
    let effort: String
    let fileHash: String
    let question: EffortBody.Question

    var body: some View {
        if question.isTickable { checkbox } else { item }
    }

    /// An inline "a · b" item: shown, but there is no checkbox in the notes to flip.
    private var item: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(Theme.text3).frame(width: 4, height: 4).frame(width: 13).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1.5 }
            text.foregroundStyle(Theme.text)
        }
        .help("Written inline after the label, so there is no checkbox to tick")
    }

    private var checkbox: some View {
        Button {
            model.edit { try $0.setQuestion(question, in: effort, expectedHash: fileHash, checked: !question.isChecked) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: question.isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(question.isChecked ? Theme.accent : Theme.text3)
                text
                    .strikethrough(question.isChecked)
                    .foregroundStyle(question.isChecked ? Theme.text3 : Theme.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(question.isChecked ? "Untick" : "Tick: writes [x] into the notes")
    }

    private var text: some View {
        Theme.markdown(question.text)
            .font(.system(size: 12))
            .lineSpacing(1.5)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
