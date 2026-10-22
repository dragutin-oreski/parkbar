import ParkBarCore
import SwiftUI

/// Efforts set aside, newest update first. Right-click to make one active again.
struct ArchivedTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelScroll {
            VStack(alignment: .leading, spacing: 6) {
                if model.vault.archived.isEmpty {
                    EmptyState(symbol: "archivebox", text: "Nothing archived. Right-click an effort and choose Archive.")
                }
                ForEach(model.vault.archived) { effort in
                    EffortRow(model: model, effort: effort, rank: nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
