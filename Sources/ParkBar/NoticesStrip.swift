import ParkBarCore
import SwiftUI

/// The recent alerts other programs left in `alerts.jsonl`, newest first, above every tab. Each says what,
/// who and why in two short lines; a click copies its `copy` text. The cross clears them all.
struct AlertsStrip: View {
    @ObservedObject var model: AppModel
    let alerts: [Notice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(alerts.prefix(3)) { AlertRow(model: model, alert: $0) }
            if alerts.count > 3 {
                Text("and \(alerts.count - 3) more in the last 30 minutes")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text3)
                    .padding(.leading, 21)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.late.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button { model.clearAlerts() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text2)
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("Clear these")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

struct AlertRow: View {
    @ObservedObject var model: AppModel
    let alert: Notice

    var body: some View {
        if let text = alert.copy {
            Button { model.copy(text, toast: "Copied") } label: { row }
                .buttonStyle(.plain)
                .help("Copy \(text)")
        } else {
            row
        }
    }

    /// Time and what, then who and why in full, then what to do.
    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: alert.symbol ?? "bell.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.late)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(alert.at, format: .dateTime.hour().minute())
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.text2)
                    Text(alert.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if alert.source != nil || alert.detail != nil {
                    (Text(alert.source.map { $0 + (alert.detail == nil ? "" : " — ") } ?? "").fontWeight(.semibold)
                        + Text(alert.detail ?? ""))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let action = alert.action {
                    Text(action)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.late)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.trailing, 14)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
