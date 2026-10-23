// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenShot",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates from GitHub releases (EdDSA-signed appcast).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Everything except the entry point, so tests can import it.
        .target(
            name: "ScreenShotKit",
            path: "Sources/ScreenShotKit",
            // The in-app self-tests (UI snapshots, live capture, interaction tests) exist only in debug builds;
            // the release app built by build.sh leaves them out.
            swiftSettings: [.define("SCREENSHOT_SELFTESTS", .when(configuration: .debug))]
        ),
        // Sparkle is linked into the app only, so the tests never load it.
        .executableTarget(name: "ScreenShot", dependencies: ["ScreenShotKit", .product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/ScreenShot"),
        .testTarget(name: "ScreenShotTests", dependencies: ["ScreenShotKit"], path: "Tests/ScreenShotTests"),
    ]
)
