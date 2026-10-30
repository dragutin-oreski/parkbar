import ParkBarCore
import SwiftUI

/// The Inbox, if it has open todos, then the active efforts in drag order, with the cold ones folded away
/// underneath.
struct EffortsTab: View {
    @ObservedObject var model: AppModel
    @State private var showCold = false

    var body: some View {
        let inbox = model.vault.inbox
        let current = model.vault.current(today: model.today)
        let cold = model.vault.cold(today: model.today)
        PanelScroll {
            VStack(alignment: .leading, spacing: 8) {
                if !inbox.isEmpty {
                    InboxSection(model: model, todos: inbox)
                        .padding(.bottom, 4)
                }
                if current.isEmpty && cold.isEmpty {
                    EmptyState(symbol: "parkingsign", text: "Nothing parked. /park writes efforts into \(Vault.effortsFolder)/.")
                }
                if !current.isEmpty {
                    Theme.sectionTitle("In play").padding(.leading, 4)
                    ReorderableList(model: model, efforts: current)
                }
                if !cold.isEmpty {
                    Button { showCold.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(showCold ? 90 : 0))
                                .foregroundStyle(Theme.text3)
                            Theme.sectionTitle("Cold")
                            Badge(text: "\(cold.count)")
                            Text("untouched \(model.vault.config.coldAfterDays)+ days, no target")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.text3)
                            Spacer()
                        }
                        .padding(.leading, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showCold {
                        ReorderableList(model: model, efforts: cold)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

/// An SF Symbol over a line of help, for a list with nothing in it.
struct EmptyState: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.text3)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}

/// Rows you can drag onto each other: dropping on a row puts the dragged effort just above it.
struct ReorderableList: View {
    @ObservedObject var model: AppModel
    let efforts: [Effort]
    @State private var dropTarget: String?
    @State private var endTargeted = false

    private var names: [String] { efforts.map(\.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(efforts) { effort in
                EffortRow(model: model, effort: effort, rank: model.vault.rank(of: effort.name))
                    .overlay(alignment: .top) { insertionLine(visible: dropTarget == effort.name).offset(y: -4) }
                    .interactive { row in
                        row.draggable(DraggedEffort(effort).payload)
                            .dropDestination(for: String.self) { items, _ in
                                guard let dragged = items.first.flatMap(DraggedEffort.init(payload:)) else { return false }
                                model.drop(dragged, before: effort.name, within: names)
                                return true
                            } isTargeted: { dropTarget = $0 ? effort.name : (dropTarget == effort.name ? nil : dropTarget) }
                    }
            }
            if !efforts.isEmpty {
                // Dropping below the last row moves to the end of this list.
                Color.clear
                    .frame(height: 8)
                    .overlay(alignment: .top) { insertionLine(visible: endTargeted) }
                    .interactive { zone in
                        zone.dropDestination(for: String.self) { items, _ in
                            guard let dragged = items.first.flatMap(DraggedEffort.init(payload:)) else { return false }
                            model.drop(dragged, before: nil, within: names)
                            return true
                        } isTargeted: { endTargeted = $0 }
                    }
            }
        }
    }

    private func insertionLine(visible: Bool) -> some View {
        Capsule()
            .fill(Theme.accent)
            .frame(height: 2)
            .padding(.horizontal, 4)
            .opacity(visible ? 1 : 0)
    }
}
