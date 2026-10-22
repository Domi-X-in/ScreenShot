import AppKit

enum CurtainMode { case area, window, ocr, scrolling }

enum CurtainResult {
    /// `pointRect` is display-local, in points, top-left origin.
    case area(screen: NSScreen, image: CGImage, pointRect: CGRect)
    case window(CGWindowID)
    case cancelled
}

/// Frozen-screen overlay used to pick an area or a window (Shottr's CurtainWindowController + RegionSelector + CrosshairView).
@MainActor final class CurtainController {
    static var current: CurtainController?

    private var windows: [NSWindow] = []
    private let completion: (CurtainResult) -> Void

    init(shots: [(NSScreen, CGImage)], windowList: [WindowInfo], mode: CurtainMode, completion: @escaping (CurtainResult) -> Void) {
        self.completion = completion
        for (screen, image) in shots {
            let w = CurtainWindow(screen: screen)
            let v = CurtainView(frame: CGRect(origin: .zero, size: screen.frame.size), screen: screen, image: image,
                                windowList: windowList, mode: mode)
            v.controller = self
            w.contentView = v
            windows.append(w)
        }
    }

    func show() {
        NSApp.activate()
        let mouseScreen = NSScreen.containingMouse()
        for w in windows {
            w.orderFrontRegardless()
            if w.screen == mouseScreen || w.frame.contains(NSEvent.mouseLocation) {
                w.makeKey()
                w.makeFirstResponder(w.contentView)
            }
        }
        NSCursor.crosshair.push()
    }

    func finish(_ result: CurtainResult) {
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        CurtainController.current = nil
        completion(result)
    }

    func activate(_ window: NSWindow?) {
        guard let window, !window.isKeyWindow else { return }
        window.makeKey()
        window.makeFirstResponder(window.contentView)
    }
}

final class CurtainWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CurtainView: NSView {
    weak var controller: CurtainController?
    private let screen: NSScreen
    private let image: CGImage
    private let bitmap: NSBitmapImageRep
    private let scale: CGFloat
    private let mode: CurtainMode
    private var windowMode: Bool
    private var windowRects: [(CGWindowID, CGRect)] = [] // view-local, flipped
    private var mouse: CGPoint?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var hover: (CGWindowID, CGRect)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: CGRect, screen: NSScreen, image: CGImage, windowList: [WindowInfo], mode: CurtainMode) {
        self.screen = screen
        self.image = image
        self.bitmap = NSBitmapImageRep(cgImage: image)
        self.scale = CGFloat(image.width) / frame.width
        self.mode = mode
        self.windowMode = mode == .window
        super.init(frame: frame)
        let o = screen.cgOrigin
        windowRects = windowList.map { ($0.id, $0.frame.offsetBy(dx: -o.x, dy: -o.y)) }
            .filter { $0.1.intersects(CGRect(origin: .zero, size: frame.size)) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
        if let win = window { mouse = convert(win.mouseLocationOutsideOfEventStream, from: nil) }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.drawFlipped(image, in: bounds)

        let hole: CGRect? = selection ?? (dragStart == nil ? hover?.1 : nil)
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole { dim.addRect(hole) }
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(windowMode && hole == nil ? 0.18 : 0.42).cgColor)
        ctx.fillPath(using: .evenOdd)

        if let sel = selection {
            drawSelection(sel, ctx: ctx)
            drawSizeLabel(for: sel)
        } else if let h = hover?.1, dragStart == nil, windowMode || mode != .scrolling {
            ctx.setFillColor(Palette.accent.withAlphaComponent(windowMode ? 0.16 : 0.05).cgColor)
            ctx.fill(h)
            ctx.setStrokeColor(Palette.accent.withAlphaComponent(windowMode ? 0.95 : 0.45).cgColor)
            ctx.setLineWidth(windowMode ? 3 : 1.5)
            ctx.stroke(h.insetBy(dx: 1.5, dy: 1.5))
        }

        if let m = mouse, !windowMode {
            // Crosshair: a dark line under a light one, readable on any content.
            let x = m.x.rounded() + 0.5, y = m.y.rounded() + 0.5
            for (color, offset) in [(NSColor.black.withAlphaComponent(0.35), CGFloat(1)), (NSColor.white.withAlphaComponent(0.75), 0)] {
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: 0, y: y + offset)); ctx.addLine(to: CGPoint(x: bounds.width, y: y + offset))
                ctx.move(to: CGPoint(x: x + offset, y: 0)); ctx.addLine(to: CGPoint(x: x + offset, y: bounds.height))
                ctx.strokePath()
            }
            drawLoupe(at: m, ctx: ctx)
        }

        drawHint()
    }

    /// Accent outline with white L-shaped corner brackets.
    private func drawSelection(_ sel: CGRect, ctx: CGContext) {
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(3)
        ctx.stroke(sel.insetBy(dx: -1.5, dy: -1.5))
        ctx.setStrokeColor(Palette.accent.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(sel.insetBy(dx: -0.75, dy: -0.75))
        let arm = min(16, sel.width / 3, sel.height / 3)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        for (cx, cy, sx, sy) in [(sel.minX, sel.minY, 1.0, 1.0), (sel.maxX, sel.minY, -1.0, 1.0),
                                 (sel.minX, sel.maxY, 1.0, -1.0), (sel.maxX, sel.maxY, -1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            ctx.move(to: CGPoint(x: cx + sx * arm, y: cy - sy * 1.5))
            ctx.addLine(to: CGPoint(x: cx - sx * 1.5, y: cy - sy * 1.5))
            ctx.addLine(to: CGPoint(x: cx - sx * 1.5, y: cy + sy * arm))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    private func drawSizeLabel(for r: CGRect) {
        let text = "\(Int((r.width * scale).rounded())) × \(Int((r.height * scale).rounded()))"
        let below = r.maxY + 10 + 26 <= bounds.height
        drawPill(text, at: CGPoint(x: r.midX, y: below ? r.maxY + 10 : r.minY - 36), centered: true, bold: true)
    }

    /// Frosted-dark capsule label, optionally with a color dot in front.
    private func drawPill(_ text: String, at p: CGPoint, centered: Bool = false, bold: Bool = false, dot: NSColor? = nil) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: bold ? .semibold : .medium),
                                                    .foregroundColor: NSColor.white]
        let s = (text as NSString).size(withAttributes: attrs)
        let dotSpace: CGFloat = dot == nil ? 0 : 16
        let w = s.width + 24 + dotSpace, h = s.height + 10
        var r = CGRect(x: p.x, y: p.y, width: w, height: h)
        if centered { r.origin.x = p.x - w / 2 }
        r.origin.x = min(max(6, r.origin.x), bounds.width - w - 6)
        let path = NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor(white: 0.08, alpha: 0.82).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
        if let dot {
            let d = NSBezierPath(ovalIn: CGRect(x: r.minX + 11, y: r.midY - 5, width: 10, height: 10))
            dot.setFill()
            d.fill()
            NSColor.white.withAlphaComponent(0.7).setStroke()
            d.stroke()
        }
        (text as NSString).draw(at: CGPoint(x: r.minX + 12 + dotSpace, y: r.minY + 5), withAttributes: attrs)
    }

    private func drawHint() {
        let text: String
        switch mode {
        case .area: text = windowMode ? "Click a window   ·   Space  area mode   ·   Esc  cancel" : "Drag to select   ·   Click a window   ·   Space  window mode   ·   Esc  cancel"
        case .window: text = "Click a window   ·   Space  area mode   ·   Esc  cancel"
        case .ocr: text = "Select the area with text or a QR code"
        case .scrolling: text = "Select the area to scroll"
        }
        guard dragStart == nil, mouse != nil, debugForceHint || screen.frame.contains(NSEvent.mouseLocation) else { return }
        drawPill(text, at: CGPoint(x: bounds.midX, y: 36), centered: true)
    }

    /// Circular pixel loupe next to the cursor: pixel grid, accent center pixel, color and coordinates below.
    private func drawLoupe(at m: CGPoint, ctx: CGContext) {
        let cells = 15, cell: CGFloat = 9
        let side = CGFloat(cells) * cell
        var origin = CGPoint(x: m.x + 28, y: m.y + 28)
        if origin.x + side > bounds.width - 6 { origin.x = m.x - 28 - side }
        if origin.y + side + 40 > bounds.height - 6 { origin.y = m.y - 28 - side - 40 }
        let box = CGRect(origin: origin, size: CGSize(width: side, height: side))

        let px = Int(m.x * scale), py = Int(m.y * scale)
        let half = cells / 2
        let src = CGRect(x: px - half, y: py - half, width: cells, height: cells)

        // Shadowed disc, then the magnified pixels clipped to it.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillEllipse(in: box)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: box)
        ctx.clip()
        let clipped = src.intersection(CGRect(origin: .zero, size: image.size))
        if !clipped.isNull, let crop = image.cropping(to: clipped) {
            let dst = CGRect(x: box.minX + (clipped.minX - src.minX) * cell, y: box.minY + (clipped.minY - src.minY) * cell,
                             width: clipped.width * cell, height: clipped.height * cell)
            ctx.interpolationQuality = .none
            ctx.drawFlipped(crop, in: dst)
        }
        // Faint pixel grid.
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<cells {
            let o = CGFloat(i) * cell
            ctx.move(to: CGPoint(x: box.minX + o, y: box.minY)); ctx.addLine(to: CGPoint(x: box.minX + o, y: box.maxY))
            ctx.move(to: CGPoint(x: box.minX, y: box.minY + o)); ctx.addLine(to: CGPoint(x: box.maxX, y: box.minY + o))
        }
        ctx.strokePath()
        ctx.restoreGState()

        let center = CGRect(x: box.minX + CGFloat(half) * cell, y: box.minY + CGFloat(half) * cell, width: cell, height: cell)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2.5); ctx.stroke(center.insetBy(dx: -1, dy: -1))
        ctx.setStrokeColor(Palette.accent.cgColor); ctx.setLineWidth(1.5); ctx.stroke(center.insetBy(dx: -1, dy: -1))
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(3)
        ctx.strokeEllipse(in: box.insetBy(dx: 1.5, dy: 1.5))

        var color: NSColor?
        var hex = ""
        if px >= 0, py >= 0, px < bitmap.pixelsWide, py < bitmap.pixelsHigh, let c = bitmap.colorAt(x: px, y: py) {
            color = c
            hex = c.hexString + "   "
        }
        drawPill("\(hex)\(px), \(py)", at: CGPoint(x: box.midX, y: box.maxY + 8), centered: true, dot: color)
    }

    // MARK: Debug (UI snapshots)

    var debugForceHint = false

    func debugPreview(mouse m: CGPoint?, selection sel: CGRect?) {
        mouse = m
        selection = sel
        debugForceHint = true
        needsDisplay = true
    }

    // MARK: Events

    private func snap(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x * scale).rounded() / scale, y: (p.y * scale).rounded() / scale)
    }

    private func updateHover(_ p: CGPoint) {
        hover = windowRects.first { $0.1.contains(p) }
    }

    override func mouseEntered(with event: NSEvent) {
        controller?.activate(window)
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.activate(window)
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        updateHover(p)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = snap(convert(event.locationInWindow, from: nil))
        if windowMode { return }
        dragStart = p
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        let p = snap(convert(event.locationInWindow, from: nil))
        mouse = p
        guard let s = dragStart else { return }
        var end = p
        if event.modifierFlags.contains(.shift) {
            let side = max(abs(p.x - s.x), abs(p.y - s.y))
            end = CGPoint(x: s.x + (p.x >= s.x ? side : -side), y: s.y + (p.y >= s.y ? side : -side))
        }
        selection = CGRect(p1: s, p2: end).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if let sel = selection, sel.width * scale >= 4, sel.height * scale >= 4 {
            let px = CGRect(x: sel.minX * scale, y: sel.minY * scale, width: sel.width * scale, height: sel.height * scale).integral
            guard let crop = image.cropping(to: px) else { controller?.finish(.cancelled); return }
            controller?.finish(.area(screen: screen, image: crop, pointRect: sel))
            return
        }
        selection = nil
        if mode != .scrolling, let h = hover {
            controller?.finish(.window(h.0))
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: controller?.finish(.cancelled) // Esc
        case 49: // Space
            if mode != .scrolling { windowMode.toggle(); selection = nil; dragStart = nil; needsDisplay = true }
        default: super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) { controller?.finish(.cancelled) }
}
