import AppKit
import ParkBarCore
import SwiftUI

/// The menu bar indicator: the parking sign from the panel's header, plus an orange number when targets
/// are due or late and a blue one for open Inbox todos. Drawn into an NSImage so the numbers keep their
/// colours (menu bar text is always monochrome). With a number showing the image is not a template, so the
/// sign takes its colour from `scheme`. A key or bell mark shows while a recent alert is listed: the renderer would otherwise draw it black on a dark menu bar.
@MainActor
enum MenuBarIcon {
    static func image(dueOrLate: Int, inbox: Int, alert: String? = nil, scheme: ColorScheme) -> NSImage {
        let renderer = ImageRenderer(content: Glyph(dueOrLate: dueOrLate, inbox: inbox, alert: alert).environment(\.colorScheme, scheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "parkingsign.square", accessibilityDescription: "ParkBar")!
        image.isTemplate = dueOrLate == 0 && inbox == 0 && alert == nil
        return image
    }

    struct Glyph: View {
        let dueOrLate: Int
        let inbox: Int
        /// The newest recent alert's symbol, if any.
        var alert: String?

        var body: some View {
            HStack(spacing: 3) {
                Image(systemName: "parkingsign.square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(dueOrLate == 0 && inbox == 0 && alert == nil ? Color.black : Color.primary)
                if let alert {
                    Image(systemName: alert).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.late)
                }
                if dueOrLate > 0 { number(dueOrLate, Theme.late) }
                if inbox > 0 { number(inbox, Theme.accent) }
            }
            .padding(.vertical, 1)
        }

        private func number(_ count: Int, _ colour: Color) -> some View {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(colour)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: MenuBarIcon.image(dueOrLate: model.vault.dueOrLateCount(today: model.today), inbox: model.vault.inbox.count,
                                         alert: model.recentAlerts.first.map { $0.symbol ?? "bell.fill" }, scheme: scheme))
    }
}
