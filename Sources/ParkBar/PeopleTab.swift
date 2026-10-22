import ParkBarCore
import SwiftUI

/// Everyone named in the notes, and for one person: what to ask them, what they owe, their agenda.
struct PeopleTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let people = model.vault.people()
        if let name = model.openPerson, let person = people.first(where: { $0.name == name }) {
            PersonView(model: model, person: person)
        } else {
            PanelScroll {
                VStack(alignment: .leading, spacing: 6) {
                    if people.isEmpty {
                        EmptyState(symbol: "person.2", text: "Nobody is named in a question, a waiting item or an agenda yet.")
                    }
                    ForEach(people) { person in
                        PersonRow(person: person, isMe: person.name == model.vault.config.meName) { model.openPerson = person.name }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }
}

/// Avatar, name, and a badge per kind of open item; the whole card opens the person.
private struct PersonRow: View {
    let person: Person
    let isMe: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Avatar(name: person.name, isMe: isMe)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if isMe {
                        Text("your own decisions").font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                }
                Spacer(minLength: 6)
                if !person.questions.isEmpty {
                    count(person.questions.count, symbol: "questionmark.bubble", help: "questions to ask", tint: Theme.accent)
                }
                if !person.waiting.isEmpty {
                    count(person.waiting.count, symbol: "hourglass", help: "waiting on them", tint: Theme.late)
                }
                if let agenda = person.agenda {
                    count(agenda.itemCount, symbol: "list.bullet", help: "on their agenda list", tint: Theme.text2)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(hovering ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func count(_ n: Int, symbol: String, help: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text("\(n)").font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(tint.opacity(0.12), in: Capsule())
        .help("\(n) \(help)")
    }
}

struct PersonView: View {
    @ObservedObject var model: AppModel
    let person: Person

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { model.openPerson = nil } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("People")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Avatar(name: person.name, size: 20, isMe: person.name == model.vault.config.meName)
                Text(person.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            PanelScroll {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(person.questionsByEffort, id: \.effort) { group in
                        card {
                            Button { model.open(effortNamed: group.effort) } label: {
                                HStack(spacing: 4) {
                                    Theme.sectionTitle(group.effort)
                                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text3)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open this effort")
                        } content: {
                            let fileHash = model.vault.effort(named: group.effort)?.contentHash ?? ""
                            ForEach(group.questions) { q in
                                QuestionRow(model: model, effort: group.effort, fileHash: fileHash, question: q)
                            }
                        }
                    }
                    if !person.waiting.isEmpty {
                        card {
                            title("Waiting on \(person.name)", symbol: "hourglass", count: person.waiting.count)
                        } content: {
                            ForEach(person.waiting) { todo in
                                let text = todo.text.hasPrefix("\(person.name) — ") ? String(todo.text.dropFirst(person.name.count + 3)) : todo.text
                                bullet(text, color: Theme.text)
                            }
                        }
                    }
                    if let agenda = person.agenda {
                        ForEach(agenda.groups, id: \.heading) { group in
                            card {
                                title(group.heading.isEmpty ? agenda.fileName : group.heading, symbol: "list.bullet", count: group.items.count)
                            } content: {
                                ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                                    bullet(item, color: Theme.text2)
                                }
                            }
                        }
                    }
                    if person.openCount == 0 && person.agenda == nil {
                        EmptyState(symbol: "checkmark.circle", text: "Nothing open.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }

    private func card<Title: View, Content: View>(@ViewBuilder title: () -> Title, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title()
            VStack(alignment: .leading, spacing: 6) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func title(_ text: String, symbol: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3)
            Theme.sectionTitle(text)
            Badge(text: "\(count)")
        }
    }

    private func bullet(_ text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(Theme.text3).frame(width: 4, height: 4).frame(width: 13)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1.5 }
            Theme.markdown(text)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
