import AppKit
import Sparkle

/// Automatic updates with Sparkle: the app reads the appcast attached to the latest GitHub release, checks its EdDSA
/// signature against SUPublicEDKey in Info.plist, and offers to install newer versions.
@MainActor final class Updates: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = Updates()
    private var controller: SPUStandardUpdaterController?

    /// Starts checking only in a bundled app that has a feed; `swift run` and self-test runs stay offline.
    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil, Bundle.main.bundleURL.pathExtension == "app"
        else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var isAvailable: Bool { controller != nil }

    @objc func checkForUpdates(_ sender: Any?) {
        guard let controller else {
            Toast.show("Updates are available in the installed app only")
            return
        }
        NSApp.activate()
        controller.checkForUpdates(sender)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    // MARK: SPUStandardUserDriverDelegate

    /// A menu bar app has no Dock icon to badge, so scheduled checks bring the update window forward gently.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate()
    }
}
