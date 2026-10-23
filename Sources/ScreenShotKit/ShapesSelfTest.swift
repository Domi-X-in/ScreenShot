import AppKit

#if SCREENSHOT_SELFTESTS
/// Self-test for typing in shapes, the callout color, content past the image, Arrange and smart guides. Sends real
/// mouse and key events to the editor. Runs only with SCREENSHOT_SELFTEST_SHAPES set (pass `-saveFolder <dir>` too).
@MainActor enum ShapesSelfTest {
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_SHAPES"] != nil else { return false }
        let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(NSColor(hex: 0xEEF1F5).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        AppLogic.shared.openEditor(ctx.makeImage()!, scale: 1)
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
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: v.convert(v.viewPoint(forImage: p), to: nil), modifierFlags: mods, timestamp: 0,
                               windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func drag(_ a: CGPoint, _ b: CGPoint, check mid: (() -> Void)? = nil) {
            v.mouseDown(with: mouse(.leftMouseDown, a))
            v.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)))
            v.mouseDragged(with: mouse(.leftMouseDragged, b))
            mid?()
            v.mouseUp(with: mouse(.leftMouseUp, b))
        }
        func click(_ p: CGPoint) {
            v.mouseDown(with: mouse(.leftMouseDown, p))
            v.mouseUp(with: mouse(.leftMouseUp, p))
        }
        func key(_ chars: String, code: UInt16) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
                win.sendEvent(e)
            }
        }
        func typed() -> String? { (win.firstResponder as? NSTextView)?.string }
        func obj(_ id: UUID) -> Annotation? { ed.doc.objects.first { $0.id == id } }

        Task { @MainActor in
            // 1 · Return types inside a rectangle.
            var st = v.style
            st.color = NSColor(hex: 0xFF3B30)
            st.width = 4
            st.fill = .none
            v.setStyle(st)
            v.tool = .rect
            drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 220))
            guard let rect = ed.doc.objects.last, rect.kind == .rect else { print("FAIL no rectangle"); exit(1) }
            v.tool = .select
            click(CGPoint(x: 100, y: 160)) // its left edge
            check(v.selection == [rect.id], "the rectangle is selected")
            key("\r", code: 36)
            try? await Task.sleep(for: .seconds(0.2))
            check(typed() != nil, "Return on a selected rectangle opens a text field")
            for (c, code) in [("O", UInt16(31)), ("K", 40)] { key(c, code: code) }
            check(typed() == "OK", "letters go into the rectangle (got \(typed() ?? "nil"))")
            v.commitText()
            check(obj(rect.id)?.text == "OK" && obj(rect.id)?.color.hexString == "#FF3B30" && obj(rect.id)?.width == 4,
                  "the text is kept and the outline keeps its color and width")
            v.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 200, y: 160), clicks: 2))
            v.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 200, y: 160), clicks: 2))
            check(typed() == "OK", "double-clicking inside edits the text again")
            v.commitText()

            // 3 · Typing in a callout, then clicking elsewhere to add another, keeps the first one's color.
            var cs = v.style
            cs.color = NSColor(hex: 0x007AFF)
            cs.callout = .box
            v.tool = .callout
            v.setStyle(cs)
            drag(CGPoint(x: 450, y: 450), CGPoint(x: 500, y: 350))
            try? await Task.sleep(for: .seconds(0.2))
            for (c, code) in [("H", UInt16(4)), ("i", 34)] { key(c, code: code) }
            let first = ed.doc.objects.last { $0.kind == .callout }
            drag(CGPoint(x: 650, y: 500), CGPoint(x: 680, y: 420)) // a second callout
            check(first.flatMap { obj($0.id) }?.color.hexString == "#007AFF", "the first callout keeps its blue after clicking away (\(first.flatMap { obj($0.id) }?.color.hexString ?? "gone"))")
            check(first.flatMap { obj($0.id) }?.text == "Hi", "and keeps its text")
            v.commitText()

            // 5 · Smart guides: a new box dragged near the rectangle's left edge snaps to it and shows a guide.
            v.tool = .oval
            drag(CGPoint(x: 400, y: 250), CGPoint(x: 480, y: 300))
            guard let oval = ed.doc.objects.last, oval.kind == .oval else { print("FAIL no oval"); exit(1) }
            v.tool = .select
            let ob = oval.bounds, rb = obj(rect.id)!.bounds
            var sawGuide = false
            drag(CGPoint(x: ob.minX, y: ob.midY), CGPoint(x: rb.minX + 3, y: ob.midY + 120)) { sawGuide = !v.guides.isEmpty }
            check(abs(obj(oval.id)!.bounds.minX - rb.minX) < 0.5, "a dragged shape snaps its left edge to the rectangle's (\(obj(oval.id)!.bounds.minX) vs \(rb.minX))")
            check(sawGuide && v.guides.isEmpty, "a guide shows while dragging and goes away after")

            // 4 · Arrange: align the oval's center to the rectangle's, then send it to the back.
            v.selectAll(nil)
            let ids = Set(ed.doc.objects.filter { $0.kind == .rect || $0.kind == .oval }.map(\.id))
            v.selectAll(nil)
            ed.doc.objects.removeAll { $0.kind == .callout }
            v.selectAll(nil)
            check(v.selection == ids, "both shapes selected")
            v.arrange(.alignCenter)
            check(abs(obj(oval.id)!.bounds.midX - obj(rect.id)!.bounds.midX) < 0.5, "Align Center lines them up")
            let item = NSMenuItem(title: "", action: #selector(ShotView.arrangeFromMenu(_:)), keyEquivalent: "")
            item.representedObject = ArrangeAction.distributeHorizontally.rawValue
            check(!v.validateMenuItem(item), "Distribute is off with only two objects")
            v.undo(nil)
            check(abs(obj(oval.id)!.bounds.midX - obj(rect.id)!.bounds.midX) > 1, "Undo puts them back")
            v.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: obj(oval.id)!.rect.midX, y: obj(oval.id)!.rect.minY)))
            v.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: obj(oval.id)!.rect.midX, y: obj(oval.id)!.rect.minY)))
            v.arrange(.sendToBack)
            check(ed.doc.objects.first?.id == oval.id, "Send to Back puts the oval under everything")
            let menu = v.menu(for: mouse(.rightMouseDown, CGPoint(x: obj(rect.id)!.rect.minX, y: obj(rect.id)!.rect.midY)))
            check(menu?.items.contains { $0.title == "Edit Text" } == true && menu?.items.contains { $0.title == "Bring to Front" } == true,
                  "right-click offers Edit Text and the Arrange commands")

            // 2 · Content past the image: drag the rectangle mostly off the left edge; the picture grows to include it.
            v.tool = .select
            click(CGPoint(x: obj(rect.id)!.rect.minX, y: obj(rect.id)!.rect.midY))
            let r0 = obj(rect.id)!.rect
            drag(CGPoint(x: r0.minX, y: r0.midY), CGPoint(x: r0.minX - 250, y: r0.midY))
            let out = ed.doc.render()
            check(Renderer.canvasSize(ed.doc).width > 800 && (out?.width ?? 0) > 800,
                  "the canvas and the copied image grow to include it (\(out?.width ?? 0) px wide)")
            check(Renderer.imageOrigin(ed.doc).x > 0, "the screenshot moves right to make room")

            print(failures == 0 ? "SHAPES SELFTEST OK" : "SHAPES SELFTEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }
}
#endif
