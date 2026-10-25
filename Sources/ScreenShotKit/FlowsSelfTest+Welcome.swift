import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// The welcome guide (R8): three steps with their names in the footer, Continue/Back/Skip and the step
    /// names as navigation, the page remembered for a relaunch, the setup choices written to the settings, and nothing
    /// moving under Reduce Motion.
    func welcomeFlow() async {
        let d = UserDefaults.standard
        let wasDone = d.object(forKey: Keys.onboardingDone), wasLook = Settings.appearance
        let after = [Keys.afterShow, Keys.afterCopy, Keys.afterSave].map { ($0, d.bool(forKey: $0)) }
        defer {
            if let wasDone { d.set(wasDone, forKey: Keys.onboardingDone) } else { d.removeObject(forKey: Keys.onboardingDone) }
            d.set(0, forKey: Keys.onboardingPage)
            for (k, v) in after { d.set(v, forKey: k) }
            d.set(wasLook, forKey: "appearance")
            Settings.applyAppearance()
            OnboardingPage.forceReduceMotion = false
        }
        d.set(false, forKey: Keys.onboardingDone)
        d.set(0, forKey: Keys.onboardingPage)
        OnboardingWindowController.show()
        guard let ob = OnboardingWindowController.shared, let win = ob.window else { check(false, "the guide opens"); return }
        await sleep(0.2)
        check(ob.pageCount == 3 && ob.debugStepTitles == ["Welcome", "Set up", "Ready"], "three steps: Welcome, Set up, Ready")
        check(win.frame.size.width >= 860 && ob.currentPage is WelcomeStep, "it opens on Welcome in the bigger window")
        check(ob.debugContinueTitle == "Get Started" && !ob.debugBackShown && ob.debugSkipShown, "Welcome: Get Started and Skip, no Back")
        if let w = ob.currentPage as? WelcomeStep {
            check(w.cards.count == 3 && w.active == 0 && w.cards[0].isActive, "three feature cards, the first lit")
            check(w.isLooping || OnboardingPage.reduceMotion, "the feature loop runs")
            w.highlight(2)
            check(w.cards[2].isActive && !w.cards[0].isActive, "the loop lights one card at a time")
        }

        ob.pressContinue(); await sleep(0.1)
        check(ob.index == 1 && d.integer(forKey: Keys.onboardingPage) == 1 && ob.currentPage is SetupStep, "Continue goes to Set up and remembers it")
        check(ob.debugContinueTitle == "Continue" && ob.debugBackShown && ob.debugSkipShown, "Set up: Back, Skip and Continue")
        if let s = ob.currentPage as? SetupStep {
            check(s.shownPath == (Settings.saveFolder.path as NSString).abbreviatingWithTildeInPath, "it shows the Screenshots folder")
            check(s.allowShown == !CGPreflightScreenCaptureAccess(), "Allow Screen Recording shows only until it is allowed")
            check(s.afterPills.count == 3 && s.afterPills.allSatisfy { $0.pill.isOn == d.bool(forKey: $0.key) }, "the three after-capture choices show the settings")
            if let first = s.afterPills.first {
                let was = d.bool(forKey: first.key)
                first.pill.toggle()
                check(d.bool(forKey: first.key) == !was && first.pill.isOn == !was, "a choice's pill turns its setting on and off")
                first.pill.toggle()
            }
            s.chooseLook("light")
            check(Settings.appearance == "light" && NSApp.appearance?.name == .aqua && s.looks.first { $0.value == "light" }?.card.isSelected == true,
                  "picking Light applies it at once and marks it")
            check(win.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua, "the new guide follows the app's look")
            s.chooseLook("system")
            check(Settings.appearance == "system", "picking System follows macOS again")
        }

        ob.pressStep(0); await sleep(0.1)
        check(ob.index == 0, "a step's name goes back to it")
        ob.pressStep(1); await sleep(0.1)
        ob.pressSkip(); await sleep(0.1)
        check(ob.index == 2 && ob.currentPage is ReadyStep, "Skip goes to Ready")
        check(ob.debugContinueTitle == "Done" && !ob.debugSkipShown && ob.debugBackShown, "Ready: Done and Back, no Skip")
        if let r = ob.currentPage as? ReadyStep {
            check(r.tiles.count == 6 && r.firstCapture.title == "Take My First Screenshot", "six shortcuts and the first capture button")
        }

        // A relaunch (macOS quits the app to apply Screen Recording) comes back on the step it was on.
        ob.window?.orderOut(nil)
        OnboardingWindowController.shared = nil
        d.set(1, forKey: Keys.onboardingPage)
        OnboardingWindowController.show()
        guard let again = OnboardingWindowController.shared else { check(false, "the guide reopens"); return }
        check(again.index == 1 && again.currentPage is SetupStep, "reopening resumes on Set up")

        // Reduce Motion: no page push, no entrance animations, no feature loop.
        OnboardingPage.forceReduceMotion = true
        again.pressStep(0); await sleep(0.05)
        let stage = again.currentPage?.superview
        let moving = (again.currentPage?.subviews ?? []).contains { !($0.layer?.animationKeys() ?? []).isEmpty }
        check(stage?.layer?.animation(forKey: "page") == nil && !moving, "under Reduce Motion pages change without animating")
        check((again.currentPage as? WelcomeStep)?.isLooping == false, "under Reduce Motion the feature loop stays still")
        OnboardingPage.forceReduceMotion = false

        again.go(to: 2)
        again.pressContinue()
        check(d.bool(forKey: Keys.onboardingDone) && d.integer(forKey: Keys.onboardingPage) == 0 && OnboardingWindowController.shared == nil,
              "Done closes the guide and marks it done")
    }
}
#endif
