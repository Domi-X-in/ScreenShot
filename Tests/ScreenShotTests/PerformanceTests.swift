import AppKit
import Testing
import UniformTypeIdentifiers
@testable import ScreenShotKit

/// Auto-save cost on a 5K screenshot: render, encode, then write with the edit data.
@Suite("Performance (5K screenshot)", .serialized)
struct PerformanceTests {
    /// 5120×2880 with screen-like detail: gradients, text-like bars and noise, so PNG can't compress it trivially.
    static let big: CGImage = makeImage(5120, 2880) { ctx in
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [NSColor(hex: 0x1E3C72).cgColor, NSColor(hex: 0x2A5298).cgColor] as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 5120, y: 2880), options: [])
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<6000 {
            ctx.setFillColor(CGColor(gray: .random(in: 0...1, using: &rng), alpha: 1))
            ctx.fill(CGRect(x: .random(in: 0..<5120, using: &rng), y: .random(in: 0..<2880, using: &rng), width: .random(in: 20..<300, using: &rng), height: 12))
        }
    }

    static func timed(_ label: String, _ block: () -> Void) -> Double {
        let t = Date()
        block()
        let ms = Date().timeIntervalSince(t) * 1000
        print(String(format: "  %@: %.0f ms", label, ms))
        return ms
    }

    @Test("one auto-save of an edited 5K screenshot")
    func autosave() throws {
        let doc = EditorDocument(image: Self.big, scale: 2)
        doc.objects = [Annotation(kind: .arrow, p1: CGPoint(x: 100, y: 100), p2: CGPoint(x: 2000, y: 1500), style: ToolStyle())]
        let url = tempDir().appendingPathComponent("big.png")
        var rendered: CGImage!
        var data: Data!
        let total = Self.timed("render", { rendered = doc.render() })
            + Self.timed("encode rendered PNG", { data = Exporter.encode(rendered, scale: 2, type: .png) })
            + Self.timed("write with edit data (base image + JSON)", {
                try? EditableFile.write(rendered: data, type: .png, state: EditState(scale: 2, backdrop: .none, objects: doc.objects),
                                        base: doc.image, to: url)
            })
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print(String(format: "  total %.0f ms, file %.1f MB", total, Double(size) / 1_000_000))
        #expect(total < 4000)

        // The next auto-save of the same document reuses the encoded original.
        let encodes = BasePNGCache.shared.encodeCount(for: doc.image)
        doc.objects.append(Annotation(kind: .rect, p1: CGPoint(x: 300, y: 300), p2: CGPoint(x: 900, y: 700), style: ToolStyle()))
        let second = Self.timed("second auto-save (render + encode + write)", {
            let r = doc.render()!
            let d = Exporter.encode(r, scale: 2, type: .png)!
            try? EditableFile.write(rendered: d, type: .png, state: EditState(scale: 2, backdrop: .none, objects: doc.objects), base: doc.image, to: url)
        })
        #expect(BasePNGCache.shared.encodeCount(for: doc.image) == encodes, "the original is not re-encoded")
        #expect(second < total)
        #expect(EditableFile.load(url)?.state?.objects.count == 2)
    }
}
