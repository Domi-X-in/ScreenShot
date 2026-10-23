import AppKit
import Testing
import Vision
@testable import ScreenShotKit

@Suite("OCR")
struct OCRTests {
    /// "INVOICE 4821" on the left half, "PAID" on the right.
    private let image = makeImage(1000, 200) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 200))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 56, weight: .semibold), .foregroundColor: NSColor.black]
        ("INVOICE 4821" as NSString).draw(at: CGPoint(x: 20, y: 60), withAttributes: attrs)
        ("PAID" as NSString).draw(at: CGPoint(x: 700, y: 60), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    @Test("reads the whole image")
    func whole() throws {
        let (text, isQR) = try #require(OCR.recognize(image, removeBreaks: true))
        #expect(!isQR)
        #expect(text.contains("4821") && text.contains("PAID"), "got \(text)")
    }

    @Test("an area reads only what is inside it")
    func area() throws {
        let part = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 600, height: 200)))
        let (text, _) = try #require(OCR.recognize(part, removeBreaks: true))
        #expect(text.contains("4821") && !text.contains("PAID"), "got \(text)")
    }

    @Test("a main language narrows Vision to it (plus English)")
    func language() {
        #expect(OCR.languages.contains { $0.code.hasPrefix("en") })
        let req = VNRecognizeTextRequest()
        OCR.configure(req, language: "es-ES")
        #expect(!req.automaticallyDetectsLanguage && req.recognitionLanguages == ["es-ES", "en-US"])
        OCR.configure(req, language: "auto")
        #expect(req.automaticallyDetectsLanguage)
        #expect(OCR.recognize(image, removeBreaks: true, language: "es-ES")?.0.contains("4821") == true)
    }
}
