import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Arrange and smart guides")
struct ArrangeTests {
    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Annotation {
        Annotation(kind: .rect, p1: CGPoint(x: x, y: y), p2: CGPoint(x: x + w, y: y + h), style: ToolStyle())
    }
    private let image = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test("align left / center / bottom line several objects up with each other")
    func align() {
        let objs = [box(100, 100, 50, 40), box(300, 200, 80, 60), box(200, 400, 120, 30)]
        let all = Set(objs.map(\.id))
        let left = Arrange.apply(.alignLeft, to: objs, selected: all, reference: image)
        #expect(left.allSatisfy { $0.rect.minX == 100 })
        let center = Arrange.apply(.alignCenter, to: objs, selected: all, reference: image)
        #expect(center.allSatisfy { $0.rect.midX == 240 }, "selection spans 100…380") // midX of the union
        let bottom = Arrange.apply(.alignBottom, to: objs, selected: all, reference: image)
        #expect(bottom.allSatisfy { $0.rect.maxY == 430 })
        #expect(left[1].rect.minY == 200, "aligning left doesn't move objects vertically")
    }

    @Test("one object aligns to the screenshot")
    func alignToImage() {
        let o = box(100, 100, 50, 40)
        let r = Arrange.apply(.alignCenter, to: [o], selected: [o.id], reference: image)
        #expect(r[0].rect.midX == 500)
        let m = Arrange.apply(.alignMiddle, to: [o], selected: [o.id], reference: image)
        #expect(m[0].rect.midY == 400)
    }

    @Test("distribute leaves equal gaps and keeps the outer objects in place")
    func distribute() {
        let objs = [box(0, 0, 100, 10), box(150, 0, 50, 10), box(500, 0, 100, 10)]
        let r = Arrange.apply(.distributeHorizontally, to: objs, selected: Set(objs.map(\.id)), reference: image)
        #expect(r[0].rect.minX == 0 && r[2].rect.minX == 500)
        #expect(r[1].rect.minX - r[0].rect.maxX == r[2].rect.minX - r[1].rect.maxX, "gaps \(r.map(\.rect.minX))")
        let two = Arrange.apply(.distributeHorizontally, to: Array(objs.prefix(2)), selected: Set(objs.prefix(2).map(\.id)), reference: image)
        #expect(two[1].rect.minX == 150, "needs three objects")
    }

    @Test("stacking order: front, back, one step forward and back")
    func order() {
        let a = box(0, 0, 1, 1), b = box(0, 0, 1, 1), c = box(0, 0, 1, 1), d = box(0, 0, 1, 1)
        let objs = [a, b, c, d]
        func ids(_ x: [Annotation]) -> [UUID] { x.map(\.id) }
        #expect(ids(Arrange.apply(.bringToFront, to: objs, selected: [b.id], reference: image)) == [a.id, c.id, d.id, b.id])
        #expect(ids(Arrange.apply(.sendToBack, to: objs, selected: [c.id], reference: image)) == [c.id, a.id, b.id, d.id])
        #expect(ids(Arrange.apply(.bringForward, to: objs, selected: [b.id], reference: image)) == [a.id, c.id, b.id, d.id])
        #expect(ids(Arrange.apply(.sendBackward, to: objs, selected: [c.id], reference: image)) == [a.id, c.id, b.id, d.id])
        #expect(ids(Arrange.apply(.bringForward, to: objs, selected: [d.id], reference: image)) == ids(objs), "already on top")
    }

    @Test("a moving box snaps its edge or center to another object within the threshold, with a guide")
    func snapRect() {
        let g = SmartGuides(targets: [CGRect(x: 100, y: 100, width: 200, height: 100)])
        let (off, guides) = g.snap(rect: CGRect(x: 104, y: 400, width: 50, height: 50), threshold: 6)
        #expect(off.dx == -4 && off.dy == 0, "left edges line up")
        #expect(guides.contains { $0.vertical && $0.position == 100 && $0.from == 100 && $0.to == 450 })
        let (center, _) = g.snap(rect: CGRect(x: 172, y: 400, width: 50, height: 50), threshold: 6)
        #expect(center.dx == 3, "centers line up (197 → 200)")
        let (far, none) = g.snap(rect: CGRect(x: 120, y: 400, width: 50, height: 50), threshold: 6)
        #expect(far.dx == 0 && none.allSatisfy { !$0.vertical })
    }

    @Test("a corner being drawn snaps to edges on both axes")
    func snapPoint() {
        let g = SmartGuides(targets: [CGRect(x: 100, y: 100, width: 200, height: 100)])
        let (p, guides) = g.snap(point: CGPoint(x: 297, y: 203), threshold: 6)
        #expect(p == CGPoint(x: 300, y: 200))
        #expect(guides.count == 2)
    }
}

@Suite("Editor content")
struct EditorContentTests {
    @Test("an object past the screenshot's edge grows the canvas; the image moves in to make room")
    func growsCanvas() throws {
        let doc = EditorDocument(image: solid(400, 300, 0x2255AA), scale: 1)
        #expect(Renderer.canvasSize(doc) == CGSize(width: 400, height: 300))
        var s = ToolStyle()
        s.fill = .opaque
        s.color = NSColor(hex: 0xFF0000)
        s.width = 2
        doc.objects = [Annotation(kind: .rect, p1: CGPoint(x: -100, y: 200), p2: CGPoint(x: -20, y: 400), style: s)]
        let size = Renderer.canvasSize(doc)
        #expect(size.width == 400 + 101 && size.height == 400 + 1, "\(size) \(doc.contentRect) \(Renderer.imageOrigin(doc))")
        #expect(Renderer.imageOrigin(doc) == CGPoint(x: 101, y: 0))
        let out = try #require(doc.render())
        #expect(out.width == 501 && out.height == 401)
        #expect(pixel(out, 60, 380).hexString == "#FF0000", "the object outside is in the picture")
        #expect(pixel(out, 300, 100).hexString == "#2255AA", "the screenshot is there too")
        #expect(PixelReader(out).color(20, 20)!.alphaComponent < 0.01, "the new area is transparent")
        let jpeg = try #require(Exporter.encode(out, scale: 1, type: .jpeg))
        let back = try #require(NSBitmapImageRep(data: jpeg)?.cgImage)
        #expect(pixel(back, 20, 20).brightnessComponent > 0.95, "JPEG fills it with white")
    }

    @Test("while dragging the canvas holds still")
    func frozen() {
        let doc = EditorDocument(image: solid(100, 100, 0), scale: 1)
        doc.frozenContentRect = doc.contentRect
        doc.objects = [Annotation(kind: .rect, p1: CGPoint(x: 200, y: 200), p2: CGPoint(x: 300, y: 300), style: ToolStyle())]
        #expect(Renderer.canvasSize(doc) == CGSize(width: 100, height: 100))
        doc.frozenContentRect = nil
        #expect(Renderer.canvasSize(doc).width > 300)
    }

    @Test("committing text in a filled callout keeps the bubble's color")
    func calloutColor() {
        var s = ToolStyle()
        s.color = NSColor(hex: 0x007AFF)
        s.callout = .box
        var c = Annotation(kind: .callout, p1: .zero, p2: .zero, style: s)
        let typed = NSAttributedString(string: "Hola", attributes: [.font: NSFont.systemFont(ofSize: c.fontSize), .foregroundColor: c.baseTextColor])
        c.setText(from: typed, scale: 1)
        #expect(c.color.hexString == "#007AFF", "bubble became \(c.color.hexString)")
        #expect(c.text == "Hola")
        // A text color picked on purpose for all the letters is kept, on the text only.
        let yellow = NSAttributedString(string: "Hola", attributes: [.font: NSFont.systemFont(ofSize: c.fontSize), .foregroundColor: NSColor(hex: 0xFFCC00)])
        c.setText(from: yellow, scale: 1)
        #expect(c.color.hexString == "#FFCC00" || c.runs?.first?.color.hasPrefix("#FFCC00") == true)
    }

    @Test("text in a rectangle leaves the outline's color and width alone, and is drawn centered")
    func shapeText() throws {
        var s = ToolStyle()
        s.color = NSColor(hex: 0xFF0000)
        s.width = 4
        var r = Annotation(kind: .rect, p1: CGPoint(x: 50, y: 50), p2: CGPoint(x: 350, y: 250), style: s)
        let typed = NSAttributedString(string: "TITLE", attributes: [.font: NSFont.systemFont(ofSize: 48, weight: .black), .foregroundColor: NSColor.black])
        r.setText(from: typed, scale: 1)
        #expect(r.color.hexString == "#FF0000" && r.width == 4)
        #expect(r.text == "TITLE" && r.shapeFontSize == 48)
        #expect(r.hit(CGPoint(x: 200, y: 150)), "a shape with text is clickable inside")
        let doc = EditorDocument(image: solid(400, 300, 0xFFFFFF), scale: 1)
        doc.objects = [r]
        let out = try #require(doc.render())
        // Dark text pixels near the middle, none near the inside of the left edge.
        var dark = 0
        for x in 150..<250 { for y in 130..<170 where pixel(out, x, y).brightnessComponent < 0.3 { dark += 1 } }
        #expect(dark > 100, "text drawn in the middle (\(dark) dark pixels)")
        #expect(pixel(out, 70, 150).hexString == "#FFFFFF")
    }
}
