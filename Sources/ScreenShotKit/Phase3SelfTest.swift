import AppKit

#if SCREENSHOT_SELFTESTS
/// Self-test for the Shottr-parity tools (measure keys, Autoadjust, Imprint, Cut Out, backdrop drag). Sends real key and
/// mouse events to the canvas. Runs only with SCREENSHOT_SELFTEST_PHASE3 set (pass `-saveFolder <dir>` too).
@MainActor enum Phase3SelfTest {
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_PHASE3"] != nil else { return false }
        // White 600×400 with a blue 200×120 box at (100, 80).
        let ctx = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        ctx.setFillColor(NSColor(hex: 0x2255AA).cgColor)
        ctx.fill(CGRect(x: 100, y: 400 - 80 - 120, width: 200, height: 120)) // CG is bottom-up
        AppLogic.shared.openEditor(ctx.makeImage()!, scale: 1)
        guard let ed = NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first, let win = ed.window else {
            print("FAIL no editor"); exit(1)
        }
        win.layoutIfNeeded()
        let v = ed.shotView
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func key(_ type: NSEvent.EventType, _ chars: String, code: UInt16, _ mods: NSEvent.ModifierFlags = [], repeated: Bool = false) {
            let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: win.windowNumber, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: repeated, keyCode: code)!
            type == .keyDown ? v.keyDown(with: e) : v.keyUp(with: e)
        }
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: v.convert(v.viewPoint(forImage: p), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func drag(_ a: CGPoint, _ b: CGPoint) {
            v.mouseDown(with: mouse(.leftMouseDown, a))
            v.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)))
            v.mouseDragged(with: mouse(.leftMouseDragged, b))
            v.mouseUp(with: mouse(.leftMouseUp, b))
        }
        func after(_ t: Double, _ f: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { f() } }
        }

        // Measure keys: a quick tap of 1 picks the Ruler; holding 2 measures and keeps the tool.
        v.tool = .arrow
        key(.keyDown, "1", code: 18)
        key(.keyUp, "1", code: 18)
        check(v.tool == .ruler, "a quick tap of 1 picks the Ruler tool")
        v.tool = .arrow
        key(.keyDown, "2", code: 19)
        key(.keyDown, "2", code: 19, repeated: true)
        after(0.4) {
            key(.keyUp, "2", code: 19)
            check(v.tool == .arrow, "holding 2 measures without changing the tool")

            // Autoadjust: Crop, then F shrinks the selection from the whole image to the blue box.
            v.tool = .crop
            key(.keyDown, "f", code: 3)
            check(v.cropSelection == CGRect(x: 100, y: 80, width: 200, height: 120), "F fits the selection to the content: \(String(describing: v.cropSelection))")

            // Imprint: I stamps an outline and a W × H label.
            key(.keyDown, "i", code: 34)
            let label = ed.doc.objects.first { $0.kind == .text }
            check(ed.doc.objects.contains { $0.kind == .rect && $0.rect == CGRect(x: 100, y: 80, width: 200, height: 120) } &&
                  label?.text.contains("×") == true, "I imprints the selection's outline and size (\(label?.text ?? "none"))")
            check(v.tool == .select, "after imprinting, the label is selected to move")

            // Cut Out: ⇧X, drag down over rows 0…80 (above the box), Enter.
            key(.keyDown, "X", code: 7, .shift)
            check(v.tool == .crop && v.cutOutMode, "⇧X opens Cut Out")
            drag(CGPoint(x: 400, y: 0), CGPoint(x: 405, y: 80))
            key(.keyDown, "\r", code: 36)
            check(ed.doc.image.height == 320 && ed.doc.image.width == 600, "Enter removes the 80 px strip: \(ed.doc.image.width)×\(ed.doc.image.height)")
            check(ed.doc.objects.contains { $0.kind == .rect && abs($0.rect.minY) < 1 }, "the imprinted outline moved up with the image")
            check(PixelReader(ed.doc.image).color(150, 10)?.hexString == "#2255AA", "the blue box now starts at the top")
            v.undo(nil)
            check(ed.doc.image.height == 400, "undo brings the strip back")

            // Backdrop: K turns it on; with Select, dragging the background moves the screenshot inside it.
            v.tool = .select
            var b = Backdrop()
            b.isOn = true
            b.aspect = .square
            b.shadow = 0
            v.setBackdrop(b)
            let o0 = Renderer.imageOrigin(ed.doc)
            check(ed.doc.layout.canvas.width == ed.doc.layout.canvas.height, "square aspect makes a square canvas")
            drag(CGPoint(x: -20, y: -20), CGPoint(x: -20, y: -120))
            let o1 = Renderer.imageOrigin(ed.doc)
            check(o1.y < o0.y - 50 && abs(o1.x - o0.x) < 1, "dragging the background moves the screenshot (\(o0) → \(o1))")
            key(.keyDown, "k", code: 40)
            check(!ed.doc.backdrop.isOn, "K turns the backdrop off")
            key(.keyDown, "k", code: 40)
            check(ed.doc.backdrop.isOn, "K turns it back on")

            print(failures == 0 ? "PHASE3 SELFTEST OK" : "PHASE3 SELFTEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }
}
#endif
