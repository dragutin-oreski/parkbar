import AppKit
import ParkBarCore
import SwiftUI

/// Sizes and colours used across the panel.
enum Theme {
    static let panelWidth: CGFloat = 420
    /// The whole panel keeps one height. A MenuBarExtra window that changes height keeps its bottom
    /// edge where it was, so going from a tall view (an effort's detail) to a shorter one moved the
    /// panel's top down, away from the menu bar.
    @MainActor static var panelHeight: CGFloat {
        min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
    }
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 10

    static let ok = Color(red: 0.22, green: 0.72, blue: 0.42)
    static let late = Color(red: 0.96, green: 0.62, blue: 0.16)
    static let critical = Color(red: 0.93, green: 0.30, blue: 0.28)
    static let accent = Color(red: 0.25, green: 0.55, blue: 0.95)

    /// Label colours set explicitly: hierarchical styles come out washed grey in a rendered PNG.
    static let text = Color(nsColor: .labelColor)
    static let text2 = Color(nsColor: .secondaryLabelColor)
    static let text3 = Color(nsColor: .tertiaryLabelColor)

    static let card = Color.primary.opacity(0.05)
    static let cardHover = Color.primary.opacity(0.09)
    static let fill = Color.primary.opacity(0.07)

    /// Neutral for a future date, accent for today, orange once late.
    static func tint(_ state: TargetState) -> Color {
        switch state {
        case .late: return late
        case .due: return accent
        case .upcoming, .none: return text2
        }
    }

    static func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(text3)
    }

    /// Inline markdown (bold, links, code) from the notes, with hard-wrapped lines joined back into
    /// paragraphs; anything the parser cannot read is shown as written.
    static func markdown(_ text: String) -> Text {
        Prose.markdown(text).map(Text.init) ?? Text(Prose.reflow(text))
    }
}

/// The app's mark: a white parking sign on an accent tile, as on the road.
struct AppMark: View {
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: "parkingsign")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

/// A small rounded count or label: "3", "Priority 2".
struct Badge: View {
    let text: String
    var tint: Color = Theme.text2
    var background: Color = Theme.fill

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// The target date as a pill with a calendar glyph: neutral ahead of time, accent today, orange once late.
struct TargetPill: View {
    let target: Day
    let today: Day

    var body: some View {
        let state: TargetState = target == today ? .due : (target < today ? .late : .upcoming)
        let tint = Theme.tint(state)
        HStack(spacing: 4) {
            Image(systemName: state == .late ? "calendar.badge.exclamationmark" : "calendar")
                .font(.system(size: 10, weight: .medium))
            Text(Labels.target(target, today: today))
                .font(.system(size: 11, weight: state == .upcoming ? .medium : .semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(state == .upcoming ? Theme.fill : tint.opacity(0.15), in: Capsule())
    }
}

/// Initials on a colour picked from the name, so each person keeps the same colour.
struct Avatar: View {
    let name: String
    var size: CGFloat = 28
    /// You (the config's `meName`): a person glyph on the accent instead of initials.
    var isMe = false

    /// Everyone but you; you keep the accent.
    private static let palette: [Color] = [
        Theme.ok, Theme.late, Theme.critical,
        Color(red: 0.58, green: 0.42, blue: 0.86), Color(red: 0.20, green: 0.66, blue: 0.72),
        Color(red: 0.86, green: 0.40, blue: 0.62), Color(red: 0.36, green: 0.40, blue: 0.85),
    ]

    var body: some View {
        Group {
            if isMe {
                Image(systemName: "person.fill").font(.system(size: size * 0.45, weight: .semibold))
            } else {
                Text(initials).font(.system(size: size * 0.4, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(isMe ? Theme.accent : color, in: Circle())
    }

    private var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    /// A stable hash: `hashValue` changes between launches.
    private var color: Color {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[sum % Self.palette.count]
    }
}

/// Drawn by hand so it renders the same in the panel and in snapshots.
struct PanelButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, prominent: prominent)
    }

    private struct Styled: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Theme.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(configuration.isPressed ? 0.75 : 1)
                .onHover { hovering = $0 }
        }

        private var background: Color {
            if prominent { return hovering ? Theme.accent.opacity(0.88) : Theme.accent }
            return hovering ? Theme.cardHover : Theme.fill
        }
    }
}

/// A borderless icon button with a round hover highlight, for rows and the footer.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, size: size)
    }

    private struct Styled: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(width: size, height: size)
                .background(hovering ? Theme.cardHover : .clear, in: Circle())
                .contentShape(Circle())
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// The card every list row and detail section sits on.
    func card(padding: CGFloat = 12, highlighted: Bool = false, radius: CGFloat = Theme.cardRadius) -> some View {
        self.padding(padding)
            .background(highlighted ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Applies AppKit-backed modifiers (drag and drop, context menus, popovers) only in the live panel:
    /// in a snapshot they would render as blank placeholders.
    func interactive<Live: View>(@ViewBuilder _ live: @escaping (Self) -> Live) -> some View {
        Interactive(base: self, live: live)
    }
}

private struct Interactive<Base: View, Live: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let base: Base
    let live: (Base) -> Live

    var body: some View {
        if isSnapshot { base } else { live(base) }
    }
}

/// Set while rendering a PNG: scroll views and other AppKit-backed controls render as blanks there.
private struct SnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

/// A vertical scroll area filling the panel's free height, or the bare content when rendering a snapshot.
struct PanelScroll<Content: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isSnapshot {
            content()
        } else {
            ScrollView { content() }
                .frame(maxHeight: .infinity)
        }
    }
}
