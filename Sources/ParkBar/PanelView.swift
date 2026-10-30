import ParkBarCore
import SwiftUI

/// The window under the menu bar icon: header, tabs, the open tab or detail, footer.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.isSnapshot) private var isSnapshot
    /// When the notes were last read, for the footer; the panel window stays alive between openings.
    @State private var reloadedAt = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            TabBar(model: model)
            Divider()
            if let problem = model.problem ?? (model.vault.hasEffortsFolder ? model.vault.problems.first : nil)
                ?? (model.setup.problems.isEmpty ? nil : model.setup.problems.joined(separator: " · ")) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(problem).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.late)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.late.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            if model.setup.isShowingExamples {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Showing a copy of the example notes").lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Back to my notes") { model.leaveExamples() }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            if let notice = model.recoveryNotice {
                HStack(spacing: 6) {
                    Image(systemName: "lifepreserver")
                    Text(notice).lineLimit(1).truncationMode(.tail).help(model.recoveredFiles.map(\.path).joined(separator: "\n"))
                    Spacer(minLength: 4)
                    Button("Show") { model.revealRecovered() }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                    Button { model.recoveryNotice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .help("Dismiss")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            content
                .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: Theme.panelWidth, height: isSnapshot ? nil : Theme.panelHeight)
        .background {
            // A rendered PNG cannot draw the material, and its stand-in ignores dark mode.
            if isSnapshot { Color(nsColor: .windowBackgroundColor) } else { Rectangle().fill(.ultraThinMaterial) }
        }
        .overlay(alignment: .bottom) { toast }
        .onReceive(model.$vault) { _ in reloadedAt = Date() }
    }

    @ViewBuilder
    private var content: some View {
        if let name = model.openEffort, let effort = model.vault.effort(named: name) {
            EffortDetailView(model: model, effort: effort)
        } else if model.vault.efforts.isEmpty && model.vault.inbox.isEmpty {
            WelcomeView(model: model)
        } else {
            switch model.tab {
            case .efforts: EffortsTab(model: model)
            case .people: PeopleTab(model: model)
            case .archived: ArchivedTab(model: model)
            }
        }
    }

    private var header: some View {
        let current = model.vault.current(today: model.today).count
        let due = model.vault.dueOrLateCount(today: model.today)
        let inbox = model.vault.inbox.count
        return HStack(spacing: 10) {
            AppMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("ParkBar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(current) in play · \(model.vault.activeOrder.count - current) cold")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
            }
            Spacer()
            HStack(spacing: 6) {
                if due > 0 { pill("\(due) due or late", symbol: "calendar.badge.exclamationmark", tint: Theme.late) }
                if inbox > 0 { pill("\(inbox) in Inbox", symbol: "tray", tint: Theme.accent) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// A count in the header, in the colour the menu bar gives it.
    private func pill(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { model.chooseFolder() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("\(model.root.lastPathComponent)\(model.setup.folderIsFromEnvironment ? " (\(ParkBarConfig.environmentKey))" : "") · read \(Self.ago(reloadedAt, now: context.date))")
                    }
                    .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.setup.folderIsFromEnvironment
                ? "\(model.root.path)\nSet by \(ParkBarConfig.environmentKey); unset it to choose a folder here"
                : "\(model.root.path)\nClick to choose another notes folder")
            Spacer()
            Button { model.reload() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(IconButtonStyle())
            .help("Read the notes again")
            Button { NSApplication.shared.terminate(nil) } label: {
                Text("Quit").font(.system(size: 11, weight: .medium)).padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .font(.caption)
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// "just now", "4 min ago", "2 h ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        return "\(Int(seconds / 3600)) h ago"
    }

    @ViewBuilder
    private var toast: some View {
        if let text = model.toast {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .padding(.bottom, 48)
                .transition(.opacity)
        }
    }
}

/// Efforts | People | Archived, with counts, as one segmented track. Plain buttons, so the bar also
/// renders in snapshots.
struct TabBar: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppModel.Tab.allCases, id: \.self) { tab in
                let selected = model.tab == tab
                Button {
                    model.tab = tab
                    model.openEffort = nil
                    model.openPerson = nil
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Theme.text : Theme.text2)
                        Text("\(count(tab))")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(selected ? Theme.accent : Theme.text3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background(selected ? selectedFill : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(selected && scheme == .light ? 0.08 : 0), radius: 1, y: 0.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var selectedFill: Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.white
    }

    private func count(_ tab: AppModel.Tab) -> Int {
        switch tab {
        case .efforts: return model.vault.activeOrder.count
        case .people: return model.vault.people().count
        case .archived: return model.vault.archived.count
        }
    }
}
