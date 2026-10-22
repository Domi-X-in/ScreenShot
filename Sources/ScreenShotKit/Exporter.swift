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
        if type == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = 0.88 }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
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

    @discardableResult
    static func save(_ img: CGImage, scale: CGFloat, quiet: Bool = false) -> URL? {
        let folder = Settings.saveFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let type = chosenType(img)
            let url = folder.appendingPathComponent(fileName(ext: type.preferredFilenameExtension ?? "png"))
            guard let data = encode(img, scale: scale, type: type) else { throw CocoaError(.fileWriteUnknown) }
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
            guard let data = encode(rendered, scale: doc.scale, type: type) else { throw CocoaError(.fileWriteUnknown) }
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
