// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ParkBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: reading the notes vault, the rules (cold, late, order) and the narrow writes. No UI.
        .target(
            name: "ParkBarCore",
            path: "Sources/ParkBarCore"
        ),
        // Menu bar app (LSUIElement).
        .executableTarget(
            name: "ParkBar",
            dependencies: ["ParkBarCore"],
            path: "Sources/ParkBar",
            exclude: ["Info.plist"]
        ),
        // WidgetKit extension (Notification Center). Assembled into ParkBar.app/Contents/PlugIns by scripts/bundle.sh.
        .executableTarget(
            name: "ParkBarWidget",
            dependencies: ["ParkBarCore"],
            path: "Sources/ParkBarWidget",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            // App extensions enter through Foundation's NSExtensionMain, which then hands over to the
            // @main WidgetBundle. Without this entry point the widget host's connection is dropped at once.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])]
        ),
        // Terminal tool: read the vault and make the same narrow edits as the app, headlessly.
        .executableTarget(
            name: "parkbar-cli",
            dependencies: ["ParkBarCore"],
            path: "Sources/ParkBarCLI"
        ),
        .testTarget(
            name: "ParkBarCoreTests",
            dependencies: ["ParkBarCore"],
            path: "Tests/ParkBarCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
