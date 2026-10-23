import AppKit

/// Starts the app: the executable's main.swift only calls this, so the code lives in a library the tests can import.
public enum ScreenShotApp {
    /// `updater` is the executable's Sparkle updater; the library itself doesn't link Sparkle.
    @MainActor public static func run(updater: AppUpdater? = nil) {
        Updates.shared.backend = updater
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
