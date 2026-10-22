import ParkBarCore
import SwiftUI

/// What the panel shows while the notes folder has no efforts: where it looked, and two ways forward.
struct WelcomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelScroll {
            VStack(spacing: 14) {
                AppMark(size: 44)
                    .padding(.top, 28)
                Text(model.vault.hasEffortsFolder ? "Nothing parked yet" : "Where are your notes?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                VStack(spacing: 6) {
                    Text("ParkBar reads one file per effort from **\(Vault.effortsFolder)/** in your notes folder, plus **\(Vault.todoFile)**. It is looking in:")
                    Text((model.root.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                    if model.setup.folderIsFromEnvironment {
                        Text("(set by \(ParkBarConfig.environmentKey))").font(.system(size: 11))
                    }
                    Text("Run /park in Claude Code to park a session here, or pick the folder you already keep notes in.")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    Button { model.chooseFolder() } label: {
                        Label("Choose folder…", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PanelButtonStyle(prominent: true))
                    Button { model.tryExamples() } label: {
                        Label("Try the example notes", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PanelButtonStyle(prominent: false))
                    .disabled(model.examples == nil)
                }
                .frame(maxWidth: 240)
                .padding(.top, 4)

                if model.examples == nil {
                    Text("The example notes are in the repo's examples/notes folder. Choose that folder, or start ParkBar with PARKBAR_NOTES set to it.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Each try is a fresh copy; your own notes and settings stay as they are.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }
}
