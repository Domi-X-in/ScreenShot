import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Shottr's GIF overlay: a two-frame animation that blinks the annotations on and off over the screenshot,
/// so a viewer sees both what was marked and what was underneath.
enum GIFOverlay {
    /// Plain frame (same canvas and backdrop, no annotations), then the annotated frame; loops forever.
    static func frames(_ doc: EditorDocument) -> (plain: CGImage, annotated: CGImage)? {
        guard let annotated = doc.render() else { return nil }
        let bare = EditorDocument(image: doc.image, scale: doc.scale)
        bare.backdrop = doc.backdrop
        guard let plain = bare.render() else { return nil }
        return (plain, annotated)
    }

    /// GIF data. Big screenshots are scaled so the longer side is at most `maxSide` (GIFs are 256-color and heavy).
    static func encode(plain: CGImage, annotated: CGImage, delay: Double = 0.9, maxSide: Int = 1600) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        for img in [plain, annotated] {
            CGImageDestinationAddImage(dest, fit(img, maxSide: maxSide), frame)
        }
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    private static func fit(_ img: CGImage, maxSide: Int) -> CGImage {
        let long = max(img.width, img.height)
        guard long > maxSide else { return img }
        return Exporter.downscale(img, by: CGFloat(long) / CGFloat(maxSide)) ?? img
    }
}
