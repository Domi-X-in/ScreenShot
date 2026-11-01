import AppKit

/// Starts the app: the executable's main.swift only calls this, so the code lives in a library the tests can import.
public enum ScreenShotApp {
    /// `updater` is the executable's Sparkle updater; the library itself doesn't link Sparkle.
    @MainActor public static func run(updater: AppUpdater? = nil) {
        Updates.shared.backend = updater
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Info.plist keeps LSUIElement, so no Dock icon flashes when "Show in Dock" is off (ROADMAP, Fase 6 · R12).
        Settings.registerDefaults()
        app.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
