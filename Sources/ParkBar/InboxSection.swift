import ParkBarCore
import SwiftUI

/// The open todos under `## Inbox`, on one card above the efforts. Each links to the efforts it names
/// and offers a copy button for every command or reply in backticks. Read-only, like all of `todo.md`:
/// you tick them in your editor.
struct InboxSection: View {
    @ObservedObject var model: AppModel
    let todos: [Todo]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Theme.sectionTitle("Inbox")
                Badge(text: "\(todos.count)", tint: Theme.accent, background: Theme.accent.opacity(0.12))
            }
            .padding(.leading, 4)
            .help("Open todos under ## Inbox in \(Vault.todoFile); tick them there")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(todos) { InboxRow(model: model, todo: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

struct InboxRow: View {
    @ObservedObject var model: AppModel
    let todo: Todo

    var body: some View {
        let efforts = model.vault.linkedEfforts(of: todo)
        let commands = todo.codeSpans
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "circle").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.text3)
            VStack(alignment: .leading, spacing: 6) {
                Theme.markdown(todo.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                if !efforts.isEmpty || !commands.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(efforts, id: \.self) { EffortLink(model: model, name: $0) }
                        ForEach(commands, id: \.self) { CopyChip(model: model, text: $0) }
                    }
                }
            }
        }
    }
}

/// An effort's name as a small accent pill; a click opens that effort.
struct EffortLink: View {
    @ObservedObject var model: AppModel
    let name: String

    var body: some View {
        Button { model.open(effortNamed: name) } label: {
            HStack(spacing: 3) {
                Text(name).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Open \(name)")
    }
}

/// A command or reply from the notes, in a pill that copies it and shows a checkmark for a moment.
/// A long one is cut in the middle, so both its start and its end stay readable.
struct CopyChip: View {
    @ObservedObject var model: AppModel
    let text: String
    @State private var copiedAt: Date?

    var body: some View {
        let copied = copiedAt != nil
        Button {
            model.copy(text, toast: "Copied")
            let now = Date()
            copiedAt = now
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedAt == now { copiedAt = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: copied ? .bold : .semibold))
                    .foregroundStyle(copied ? Theme.ok : Theme.text2)
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Copy \(text)")
    }
}

/// Lays its pills out left to right, starting a new line when the next one does not fit. A pill wider
/// than the whole line gets the line's width, so its text is cut instead of running off the card.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(width: bounds.width, subviews).frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat?, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth { size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) }
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            widest = max(widest, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: widest, height: y + lineHeight), frames)
    }
}
