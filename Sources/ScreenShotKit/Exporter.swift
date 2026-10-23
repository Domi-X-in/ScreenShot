import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor enum Exporter {
    static func copy(_ img: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: img)
        rep.size = NSSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = encode(img, scale: scale, type: .png) { pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    /// Encodes with DPI metadata so Retina captures keep their point size when opened elsewhere.
    nonisolated static func encode(_ img: CGImage, scale: CGFloat, type: UTType) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * scale,
            kCGImagePropertyDPIHeight: 72 * scale,
        ]
        var img = img
        if type == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = 0.88
            // JPEG has no transparency: areas outside the screenshot (objects past its edges) go white, not black.
            img = flattened(img) ?? img
        }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    nonisolated static func flattened(_ img: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(.white)
        ctx.fill(r)
        ctx.draw(img, in: r)
        return ctx.makeImage()
    }

    /// "Automatic" format: photos/gradients → JPEG, flat UI/text → PNG (heuristic: color variety on a downsample).
    static func autoType(for img: CGImage) -> UTType {
        if img.alphaInfo != .none && img.alphaInfo != .noneSkipFirst && img.alphaInfo != .noneSkipLast { return .png }
        let side = 96
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = ctx.data else { return .png }
        ctx.interpolationQuality = .low
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: side, height: side))
        let px = data.bindMemory(to: UInt32.self, capacity: side * side)
        var colors = Set<UInt32>()
        for i in 0..<(side * side) { colors.insert(px[i] & 0x00F8_F8F8) }
        return Double(colors.count) / Double(side * side) > 0.35 ? .jpeg : .png
    }

    static func fileName(ext: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "ScreenShot \(f.string(from: Date())).\(ext)"
    }

    private static func chosenType(_ img: CGImage) -> UTType {
        switch Settings.saveFormat {
        case "jpg": .jpeg
        case "auto": autoType(for: img)
        default: .png
        }
    }

    /// "Save Retina screenshots at 1×": halves (or thirds) a Retina image before it is written.
    nonisolated static func forSaving(_ img: CGImage, scale: CGFloat) -> (CGImage, CGFloat) {
        guard Settings.saveRetinaAt1x, scale > 1, let small = downscale(img, by: scale) else { return (img, scale) }
        return (small, 1)
    }

    nonisolated static func downscale(_ img: CGImage, by scale: CGFloat) -> CGImage? {
        let w = max(1, Int((CGFloat(img.width) / scale).rounded())), h = max(1, Int((CGFloat(img.height) / scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    @discardableResult
    static func save(_ img: CGImage, scale: CGFloat, quiet: Bool = false) -> URL? {
        let folder = Settings.saveFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let type = chosenType(img)
            let url = folder.appendingPathComponent(fileName(ext: type.preferredFilenameExtension ?? "png"))
            let (out, outScale) = forSaving(img, scale: scale)
            guard let data = encode(out, scale: outScale, type: type) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
            if !quiet { Toast.show("Saved to \(folder.lastPathComponent)") }
            NotificationCenter.default.post(name: .screenshotSaved, object: url)
            return url
        } catch {
            Toast.show("Failed to save file: \(error.localizedDescription)")
            return nil
        }
    }

    /// Saves an editor document with its annotations kept editable. Writes back to the file it came from, if any.
    @discardableResult
    static func saveEditable(_ doc: EditorDocument, rendered: CGImage, to target: URL? = nil, quiet: Bool = false) -> URL? {
        do {
            let url: URL
            let type: UTType
            if let t = target ?? doc.fileURL {
                url = t
                type = ["jpg", "jpeg"].contains(t.pathExtension.lowercased()) ? .jpeg : .png
            } else {
                let folder = Settings.saveFolder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                type = chosenType(rendered)
                url = folder.appendingPathComponent(fileName(ext: type.preferredFilenameExtension ?? "png"))
            }
            // Only the visible image is reduced; the editable copy inside keeps every pixel.
            let (out, outScale) = forSaving(rendered, scale: doc.scale)
            guard let data = encode(out, scale: outScale, type: type) else { throw CocoaError(.fileWriteUnknown) }
            let state = EditState(scale: doc.scale, backdrop: doc.backdrop, objects: doc.objects)
            try EditableFile.write(rendered: data, type: type, state: state, base: doc.image, to: url)
            doc.fileURL = url
            if !quiet { Toast.show("Saved \(url.lastPathComponent)") }
            NotificationCenter.default.post(name: .screenshotSaved, object: url)
            return url
        } catch {
            Toast.show("Failed to save file: \(error.localizedDescription)")
            return nil
        }
    }

}
