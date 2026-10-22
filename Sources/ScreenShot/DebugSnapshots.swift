import AppKit

/// UI self-check: with SCREENSHOT_SNAPSHOT_DIR and SCREENSHOT_SNAPSHOT_IMAGE set, opens each window, renders it to PNG
/// with AppKit's own view drawing (no screen recording needed) and quits. Does nothing otherwise.
@MainActor enum DebugSnapshots {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_SNAPSHOT_DIR"], let imagePath = env["SCREENSHOT_SNAPSHOT_IMAGE"],
              let ns = NSImage(contentsOfFile: imagePath), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        let out = URL(fileURLWithPath: dir)
        if let look = env["SCREENSHOT_SNAPSHOT_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
        }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        AppLogic.shared.openEditor(img, scale: 2)
        let editor = NSApp.windows.first { $0.windowController is EditorWindowController }
        if let ed = editor?.windowController as? EditorWindowController {
            let w = CGFloat(img.width), h = CGFloat(img.height)
            var a = Annotation(kind: .arrow, p1: CGPoint(x: w * 0.1, y: h * 0.1), p2: CGPoint(x: w * 0.4, y: h * 0.3), style: ed.shotView.style)
            ed.doc.objects.append(a)
            a = Annotation(kind: .rect, p1: CGPoint(x: w * 0.5, y: h * 0.1), p2: CGPoint(x: w * 0.8, y: h * 0.3), style: ed.shotView.style)
            ed.doc.objects.append(a)
            var c = Annotation(kind: .counter, p1: CGPoint(x: w * 0.2, y: h * 0.6), p2: .zero, style: ed.shotView.style)
            c.number = 1
            c.shape = .bubble
            ed.doc.objects.append(c)
            var callout = Annotation(kind: .callout, p1: CGPoint(x: w * 0.55, y: h * 0.45), p2: .zero, style: ed.shotView.style)
            callout.text = "New feature here"
            callout.calloutStyle = .box
            callout.color = NSColor(hex: 0x007AFF)
            callout.pointer = CGPoint(x: w * 0.42, y: h * 0.7)
            ed.doc.objects.append(callout)
            ed.shotView.tool = .callout
        }

        var steps: [(String, () -> NSWindow?)] = [
            ("editor", { editor }),
            ("panel-color", { openPanel(editor, 0) }),
            ("panel-resize", { openPanel(editor, 1) }),
            ("panel-zoom", { openPanel(editor, 2) }),
            ("prefs-general", { openPrefs(pane: 0) }),
            ("prefs-hotkeys", { openPrefs(pane: 1) }),
            ("prefs-advanced", { openPrefs(pane: 2) }),
        ]
        steps.append(("overlay", {
            // The capture overlay, rendered over the test image instead of a live screen.
            let size = CGSize(width: 820, height: 560)
            let w = NSWindow(contentRect: CGRect(origin: CGPoint(x: 60, y: 60), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            let v = CurtainView(frame: CGRect(origin: .zero, size: size), screen: NSScreen.main!, image: img, windowList: [], mode: .area)
            w.contentView = v
            w.orderFront(nil)
            v.debugPreview(mouse: CGPoint(x: 560, y: 330), selection: CGRect(x: 160, y: 140, width: 320, height: 210))
            return w
        }))
        steps.append(("toast", {
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            Toast.show("Copied to the clipboard", duration: 3)
            return NSApp.windows.first { !before.contains(ObjectIdentifier($0)) }
        }))
        steps.append(("toast-warning", {
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            Toast.show("No text detected in the selected area", duration: 3)
            return NSApp.windows.first { !before.contains(ObjectIdentifier($0)) }
        }))
        steps.append(("pin", {
            Pins.pin(img, scale: 2, near: nil)
            let w = NSApp.windows.last { $0 is PinWindow }
            if let v = w?.contentView { v.mouseEntered(with: NSEvent()) }
            return w
        }))
        steps.append(("thumbnail", {
            Thumbnail.show(img, scale: 2)
            return NSApp.windows.last { $0.frame.width == 267 }
        }))

        func next(_ i: Int) {
            guard i < steps.count else { NSApp.terminate(nil); return }
            let (name, open) = steps[i]
            let win = open()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let win { write(win, to: out.appendingPathComponent("\(name).png")) }
                next(i + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { next(0) }
    }

    /// Opens one info panel and returns its popover window.
    private static func openPanel(_ editor: NSWindow?, _ which: Int) -> NSWindow? {
        guard let ed = editor?.windowController as? EditorWindowController, let content = editor?.contentView,
              let info = findInfo(in: content), let anchor = info.subviews.first?.subviews.first else { return nil }
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        switch which {
        case 0: ed.showColorPanel(from: anchor)
        case 1: ed.showResizePanel()
        default: ed.showZoomPanel(from: anchor)
        }
        return NSApp.windows.first { !before.contains(ObjectIdentifier($0)) } ?? NSApp.windows.last
    }

    private static func findInfo(in v: NSView) -> InfoCellsView? {
        if let i = v as? InfoCellsView { return i }
        for s in v.subviews { if let f = findInfo(in: s) { return f } }
        return nil
    }

    private static func openPrefs(pane: Int) -> NSWindow? {
        (NSApp.delegate as? AppDelegate)?.showPreferences()
        guard let w = NSApp.windows.first(where: { $0.windowController is PreferencesWindowController }),
              let tb = w.toolbar, pane < tb.items.count else { return nil }
        let item = tb.items[pane]
        if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        return w
    }

    /// Renders the whole window frame (title bar and toolbar included) through the view hierarchy.
    private static func write(_ window: NSWindow, to url: URL) {
        guard let frameView = window.contentView?.superview else { return }
        frameView.layoutSubtreeIfNeeded()
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Auto-save / same-window switching self-test. Runs only with SCREENSHOT_SELFTEST_DIR set (pass `-saveFolder <dir>` too),
/// prints PASS/FAIL lines and quits.
@MainActor enum SelfTest {
    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_DIR"] else { return false }
        let a = URL(fileURLWithPath: dir).appendingPathComponent("a.png")
        let b = URL(fileURLWithPath: dir).appendingPathComponent("b.png")
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func editors() -> [EditorWindowController] { NSApp.windows.compactMap { $0.windowController as? EditorWindowController }.filter { $0.window?.isVisible == true } }
        func after(_ t: Double, _ f: @escaping @MainActor () -> Void) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(t))
                f()
            }
        }

        AppLogic.shared.openFile(a)
        guard let ed = editors().first else { print("FAIL no editor"); exit(1) }
        var text = Annotation(kind: .text, p1: CGPoint(x: 40, y: 40), p2: .zero, style: ed.shotView.style)
        text.text = "kept"
        ed.doc.objects.append(text)
        ed.shotView.markChanged()
        after(1.6) {
            check(EditableFile.load(a)?.state?.objects.first?.text == "kept", "A auto-saved its text ~1s after the edit")
            ed.switchTo(b)
            check(editors().count == 1 && ed.doc.fileURL?.lastPathComponent == "b.png", "thumbnail switch reuses the same window")
            let arrow = Annotation(kind: .arrow, p1: CGPoint(x: 10, y: 10), p2: CGPoint(x: 200, y: 120), style: ed.shotView.style)
            ed.doc.undoStack.append(.init(image: ed.doc.image, objects: ed.doc.objects, backdrop: ed.doc.backdrop))
            ed.doc.objects.append(arrow)
            ed.shotView.markChanged()
            ed.switchTo(a) // immediately, before the auto-save timer fires
            check(EditableFile.load(b)?.state?.objects.first?.kind == .arrow, "B saved on switching away (no wait)")
            check(ed.doc.fileURL?.lastPathComponent == "a.png" && ed.doc.objects.first?.text == "kept", "back on A with its text still editable")
            ed.switchTo(b)
            check(!ed.doc.undoStack.isEmpty, "B kept its undo history across the switch")
            check(EditableFile.load(a)?.state?.objects.count == 1, "reloaded from disk (as after a restart), A still has its object")

            // A new capture has no file yet: its first edit creates one in the Screenshots folder.
            AppLogic.shared.openEditor(ed.doc.image, scale: 2)
            guard let fresh = editors().first(where: { $0.doc.fileURL == nil }) else { print("FAIL fresh editor"); exit(1) }
            fresh.doc.objects.append(Annotation(kind: .rect, p1: CGPoint(x: 5, y: 5), p2: CGPoint(x: 90, y: 90), style: fresh.shotView.style))
            fresh.shotView.markChanged()
            after(1.6) {
                let url = fresh.doc.fileURL
                check(url != nil && EditableFile.load(url!)?.state?.objects.first?.kind == .rect, "new capture got a file on its first edit")
                print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
                exit(failures == 0 ? 0 : 1)
            }
        }
        return true
    }
}

/// Selection self-test: sends real mouse events to the canvas. Runs only with SCREENSHOT_SELFTEST_SELECT=<image path>.
@MainActor enum SelectionSelfTest {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_SELECT"],
              let ns = NSImage(contentsOfFile: path), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        AppLogic.shared.openEditor(img, scale: 2)
        guard let ed = NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first, let win = ed.window else {
            print("FAIL no editor"); exit(1)
        }
        let v = ed.shotView
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        win.layoutIfNeeded()
        var style = v.style
        style.width = 4
        let r1 = Annotation(kind: .rect, p1: CGPoint(x: 100, y: 100), p2: CGPoint(x: 300, y: 250), style: style)
        let r2 = Annotation(kind: .rect, p1: CGPoint(x: 500, y: 400), p2: CGPoint(x: 700, y: 600), style: style)
        ed.doc.objects = [r1, r2]
        v.tool = .select

        func event(_ type: NSEvent.EventType, _ imagePoint: CGPoint, _ mods: NSEvent.ModifierFlags = []) -> NSEvent {
            let wp = v.convert(v.viewPoint(forImage: imagePoint), to: nil)
            return NSEvent.mouseEvent(with: type, location: wp, modifierFlags: mods, timestamp: 0, windowNumber: win.windowNumber,
                                      context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func click(_ p: CGPoint, _ mods: NSEvent.ModifierFlags = []) {
            v.mouseDown(with: event(.leftMouseDown, p, mods)); v.mouseUp(with: event(.leftMouseUp, p, mods))
        }
        func dragFrom(_ a: CGPoint, to b: CGPoint, _ mods: NSEvent.ModifierFlags = []) {
            v.mouseDown(with: event(.leftMouseDown, a, mods))
            v.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), mods))
            v.mouseDragged(with: event(.leftMouseDragged, b, mods))
            v.mouseUp(with: event(.leftMouseUp, b, mods))
        }
        func obj(_ id: UUID) -> Annotation? { ed.doc.objects.first { $0.id == id } }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 3 }

        click(CGPoint(x: 100, y: 175)) // on r1's left edge
        check(v.selection == [r1.id], "click selects one object")
        click(CGPoint(x: 600, y: 400), .shift) // r2's top edge
        check(v.selection == [r1.id, r2.id], "Shift-click adds a second object")
        dragFrom(CGPoint(x: 100, y: 175), to: CGPoint(x: 140, y: 205))
        check(near(obj(r1.id)!.rect.minX, 140) && near(obj(r2.id)!.rect.minX, 540) && near(obj(r2.id)!.rect.minY, 430),
              "dragging moves the whole selection")
        click(CGPoint(x: 140, y: 205)) // single-select r1 again
        let before = obj(r1.id)!.rect
        dragFrom(CGPoint(x: before.maxX, y: before.maxY), to: CGPoint(x: before.maxX + 60, y: before.maxY + 40))
        let after = obj(r1.id)!.rect
        check(near(after.width, before.width + 60) && near(after.height, before.height + 40) && near(after.minX, before.minX),
              "corner handle resizes, opposite corner stays put")
        click(CGPoint(x: 20, y: 20)) // empty: clears
        check(v.selection.isEmpty, "click on empty space clears the selection")
        dragFrom(CGPoint(x: 20, y: 20), to: CGPoint(x: 900, y: 700))
        check(v.selection == [r1.id, r2.id], "drag on empty space selects everything it touches")
        let count = ed.doc.objects.count
        let r1Before = obj(r1.id)!.rect
        dragFrom(CGPoint(x: r1Before.minX, y: r1Before.midY), to: CGPoint(x: r1Before.minX + 30, y: r1Before.midY), .option)
        let copies = ed.doc.objects.filter { $0.id != r1.id && $0.id != r2.id }
        check(ed.doc.objects.count == count + 2 && obj(r1.id)!.rect == r1Before && copies.contains { near($0.rect.minX, r1Before.minX + 30) },
              "⌥-drag duplicates the selection, moves the copies and leaves the originals")
        v.selectAll(nil)
        check(v.selection.count == 4, "⌘A selects every object")
        v.delete(nil)
        check(ed.doc.objects.isEmpty, "Delete removes the whole selection")
        v.undo(nil)
        check(ed.doc.objects.count == 4, "Undo brings them back")
        print(failures == 0 ? "SELECT SELFTEST OK" : "SELECT SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}

/// Text tool self-test: clicks with the Text tool and types with real key events, pausing past the auto-save delay.
/// Runs only with SCREENSHOT_SELFTEST_TEXT=<image path> (pass `-saveFolder <dir>` too).
@MainActor enum TextSelfTest {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_TEXT"],
              let ns = NSImage(contentsOfFile: path), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        AppLogic.shared.openEditor(img, scale: 2)
        guard let ed = NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first, let win = ed.window else {
            print("FAIL no editor"); exit(1)
        }
        let v = ed.shotView
        win.makeKeyAndOrderFront(nil)
        win.layoutIfNeeded()
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: v.convert(v.viewPoint(forImage: p), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ chars: String, code: UInt16) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
                win.sendEvent(e)
            }
        }
        func typed() -> String? { (win.firstResponder as? NSTextView)?.string }
        func after(_ t: Double, _ f: @escaping @MainActor () -> Void) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(t))
                f()
            }
        }

        v.tool = .text
        let at = CGPoint(x: 300, y: 300)
        v.mouseDown(with: mouse(.leftMouseDown, at))
        v.mouseUp(with: mouse(.leftMouseUp, at))
        check(typed() != nil, "clicking with the Text tool opens a field that has keyboard focus")
        after(0.4) {
            key("H", code: 4)
            check(typed() == "H", "first letter is typed into the field")
            after(1.5) { // longer than the auto-save delay
                check(typed() != nil, "field is still open after a pause longer than auto-save")
                key("i", code: 34)
                after(1.5) {
                    key("!", code: 18)
                    check(typed() == "Hi!", "letters typed after pauses all land in the field (got \(typed() ?? "nil"))")
                    // "a" (Arrow) and "t" (Text) are tool shortcuts on the canvas; in the field they are just letters.
                    key(" ", code: 49); key("a", code: 0); key("t", code: 17)
                    check(typed() == "Hi! at" && v.tool == .text, "tool-shortcut letters type normally (got \(typed() ?? "nil"))")
                    key("\r", code: 36)
                    check(ed.doc.objects.contains { $0.kind == .text && $0.text == "Hi! at" }, "Return commits the text as an object")
                    after(1.5) {
                        let saved = ed.doc.fileURL.flatMap { EditableFile.load($0)?.state?.objects.contains { $0.text == "Hi! at" } } ?? false
                        check(saved, "committed text is auto-saved and editable")
                        print(failures == 0 ? "TEXT SELFTEST OK" : "TEXT SELFTEST FAILED (\(failures))")
                        exit(failures == 0 ? 0 : 1)
                    }
                }
            }
        }
        return true
    }
}

/// Text styling self-test: types, selects letters with Shift+arrows, then changes color/size/font from the options bar.
/// Runs only with SCREENSHOT_SELFTEST_TEXTSTYLE=<image path> (pass `-saveFolder <dir>` too).
@MainActor enum TextStyleSelfTest {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_TEXTSTYLE"],
              let ns = NSImage(contentsOfFile: path), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        AppLogic.shared.openEditor(img, scale: 2)
        guard let ed = NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first, let win = ed.window else {
            print("FAIL no editor"); exit(1)
        }
        let v = ed.shotView
        win.makeKeyAndOrderFront(nil)
        win.layoutIfNeeded()
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func key(_ chars: String, code: UInt16, _ mods: NSEvent.ModifierFlags = []) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                win.sendEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: win.windowNumber,
                                               context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
            }
        }
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        var editor: NSTextView? { win.firstResponder as? NSTextView }
        func color(at i: Int) -> String? { (editor?.textStorage?.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor)?.hexString }
        func fontName(at i: Int) -> String? { (editor?.textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont)?.fontName }
        func pointSize(at i: Int) -> CGFloat { (editor?.textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont)?.pointSize ?? 0 }

        var start = v.style
        start.color = NSColor(hex: 0xFF3B30); start.width = 4; start.font = .sans
        v.setStyle(start)
        v.tool = .text
        let at = CGPoint(x: 300, y: 300)
        let wp = v.convert(v.viewPoint(forImage: at), to: nil)
        for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let e = NSEvent.mouseEvent(with: t, location: wp, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1)!
            if t == .leftMouseDown { v.mouseDown(with: e) } else { v.mouseUp(with: e) }
        }
        for (c, code) in [("H", UInt16(4)), ("e", 14), ("l", 37), ("l", 37), ("o", 31)] { key(c, code: code) }
        key(left, code: 123, [.shift, .function, .numericPad])
        key(left, code: 123, [.shift, .function, .numericPad])
        check(editor?.selectedRange() == NSRange(location: 3, length: 2), "Shift+Left twice selects \"lo\"")
        let sizeBefore = pointSize(at: 0)

        // What the options bar does when you pick a color, size and font.
        var picked = start
        picked.color = NSColor(hex: 0x007AFF); picked.width = 8; picked.font = .goofy
        v.setStyle(picked)
        check(color(at: 3) == "#007AFF" && color(at: 4) == "#007AFF", "selected letters take the new color (got \(color(at: 3) ?? "nil"))")
        check(fontName(at: 3)?.contains("Chalkboard") == true, "selected letters take the new font (got \(fontName(at: 3) ?? "nil"))")
        check(pointSize(at: 3) > sizeBefore, "selected letters take the new size (\(sizeBefore) → \(pointSize(at: 3)))")
        check(color(at: 0) == "#FF3B30" && fontName(at: 0)?.contains("Chalkboard") == false, "unselected letters keep their style")
        check(editor != nil, "the text field is still open for typing")

        key("\r", code: 36)
        let obj = ed.doc.objects.first { $0.kind == .text }
        check(obj?.text == "Hello" && (obj?.runs?.count ?? 0) >= 2, "committed text keeps per-letter styles (\(obj?.runs?.count ?? 0) runs)")
        let blueRun = obj?.runs?.first { $0.location == 3 }
        check(blueRun?.color == "#007AFFFF" && blueRun?.font == .goofy && (blueRun?.size ?? 0) > (obj?.fontSize ?? 99),
              "the \"lo\" run has the new color, font and size")

        // Restyling a selected (not edited) text object restyles all of it.
        v.selectAll(nil)
        var green = picked
        green.color = NSColor(hex: 0x34C759)
        v.setStyle(green)
        let restyled = ed.doc.objects.first { $0.kind == .text }
        check(restyled?.color.hexString == "#34C759" && restyled?.runs == nil, "styling a selected text object applies to all of it")
        print(failures == 0 ? "TEXTSTYLE SELFTEST OK" : "TEXTSTYLE SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}

/// Info cells self-test (color, size/resize, zoom). Runs only with SCREENSHOT_SELFTEST_INFO=<image path>.
@MainActor enum InfoSelfTest {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_INFO"],
              let ns = NSImage(contentsOfFile: path), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        // Shottr's own sample color and labels (#FFC200).
        let sample = NSColor(hex: 0xFFC200)
        let expected: [ColorFormat: String] = [
            .hex: "#FFC200", .hexNoHash: "FFC200", .cssRGBA: "rgba(255, 194, 0, 1)", .rgbUnit: "(1.00, 0.76, 0.00)",
            .android: "0xFFFFC200", .uiColor: "UIColor(red: 1.00, green: 0.76, blue: 0.00, alpha: 1.00)", .csharp: "Color.fromArgb(255, 194, 0);",
        ]
        for (f, want) in expected { check(f.string(sample) == want, "color format \(f.rawValue) → \(f.string(sample))") }
        check(ColorFormat.oklch.string(sample).hasPrefix("oklch(84."), "OKLCH → \(ColorFormat.oklch.string(sample))")

        AppLogic.shared.openEditor(img, scale: 2)
        guard let ed = NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first, let win = ed.window else {
            print("FAIL no editor"); exit(1)
        }
        win.layoutIfNeeded()
        let v = ed.shotView
        let info = win.contentView.flatMap { find(InfoCellsView.self, in: $0) }
        let infoFrame = info.map { $0.convert($0.bounds, to: nil) } ?? .zero
        check(info != nil && info!.window != nil && win.contentView!.bounds.contains(infoFrame) && infoFrame.width > 100,
              "info cells are in the window, not in the toolbar overflow (\(Int(infoFrame.minX))…\(Int(infoFrame.maxX)) of \(Int(win.frame.width)))")

        let w0 = ed.doc.image.width
        ed.showResizePanel()
        check(ed.doc.image.width == w0, "opening the resize panel changes nothing by itself")
        v.resizeImage(by: 0.5)
        check(ed.doc.image.width == w0 / 2, "resize to 50% halves the image (\(w0) → \(ed.doc.image.width))")
        v.undo(nil)
        check(ed.doc.image.width == w0, "resize can be undone")

        Settings.showPoints = false
        ed.updateInfo()
        let px = find(InfoCellsView.self, in: win.contentView!)!.sizeText
        ed.toggleSizeUnits()
        let pt = find(InfoCellsView.self, in: win.contentView!)!.sizeText
        check(px.hasSuffix("px") && pt.hasSuffix("pt") && px != pt, "P switches the size between px and pt (\(px) → \(pt))")
        Settings.showPoints = false

        let fit = v.zoomPercent
        v.zoomToActualSize()
        check(v.zoomPercent == 100, "zoom panel 100% button gives 100% (was \(fit)%)")
        v.zoomIn(nil)
        check(v.zoomPercent == 125, "zoom panel + zooms in (\(v.zoomPercent)%)")
        v.zoomToFit(nil)
        check(v.zoomPercent == fit, "Fit to Window returns to \(fit)%")

        let dark = ed.doc.darkestColor(around: CGPoint(x: 512, y: 880), radius: 10)
        let avg = ed.doc.averageColor(in: CGRect(x: 380, y: 300, width: 200, height: 200))
        check(dark != nil && dark!.luminance < 0.3, "Shift+Tab text color picks the darkest nearby pixel (\(dark?.hexString ?? "nil"))")
        check(avg != nil && avg!.blueComponent > avg!.redComponent, "C copies the area's average color (\(avg?.hexString ?? "nil"), screen is blue)")
        print(failures == 0 ? "INFO SELFTEST OK" : "INFO SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }

    private static func find<T: NSView>(_ type: T.Type, in v: NSView) -> T? {
        if let t = v as? T { return t }
        for s in v.subviews { if let f = find(type, in: s) { return f } }
        return nil
    }
}

/// Callout self-test with real mouse/keyboard events. Runs only with SCREENSHOT_SELFTEST_CALLOUT=<image path>.
@MainActor enum CalloutSelfTest {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_CALLOUT"],
              let ns = NSImage(contentsOfFile: path), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        AppLogic.shared.openEditor(img, scale: 2)
        guard let ed = NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first, let win = ed.window else {
            print("FAIL no editor"); exit(1)
        }
        let v = ed.shotView
        win.makeKeyAndOrderFront(nil)
        win.layoutIfNeeded()
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func ev(_ t: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: v.convert(v.viewPoint(forImage: p), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func drag(_ a: CGPoint, _ b: CGPoint) {
            v.mouseDown(with: ev(.leftMouseDown, a))
            v.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)))
            v.mouseDragged(with: ev(.leftMouseDragged, b))
            v.mouseUp(with: ev(.leftMouseUp, b))
        }
        func key(_ c: String, _ code: UInt16) {
            for t in [NSEvent.EventType.keyDown, .keyUp] {
                win.sendEvent(NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                                               context: nil, characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)!)
            }
        }
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { a.distance(to: b) < 3 }
        func callouts() -> [Annotation] { ed.doc.objects.filter { $0.kind == .callout } }

        var st = v.style
        st.callout = .speech
        v.setStyle(st)
        v.tool = .callout
        let target = CGPoint(x: 400, y: 640), place = CGPoint(x: 560, y: 300)
        drag(target, place)
        check(callouts().count == 1 && near(callouts()[0].calloutPointer, target) && near(callouts()[0].p1, place),
              "drag from target to spot creates a callout aiming at the target")
        check(callouts().first?.calloutStyle == .speech, "it uses the chosen design (Speech)")
        check(win.firstResponder is NSTextView, "typing starts right away")
        for (c, code) in [("L", UInt16(37)), ("o", 31), ("o", 31), ("k", 40)] { key(c, code) }
        check(callouts().first?.text == "Look", "the bubble follows the text while typing")
        key("\r", 36)
        check(callouts().first?.text == "Look" && !(win.firstResponder is NSTextView), "Return finishes the text")

        let box = callouts()[0].calloutBox
        drag(callouts()[0].calloutPointer, CGPoint(x: 120, y: 120))
        check(near(callouts()[0].calloutPointer, CGPoint(x: 120, y: 120)) && callouts()[0].calloutBox == box,
              "dragging the tip re-aims it anywhere; the bubble stays")
        v.tool = .select
        drag(CGPoint(x: box.midX, y: box.midY), CGPoint(x: box.midX + 60, y: box.midY + 40))
        check(near(callouts()[0].p1, CGPoint(x: box.minX + 60, y: box.minY + 40)) && near(callouts()[0].calloutPointer, CGPoint(x: 120, y: 120)),
              "dragging the bubble moves it and keeps the tip on its target")
        var shout = v.style
        shout.callout = .shout
        v.setStyle(shout)
        check(callouts()[0].calloutStyle == .shout, "the design picker restyles the selected callout")

        v.tool = .callout
        let click = CGPoint(x: 800, y: 800)
        v.mouseDown(with: ev(.leftMouseDown, click))
        v.mouseUp(with: ev(.leftMouseUp, click))
        key("H", 4); key("i", 34); key("\r", 36)
        let second = callouts().last
        check(callouts().count == 2 && near(second!.calloutPointer, click) && second!.p1.x > click.x && second!.p1.y < click.y,
              "a plain click places the bubble up-right, aimed at the click")

        let data = try? JSONEncoder().encode(ed.doc.objects)
        let back = data.flatMap { try? JSONDecoder().decode([Annotation].self, from: $0) }?.filter { $0.kind == .callout }
        check(back?.first?.calloutStyle == .shout && back.map { near($0[0].calloutPointer, CGPoint(x: 120, y: 120)) } == true && back?.first?.text == "Look",
              "design, text and target survive saving")
        print(failures == 0 ? "CALLOUT SELFTEST OK" : "CALLOUT SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}

/// Appearance setting self-test: clicks System / Light / Dark in Preferences and checks the windows follow.
/// Runs only with SCREENSHOT_SELFTEST_APPEARANCE=<image path>; restores the original setting when done.
@MainActor enum AppearanceSelfTest {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_APPEARANCE"],
              let ns = NSImage(contentsOfFile: path), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let original = UserDefaults.standard.string(forKey: "appearance")
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func isDark(_ a: NSAppearance) -> Bool { a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
        func radio(_ title: String, in v: NSView) -> NSButton? {
            if let b = v as? NSButton, b.title == title, v is DefaultsRadio { return b }
            for s in v.subviews { if let f = radio(title, in: s) { return f } }
            return nil
        }
        func after(_ t: Double, _ f: @escaping @MainActor () -> Void) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(t))
                f()
            }
        }

        AppLogic.shared.openEditor(img, scale: 2)
        (NSApp.delegate as? AppDelegate)?.showPreferences()
        guard let prefs = NSApp.windows.first(where: { $0.windowController is PreferencesWindowController }),
              let editor = NSApp.windows.first(where: { $0.windowController is EditorWindowController }),
              let content = prefs.contentView else { print("FAIL windows"); exit(1) }
        check(radio("System", in: content) != nil && radio("Light", in: content) != nil && radio("Dark", in: content) != nil,
              "General has an Appearance row with System / Light / Dark")

        radio("Dark", in: content)?.performClick(nil)
        after(0.3) {
            check(UserDefaults.standard.string(forKey: "appearance") == "dark", "clicking Dark saves the choice")
            check(isDark(NSApp.effectiveAppearance) && isDark(editor.effectiveAppearance) && isDark(prefs.effectiveAppearance),
                  "Dark turns the editor and Preferences dark right away")
            radio("Light", in: content)?.performClick(nil)
            after(0.3) {
                check(!isDark(NSApp.effectiveAppearance) && !isDark(editor.effectiveAppearance), "Light turns them light")
                radio("System", in: content)?.performClick(nil)
                after(0.3) {
                    check(NSApp.appearance == nil, "System follows macOS again")
                    if let original { UserDefaults.standard.set(original, forKey: "appearance") } else { UserDefaults.standard.removeObject(forKey: "appearance") }
                    print(failures == 0 ? "APPEARANCE SELFTEST OK" : "APPEARANCE SELFTEST FAILED (\(failures))")
                    exit(failures == 0 ? 0 : 1)
                }
            }
        }
        return true
    }
}

/// Option defaults self-test through the real right-click menus. Runs only with SCREENSHOT_SELFTEST_DEFAULTS=<image path>;
/// restores the user's saved defaults when done.
@MainActor enum DefaultsSelfTest {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_DEFAULTS"],
              let ns = NSImage(contentsOfFile: path), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let saved = UserDefaults.standard.dictionary(forKey: ToolStyle.defaultsKey)
        UserDefaults.standard.removeObject(forKey: ToolStyle.defaultsKey)
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func editors() -> [EditorWindowController] { NSApp.windows.compactMap { $0.windowController as? EditorWindowController } }
        func find<T: NSView>(_ t: T.Type, in v: NSView, where ok: (T) -> Bool) -> T? {
            if let x = v as? T, ok(x) { return x }
            for s in v.subviews { if let f = find(t, in: s, where: ok) { return f } }
            return nil
        }
        func rightClickMenu(_ c: DefaultableSegmentedControl, segment i: Int) -> NSMenu? {
            let w = c.bounds.width / CGFloat(c.segmentCount)
            let p = c.convert(CGPoint(x: w * (CGFloat(i) + 0.5), y: c.bounds.midY), to: nil)
            let e = NSEvent.mouseEvent(with: .rightMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: c.window!.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            return c.menu(for: e)
        }

        check(ToolStyle.loadDefaults().callout == .box, "built-in default callout is Professional · Box")
        AppLogic.shared.openEditor(img, scale: 2)
        let ed = editors()[0]
        ed.window?.layoutIfNeeded()
        check(ed.shotView.style.callout == .box, "a new editor starts with the Box callout")
        ed.shotView.tool = .callout
        guard let content = ed.window?.contentView,
              let callouts = find(DefaultableSegmentedControl.self, in: content, where: { $0.segmentCount == CalloutStyle.allCases.count && $0.name(of: 0).contains("Box") })
        else { print("FAIL callout control not found"); exit(1) }
        check(callouts.defaultIndex == CalloutStyle.box.rawValue, "the Box segment carries the default marker")

        let menu = rightClickMenu(callouts, segment: CalloutStyle.thought.rawValue)
        check(menu?.items.first?.title == "Set “Fun · Thought” as Default", "right-click offers “\(menu?.items.first?.title ?? "nil")”")
        menu?.performActionForItem(at: 0)
        check(ToolStyle.loadDefaults().callout == .thought, "Thought is saved as the default")
        check(callouts.defaultIndex == CalloutStyle.thought.rawValue, "the marker moves to Thought")
        check(ed.shotView.style.callout == .thought, "Thought is also selected right away")

        callouts.selectedSegment = CalloutStyle.speech.rawValue
        callouts.sendAction(callouts.action, to: callouts.target)
        check(ed.shotView.style.callout == .speech && ToolStyle.loadDefaults().callout == .thought,
              "an ordinary click picks Speech for now without changing the default")

        AppLogic.shared.openEditor(img, scale: 2)
        let second = editors().first { $0 !== ed }
        check(second?.shotView.style.callout == .thought, "a new editor starts from the new default (Thought)")

        let reset = rightClickMenu(callouts, segment: 0)
        if let i = reset?.items.firstIndex(where: { $0.title == "Reset to Original Default" }) { reset?.performActionForItem(at: i) }
        check(ToolStyle.loadDefaults().callout == .box && callouts.defaultIndex == CalloutStyle.box.rawValue, "Reset to Original Default goes back to Box")

        // Color and size defaults through their right-click menus.
        var picked = ed.shotView.style
        picked.color = NSColor(hex: 0x007AFF)
        picked.width = 9
        ed.shotView.setStyle(picked)
        ed.syncToolbar()
        guard let bar = find(OptionsBar.self, in: content, where: { _ in true }) else { print("FAIL options bar"); exit(1) }
        for (what, title) in [("color", "Set #007AFF as Default Color"), ("size", "Set Size 9 as Default")] {
            let m = NSMenu()
            m.identifier = NSUserInterfaceItemIdentifier(what)
            bar.menuNeedsUpdate(m)
            check(m.items.first?.title == title, "\(what) menu offers “\(m.items.first?.title ?? "nil")”")
            m.performActionForItem(at: 0)
        }
        let d = ToolStyle.loadDefaults()
        check(d.color.hexString == "#007AFF" && d.width == 9, "color and size are saved as defaults")

        if let saved { UserDefaults.standard.set(saved, forKey: ToolStyle.defaultsKey) } else { UserDefaults.standard.removeObject(forKey: ToolStyle.defaultsKey) }
        print(failures == 0 ? "DEFAULTS SELFTEST OK" : "DEFAULTS SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
