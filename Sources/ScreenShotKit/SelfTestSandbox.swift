import AppKit

#if SCREENSHOT_SELFTESTS
/// Debug builds share the app's settings domain, so every self-test or snapshot run copies the user's saved settings
/// and clipboard when it starts and puts them back when the process exits (self-tests end with exit()). Values passed
/// on the command line (-saveFolder) live in the argument domain and are never written back.
enum SelfTestSandbox {
    nonisolated(unsafe) private static var settings: [String: Any]?
    nonisolated(unsafe) private static var clipboard: [(NSPasteboard.PasteboardType, Data)] = []
    private static let domain = Bundle.main.bundleIdentifier ?? "local.screenshot.app"

    static var isTestRun: Bool {
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("SCREENSHOT_SELFTEST_") || $0.hasPrefix("SCREENSHOT_SNAPSHOT_")
            || $0 == "SCREENSHOT_ONBOARDING_SHOTS" }
    }

    static func begin() {
        guard settings == nil else { return }
        settings = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        clipboard = (NSPasteboard.general.pasteboardItems?.first?.types ?? []).compactMap { t in NSPasteboard.general.data(forType: t).map { (t, $0) } }
        atexit { SelfTestSandbox.restore() }
    }

    static func restore() {
        guard let settings else { return }
        UserDefaults.standard.setPersistentDomain(settings, forName: domain)
        // Write it to disk now: the process is exiting and won't get another chance.
        CFPreferencesAppSynchronize(domain as CFString)
        let pb = NSPasteboard.general
        pb.clearContents()
        if !clipboard.isEmpty {
            let item = NSPasteboardItem()
            for (t, d) in clipboard { item.setData(d, forType: t) }
            pb.writeObjects([item])
        }
    }
}
#endif
