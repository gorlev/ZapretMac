// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZapretMac",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "ZapretMacKit"),
        .executableTarget(
            name: "ZapretMac",
            dependencies: ["ZapretMacKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // The root helper for Transparent mode, started by launchd. Foundation only.
        .executableTarget(name: "ZapretMacHelper", dependencies: ["ZapretMacKit"]),
        .testTarget(name: "ZapretMacKitTests", dependencies: ["ZapretMacKit"]),
    ]
)
