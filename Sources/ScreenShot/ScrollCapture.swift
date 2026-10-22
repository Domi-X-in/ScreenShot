import AppKit
import ApplicationServices

/// Scrolling capture (Shottr's ScrollCapturer): repeatedly captures an area while it scrolls and stitches the new rows.
@MainActor final class ScrollCapture {
    static var current: ScrollCapture?
    /// Live capture self-test only: receives the stitched result instead of opening the editor.
    static var onFinishForTest: ((CGImage) -> Void)?

    private let screen: NSScreen
    private let rect: CGRect // display-local points, top-left origin
    private var auto: Bool
    private var running = true
    private var border: NSWindow?
    private var panel: NSPanel?
    private let statusLabel = NSTextField(labelWithString: "Starting…")
    private var monitors: [Any] = []
    private let maxHeight = 30000

    static func start(screen: NSScreen, rect: CGRect, auto: Bool) {
        guard current == nil else { return }
        let s = ScrollCapture(screen: screen, rect: rect, auto: auto)
        current = s
        s.begin()
    }

    private init(screen: NSScreen, rect: CGRect, auto: Bool) {
        self.screen = screen
        self.rect = rect
        self.auto = auto
    }

    private var globalRect: CGRect {
        let sf = screen.frame
        return CGRect(x: sf.minX + rect.minX, y: sf.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func begin() {
        if auto {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(opts) {
                Toast.show("Automatic scrolling requires Accessibility permission. Scroll manually now, then press Done.", duration: 4)
                auto = false
            } else {
                Toast.show("Don't touch the mouse until it stops. Press Esc to stop.", duration: 2.5)
            }
        } else {
            Toast.show("Scroll the content slowly, then press Done or Esc.", duration: 2.5)
        }
        showChrome()
        let handler: (NSEvent) -> Void = { [weak self] e in
            if e.keyCode == 53 { self?.stop() }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { handler($0); return $0 }) { monitors.append(m) }
        Task { await loop() }
    }

    func stop() { running = false }

    private func showChrome() {
        let g = globalRect
        let b = NSWindow(contentRect: g.insetBy(dx: -3, dy: -3), styleMask: .borderless, backing: .buffered, defer: false)
        b.isOpaque = false
        b.backgroundColor = .clear
        b.ignoresMouseEvents = true
        b.level = .statusBar
        b.isReleasedWhenClosed = false
        b.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.borderWidth = 2
        v.layer?.borderColor = NSColor.systemRed.cgColor
        v.layer?.cornerRadius = 3
        b.contentView = v
        b.orderFrontRegardless()
        border = b

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.bezelColor = .controlAccentColor
        let stack = NSStackView(views: [statusLabel, done])
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 8)
        stack.spacing = 12
        let size = CGSize(width: 260, height: 40)
        let vf = screen.visibleFrame
        var y = g.minY - size.height - 10
        if y < vf.minY { y = min(g.maxY + 10, vf.maxY - size.height) }
        let p = NSPanel(contentRect: CGRect(x: g.midX - size.width / 2, y: y, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor), stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor), stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        p.contentView = fx
        p.orderFrontRegardless()
        panel = p
    }

    @objc private func doneClicked() { stop() }

    private func capture() async throws -> CGImage {
        // Refreshing the shareable content each time keeps our own overlay windows excluded.
        let content = try await Capturer.content()
        return try await Capturer.captureScreen(screen, content: content, sourceRect: rect)
    }

    private func scrollOnce() {
        let o = screen.cgOrigin
        let center = CGPoint(x: o.x + rect.midX, y: o.y + rect.midY)
        let fraction = min(0.7, 0.3 + Settings.scrollSpeed * 0.5)
        let amount = Int32(max(20, rect.height * fraction) / 3)
        let dir: Int32 = Settings.reverseAutoscroll ? 1 : -1
        for _ in 0..<3 {
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dir * amount, wheel2: 0, wheel3: 0) else { continue }
            e.location = center
            e.post(tap: .cghidEventTap)
        }
    }

    private func loop() async {
        var strips: [CGImage] = []
        do {
            try await Task.sleep(for: .milliseconds(200))
            var prev = try await capture()
            strips = [prev]
            var total = prev.height
            var still = 0
            if auto {
                let o = screen.cgOrigin
                CGWarpMouseCursorPosition(CGPoint(x: o.x + rect.midX, y: o.y + rect.midY))
            }
            while running && total < maxHeight {
                if auto { scrollOnce() }
                try await Task.sleep(for: .milliseconds(auto ? 380 : 220))
                let cur = try await capture()
                let a = prev
                let off = await Task.detached(priority: .userInitiated) { Stitcher.offset(a, cur) }.value
                guard let off, off > 0 else {
                    if auto { still += 1; if still >= 3 { break } }
                    continue
                }
                still = 0
                if let strip = cur.cropping(to: CGRect(x: 0, y: cur.height - off, width: cur.width, height: off)) {
                    strips.append(strip)
                    total += off
                }
                prev = cur
                statusLabel.stringValue = "\(total) px captured"
            }
        } catch {
            Toast.show("Scrolling capture failed: \(error.localizedDescription)")
        }
        finish(strips)
    }

    private func finish(_ strips: [CGImage]) {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        border?.orderOut(nil)
        panel?.orderOut(nil)
        ScrollCapture.current = nil
        guard let img = Stitcher.compose(strips) else { return }
        if let hook = ScrollCapture.onFinishForTest { hook(img); return }
        AppLogic.shared.handleCapture(img, scale: screen.backingScaleFactor)
    }
}

enum Stitcher {
    /// 8-bit grayscale buffer, rows top to bottom.
    static func gray(_ img: CGImage) -> [UInt8] {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h)
        buf.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }

    /// How many rows the content moved up between `a` and `b`; nil when the frames don't line up.
    static func offset(_ a: CGImage, _ b: CGImage) -> Int? {
        guard a.width == b.width, a.height == b.height else { return nil }
        let w = a.width, h = a.height
        let A = gray(a), B = gray(b)
        let minOverlap = max(20, h / 5)
        guard h > minOverlap else { return nil }
        let colStep = max(1, w / 160)
        var bestD = 0
        var bestCost = Double.infinity
        A.withUnsafeBufferPointer { pa in
            B.withUnsafeBufferPointer { pb in
                for d in 0...(h - minOverlap) {
                    let rowStep = max(1, (h - d) / 120)
                    var sum = 0, n = 0
                    var y = 0
                    while y < h - d {
                        let ra = (y + d) * w, rb = y * w
                        var x = 0
                        while x < w {
                            sum += abs(Int(pa[ra + x]) - Int(pb[rb + x]))
                            n += 1
                            x += colStep
                        }
                        y += rowStep
                    }
                    let cost = Double(sum) / Double(max(n, 1))
                    if cost < bestCost {
                        bestCost = cost
                        bestD = d
                    }
                }
            }
        }
        return bestCost < 6 ? bestD : nil
    }

    static func compose(_ strips: [CGImage]) -> CGImage? {
        guard let first = strips.first else { return nil }
        if strips.count == 1 { return first }
        let w = first.width
        let total = strips.reduce(0) { $0 + $1.height }
        guard let ctx = CGContext(data: nil, width: w, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        var top = 0
        for s in strips {
            ctx.draw(s, in: CGRect(x: 0, y: total - top - s.height, width: s.width, height: s.height))
            top += s.height
        }
        return ctx.makeImage()
    }
}
