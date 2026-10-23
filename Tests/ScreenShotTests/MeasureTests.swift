import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Measure and Autoadjust")
struct MeasureTests {
    /// White 300×200 with a blue 100×60 button at (50, 40).
    private let image = makeImage(300, 200) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        ctx.setFillColor(NSColor(hex: 0x2255AA).cgColor)
        ctx.fill(CGRect(x: 50, y: 40, width: 100, height: 60))
    }

    @Test("the span stops at the edges of the area under the pointer")
    func spanInside() throws {
        let s = try #require(Measure.span(at: 80, 70, in: PixelReader(image)))
        #expect(s == .init(left: 50, right: 149, top: 40, bottom: 99))
        #expect(s.width == 100 && s.height == 60)
    }

    @Test("on the background the span reaches the button or the image edge")
    func spanOutside() throws {
        let s = try #require(Measure.span(at: 20, 70, in: PixelReader(image)))
        #expect(s.left == 0 && s.right == 49, "stops before the button")
        #expect(s.top == 0 && s.bottom == 199)
        #expect(Measure.span(at: 400, 10, in: PixelReader(image)) == nil)
    }

    @Test("Autoadjust shrinks the selection to the content")
    func autoadjust() {
        let px = PixelReader(image)
        #expect(Autoadjust.fit(CGRect(x: 0, y: 0, width: 300, height: 200), in: px) == CGRect(x: 50, y: 40, width: 100, height: 60))
        #expect(Autoadjust.fit(CGRect(x: 10, y: 10, width: 200, height: 150), in: px) == CGRect(x: 50, y: 40, width: 100, height: 60))
    }

    @Test("Autoadjust leaves a selection of only background alone")
    func autoadjustEmpty() {
        let r = CGRect(x: 200, y: 120, width: 60, height: 60)
        #expect(Autoadjust.fit(r, in: PixelReader(image)) == r)
    }
}
