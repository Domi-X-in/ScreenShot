import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Backdrop panel")
struct BackdropTests {
    private func doc(_ w: Int = 400, _ h: Int = 200, _ edit: (inout Backdrop) -> Void) -> EditorDocument {
        let d = EditorDocument(image: solid(w, h, 0x000000), scale: 1)
        var b = Backdrop()
        b.isOn = true
        b.shadow = 0
        edit(&b)
        d.backdrop = b
        return d
    }

    @Test("off means no padding at all")
    func off() {
        let d = EditorDocument(image: solid(400, 200, 0), scale: 1)
        #expect(Renderer.canvasSize(d) == CGSize(width: 400, height: 200))
        #expect(Renderer.imageOrigin(d) == .zero)
    }

    @Test("aspect presets give the canvas their ratio", arguments: Backdrop.Aspect.allCases.filter { $0 != .auto })
    func aspect(_ a: Backdrop.Aspect) throws {
        for (w, h) in [(400, 200), (200, 400), (300, 300)] {
            let d = doc(w, h) { $0.aspect = a }
            let c = Renderer.canvasSize(d)
            let ratio = try #require(a.ratio)
            #expect(abs(c.width / c.height - ratio) < 0.01, "\(a) on \(w)×\(h) gave \(c)")
            #expect(c.width >= CGFloat(w) && c.height >= CGFloat(h))
        }
    }

    @Test("padding is a share of the longer side; inset adds a frame")
    func paddingAndInset() {
        let d = doc { $0.padding = 0.1; $0.inset = 0.05 }
        // 400 long side → 40 padding + 20 inset on every side.
        #expect(Renderer.canvasSize(d) == CGSize(width: 520, height: 320))
        #expect(Renderer.imageOrigin(d) == CGPoint(x: 60, y: 60))
    }

    @Test("offset moves the screenshot to the edges; recentering is offset zero")
    func offset() {
        let d = doc { $0.aspect = .square; $0.padding = 0.1 }
        let centered = Renderer.imageOrigin(d)
        d.backdrop.offset = CGPoint(x: -1, y: -1)
        #expect(Renderer.imageOrigin(d) == CGPoint(x: 0, y: 0))
        d.backdrop.offset = CGPoint(x: 1, y: 1)
        let c = Renderer.canvasSize(d)
        #expect(Renderer.imageOrigin(d) == CGPoint(x: c.width - 400, y: c.height - 200))
        d.backdrop.offset = .zero
        #expect(Renderer.imageOrigin(d) == centered)
    }

    @Test("solid fill paints the padding; outer radius makes the corners transparent")
    func solidAndRadius() {
        let d = doc { $0.fill = .solid; $0.colors = ["#2255AA"]; $0.outerRadius = 0.1 }
        let out = d.render()!
        let c = Renderer.canvasSize(d)
        #expect(pixel(out, Int(c.width) / 2, 6).hexString == "#2255AA")
        #expect(PixelReader(out).color(0, 0)!.alphaComponent < 0.01, "corner should be transparent")
        #expect(pixel(out, Int(c.width) / 2, Int(c.height) / 2).hexString == "#000000", "the screenshot stays in the middle")
    }

    @Test("every fill renders something other than the screenshot around it", arguments: Backdrop.Fill.allCases)
    func fills(_ f: Backdrop.Fill) {
        let img = makeImage(400, 200) { ctx in
            ctx.setFillColor(NSColor(hex: 0xFF8800).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let d = EditorDocument(image: img, scale: 1)
        var b = Backdrop()
        b.isOn = true
        b.fill = f
        b.colors = ["#4FACFE", "#00F2FE"]
        d.backdrop = b
        let out = d.render()!
        let edge = PixelReader(out).color(4, 4)!
        #expect(edge.alphaComponent > 0.99, "\(f) left the corner empty")
        if f == .blurredImage {
            #expect(edge.redComponent > 0.6, "blurred backdrop should take the screenshot's orange, got \(edge.hexString)")
        } else {
            #expect(edge.blueComponent > 0.6, "\(f) should use the backdrop colors, got \(edge.hexString)")
        }
    }

    @Test("files saved with the old preset number still open with that backdrop")
    func legacy() throws {
        let old = #"{"version":1,"scale":2,"backdrop":2,"objects":[]}"#
        let s = try JSONDecoder().decode(EditState.self, from: Data(old.utf8))
        #expect(s.backdrop.isOn && s.backdrop.colors == ["#FA709A", "#FEE140"])
        let none = try JSONDecoder().decode(EditState.self, from: Data(#"{"version":1,"scale":2,"backdrop":0,"objects":[]}"#.utf8))
        #expect(!none.backdrop.isOn)
    }
}
