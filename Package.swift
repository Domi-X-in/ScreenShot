// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenShot",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything except the entry point, so tests can import it.
        .target(
            name: "ScreenShotKit",
            path: "Sources/ScreenShotKit",
            // The in-app self-tests (UI snapshots, live capture, interaction tests) exist only in debug builds;
            // the release app built by build.sh leaves them out.
            swiftSettings: [.define("SCREENSHOT_SELFTESTS", .when(configuration: .debug))]
        ),
        .executableTarget(name: "ScreenShot", dependencies: ["ScreenShotKit"], path: "Sources/ScreenShot"),
        .testTarget(name: "ScreenShotTests", dependencies: ["ScreenShotKit"], path: "Tests/ScreenShotTests"),
    ]
)
