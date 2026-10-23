import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var prefs: PreferencesWindowController?

    private var appearanceObserver: NSKeyValueObservation?
    private var menuIconObserver: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        Settings.applyAppearance()
        // Preferences writes the choice to defaults; apply it the moment it changes.
        appearanceObserver = UserDefaults.standard.observe(\.appearance, options: [.new]) { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { Settings.applyAppearance() } }
        }
        NSApp.mainMenu = buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenShot")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // With the icon hidden, opening the app again (Finder, Spotlight) brings up Preferences.
        statusItem.isVisible = !Settings.hideMenuBarIcon
        menuIconObserver = UserDefaults.standard.observe(\.hideMenuBarIcon, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.statusItem.isVisible = !Settings.hideMenuBarIcon } }
        }

        HotKeyCenter.shared.handler = { AppLogic.shared.run($0) }
        HotKeyCenter.shared.reload()

        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        #if SCREENSHOT_SELFTESTS
        // Debug builds only: a self-test or UI snapshot run, chosen by environment variable, drives the app and quits.
        let selfTests: [() -> Bool] = [
            LiveCaptureTest.runIfRequested, SelfTest.runIfRequested, SelectionSelfTest.runIfRequested, TextSelfTest.runIfRequested,
            TextStyleSelfTest.runIfRequested, InfoSelfTest.runIfRequested, CalloutSelfTest.runIfRequested,
            AppearanceSelfTest.runIfRequested, DefaultsSelfTest.runIfRequested, Phase3SelfTest.runIfRequested,
        ]
        if selfTests.contains(where: { $0() }) { return }
        if ProcessInfo.processInfo.environment["SCREENSHOT_SNAPSHOT_DIR"] != nil {
            DebugSnapshots.runIfRequested()
            return
        }
        #endif
        Capturer.requestPermissionOnFirstLaunch()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL { AppLogic.shared.openFile(url) } else { AppLogic.shared.handleDeepLink(url) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPreferences() }
        return true
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        AppLogic.shared.handleDeepLink(url)
    }

    // MARK: Status menu (rebuilt on open so it reflects the current shortcuts)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let order: [HotkeyAction?] = [.fullscreen, .area, .repeatArea, .delayed, nil, .anyWindow, .activeWindow, nil,
                                      .scrolling, .scrollingManual, nil, .ocr]
        for a in order {
            guard let a else { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: a.title, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = a.rawValue
            if let s = HotKeyCenter.shared.shortcut(for: a), s.key.count == 1 {
                item.keyEquivalent = s.key.lowercased()
                item.keyEquivalentModifierMask = s.nsModifiers
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(item("Load From Clipboard", #selector(loadClipboard)))
        menu.addItem(item("Open Image…", #selector(openImage)))
        let library = item("Library…", #selector(showLibrary))
        library.keyEquivalent = "l"
        menu.addItem(library)
        menu.addItem(.separator())
        let prefs = item("Preferences…", #selector(showPreferences))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        let quit = NSMenuItem(title: "Quit ScreenShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

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

    @objc func showPreferences() {
        if prefs == nil { prefs = PreferencesWindowController() }
        NSApp.activate()
        prefs?.window?.center()
        prefs?.showWindow(nil)
    }

    // MARK: Main menu (gives editor windows ⌘C, ⌘S, ⌘Z… via the responder chain)

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            items.forEach { m.addItem($0) }
            holder.submenu = m
            main.addItem(holder)
        }
        func mi(_ title: String, _ action: String, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        submenu("ScreenShot", [prefs, .separator(), mi("Hide ScreenShot", "hide:", "h"), .separator(), mi("Quit ScreenShot", "terminate:", "q")])
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
        submenu("View", [
            mi("Zoom In", "zoomIn:", "="),
            mi("Zoom Out", "zoomOut:", "-"),
            mi("Zoom to Fit", "zoomToFit:", "0"),
        ])
        return main
    }
}

extension UserDefaults {
    /// KVO-observable mirror of the "appearance" key (the property name must match the key for KVO).
    @objc dynamic var appearance: String? { string(forKey: "appearance") }
    @objc dynamic var hideMenuBarIcon: Bool { bool(forKey: Keys.hideMenuBarIcon) }
}
