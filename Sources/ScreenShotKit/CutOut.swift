import AppKit

/// Shottr's Cut Out (scissors): removes a full-width or full-height strip and joins the two sides.
enum CutOut {
    /// A strip across the whole image. `rows` removes a horizontal band (y range); otherwise a vertical band (x range).
    struct Strip: Equatable {
        var rows: Bool
        var range: ClosedRange<CGFloat>
        var length: CGFloat { range.upperBound - range.lowerBound }

        func rect(in size: CGSize) -> CGRect {
            rows ? CGRect(x: 0, y: range.lowerBound, width: size.width, height: length)
                 : CGRect(x: range.lowerBound, y: 0, width: length, height: size.height)
        }
    }

    /// The strip a drag from `a` to `b` describes: dragging mostly up/down cuts rows, mostly sideways cuts columns.
    static func strip(from a: CGPoint, to b: CGPoint, in size: CGSize) -> Strip {
        let rows = abs(b.y - a.y) >= abs(b.x - a.x)
        let limit = rows ? size.height : size.width
        let lo = max(0, min(rows ? a.y : a.x, rows ? b.y : b.x).rounded())
        let hi = min(limit, max(rows ? a.y : a.x, rows ? b.y : b.x).rounded())
        return Strip(rows: rows, range: lo...max(lo, hi))
    }

    /// The image without the strip (top-left-origin coordinates), or nil if nothing would be left.
    static func apply(_ strip: Strip, to image: CGImage) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let newW = strip.rows ? w : w - strip.length, newH = strip.rows ? h - strip.length : h
        guard strip.length >= 1, newW >= 1, newH >= 1 else { return nil }
        var space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        if space.model != .rgb { space = CGColorSpace(name: CGColorSpace.sRGB)! }
        guard let ctx = CGContext(data: nil, width: Int(newW), height: Int(newH), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: newH)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        let lo = strip.range.lowerBound, hi = strip.range.upperBound
        // The part before the strip stays put; the part after it moves back by the strip's length.
        let before = strip.rows ? CGRect(x: 0, y: 0, width: w, height: lo) : CGRect(x: 0, y: 0, width: lo, height: h)
        let after = strip.rows ? CGRect(x: 0, y: hi, width: w, height: h - hi) : CGRect(x: hi, y: 0, width: w - hi, height: h)
        for (part, shift) in [(before, CGFloat(0)), (after, strip.length)] where part.width >= 1 && part.height >= 1 {
            guard let piece = image.cropping(to: part) else { continue }
            let dest = strip.rows ? part.offsetBy(dx: 0, dy: -shift) : part.offsetBy(dx: -shift, dy: 0)
            ctx.drawFlipped(piece, in: dest)
        }
        return ctx.makeImage()
    }

    /// Moves annotations past the strip back with the image; ones centered inside it land on the seam.
    static func shift(_ objects: [Annotation], by strip: Strip) -> [Annotation] {
        objects.map { o in
            var m = o
            let c = strip.rows ? o.bounds.midY : o.bounds.midX
            let d: CGFloat
            if c >= strip.range.upperBound { d = strip.length } else if c > strip.range.lowerBound { d = c - strip.range.lowerBound } else { return o }
            m.offset(by: strip.rows ? CGVector(dx: 0, dy: -d) : CGVector(dx: -d, dy: 0))
            if m.kind == .blur { m.textRects = nil }
            return m
        }
    }
}
