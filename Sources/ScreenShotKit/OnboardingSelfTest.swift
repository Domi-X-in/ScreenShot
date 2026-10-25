import AppKit
import ScreenCaptureKit

#if SCREENSHOT_SELFTESTS
/// Walks through the welcome guide. With SCREENSHOT_SELFTEST_ONBOARDING set, checks the flow (PASS/FAIL lines); with
/// SCREENSHOT_ONBOARDING_SHOTS=<dir> it also captures the real window on every step (needs Screen Recording), Welcome
/// at three moments of its feature loop. The user's guide settings are put back before quitting.
@MainActor enum OnboardingSelfTest {
    static func runIfRequested() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["SCREENSHOT_SELFTEST_ONBOARDING"] != nil || env["SCREENSHOT_ONBOARDING_SHOTS"] != nil else { return false }
        let shots = env["SCREENSHOT_ONBOARDING_SHOTS"].map(URL.init(fileURLWithPath:))
        let d = UserDefaults.standard
        // SelfTestSandbox puts every setting back on exit; this only resets what the rest of this run sees.
        let saved = [Keys.onboardingDone, Keys.onboardingPage, "askedScreenRecording", "appearance"].map {
            ($0, d.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[$0])
        }
        func restore() { for (k, v) in saved { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        if let shots { try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true) }

        Task { @MainActor in
            d.set(false, forKey: Keys.onboardingDone)
            d.set(0, forKey: Keys.onboardingPage)
            OnboardingWindowController.show()
            guard let ob = OnboardingWindowController.shared, let win = ob.window else { print("FAIL no guide window"); exit(1) }
            check(win.isVisible && ob.index == 0, "the guide opens on its first page")
            for i in 0..<ob.pageCount {
                if i > 0 { ob.pressContinue() }
                check(ob.index == i && d.integer(forKey: Keys.onboardingPage) == i, "Continue goes to page \(i + 1) and remembers it")
                if let shots {
                    // Animated scenes are captured at several moments of their loop.
                    let moments: [Double] = ob.currentPage is WelcomeStep ? [1.2, 3.9, 6.5] : [1.2]
                    var waited = 0.0
                    for (n, t) in moments.enumerated() {
                        try? await Task.sleep(for: .seconds(t - waited))
                        waited = t
                        await capture(win, to: shots.appendingPathComponent("welcome-\(i + 1)\(moments.count > 1 ? "-\(n + 1)" : "").png"))
                    }
                } else {
                    try? await Task.sleep(for: .seconds(0.3))
                }
                if let setup = ob.currentPage as? SetupStep {
                    setup.chooseLook("light")
                    check(Settings.appearance == "light" && setup.looks.first { $0.value == "light" }?.card.isSelected == true && NSApp.appearance?.name == .aqua,
                          "picking Light applies it to the app and marks the preview")
                    check(win.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua, "the guide follows the app's look")
                    setup.chooseLook("system")
                    check(Settings.appearance == "system", "picking System follows macOS again")
                    check(setup.shownPath == (Settings.saveFolder.path as NSString).abbreviatingWithTildeInPath, "Set up shows the Screenshots folder")
                }
            }
            check(ob.currentPage is ReadyStep, "the last step is Ready")
            ob.pressContinue()
            check(d.bool(forKey: Keys.onboardingDone) && !win.isVisible, "Finish closes the guide and marks it done")
            d.set(1, forKey: Keys.onboardingPage)
            d.set(false, forKey: Keys.onboardingDone)
            OnboardingWindowController.show()
            check(OnboardingWindowController.shared?.index == 1, "reopening resumes on the step it was on (after macOS restarts the app)")
            OnboardingWindowController.shared?.window?.orderOut(nil)
            restore()
            Settings.applyAppearance()
            print(failures == 0 ? "ONBOARDING SELFTEST OK" : "ONBOARDING SELFTEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }

    private static func capture(_ win: NSWindow, to url: URL) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let w = content.windows.first(where: { $0.windowID == CGWindowID(win.windowNumber) }) else { print("NOTE window not shareable"); return }
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let cfg = SCStreamConfiguration()
            cfg.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            cfg.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            cfg.ignoreShadowsSingleWindow = true
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            print("NOTE capture failed: \(error.localizedDescription)")
        }
    }
}
#endif
