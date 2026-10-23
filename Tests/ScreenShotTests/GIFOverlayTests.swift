import AppKit
import ImageIO
import Testing
@testable import ScreenShotKit

@Suite("GIF overlay")
struct GIFOverlayTests {
    @Test("two frames, without and with the annotations, looping forever")
    func frames() throws {
        let doc = EditorDocument(image: solid(300, 200, 0xFFFFFF), scale: 1)
        var s = ToolStyle()
        s.color = NSColor(hex: 0xFF0000)
        s.width = 10
        doc.objects = [Annotation(kind: .line, p1: CGPoint(x: 0, y: 100), p2: CGPoint(x: 300, y: 100), style: s)]
        let (plain, annotated) = try #require(GIFOverlay.frames(doc))
        let data = try #require(GIFOverlay.encode(plain: plain, annotated: annotated))
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(src) == 2)
        let props = CGImageSourceCopyProperties(src, nil) as? [CFString: Any]
        #expect((props?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int == 0)
        let f0 = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let f1 = try #require(CGImageSourceCreateImageAtIndex(src, 1, nil))
        #expect(pixel(f0, 150, 100).redComponent > 0.9 && pixel(f0, 150, 100).greenComponent > 0.9, "first frame is the plain screenshot")
        #expect(pixel(f1, 150, 100).redComponent > 0.9 && pixel(f1, 150, 100).greenComponent < 0.2, "second frame shows the red line")
    }

    @Test("big screenshots are scaled down for the GIF")
    func size() throws {
        let big = solid(3200, 1800, 0x336699)
        let data = try #require(GIFOverlay.encode(plain: big, annotated: big))
        let img = try #require(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil))
        #expect(img.width == 1600 && img.height == 900)
    }
}
