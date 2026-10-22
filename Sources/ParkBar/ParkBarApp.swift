import AppKit
import ParkBarCore
import SwiftUI

@main
struct ParkBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: AppModel.shared)
        } label: {
            MenuBarLabel(model: AppModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces with LSUIElement: keeps the Dock icon away even when run as a bare binary.
        NSApplication.shared.setActivationPolicy(.accessory)
        if let options = SnapshotOptions(arguments: CommandLine.arguments) {
            Task { @MainActor in exit(PanelSnapshot.run(options) ? 0 : 1) }
        }
    }

    /// `parkbar://effort/<name>` from the widget: show that effort and open the panel.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let name = urls.lazy.compactMap(WidgetSnapshot.effortName(in:)).first else { return }
        Task { @MainActor in
            AppModel.shared.open(effortNamed: name)
            StatusItem.click()
        }
    }
}

/// Opens the MenuBarExtra window from code. SwiftUI has no API for it, so this clicks the status item's
/// button, which lives in an NSStatusBarWindow. Best effort: if AppKit changes that, nothing happens.
@MainActor
enum StatusItem {
    static func click() {
        for window in NSApp.windows where String(describing: type(of: window)).contains("NSStatusBarWindow") {
            if let button = window.contentView?.subviews.compactMap({ $0 as? NSButton }).first ?? window.contentView as? NSButton {
                button.performClick(nil)
                return
            }
        }
    }
}

// MARK: - Snapshot (dev aid)

/// `ParkBar --snapshot out.png [--notes DIR] [--today YYYY-MM-DD] [--tab efforts|people|archived]
///  [--detail NAME] [--person NAME] [--dark] [--notice TEXT]` renders the panel (and `out-label.png`) and exits.
struct SnapshotOptions {
    var path: String
    var notes: URL?
    var today: Day?
    var tab = AppModel.Tab.efforts
    var detail: String?
    var person: String?
    var dark = false
    var notice: String?

    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        guard let path = value("--snapshot") else { return nil }
        self.path = path
        notes = value("--notes").map { URL(fileURLWithPath: $0, isDirectory: true) }
        today = value("--today").flatMap(Day.init)
        tab = value("--tab").flatMap { t in AppModel.Tab.allCases.first { $0.rawValue.lowercased() == t } } ?? .efforts
        detail = value("--detail")
        person = value("--person")
        dark = arguments.contains("--dark")
        notice = value("--notice")
    }
}

@MainActor
enum PanelSnapshot {
    static func run(_ options: SnapshotOptions) -> Bool {
        let model = AppModel(root: options.notes, live: false, today: options.today ?? .today())
        model.tab = options.tab
        model.openEffort = options.detail
        model.openPerson = options.person
        model.recoveryNotice = options.notice
        let scheme: ColorScheme = options.dark ? .dark : .light
        NSApp.appearance = NSAppearance(named: options.dark ? .darkAqua : .aqua)
        let ok = write(PanelView(model: model), to: options.path, scheme: scheme)
            && write(MenuBarLabel(model: model).padding(4), to: options.path.replacingOccurrences(of: ".png", with: "-label.png"),
                     width: nil, scheme: scheme)
        FileHandle.standardError.write(Data("snapshot \(ok ? "written" : "FAILED"): \(options.path)\n".utf8))
        return ok
    }

    static func write<V: View>(_ view: V, to path: String, width: CGFloat? = Theme.panelWidth, scheme: ColorScheme = .light) -> Bool {
        let content = view
            .environment(\.isSnapshot, true)
            .environment(\.colorScheme, scheme)
            .frame(width: width)
            .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return FileManager.default.createFile(atPath: path, contents: png)
    }
}
