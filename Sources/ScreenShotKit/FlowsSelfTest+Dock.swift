import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// R12: the Dock icon (on by default), its setting, the full main menu, and Copy and Close giving the focus back.
    func dockFlow() async {
        let d = UserDefaults.standard
        defer {
            d.set(false, forKey: Keys.closeAfterCopySave)
            d.set(true, forKey: Keys.showInDock)
            d.set(false, forKey: Keys.hideMenuBarIcon)
        }
        d.set(true, forKey: Keys.showInDock)
        d.set(false, forKey: Keys.hideMenuBarIcon)
        await sleep(0.2)
        check(NSApp.activationPolicy() == .regular, "the app has a Dock icon by default")

        let menus = NSApp.mainMenu?.items.map(\.title) ?? []
        for t in ["ScreenShot", "File", "Edit", "Arrange", "View", "Window", "Help"] { check(menus.contains(t), "the main menu has \(t)") }
        check(NSApp.windowsMenu?.title == "Window" && NSApp.helpMenu?.title == "Help", "macOS knows the Window and Help menus")

        // The two icons can't both be hidden.
        d.set(false, forKey: Keys.showInDock)
        await sleep(0.3)
        check(NSApp.activationPolicy() == .accessory, "turning the setting off removes the Dock icon")
        d.set(true, forKey: Keys.hideMenuBarIcon)
        await sleep(0.3)
        check(Settings.showInDock && NSApp.activationPolicy() == .regular, "hiding the menu bar icon brings the Dock icon back")
        d.set(false, forKey: Keys.showInDock)
        await sleep(0.3)
        check(!Settings.hideMenuBarIcon, "removing the Dock icon brings the menu bar icon back")
        let box = DefaultsCheckbox("Dock", key: Keys.showInDock)
        d.set(true, forKey: Keys.showInDock)
        await sleep(0.3)
        check(box.state == .on, "the Preferences checkbox follows the change")

        // Copy and Close gives the focus back, so the picture can be pasted at once; pins stay.
        d.set(true, forKey: Keys.closeAfterCopySave)
        guard let ed = await openEditor(Self.sampleImage(640, 360, text: "Paste me")) else { check(false, "the editor opens"); return }
        ed.pinImage()
        await sleep(0.3)
        let pin = NSApp.windows.first { $0 is PinWindow && $0.isVisible }
        guard let again = await openEditor(Self.sampleImage(640, 360, text: "Paste me too")), let r = again.debugEditorRibbon else { return }
        NSApp.activate()
        await sleep(0.3)
        // macOS may refuse the focus to an app started from a script; then there is no focus to give back.
        let wasInFront = NSApp.isActive
        r.copyImage.action?()
        await sleep(0.8)
        let front = NSWorkspace.shared.frontmostApplication
        if wasInFront {
            check(front?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  "Copy and Close gives the focus to the app before (\(front?.localizedName ?? "none"))")
        } else {
            print("SKIP [dock] macOS kept \(front?.localizedName ?? "another app") in front, so giving the focus back can't be checked")
        }
        check(pin?.isVisible == true, "the pin stays on screen")
        pin?.close()
        NSApp.activate()
        await sleep(0.2)
    }
}

/// R12: with another app in full screen (Tools/fullscreen-test.sh), the capture windows stay on that Space. The editor's
/// behaviour is printed, not judged, so the two activation policies can be compared.
@MainActor enum SpacesSelfTest {
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_SPACES"] != nil else { return false }
        Task { @MainActor in await run() }
        return true
    }

    private static func sleep(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    private static func run() async {
        var changes = 0
        let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { changes += 1 }
        }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        func report(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what, "(Space changes: \(changes))") }
        let front = { NSWorkspace.shared.frontmostApplication?.localizedName ?? "none" }
        print("INFO policy \(NSApp.activationPolicy() == .regular ? "regular" : "accessory"), front \(front())")
        await sleep(1)

        let screen = NSScreen.containingMouse()
        let image = FlowsSelfTest.sampleImage(screen.frame.width > 0 ? Int(screen.frame.width) : 800, Int(screen.frame.height))
        let curtain = CurtainController(shots: [(screen, image)], windowList: [], mode: .area) { _ in }
        CurtainController.current = curtain
        curtain.show()
        await sleep(1.5)
        let shown = NSApp.windows.first { $0 is CurtainWindow }
        report(changes == 0 && shown?.isOnActiveSpace == true, "the area curtain opens over the full-screen app")
        report(shown?.isKeyWindow == true, "the area curtain takes the keyboard (Esc)")
        curtain.finish(.cancelled)
        await sleep(0.5)

        Pins.pin(FlowsSelfTest.sampleImage(400, 300), scale: 2, near: nil)
        await sleep(1)
        let pin = NSApp.windows.first { $0 is PinWindow && $0.isVisible }
        report(changes == 0 && pin?.isOnActiveSpace == true, "a pin opens over the full-screen app")

        AppLogic.shared.openEditor(FlowsSelfTest.sampleImage(640, 400), scale: 2)
        await sleep(2)
        print("INFO editor: on the active Space \(AppLogic.shared.editor?.window?.isOnActiveSpace == true), Space changes \(changes), front \(front())")
        AppLogic.shared.closeAllWindows()
        await sleep(2)
        print("INFO after Copy and Close: Space changes \(changes), front \(front()), pin on the active Space \(pin?.isOnActiveSpace == true)")
        pin?.close()
        print("SPACES SELFTEST DONE")
        exit(0)
    }
}
#endif
