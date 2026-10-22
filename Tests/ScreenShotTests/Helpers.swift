import AppKit
@testable import ScreenShotKit

/// Builds a test image by drawing into a top-left-origin context.
func makeImage(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}

func solid(_ w: Int, _ h: Int, _ hex: UInt32) -> CGImage {
    makeImage(w, h) { $0.setFillColor(NSColor(hex: hex).cgColor); $0.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
}

/// Pixel color at a top-left-origin position, in sRGB.
func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> NSColor {
    PixelReader(img).color(x, y)!
}

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenShotTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}
