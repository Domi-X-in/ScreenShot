import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Hand-drawn strokes")
struct SketchTests {
    @Test("the wobble is the same on every redraw and differs between objects")
    func deterministic() {
        let id = UUID(), other = UUID()
        let a = Sketch.strokes([(CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0))], width: 4, id: id)
        let b = Sketch.strokes([(CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0))], width: 4, id: id)
        let c = Sketch.strokes([(CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0))], width: 4, id: other)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("strokes stay close to the true shape")
    func close() {
        let r = CGRect(x: 50, y: 50, width: 300, height: 200)
        let box = Sketch.ellipse(in: r, width: 4, id: UUID()).boundingBoxOfPath
        #expect(abs(box.minX - r.minX) < 12 && abs(box.maxY - r.maxY) < 12, "\(box)")
        let line = Sketch.strokes([(CGPoint(x: 0, y: 100), CGPoint(x: 400, y: 100))], width: 4, id: UUID()).boundingBoxOfPath
        #expect(line.height < 16)
    }

    @Test("the hand-drawn option is saved with the object")
    func codable() throws {
        var s = ToolStyle()
        s.sketch = true
        let a = Annotation(kind: .rect, p1: .zero, p2: CGPoint(x: 10, y: 10), style: s)
        let back = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(a))
        #expect(back.sketch)
        let plain = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(Annotation(kind: .rect, p1: .zero, p2: .zero, style: ToolStyle())))
        #expect(!plain.sketch)
    }
}
