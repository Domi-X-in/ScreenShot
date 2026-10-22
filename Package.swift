// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenShot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ScreenShot", path: "Sources/ScreenShot")
    ]
)
