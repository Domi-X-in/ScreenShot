import AppKit
import ScreenShotKit
import Sparkle

/// Automatic updates with Sparkle: reads the appcast attached to the latest GitHub release, checks its EdDSA signature
/// against SUPublicEDKey in Info.plist, and offers to install newer versions.
@MainActor final class SparkleUpdater: NSObject, AppUpdater, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    /// Only a bundled app with a feed checks; `swift run` and self-test runs stay offline.
    func start() -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil, Bundle.main.bundleURL.pathExtension == "app" else { return false }
        if controller == nil {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        }
        return true
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

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
