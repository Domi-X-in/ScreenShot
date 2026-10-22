import AppKit
import CoreImage.CIFilterBuiltins
import ScreenCaptureKit

#if SCREENSHOT_SELFTESTS
/// Live capture self-test: real screen captures of test windows this app draws, using the app's own Screen Recording
/// permission. Launch through Launch Services so the permission applies, e.g.
/// `open -n -W build/ScreenShot.app --env SCREENSHOT_SELFTEST_LIVE=/tmp/live.txt --args -saveFolder /tmp/x`.
/// Results go to that file (PASS/FAIL/SKIP lines). Does nothing without the variable.
@MainActor enum LiveCaptureTest {
    // Known test pattern, in window points (top-left origin).
    static let blocks: [(CGRect, UInt32)] = [
        (CGRect(x: 20, y: 20, width: 80, height: 110), 0xFF0000), (CGRect(x: 120, y: 20, width: 80, height: 110), 0x00C000),
        (CGRect(x: 220, y: 20, width: 80, height: 110), 0x0000FF), (CGRect(x: 320, y: 20, width: 80, height: 110), 0xFFD000),
    ]
    static let textRect = CGRect(x: 20, y: 150, width: 390, height: 70)
    static let qrRect = CGRect(x: 430, y: 20, width: 150, height: 150)
    static let qrPayload = "https://github.com/Domi-X-in/ScreenShot"
    static let patternSize = CGSize(width: 600, height: 240)
    static let bandHeight: CGFloat = 100
    static let bandCount = 15

    private static var lines: [String] = []
    private static var failures = 0
    private static var resultURL: URL!

    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_LIVE"] else { return false }
        resultURL = URL(fileURLWithPath: path)
        Task { @MainActor in
            await run()
            let skippedAll = lines.contains { $0.hasPrefix("SKIP the screen is locked") }
            write(skippedAll ? "LIVE SELFTEST SKIPPED (screen locked)" : failures == 0 ? "LIVE SELFTEST OK" : "LIVE SELFTEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }

    // MARK: Reporting

    private static func write(_ line: String) {
        lines.append(line)
        print(line)
        try? lines.joined(separator: "\n").appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
    }

    private static func check(_ ok: Bool, _ what: String) {
        write("\(ok ? "PASS" : "FAIL") \(what)")
        if !ok { failures += 1 }
    }

    private static func skip(_ what: String) { write("SKIP \(what)") }

    /// Saves a captured image next to the results, for inspecting failures.
    private static func dump(_ img: CGImage, _ name: String) {
        let url = resultURL.deletingLastPathComponent().appendingPathComponent("\(name).png")
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func sleep(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    /// Color at a point given in image pixels (top-left origin), in sRGB.
    private static func color(_ img: CGImage, _ x: CGFloat, _ y: CGFloat) -> NSColor? {
        PixelReader(img).color(Int(x), Int(y))
    }

    /// Index of the candidate closest to `c` (sRGB distance). Captures come back in the display's color space,
    /// so saturated colors shift a little; "closest of the expected colors" is robust where fixed tolerances are not.
    private static func nearest(_ c: NSColor?, _ candidates: [NSColor]) -> Int? {
        guard let c else { return nil }
        return candidates.indices.min { a, b in dist(c, candidates[a]) < dist(c, candidates[b]) }
    }

    private static func dist(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let b = b.usingColorSpace(.sRGB)!
        return pow(a.redComponent - b.redComponent, 2) + pow(a.greenComponent - b.greenComponent, 2) + pow(a.blueComponent - b.blueComponent, 2)
    }

    /// The pattern's colors plus white and black: what any sampled pattern pixel should be closest to.
    private static let patternColors = blocks.map { NSColor(hex: $0.1) } + [NSColor.white, NSColor.black]

    private static func isBlock(_ c: NSColor?, _ index: Int) -> Bool { nearest(c, patternColors) == index }

    // MARK: Test windows

    /// Pattern window: four color blocks, large text and a QR code.
    private static func makePatternWindow(on screen: NSScreen) -> NSWindow {
        let vf = screen.visibleFrame
        let frame = CGRect(x: vf.minX + 60, y: vf.maxY - 160 - patternSize.height, width: patternSize.width, height: patternSize.height)
        let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.hasShadow = true
        w.contentView = PatternView(frame: CGRect(origin: .zero, size: patternSize))
        w.orderFrontRegardless()
        return w
    }

    /// Scrolling window: tall document of colored, numbered bands.
    private static func makeScrollWindow(on screen: NSScreen) -> (NSWindow, NSScrollView) {
        let vf = screen.visibleFrame
        let size = CGSize(width: 360, height: 300)
        let frame = CGRect(x: vf.minX + 60, y: vf.minY + 120, width: size.width, height: size.height)
        let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .floating
        w.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: CGRect(origin: .zero, size: size))
        scroll.hasVerticalScroller = false
        scroll.documentView = BandsView(frame: CGRect(x: 0, y: 0, width: size.width, height: bandHeight * CGFloat(bandCount)))
        w.contentView = scroll
        w.orderFrontRegardless()
        return (w, scroll)
    }

    static func bandColor(_ i: Int) -> NSColor {
        NSColor(hue: CGFloat(i % bandCount) / CGFloat(bandCount), saturation: 0.75, brightness: 0.95, alpha: 1).usingColorSpace(.sRGB)!
    }

    /// A rect on `screen` in display-local points, top-left origin (what captures take as sourceRect).
    private static func displayLocal(_ globalRect: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(x: globalRect.minX - screen.frame.minX, y: screen.frame.maxY - globalRect.maxY, width: globalRect.width, height: globalRect.height)
    }

    // MARK: The run

    private static func run() async {
        write("Live capture self-test · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(NSScreen.screens.count) display(s)")
        // A locked screen (e.g. while working remotely) shows the lock screen instead of the test windows.
        if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
            skip("the screen is locked: unlock the Mac and run again (captures would only see the lock screen)")
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            check(false, "Screen Recording permission is granted to this app")
            return
        }
        check(true, "Screen Recording permission is granted to this app")
        Settings.d.set(true, forKey: Keys.afterShow) // the hook intercepts before any editor opens

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let scale = screen.backingScaleFactor
        Capturer.includeOwnWindows = true
        NSApp.activate()
        let pattern = makePatternWindow(on: screen)
        await sleep(0.8)
        let patternLocal = displayLocal(pattern.frame, on: screen)

        await fullscreen(screen, scale: scale, patternLocal: patternLocal)
        await areaThroughOverlay(screen, scale: scale, patternLocal: patternLocal)
        await delayed(screen, scale: scale)
        await window(pattern, scale: scale)
        await otherAppsWindows()
        await ocrAndQR(screen, scale: scale, patternLocal: patternLocal)
        pattern.orderOut(nil)
        await scrolling(screen, scale: scale)
        await multipleDisplays()
        Capturer.includeOwnWindows = false
    }

    /// Runs an app flow and waits for its capture through the test hook.
    private static func captureVia(timeout: Double = 8, _ start: () -> Void) async -> (CGImage, CGFloat)? {
        var result: (CGImage, CGFloat)?
        AppLogic.shared.captureHookForTest = { img, s in result = (img, s) }
        start()
        var waited = 0.0
        while result == nil && waited < timeout {
            await sleep(0.1)
            waited += 0.1
        }
        AppLogic.shared.captureHookForTest = nil
        return result
    }

    private static func fullscreen(_ screen: NSScreen, scale: CGFloat, patternLocal: CGRect) async {
        guard let (img, s) = await captureVia({ AppLogic.shared.captureFullscreen() }) else {
            check(false, "fullscreen capture produced an image"); return
        }
        let expected = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        check(abs(CGFloat(img.width) - expected.width) <= 2 && abs(CGFloat(img.height) - expected.height) <= 2 && s == scale,
              "fullscreen is the whole display: \(img.width)×\(img.height) px at \(s)× (expected \(Int(expected.width))×\(Int(expected.height)))")
        let red = blocks[0].0
        let c = color(img, (patternLocal.minX + red.midX) * scale, (patternLocal.minY + red.midY) * scale)
        check(isBlock(c, 0), "fullscreen shows real screen content (red block reads \(c?.hexString ?? "nil"))")
    }

    /// Area capture end to end: the frozen-screen overlay, a mouse drag over the pattern, then Repeat Area.
    private static func areaThroughOverlay(_ screen: NSScreen, scale: CGFloat, patternLocal: CGRect) async {
        let sel = CGRect(x: patternLocal.minX + 10, y: patternLocal.minY + 10, width: 400, height: 130)
        let result = await captureVia {
            AppLogic.shared.captureArea(mode: .area)
            Task { @MainActor in
                // Wait for the overlay, then drag across it like a user would.
                var curtain: CurtainView?
                for _ in 0..<50 where curtain == nil {
                    await sleep(0.1)
                    curtain = NSApp.windows.compactMap { $0.contentView as? CurtainView }.first { $0.window?.screen == screen }
                }
                guard let v = curtain, let w = v.window else { return }
                @MainActor func ev(_ t: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: t, location: v.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                v.mouseDown(with: ev(.leftMouseDown, sel.origin))
                v.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: sel.midX, y: sel.midY)))
                v.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: sel.maxX, y: sel.maxY)))
                v.mouseUp(with: ev(.leftMouseUp, CGPoint(x: sel.maxX, y: sel.maxY)))
            }
        }
        guard let (img, _) = result else { check(false, "area capture through the overlay produced an image"); return }
        dump(img, "area")
        check(abs(CGFloat(img.width) - sel.width * scale) <= 2 && abs(CGFloat(img.height) - sel.height * scale) <= 2,
              "area capture matches the dragged selection: \(img.width)×\(img.height) px")
        let read = blocks.map { b in color(img, (b.0.midX - 10) * scale, (b.0.midY - 10) * scale) }
        check(read.enumerated().allSatisfy { isBlock($0.element, $0.offset) },
              "area capture contains the four color blocks in place (\(read.map { $0?.hexString ?? "nil" }.joined(separator: " ")))")
        check(!NSApp.windows.contains { $0 is CurtainWindow && $0.isVisible }, "the overlay closes after the capture")

        guard let (again, _) = await captureVia({ AppLogic.shared.repeatArea() }) else {
            check(false, "Repeat Area Capture produced an image"); return
        }
        dump(again, "repeat")
        check(again.width == img.width && again.height == img.height && isBlock(color(again, 60 * scale, 60 * scale), 0),
              "Repeat Area Capture grabs the same area again (\(again.width)×\(again.height) px)")
    }

    private static func delayed(_ screen: NSScreen, scale: CGFloat) async {
        let start = Date()
        guard let (img, _) = await captureVia(timeout: 8, { AppLogic.shared.run(.delayed) }) else {
            check(false, "delayed screenshot produced an image"); return
        }
        let took = Date().timeIntervalSince(start)
        check(took >= 2.9 && took < 6 && CGFloat(img.width) == screen.frame.width * scale,
              String(format: "delayed screenshot waits 3 s, then captures the display (%.1f s)", took))
    }

    private static func window(_ pattern: NSWindow, scale: CGFloat) async {
        let original = Settings.windowShadow
        defer { Settings.d.set(original, forKey: Keys.windowShadow) }
        do {
            let content = try await Capturer.content()
            let id = CGWindowID(pattern.windowNumber)
            Settings.d.set(false, forKey: Keys.windowShadow)
            let plain = try await Capturer.captureWindow(id: id, content: content)
            dump(plain, "window")
            check(abs(CGFloat(plain.width) - pattern.frame.width * scale) <= 2 && abs(CGFloat(plain.height) - pattern.frame.height * scale) <= 2,
                  "window capture without shadow is exactly the window: \(plain.width)×\(plain.height) px")
            let blue = color(plain, blocks[2].0.midX * scale, blocks[2].0.midY * scale)
            check(isBlock(blue, 2), "window capture shows the window's content (blue block reads \(blue?.hexString ?? "nil"))")
            Settings.d.set(true, forKey: Keys.windowShadow)
            let shadowed = try await Capturer.captureWindow(id: id, content: content)
            dump(shadowed, "window-shadow")
            // The shadow adds a soft transparent margin, larger below the window than above it.
            check(shadowed.width > plain.width + 10 && shadowed.height > plain.height + 10,
                  "window capture with shadow includes the shadow: \(shadowed.width)×\(shadowed.height) px vs \(plain.width)×\(plain.height)")
            let edge = color(shadowed, 2, CGFloat(shadowed.height) / 2)
            let mid = color(shadowed, CGFloat(shadowed.width) / 2, CGFloat(shadowed.height) / 2)
            check((edge?.alphaComponent ?? 1) < 0.5 && (mid?.alphaComponent ?? 0) > 0.95,
                  "the shadow is transparent at the edges and the window is solid in the middle")
        } catch {
            check(false, "window capture works (\(error.localizedDescription))")
        }
    }

    /// The Active/Any Window paths list other apps' windows and can capture them.
    private static func otherAppsWindows() async {
        let list = Capturer.windowList()
        guard let first = list.first else { skip("no other app windows on screen to capture"); return }
        check(list.allSatisfy { $0.frame.width > 40 && $0.frame.height > 40 && $0.pid != ProcessInfo.processInfo.processIdentifier },
              "window list has \(list.count) other-app window(s), none of ours")
        do {
            let img = try await Capturer.captureWindow(id: first.id, content: try await Capturer.content())
            check(img.width > 40 && img.height > 40, "another app's window can be captured (\(img.width)×\(img.height) px)")
        } catch {
            check(false, "another app's window can be captured (\(error.localizedDescription))")
        }
    }

    private static func ocrAndQR(_ screen: NSScreen, scale: CGFloat, patternLocal: CGRect) async {
        do {
            let content = try await Capturer.content()
            let textArea = textRect.offsetBy(dx: patternLocal.minX, dy: patternLocal.minY)
            let textImg = try await Capturer.captureScreen(screen, content: content, sourceRect: textArea)
            dump(textImg, "text")
            let text = await Task.detached { OCR.recognize(textImg, removeBreaks: false) }.value
            check(text?.0.contains("4242") == true && text?.1 == false, "OCR reads the text in a real capture (“\(text?.0 ?? "nothing")”)")
            let qrArea = qrRect.insetBy(dx: -8, dy: -8).offsetBy(dx: patternLocal.minX, dy: patternLocal.minY)
            let qrImg = try await Capturer.captureScreen(screen, content: content, sourceRect: qrArea)
            let qr = await Task.detached { OCR.recognize(qrImg, removeBreaks: false) }.value
            check(qr?.0 == qrPayload && qr?.1 == true, "QR code is decoded from a real capture (“\(qr?.0 ?? "nothing")”)")
        } catch {
            check(false, "OCR/QR captures work (\(error.localizedDescription))")
        }
    }

    /// Manual scrolling capture while the test window scrolls itself; checks the stitched image band by band.
    private static func scrolling(_ screen: NSScreen, scale: CGFloat) async {
        let (win, scroll) = makeScrollWindow(on: screen)
        defer { win.orderOut(nil) }
        await sleep(0.6)
        let rect = displayLocal(win.frame, on: screen)
        var stitched: CGImage?
        ScrollCapture.onFinishForTest = { stitched = $0 }
        defer { ScrollCapture.onFinishForTest = nil }
        ScrollCapture.start(screen: screen, rect: rect, auto: false)
        await sleep(1.0)
        let maxOffset = bandHeight * CGFloat(bandCount) - win.frame.height
        var y: CGFloat = 0
        while y < maxOffset {
            y = min(maxOffset, y + 110)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            await sleep(0.45)
        }
        await sleep(0.6)
        ScrollCapture.current?.stop()
        for _ in 0..<40 where stitched == nil { await sleep(0.1) }
        guard let img = stitched else { check(false, "scrolling capture finished with a stitched image"); return }
        dump(img, "scroll")
        let expectedHeight = bandHeight * CGFloat(bandCount) * scale
        check(abs(CGFloat(img.height) - expectedHeight) <= 6 * scale,
              "scrolling capture stitches the whole document: \(img.height) px tall (expected \(Int(expectedHeight)))")
        let bands = (0..<bandCount).map(bandColor)
        var matches = 0
        for i in 0..<bandCount where nearest(color(img, 12 * scale, (CGFloat(i) * bandHeight + 15) * scale), bands) == i { matches += 1 }
        check(matches == bandCount, "every band lands in the right place in the stitched image (\(matches)/\(bandCount))")
    }

    private static func multipleDisplays() async {
        guard NSScreen.screens.count > 1 else { skip("multiple displays: only one display connected"); return }
        do {
            let content = try await Capturer.content()
            for s in NSScreen.screens {
                let img = try await Capturer.captureScreen(s, content: content)
                check(CGFloat(img.width) == s.frame.width * s.backingScaleFactor, "display \(s.localizedName) captures at its own size (\(img.width)×\(img.height))")
            }
        } catch {
            check(false, "every display can be captured (\(error.localizedDescription))")
        }
    }
}

/// Test pattern: color blocks, large text and a QR code.
private final class PatternView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        for (r, hex) in LiveCaptureTest.blocks {
            NSColor(hex: hex).setFill()
            r.fill()
        }
        ("SCREENSHOT 4242" as NSString).draw(in: LiveCaptureTest.textRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: NSColor.black,
        ])
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(LiveCaptureTest.qrPayload.utf8)
        qr.correctionLevel = "M"
        if let out = qr.outputImage {
            let rep = NSCIImageRep(ciImage: out)
            let img = NSImage(size: rep.size)
            img.addRepresentation(rep)
            NSGraphicsContext.current?.imageInterpolation = .none
            img.draw(in: LiveCaptureTest.qrRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

/// Tall document of colored bands, each labelled with its number (the label gives the stitcher texture).
private final class BandsView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<LiveCaptureTest.bandCount {
            let r = CGRect(x: 0, y: CGFloat(i) * LiveCaptureTest.bandHeight, width: bounds.width, height: LiveCaptureTest.bandHeight)
            LiveCaptureTest.bandColor(i).setFill()
            r.fill()
            ("Band \(i)" as NSString).draw(at: CGPoint(x: 120 + CGFloat(i % 4) * 30, y: r.minY + 30), withAttributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.black.withAlphaComponent(0.75),
            ])
        }
    }
}
#endif
