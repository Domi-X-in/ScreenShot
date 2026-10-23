import AppKit

/// Shottr's "Window Screenshot Background": puts a captured window on the desktop wallpaper or a solid color
/// instead of leaving it transparent.
enum WindowBackground {
    enum Fill {
        case image(CGImage)
        case color(NSColor)
    }

    /// The window centered on the fill, with a margin of 6% of its longer side (at least 24 px) all around.
    static func compose(_ window: CGImage, on fill: Fill) -> CGImage? {
        let w = CGFloat(window.width), h = CGFloat(window.height)
        let margin = max(24, (max(w, h) * 0.06).rounded())
        let size = CGSize(width: w + 2 * margin, height: h + 2 * margin)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        switch fill {
        case let .color(c):
            ctx.setFillColor((c.usingColorSpace(.sRGB) ?? c).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        case let .image(img):
            // Aspect-fill, centered.
            let k = max(size.width / CGFloat(img.width), size.height / CGFloat(img.height))
            let iw = CGFloat(img.width) * k, ih = CGFloat(img.height) * k
            ctx.draw(img, in: CGRect(x: (size.width - iw) / 2, y: (size.height - ih) / 2, width: iw, height: ih))
        }
        ctx.draw(window, in: CGRect(x: margin, y: margin, width: w, height: h))
        return ctx.makeImage()
    }

    /// The fill the preference asks for, or nil for a transparent background.
    @MainActor static func current(for screen: NSScreen) -> Fill? {
        switch Settings.windowBackground {
        case "wallpaper":
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen), let ns = NSImage(contentsOf: url),
                  let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return .color(Settings.windowBackgroundColor) }
            return .image(img)
        case "color":
            return .color(Settings.windowBackgroundColor)
        default:
            return nil
        }
    }
}
