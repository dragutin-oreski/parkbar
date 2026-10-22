import AppKit
import ParkBarCore
import SwiftUI

/// The menu bar indicator: the parking sign from the panel's header, plus an orange number when targets
/// are due or late. Drawn into an NSImage so the number can keep its colour (menu bar text is always
/// monochrome).
@MainActor
enum MenuBarIcon {
    static func image(dueOrLate count: Int) -> NSImage {
        let renderer = ImageRenderer(content: Glyph(count: count))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "parkingsign.square", accessibilityDescription: "ParkBar")!
        image.isTemplate = count == 0
        return image
    }

    struct Glyph: View {
        let count: Int

        var body: some View {
            HStack(spacing: 3) {
                Image(systemName: "parkingsign.square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(count == 0 ? Color.black : Color.primary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.late)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(nsImage: MenuBarIcon.image(dueOrLate: model.vault.dueOrLateCount(today: model.today)))
    }
}
