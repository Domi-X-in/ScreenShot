import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Color formats")
struct ColorFormatTests {
    /// Shottr's own sample color and labels.
    @Test("match Shottr's examples for #FFC200", arguments: [
        (ColorFormat.hex, "#FFC200"), (.hexNoHash, "FFC200"), (.cssRGBA, "rgba(255, 194, 0, 1)"), (.rgbUnit, "(1.00, 0.76, 0.00)"),
        (.android, "0xFFFFC200"), (.uiColor, "UIColor(red: 1.00, green: 0.76, blue: 0.00, alpha: 1.00)"), (.csharp, "Color.fromArgb(255, 194, 0);"),
    ])
    func format(_ f: ColorFormat, _ expected: String) {
        #expect(f.string(NSColor(hex: 0xFFC200)) == expected)
    }

    @Test func oklch() { #expect(ColorFormat.oklch.string(NSColor(hex: 0xFFC200)).hasPrefix("oklch(84.")) }
}

@Suite("Rendering")
struct RenderTests {
    @Test("Blur Text patches are fully opaque (text must not show through)")
    func blurTextOpaque() {
        // Thin, text-line-sized region: almost every block is at the edge.
        let img = makeImage(300, 120) { ctx in
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 120))
            ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 20, y: 50, width: 200, height: 20))
        }
        let doc = EditorDocument(image: img, scale: 1)
        let patch = doc.concealedPatch(for: CGRect(x: 10, y: 40, width: 240, height: 40), textLine: true)!
        for (x, y) in [(0, 0), (patch.width - 1, patch.height - 1), (patch.width / 2, patch.height / 2), (0, patch.height - 1)] {
            #expect(pixel(patch, x, y).alphaComponent > 0.99)
        }
    }

    @Test("Erase fills with the dominant surrounding color, not a mix")
    func eraseDominant() {
        let img = makeImage(200, 200) { ctx in
            ctx.setFillColor(NSColor(hex: 0x2255AA).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 30)) // a strip of another color
        }
        let c = EditorDocument(image: img, scale: 1).edgeColor(around: CGRect(x: 50, y: 25, width: 100, height: 100))
        #expect(c.hexString == "#2255AA", "got \(c.hexString)")
    }

    @Test("annotations are drawn into the export")
    func arrowRendered() {
        let doc = EditorDocument(image: solid(300, 200, 0xFFFFFF), scale: 1)
        var s = ToolStyle()
        s.color = NSColor(hex: 0xFF0000)
        s.width = 8
        doc.objects = [Annotation(kind: .line, p1: CGPoint(x: 20, y: 100), p2: CGPoint(x: 280, y: 100), style: s)]
        let out = doc.render()!
        #expect(pixel(out, 150, 100).hexString == "#FF0000", "line pixel \(pixel(out, 150, 100).hexString)")
        #expect(pixel(out, 150, 20).hexString == "#FFFFFF", "background \(pixel(out, 150, 20).hexString)")
    }

    @Test("a backdrop pads the canvas and keeps the image inside")
    func backdrop() {
        let doc = EditorDocument(image: solid(200, 100, 0x000000), scale: 1)
        doc.backdrop.isOn = true
        let size = Renderer.canvasSize(doc)
        #expect(size.width > 200 && size.height > 100)
        let out = doc.render()!
        #expect(pixel(out, Int(size.width) / 2, Int(size.height) / 2).hexString == "#000000")
    }
}
