import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Cut Out")
struct CutOutTests {
    /// Three horizontal bands (red, green, blue) of 100 px each, 200 px wide.
    private let bands = makeImage(200, 300) { ctx in
        for (i, hex) in [0xFF0000, 0x00FF00, 0x0000FF].enumerated() {
            ctx.setFillColor(NSColor(hex: UInt32(hex)).cgColor)
            ctx.fill(CGRect(x: 0, y: i * 100, width: 200, height: 100))
        }
    }

    @Test("dragging up or down picks rows, sideways picks columns")
    func direction() {
        let size = CGSize(width: 200, height: 300)
        #expect(CutOut.strip(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 60, y: 200), in: size) == .init(rows: true, range: 100...200))
        #expect(CutOut.strip(from: CGPoint(x: 150, y: 10), to: CGPoint(x: 20, y: 30), in: size) == .init(rows: false, range: 20...150))
        #expect(CutOut.strip(from: CGPoint(x: 0, y: -50), to: CGPoint(x: 0, y: 900), in: size).range == 0...300, "clamped to the image")
    }

    @Test("removing the middle band joins the first and last")
    func rows() throws {
        let out = try #require(CutOut.apply(.init(rows: true, range: 100...200), to: bands))
        #expect(out.width == 200 && out.height == 200)
        #expect(pixel(out, 100, 50).hexString == "#FF0000")
        #expect(pixel(out, 100, 99).hexString == "#FF0000")
        #expect(pixel(out, 100, 100).hexString == "#0000FF", "blue moves up to the seam")
        #expect(pixel(out, 100, 199).hexString == "#0000FF")
    }

    @Test("removing columns narrows the image")
    func columns() throws {
        let out = try #require(CutOut.apply(.init(rows: false, range: 0...150), to: bands))
        #expect(out.width == 50 && out.height == 300)
        #expect(pixel(out, 25, 250).hexString == "#0000FF")
    }

    @Test("cutting everything is refused")
    func everything() {
        #expect(CutOut.apply(.init(rows: true, range: 0...300), to: bands) == nil)
    }

    @Test("annotations below the strip move up with the image; ones above stay")
    func annotations() {
        let s = ToolStyle()
        let above = Annotation(kind: .rect, p1: CGPoint(x: 10, y: 10), p2: CGPoint(x: 50, y: 50), style: s)
        let below = Annotation(kind: .rect, p1: CGPoint(x: 10, y: 250), p2: CGPoint(x: 50, y: 290), style: s)
        let moved = CutOut.shift([above, below], by: .init(rows: true, range: 100...200))
        #expect(moved[0].p1 == above.p1)
        #expect(moved[1].p1 == CGPoint(x: 10, y: 150))
    }
}
