import AppKit

/// What the app needs from an updater. The executable supplies the Sparkle one, so this library (and its tests)
/// never load Sparkle.
@MainActor public protocol AppUpdater: AnyObject {
    /// Starts background checks; false when this copy can't update (not a bundled app, no feed).
    func start() -> Bool
    func checkForUpdates()
    var automaticallyChecks: Bool { get set }
    var lastCheck: Date? { get }
}

/// The app's single entry point for updates: menus and Preferences talk to this.
@MainActor final class Updates: NSObject {
    static let shared = Updates()
    var backend: AppUpdater?
    private(set) var isAvailable = false

    func start() {
        isAvailable = backend?.start() ?? false
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard isAvailable, let backend else {
            Toast.show("Updates are available in the installed app only")
            return
        }
        NSApp.activate()
        backend.checkForUpdates()
    }

    var automaticallyChecks: Bool {
        get { backend?.automaticallyChecks ?? false }
        set { backend?.automaticallyChecks = newValue }
    }

    var lastCheck: Date? { backend?.lastCheck }
}
