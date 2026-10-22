import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Annotations")
struct AnnotationTests {
    @Test("every kind survives encoding", arguments: Tool.allCases)
    func codable(kind: Tool) throws {
        var a = Annotation(kind: kind, p1: CGPoint(x: 10, y: 20), p2: CGPoint(x: 110, y: 90), style: ToolStyle())
        a.text = "x"
        let back = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(a))
        #expect(back.id == a.id && back.kind == kind && back.p1 == a.p1 && back.p2 == a.p2 && back.color.rgbaHex == a.color.rgbaHex)
    }

    @Test("a callout's bounds include its pointer, wherever it points", arguments: [
        CGPoint(x: -200, y: 400), CGPoint(x: 600, y: -100), CGPoint(x: 900, y: 900),
    ])
    func calloutBounds(tip: CGPoint) {
        for style in CalloutStyle.allCases {
            var c = Annotation(kind: .callout, p1: CGPoint(x: 100, y: 100), p2: .zero, style: ToolStyle())
            c.text = "Hello"
            c.calloutStyle = style
            c.pointer = tip
            #expect(c.bounds.contains(tip), "\(style.title)")
            #expect(c.hit(CGPoint(x: c.calloutBox.midX, y: c.calloutBox.midY)))
        }
    }

    @Test("rectangles are hit on their border, not inside")
    func rectHit() {
        let r = Annotation(kind: .rect, p1: CGPoint(x: 0, y: 0), p2: CGPoint(x: 200, y: 200), style: ToolStyle())
        #expect(r.hit(CGPoint(x: 0, y: 100)))
        #expect(!r.hit(CGPoint(x: 100, y: 100)))
    }

    @Test("the magnifier lens is placed inside the image when there is room")
    func lensPlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let source = CGRect(x: 900, y: 700, width: 60, height: 40) // bottom-right corner
        let c = Annotation.defaultLensCenter(source: source, lensSize: CGSize(width: 180, height: 120), bounds: bounds)
        #expect(bounds.contains(CGRect(x: c.x - 90, y: c.y - 60, width: 180, height: 120)))
    }

    @Test("counters continue from the last one")
    func nextCounter() {
        let doc = EditorDocument(image: solid(10, 10, 0), scale: 1)
        var c = Annotation(kind: .counter, p1: .zero, p2: .zero, style: ToolStyle())
        c.number = 10
        doc.objects = [c]
        #expect(doc.nextCounter == 11)
    }
}

@Suite("Option defaults", .serialized)
struct DefaultsTests {
    @Test("built-in defaults: Professional · Box callout, red, size 4")
    func builtIn() {
        let s = ToolStyle()
        #expect(s.callout == .box && s.color.hexString == "#FF3B30" && s.width == 4)
    }

    @Test("changing one default keeps the others")
    func update() {
        let key = ToolStyle.defaultsKey
        let saved = UserDefaults.standard.dictionary(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.removeObject(forKey: key)
        ToolStyle.updateDefaults { $0.callout = .thought }
        ToolStyle.updateDefaults { $0.width = 9 }
        let d = ToolStyle.loadDefaults()
        #expect(d.callout == .thought && d.width == 9 && d.arrow == .tapered)
    }
}

@Suite("Window capture helpers")
struct CaptureHelperTests {
    @Test("transparent margins are trimmed")
    @MainActor func trim() {
        let img = makeImage(100, 80) { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: 100, height: 80))
            ctx.setFillColor(NSColor.red.cgColor)
            ctx.fill(CGRect(x: 10, y: 20, width: 30, height: 40))
        }
        let t = Capturer.trimTransparent(img)
        #expect(t?.width == 30 && t?.height == 40)
    }
}
