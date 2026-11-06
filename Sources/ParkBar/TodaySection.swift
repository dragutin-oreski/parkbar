import ParkBarCore
import SwiftUI

/// The day's plan, on one card at the top of the Efforts tab: a few things you mean to do today, ticked
/// here, plus whatever was left open on earlier days, to keep for today or drop. Kept in `today.md`.
struct TodaySection: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @FocusState private var adding: Bool

    var body: some View {
        let plan = model.vault.todayPlan
        let items = plan.items(on: model.today)
        let leftovers = plan.leftovers(on: model.today)
        let progress = plan.progress(on: model.today)
        let allDone = progress.total > 0 && progress.done == progress.total
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Theme.sectionTitle("Today")
                if progress.total > 0 {
                    Badge(text: "\(progress.done)/\(progress.total)", tint: allDone ? Theme.ok : Theme.text2,
                          background: allDone ? Theme.ok.opacity(0.14) : Theme.fill)
                }
            }
            .padding(.leading, 4)
            .help("Your plan for today, kept in \(Vault.todayFile)")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { TodayRow(model: model, item: $0) }
                if !leftovers.isEmpty {
                    Text("Left from earlier")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .padding(.top, items.isEmpty ? 0 : 4)
                    ForEach(leftovers) { LeftoverRow(model: model, item: $0) }
                }
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text3)
                    TextField(items.isEmpty ? "What do you want to get done today?" : "Add one more", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($adding)
                        .onSubmit(add)
                }
                .padding(.top, items.isEmpty && leftovers.isEmpty ? 0 : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func add() {
        guard TodayPlan.cleaned(draft) != nil else { return }
        if model.addToday(draft) { draft = "" }
        adding = true
    }
}

/// One of today's items: a circle to tick, the text, and a cross on hover to remove it.
struct TodayRow: View {
    @ObservedObject var model: AppModel
    let item: TodayPlan.Item
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Button { model.setToday(item, checked: !item.isChecked) } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.isChecked ? Theme.ok : Theme.text3)
            }
            .buttonStyle(.plain)
            .help(item.isChecked ? "Mark as not done" : "Mark as done")
            Theme.markdown(item.text)
                .font(.system(size: 12))
                .foregroundStyle(item.isChecked ? Theme.text3 : Theme.text)
                .strikethrough(item.isChecked, color: Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            SmallIconButton(symbol: "xmark", help: "Remove from today") { model.removeToday(item) }
                .opacity(hovering ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// An open item from an earlier day: keep it for today, or drop it.
struct LeftoverRow: View {
    @ObservedObject var model: AppModel
    let item: TodayPlan.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "circle.dashed").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text3)
            VStack(alignment: .leading, spacing: 1) {
                Theme.markdown(item.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.day.map { "from \(Self.label($0))" } ?? "from earlier")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 4)
            SmallIconButton(symbol: "arrow.up", help: "Keep for today") { model.keepForToday(item) }
            SmallIconButton(symbol: "xmark", help: "Drop it") { model.removeToday(item) }
        }
    }

    /// "Thu 5 Nov".
    static func label(_ day: Day) -> String {
        guard let date = day.date() else { return day.description }
        let format = DateFormatter()
        format.timeZone = TimeZone(identifier: "UTC")
        format.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return format.string(from: date)
    }
}

/// A small round icon button for a row's quick actions.
struct SmallIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.text2)
                .frame(width: 18, height: 18)
                .background(Theme.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
