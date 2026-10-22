import ParkBarCore
import SwiftUI
import WidgetKit

@main
struct ParkBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        ParkBarWidget()
    }
}

struct ParkBarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ParkBarTop", provider: SnapshotProvider()) { entry in
            ParkBarWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ParkBar")
        .description("Your top parked efforts, with the next step and target date.")
        .supportedFamilies([.systemMedium])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads the snapshot the app wrote. A fresh entry after midnight keeps "today" and "late" right;
/// the app also asks WidgetKit to reload whenever the top efforts change.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? Self.sample : WidgetSnapshotStore.read(from: WidgetSnapshotStore.widgetSideURL())
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read(from: WidgetSnapshotStore.widgetSideURL())
        let now = Date()
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        let entries = [SnapshotEntry(date: now, snapshot: snapshot), SnapshotEntry(date: midnight, snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let sample = WidgetSnapshot(updatedAt: Date(), items: [
        .init(name: "Garden shed", next: "Book the delivery for Friday", target: Day.today().adding(days: 2)),
        .init(name: "Bike repair", next: "Buy a new inner tube", target: Day.today().adding(days: -2)),
        .init(name: "Tax return", next: "Find last year's receipts", target: nil),
    ])
}

struct ParkBarWidgetView: View {
    let entry: SnapshotEntry

    /// The panel's colours (the app's Theme is not linked into the extension).
    private static let accent = Color(red: 0.25, green: 0.55, blue: 0.95)
    private static let late = Color(red: 0.96, green: 0.62, blue: 0.16)

    var body: some View {
        let today = Day.today(now: entry.date)
        if let items = entry.snapshot?.items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Link(destination: WidgetSnapshot.url(for: item.name) ?? URL(string: "parkbar://")!) {
                        row(item, rank: index + 1, today: today)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "parkingsign.square").font(.title2).foregroundStyle(.secondary)
                Text("Open ParkBar once, or park an effort").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ item: WidgetSnapshot.Item, rank: Int, today: Day) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 15, height: 15)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                if let next = item.next {
                    Text(next).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let target = item.target {
                pill(target, today: today)
            }
        }
    }

    /// Neutral ahead of time, accent today, orange once late: the same pill as in the panel.
    private func pill(_ target: Day, today: Day) -> some View {
        let tint: Color = target == today ? Self.accent : (target < today ? Self.late : .secondary)
        return HStack(spacing: 3) {
            Image(systemName: target < today ? "calendar.badge.exclamationmark" : "calendar")
                .font(.system(size: 8, weight: .medium))
            Text(Labels.target(target, today: today))
                .font(.system(size: 10, weight: target > today ? .medium : .semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(target > today ? Color.primary.opacity(0.07) : tint.opacity(0.15), in: Capsule())
    }
}
