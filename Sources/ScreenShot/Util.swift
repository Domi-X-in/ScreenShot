import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Height of the primary display; used to flip between CG (top-left) and AppKit (bottom-left) global coordinates.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func containingMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main ?? screens[0]
    }

    /// Top-left corner of this screen in CG global coordinates.
    var cgOrigin: CGPoint {
        CGPoint(x: frame.minX, y: NSScreen.primaryHeight - frame.maxY)
    }
}

enum Geo {
    /// Converts between CG global (top-left origin) and AppKit global (bottom-left origin) rects. The formula is symmetric.
    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: NSScreen.primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

extension CGRect {
    init(p1: CGPoint, p2: CGPoint) {
        self.init(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGVector) -> CGPoint { CGPoint(x: a.x + b.dx, y: a.y + b.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }

    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }

    func distance(toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2))
        return distance(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// "#RRGGBBAA", used to persist annotation colors.
    var rgbaHex: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000FF" }
        return String(format: "#%02X%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()), Int((c.alphaComponent * 255).rounded()))
    }

    convenience init?(rgbaHex s: String) {
        let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard hex.count == 8 || hex.count == 6, var v = UInt32(hex, radix: 16) else { return nil }
        if hex.count == 6 { v = v << 8 | 0xFF }
        self.init(srgbRed: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
                  blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
    }

    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    }

    var contrasting: NSColor { luminance > 0.6 ? .black : .white }
}

extension CGContext {
    /// Draws an image right side up inside `r` when the context's CTM is flipped (top-left origin).
    func drawFlipped(_ image: CGImage, in r: CGRect) {
        saveGState()
        translateBy(x: 0, y: r.minY + r.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: r)
        restoreGState()
    }
}

extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }
}
