import AppKit

/// Starts the app: the executable's main.swift only calls this, so the code lives in a library the tests can import.
public enum ScreenShotApp {
    @MainActor public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
