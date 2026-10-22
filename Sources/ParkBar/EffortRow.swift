import ParkBarCore
import SwiftUI

/// One effort in a list, on a card: rank (a drag handle on hover), name, target, copy-resume, and the
/// next step below.
struct EffortRow: View {
    @ObservedObject var model: AppModel
    let effort: Effort
    /// Place in the drag order; nil for archived efforts.
    let rank: Int?
    @State private var editingTarget = false
    @State private var editingNext = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let rank {
                ZStack {
                    Badge(text: "\(rank)").opacity(hovering ? 0 : 1)
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .opacity(hovering ? 1 : 0)
                }
                .frame(width: 20)
                .padding(.top, 3)
                .help("Drag to reorder")
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(effort.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if effort.status != .active && effort.status != .archived {
                        Badge(text: effort.status.text.uppercased())
                            .help("Kept out of the drag order until its fields are fixed")
                    }
                    Spacer(minLength: 6)
                    targetArea
                    CopyResumeButton(model: model, effort: effort)
                }
                .frame(minHeight: 22)
                Text(effort.next ?? "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .interactive { next in
                        next.popover(isPresented: $editingNext, arrowEdge: .bottom) {
                            NextEditor(model: model, effort: effort) { editingNext = false }
                        }
                    }
            }
        }
        .padding(.leading, rank == nil ? 12 : 8)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(hovering ? Theme.cardHover : Theme.card,
                    in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.openEffort = effort.name }
        .interactive { $0.contextMenu { menu } }
    }

    /// The target pill, or for an active effort without one a faint "Set target" on hover. Both open the
    /// same editor as the context menu; the stack stays put so the popover keeps its anchor.
    private var targetArea: some View {
        let editable = effort.status == .active
        return ZStack(alignment: .trailing) {
            if let target = effort.target, editable {
                Button { editingTarget = true } label: { TargetPill(target: target, today: model.today) }
                    .buttonStyle(.plain)
                    .help("Change the target")
            } else if let target = effort.target {
                TargetPill(target: target, today: model.today)
            } else if editable && (hovering || editingTarget) {
                Button { editingTarget = true } label: {
                    Label("Set target", systemImage: "calendar.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 1, height: 16)
            }
        }
        .interactive { area in
            area.popover(isPresented: $editingTarget, arrowEdge: .trailing) {
                TargetEditor(model: model, effort: effort) { editingTarget = false }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if effort.status == .active {
            Button("Set target…") { editingTarget = true }
            Button("Clear target") { model.edit { try $0.setTarget(nil, on: effort.name) } }
                .disabled(effort.target == nil)
            Button("Edit next…") { editingNext = true }
            Divider()
            Button("Archive") { model.edit { try $0.archive(effort.name) } }
        } else {
            Button("Make active") { model.activate(effort.name) }
        }
        Divider()
        Button("Copy resume command") { model.copyResume(effort) }
            .disabled(effort.resume == nil)
        Button(model.opensInObsidian ? "Open in Obsidian" : "Open Note") { model.openNote(effort) }
    }
}

/// Copies the resume command and shows a checkmark for a moment; an empty slot when there is none.
struct CopyResumeButton: View {
    @ObservedObject var model: AppModel
    let effort: Effort
    @State private var copiedAt: Date?

    var body: some View {
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
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: copied ? .bold : .regular))
                    .foregroundStyle(copied ? Theme.ok : Theme.text2)
            }
            .buttonStyle(IconButtonStyle())
            .help(copied ? "Copied" : "Copy the resume command")
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }
}
