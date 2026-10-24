import AppKit

#if SCREENSHOT_SELFTESTS
/// Real-usage flows across features, driven with mouse and key events (⌘ shortcuts go through the menu bar like a real
/// key press). Runs only with SCREENSHOT_SELFTEST_FLOWS set (pass `-saveFolder <dir>` too). The user's settings and
/// clipboard are put back before quitting. Prints PASS/FAIL lines per flow.
@MainActor final class FlowsSelfTest {
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_FLOWS"] != nil else { return false }
        let t = FlowsSelfTest()
        Task { @MainActor in await t.run() }
        return true
    }

    private var failures = 0
    private var flow = ""
    private let only = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_FLOWS"].flatMap { $0 == "1" ? nil : $0 }

    func check(_ ok: Bool, _ what: @autoclosure () -> String) {
        let w = what()
        print(ok ? "PASS" : "FAIL", "[\(flow)] \(w)")
        if !ok { failures += 1 }
    }

    // MARK: Setup and helpers

    let folder = Settings.saveFolder

    // Settings and clipboard are saved at launch and put back at exit by SelfTestSandbox.
    private func preserve() {}
    private func restore() { SelfTestSandbox.restore() }

    func sleep(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    var editors: [EditorWindowController] {
        NSApp.windows.compactMap { $0.windowController as? EditorWindowController }.filter { $0.window?.isVisible == true }
    }

    /// A screenshot-like test image: light UI with a dark title bar, colored cards and black text.
    nonisolated static func sampleImage(_ w: Int = 1200, _ h: Int = 800, text: String = "Invoice 4821 PAID") -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(NSColor(hex: 0xF4F6F9).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(NSColor(hex: 0x23262E).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: 60))
        for (i, c) in [0x3DA9FF, 0xFF6A3D, 0x34C759].enumerated() {
            ctx.setFillColor(NSColor(hex: UInt32(c)).cgColor)
            ctx.fill(CGRect(x: 80 + i * 360, y: 140, width: 300, height: 200))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (text as NSString).draw(at: CGPoint(x: 90, y: 420), withAttributes: [.font: NSFont.systemFont(ofSize: 54, weight: .semibold),
                                                                           .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    /// Opens an editor on `img` and returns it, key and laid out.
    func openEditor(_ img: CGImage = sampleImage(), scale: CGFloat = 1, url: URL? = nil) async -> EditorWindowController? {
        let before = Set(editors.map(ObjectIdentifier.init))
        AppLogic.shared.openEditor(img, scale: scale, url: url)
        await sleep(0.3)
        let ed = editors.first { !before.contains(ObjectIdentifier($0)) } ?? editors.last
        ed?.window?.makeKeyAndOrderFront(nil)
        ed?.window?.layoutIfNeeded()
        return ed
    }

    func mouse(_ ed: EditorWindowController, _ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1,
               mods: NSEvent.ModifierFlags = []) -> NSEvent {
        let v = ed.shotView
        return NSEvent.mouseEvent(with: type, location: v.convert(v.viewPoint(forImage: p), to: nil), modifierFlags: mods, timestamp: 0,
                                  windowNumber: ed.window!.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    func drag(_ ed: EditorWindowController, _ a: CGPoint, _ b: CGPoint, mods: NSEvent.ModifierFlags = [], steps: Int = 4) {
        let v = ed.shotView
        v.mouseDown(with: mouse(ed, .leftMouseDown, a, mods: mods))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            v.mouseDragged(with: mouse(ed, .leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), mods: mods))
        }
        v.mouseUp(with: mouse(ed, .leftMouseUp, b, mods: mods))
    }

    func click(_ ed: EditorWindowController, _ p: CGPoint, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) {
        ed.shotView.mouseDown(with: mouse(ed, .leftMouseDown, p, clicks: clicks, mods: mods))
        ed.shotView.mouseUp(with: mouse(ed, .leftMouseUp, p, clicks: clicks, mods: mods))
    }

    private static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "\r": 36, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, " ": 49,
        "\t": 48, "\u{7f}": 51, "\u{1b}": 53,
    ]

    /// The window the user is working in: the key window, or the frontmost editor while the Mac is locked.
    var activeWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.windowController is EditorWindowController && $0.isVisible }
    }

    /// Finds the menu bar item for a ⌘ shortcut, like AppKit does when the key is pressed.
    func menuItem(for key: String, mods: NSEvent.ModifierFlags) -> NSMenuItem? {
        func search(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if let sub = item.submenu, let found = search(sub) { return found }
                let itemMods = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
                if item.keyEquivalent.lowercased() == key.lowercased(), item.action != nil,
                   itemMods == mods.intersection([.command, .shift, .option, .control]) { return item }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(search)
    }

    /// Types `s` as key presses into the window in use. ⌘ shortcuts are looked up in the menu bar and their action
    /// runs through that window's responder chain, the way AppKit dispatches them (this also works while the Mac is
    /// locked, when no app can be frontmost).
    func type(_ s: String, mods: NSEvent.ModifierFlags = []) {
        guard let win = activeWindow else { return }
        if mods.contains(.command) {
            guard let item = menuItem(for: s, mods: mods), let action = item.action else {
                check(false, "a menu bar item answers ⌘\(s.uppercased())"); return
            }
            let responder = win.firstResponder ?? win
            if let target = NSApp.target(forAction: action, to: item.target, from: item) as? NSMenuItemValidation, target === responder {
                _ = target.validateMenuItem(item)
            }
            if !responder.tryToPerform(action, with: item), !(win.windowController?.tryToPerform(action, with: item) ?? false) {
                check(false, "⌘\(s.uppercased()) (\(item.title)) reached the editor")
            }
            return
        }
        for ch in s.map(String.init) {
            let lower = ch.lowercased()
            let code = Self.keyCodes[lower] ?? 0
            var m = mods
            if ch != lower { m.insert(.shift) }
            for kind in [NSEvent.EventType.keyDown, .keyUp] {
                let e = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: m, timestamp: 0, windowNumber: win.windowNumber, context: nil,
                                         characters: ch, charactersIgnoringModifiers: lower, isARepeat: false, keyCode: code)!
                win.sendEvent(e)
            }
        }
    }

    func key(_ named: String, mods: NSEvent.ModifierFlags = []) {
        let codes: [String: (UInt16, String)] = ["return": (36, "\r"), "esc": (53, "\u{1b}"), "delete": (51, "\u{7f}"), "tab": (48, "\t"),
                                                  "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "down": (125, "\u{F701}"),
                                                  "up": (126, "\u{F700}")]
        guard let (code, chars) = codes[named], let win = activeWindow else { return }
        for kind in [NSEvent.EventType.keyDown, .keyUp] {
            let e = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: win.windowNumber, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            win.sendEvent(e)
        }
    }

    func typed(_ ed: EditorWindowController) -> String? { (ed.window?.firstResponder as? NSTextView)?.string }

    /// Pixel equality on a grid (for "it looks the same after reopening").
    func samePicture(_ a: CGImage?, _ b: CGImage?, tolerance: Int = 6) -> Bool {
        guard let a, let b, a.width == b.width, a.height == b.height else { return false }
        let pa = PixelReader(a), pb = PixelReader(b)
        for y in stride(from: 0, to: a.height, by: max(1, a.height / 40)) {
            for x in stride(from: 0, to: a.width, by: max(1, a.width / 40)) {
                guard let ca = pa.color(x, y), let cb = pb.color(x, y) else { return false }
                let d = [abs(ca.redComponent - cb.redComponent), abs(ca.greenComponent - cb.greenComponent), abs(ca.blueComponent - cb.blueComponent),
                         abs(ca.alphaComponent - cb.alphaComponent)].max()! * 255
                if Int(d) > tolerance { return false }
            }
        }
        return true
    }

    /// With FLOWS_SHOTS=<dir>, saves a picture of the window (for looking at the UI a flow leaves behind).
    func snapshot(_ ed: EditorWindowController, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["FLOWS_SHOTS"], let frame = ed.window?.contentView?.superview else { return }
        frame.layoutSubtreeIfNeeded()
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func closeAllEditors() async {
        for ed in editors { ed.window?.performClose(nil) }
        await sleep(0.4)
    }

    // MARK: Run

    private func run() async {
        setvbuf(stdout, nil, _IONBF, 0) // lines show up even if the app crashes
        preserve()
        // Known starting point for the options the flows rely on.
        let d = UserDefaults.standard
        d.removeObject(forKey: ToolStyle.defaultsKey)
        d.set(true, forKey: Keys.afterShow)
        d.set(false, forKey: Keys.afterCopy)
        d.set(false, forKey: Keys.afterSave)
        d.set("editor", forKey: Keys.afterAreaShow)
        d.set(false, forKey: Keys.saveRetinaAt1x)
        d.set("png", forKey: Keys.saveFormat)
        d.set(true, forKey: Keys.urlScheme)
        Settings.snapToGuides = true
        NSApp.activate()

        let flows: [(String, () async -> Void)] = [
            ("annotate-save-reopen", annotateSaveReopen),
            ("copy-paste", copyPaste),
            ("crop-cut-outside", cropAndCutWithOutsideContent),
            ("backdrop-resize-gif", backdropResizeGIF),
            ("undo-redo-chain", undoRedoChain),
            ("keyboard", keyboardFlow),
            ("text-styles", textStylesFlow),
            ("switch-files", switchFilesFlow),
            ("capture-settings", captureSettingsFlow),
            ("color-zoom-info", colorZoomInfoFlow),
            ("callout-editing", calloutEditingFlow),
            ("style-sync", styleSyncFlow),
            ("formatting", formattingFlow),
            ("panels", panelsFlow),
            ("windows", windowsFlow),
            ("library", libraryFlow),
            ("preferences", preferencesFlow),
        ]
        // SCREENSHOT_SELFTEST_FLOWS=<flow name> runs one flow; any other value runs them all.
        let pick = flows.contains { $0.0 == only } ? only : nil
        for (name, f) in flows where pick == nil || pick == name {
            flow = name
            await f()
            await closeAllEditors()
        }
        restore()
        print(failures == 0 ? "FLOWS SELFTEST OK" : "FLOWS SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
