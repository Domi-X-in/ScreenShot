import AppKit

/// Shottr's measuring: hold 1 for the distances across the area under the pointer, hold 2 for its bounding box.
/// The area is the run of pixels matching the one under the pointer, so it stops at the first visible edge.
enum Measure {
    enum Mode { case lines, box }

    /// Inclusive pixel bounds of the matching run through (x, y): left…right on that row, top…bottom on that column.
    struct Span: Equatable {
        var left, right, top, bottom: Int
        var width: Int { right - left + 1 }
        var height: Int { bottom - top + 1 }
    }

    static let tolerance = 12

    static func span(at x: Int, _ y: Int, in px: PixelReader) -> Span? {
        guard x >= 0, y >= 0, x < px.width, y < px.height else { return nil }
        var s = Span(left: x, right: x, top: y, bottom: y)
        while s.left > 0, px.same(s.left - 1, y, x, y, tolerance: tolerance) { s.left -= 1 }
        while s.right < px.width - 1, px.same(s.right + 1, y, x, y, tolerance: tolerance) { s.right += 1 }
        while s.top > 0, px.same(x, s.top - 1, x, y, tolerance: tolerance) { s.top -= 1 }
        while s.bottom < px.height - 1, px.same(x, s.bottom + 1, x, y, tolerance: tolerance) { s.bottom += 1 }
        return s
    }

    /// Draws the measurement in image coordinates (flipped context); `hairline` is one screen point.
    static func draw(_ s: Span, mode: Mode, at p: CGPoint, hairline: CGFloat, unit: CGFloat, unitName: String, ctx: CGContext) {
        let accent = NSColor.systemPink
        let l = CGFloat(s.left), r = CGFloat(s.right + 1), t = CGFloat(s.top), b = CGFloat(s.bottom + 1)
        let cx = CGFloat(Int(p.x)) + 0.5, cy = CGFloat(Int(p.y)) + 0.5
        func size(_ v: Int) -> String { "\(Int((CGFloat(v) / unit).rounded()))" }
        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.5 * hairline)
        switch mode {
        case .lines:
            ctx.move(to: CGPoint(x: l, y: cy)); ctx.addLine(to: CGPoint(x: r, y: cy))
            ctx.move(to: CGPoint(x: cx, y: t)); ctx.addLine(to: CGPoint(x: cx, y: b))
            // End ticks.
            let tick = 5 * hairline
            for x in [l, r] { ctx.move(to: CGPoint(x: x, y: cy - tick)); ctx.addLine(to: CGPoint(x: x, y: cy + tick)) }
            for y in [t, b] { ctx.move(to: CGPoint(x: cx - tick, y: y)); ctx.addLine(to: CGPoint(x: cx + tick, y: y)) }
            ctx.strokePath()
            ctx.restoreGState()
            Renderer.drawLabel("\(size(s.width)) \(unitName)", at: CGPoint(x: (l + r) / 2, y: cy - 14 * hairline), size: 11 * hairline,
                               ctx: ctx, centered: true)
            Renderer.drawLabel("\(size(s.height)) \(unitName)", at: CGPoint(x: cx + 30 * hairline, y: (t + b) / 2), size: 11 * hairline,
                               ctx: ctx, centered: true)
        case .box:
            let box = CGRect(x: l, y: t, width: r - l, height: b - t)
            ctx.setFillColor(accent.withAlphaComponent(0.12).cgColor)
            ctx.fill(box)
            ctx.stroke(box)
            ctx.restoreGState()
            Renderer.drawLabel("\(size(s.width)) × \(size(s.height)) \(unitName)", at: CGPoint(x: box.midX, y: box.maxY + 12 * hairline),
                               size: 11 * hairline, ctx: ctx, centered: true)
        }
    }
}

/// Shottr's Autoadjust: shrinks a selection to the content inside it by dropping edges that are one flat color.
enum Autoadjust {
    static func fit(_ rect: CGRect, in px: PixelReader, tolerance: Int = 10) -> CGRect {
        var minX = max(0, Int(rect.minX)), minY = max(0, Int(rect.minY))
        var maxX = min(px.width - 1, Int(rect.maxX) - 1), maxY = min(px.height - 1, Int(rect.maxY) - 1)
        guard maxX > minX, maxY > minY else { return rect }
        // The background is the color at the selection's top-left corner.
        let bx = minX, by = minY
        func rowIsBackground(_ y: Int) -> Bool { (minX...maxX).allSatisfy { px.same($0, y, bx, by, tolerance: tolerance) } }
        func columnIsBackground(_ x: Int) -> Bool { (minY...maxY).allSatisfy { px.same(x, $0, bx, by, tolerance: tolerance) } }
        while minY < maxY, rowIsBackground(minY) { minY += 1 }
        while maxY > minY, rowIsBackground(maxY) { maxY -= 1 }
        while minX < maxX, columnIsBackground(minX) { minX += 1 }
        while maxX > minX, columnIsBackground(maxX) { maxX -= 1 }
        // Nothing but background: keep the selection as it was.
        if minX == maxX && minY == maxY && rowIsBackground(minY) { return rect }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
