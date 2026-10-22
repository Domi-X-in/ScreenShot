import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Scrolling capture stitching")
struct StitcherTests {
    /// A tall page of random bars; frames are 300-px windows into it.
    static let page = makeImage(400, 3000) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 3000))
        var rng = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: 3000, by: 18) {
            ctx.setFillColor(CGColor(gray: CGFloat.random(in: 0...0.6, using: &rng), alpha: 1))
            ctx.fill(CGRect(x: Int.random(in: 0...50, using: &rng), y: y, width: Int.random(in: 100...350, using: &rng), height: 10))
        }
    }

    func frame(_ top: Int) -> CGImage { Self.page.cropping(to: CGRect(x: 0, y: top, width: 400, height: 300))! }

    @Test("detects how far the content moved", arguments: [(0, 0), (0, 137), (100, 340), (500, 520)])
    func offset(from a: Int, to b: Int) {
        #expect(Stitcher.offset(frame(a), frame(b)) == b - a)
    }

    @Test("composes strips top to bottom")
    func compose() {
        let strip = frame(100).cropping(to: CGRect(x: 0, y: 200, width: 400, height: 100))!
        let out = Stitcher.compose([frame(0), strip])
        #expect(out?.height == 400)
    }
}
