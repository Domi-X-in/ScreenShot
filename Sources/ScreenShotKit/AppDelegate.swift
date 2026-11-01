import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var prefs: PreferencesWindowController?

    private var appearanceObserver: NSKeyValueObservation?
    private var menuIconObserver: NSKeyValueObservation?
    private var dockObserver: NSKeyValueObservation?
    private var launchedByUser = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        Settings.applyAppearance()
        // Preferences writes the choice to defaults; apply it the moment it changes.
        appearanceObserver = UserDefaults.standard.observe(\.appearance, options: [.new]) { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { Settings.applyAppearance() } }
        }
        NSApp.mainMenu = buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The viewfinder mark of the icon family (ROADMAP, Fase 6 · R7); a template image, so macOS tints it for the menu bar.
        statusItem.button?.image = Self.statusMark()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = !Settings.hideMenuBarIcon
        // One way back in always stays: hiding the menu bar icon brings the Dock icon back, and the other way around.
        menuIconObserver = UserDefaults.standard.observe(\.hideMenuBarIcon, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.statusItem.isVisible = !Settings.hideMenuBarIcon
                    if Settings.hideMenuBarIcon && !Settings.showInDock { UserDefaults.standard.set(true, forKey: Keys.showInDock) }
                }
            }
        }
        dockObserver = UserDefaults.standard.observe(\.showInDock, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyDockSetting() } }
        }

        AppLogic.shared.trackPreviousApp()
        HotKeyCenter.shared.handler = { AppLogic.shared.run($0) }
        HotKeyCenter.shared.reload()

        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        #if SCREENSHOT_SELFTESTS
        // Debug builds only: a self-test or UI snapshot run, chosen by environment variable, drives the app and quits.
        // The user's settings and clipboard are put back when it exits.
        if SelfTestSandbox.isTestRun { SelfTestSandbox.begin() }
        let selfTests: [() -> Bool] = [
            LiveCaptureTest.runIfRequested, SelfTest.runIfRequested, SelectionSelfTest.runIfRequested, TextSelfTest.runIfRequested,
            TextStyleSelfTest.runIfRequested, InfoSelfTest.runIfRequested, CalloutSelfTest.runIfRequested,
            AppearanceSelfTest.runIfRequested, DefaultsSelfTest.runIfRequested, Phase3SelfTest.runIfRequested, OnboardingSelfTest.runIfRequested, ShapesSelfTest.runIfRequested, FlowsSelfTest.runIfRequested,
            RibbonSelfTest.runIfRequested, SpacesSelfTest.runIfRequested,
        ]
        if selfTests.contains(where: { $0() }) { return }
        if RibbonDemo.openIfRequested() { return }
        if ProcessInfo.processInfo.environment["SCREENSHOT_SNAPSHOT_DIR"] != nil {
            DebugSnapshots.runIfRequested()
            return
        }
        #endif
        // First launch: the welcome guide explains and asks for Screen Recording itself.
        if OnboardingWindowController.isDone {
            Capturer.requestPermissionOnFirstLaunch()
            if launchedByUser { AppLogic.shared.showEditor() }
        } else {
            OnboardingWindowController.show()
        }
        Updates.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL { AppLogic.shared.openFile(url) } else { AppLogic.shared.handleDeepLink(url) }
        }
    }

    private func applyDockSetting() {
        if !Settings.showInDock && Settings.hideMenuBarIcon { UserDefaults.standard.set(false, forKey: Keys.hideMenuBarIcon) }
        let wasActive = NSApp.isActive
        NSApp.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
        // Changing the policy can take the focus away from the window the setting was changed in.
        if wasActive { NSApp.activate() }
    }

    /// Opening the app again (Dock, Finder, Spotlight) always shows the editor, even with a pin or the Library on screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if OnboardingWindowController.shared?.window?.isVisible != true { AppLogic.shared.showEditor() }
        return true
    }

    /// Read here, while the launch event is current: only a plain launch shows the editor, not one at login, for a link or a file.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        launchedByUser = event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue != OSType(keyAELaunchedAsLogInItem)
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        AppLogic.shared.handleDeepLink(url)
    }

    // MARK: Status menu (rebuilt on open so it reflects the current shortcuts)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // The home window: capture buttons and every screenshot (the Library).
        let open = item("Open ScreenShot", #selector(showLibrary))
        open.keyEquivalent = "l"
        open.image = Icons.image(.photo, size: 16)
        menu.addItem(open)
        menu.addItem(.separator())
        let order: [HotkeyAction?] = [.fullscreen, .area, .repeatArea, .delayed, nil, .anyWindow, .activeWindow, nil,
                                      .scrolling, .scrollingManual, nil, .ocr]
        for a in order {
            guard let a else { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: a.title, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = a.rawValue
            item.image = Icons.image(Self.icon(for: a), size: 16)
            if let s = HotKeyCenter.shared.shortcut(for: a), s.key.count == 1 {
                item.keyEquivalent = s.key.lowercased()
                item.keyEquivalentModifierMask = s.nsModifiers
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clipboard = item("Load From Clipboard", #selector(loadClipboard))
        let openImage = item("Open Image…", #selector(openImage))
        menu.addItem(clipboard)
        menu.addItem(openImage)
        menu.addItem(.separator())
        let welcome = item("Welcome Guide…", #selector(showWelcome))
        menu.addItem(welcome)
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(Updates.checkForUpdates(_:)), keyEquivalent: "")
        update.target = Updates.shared
        menu.addItem(update)
        let prefs = item("Preferences…", #selector(showPreferences))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        let quit = NSMenuItem(title: "Quit ScreenShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        for (i, icon) in [(clipboard, IconName.paste), (openImage, .openImage), (welcome, .guide), (update, .updates), (prefs, .prefs), (quit, .power)] {
            i.image = Icons.image(icon, size: 16)
        }
    }

    /// The status menu's icon for a capture.
    static func icon(for a: HotkeyAction) -> IconName {
        switch a {
        case .fullscreen: .capFull
        case .area: .capArea
        case .repeatArea: .capRepeat
        case .delayed: .capTimer
        case .anyWindow: .capWindow
        case .activeWindow: .capActive
        case .scrolling: .capScroll
        case .scrollingManual: .capScrollManual
        case .ocr: .ocr
        }
    }

    /// The menu bar mark: the icon family's viewfinder, as a template image at the menu bar's size.
    static func statusMark() -> NSImage {
        let img = Icons.image(.statusMark, size: 18, stroke: 1.6)
        img.accessibilityDescription = "ScreenShot"
        return img
    }

    #if SCREENSHOT_SELFTESTS
    var debugStatusItem: NSStatusItem { statusItem }
    #endif

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let a = HotkeyAction(rawValue: raw) else { return }
        // Let the status menu disappear before freezing the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { AppLogic.shared.run(a) }
    }

    @objc private func loadClipboard() { AppLogic.shared.loadFromClipboard() }
    @objc private func openImage() { AppLogic.shared.chooseFile() }
    @objc func showLibrary() { LibraryWindowController.show() }
    @objc func showWelcome() { OnboardingWindowController.show(from: 0) }

    func closePreferences() { prefs?.close() }

    @objc func showPreferences() {
        if prefs == nil { prefs = PreferencesWindowController() }
        NSApp.activate()
        prefs?.window?.center()
        prefs?.showWindow(nil)
    }

    // MARK: Main menu (gives editor windows ⌘C, ⌘S, ⌘Z… via the responder chain)

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        @discardableResult func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            items.forEach { m.addItem($0) }
            holder.submenu = m
            main.addItem(holder)
            return m
        }
        func mi(_ title: String, _ action: String, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(Updates.checkForUpdates(_:)), keyEquivalent: "")
        update.target = Updates.shared
        submenu("ScreenShot", [
            mi("About ScreenShot", "orderFrontStandardAboutPanel:", ""),
            .separator(),
            prefs,
            update,
            .separator(),
            mi("Hide ScreenShot", "hide:", "h"),
            mi("Hide Others", "hideOtherApplications:", "h", [.command, .option]),
            mi("Show All", "unhideAllApplications:", ""),
            .separator(),
            mi("Quit ScreenShot", "terminate:", "q"),
        ])
        let library = NSMenuItem(title: "Library…", action: #selector(showLibrary), keyEquivalent: "l")
        library.target = self
        submenu("File", [
            library,
            .separator(),
            mi("Save", "saveDocument:", "s"),
            mi("Save As…", "saveDocumentAs:", "s", [.command, .shift]),
            mi("Save Blinking GIF", "saveGIF:", "g", [.command, .shift]),
            mi("Pin", "pinImage:", "p"),
            .separator(),
            mi("Close", "performClose:", "w"),
        ])
        submenu("Edit", [
            mi("Undo", "undo:", "z"),
            mi("Redo", "redo:", "z", [.command, .shift]),
            .separator(),
            mi("Cut", "cut:", "x"),
            mi("Copy", "copy:", "c"),
            mi("Paste", "paste:", "v"),
            mi("Select All", "selectAll:", "a"),
            mi("Duplicate", "duplicate:", "d"),
            mi("Delete", "delete:", "", []),
            .separator(),
            mi("Recognize Text or QR", "recognizeText:", "o"),
        ])
        submenu("Arrange", ArrangeMenu.items(includeSnap: true))
        submenu("View", [
            mi("Zoom In", "zoomIn:", "="),
            mi("Zoom Out", "zoomOut:", "-"),
            mi("Zoom to Fit", "zoomToFit:", "0"),
        ])
        NSApp.windowsMenu = submenu("Window", [
            mi("Minimize", "performMiniaturize:", "m"),
            mi("Zoom", "performZoom:", ""),
            .separator(),
            mi("Bring All to Front", "arrangeInFront:", ""),
        ])
        let guide = NSMenuItem(title: "Welcome Guide…", action: #selector(showWelcome), keyEquivalent: "")
        guide.target = self
        let help = NSMenuItem(title: "ScreenShot Help", action: #selector(openHelp), keyEquivalent: "?")
        help.target = self
        NSApp.helpMenu = submenu("Help", [help, guide])
        return main
    }

    @objc private func openHelp() {
        if let url = URL(string: "https://github.com/Domi-X-in/ScreenShot#readme") { NSWorkspace.shared.open(url) }
    }
}

extension UserDefaults {
    /// KVO-observable mirror of the "appearance" key (the property name must match the key for KVO).
    @objc dynamic var appearance: String? { string(forKey: "appearance") }
    @objc dynamic var hideMenuBarIcon: Bool { bool(forKey: Keys.hideMenuBarIcon) }
    @objc dynamic var showInDock: Bool { bool(forKey: Keys.showInDock) }
}
