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

    /// Names handed out whose file may not be written yet (auto-save writes off the main thread).
    private static var reservedNames = Set<String>()

    /// A new file in `folder`: names only go down to the second, so two captures saved in the same second get "… 2".
    static func unusedURL(in folder: URL, ext: String) -> URL {
        unusedURL(in: folder, stem: URL(fileURLWithPath: fileName(ext: ext)).deletingPathExtension().lastPathComponent, ext: ext)
    }

    private static func unusedURL(in folder: URL, stem: String, ext: String) -> URL {
        var url = folder.appendingPathComponent("\(stem).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) || reservedNames.contains(url.path) {
            url = folder.appendingPathComponent("\(stem) \(n).\(ext)")
            n += 1
        }
        reservedNames.insert(url.path)
        return url
    }

    /// Whether a save can replace this file: the app writes PNG and JPEG only, and bytes of another format under a
    /// .gif, .heic or .tiff name would destroy the original (a GIF's animation, for one).
    nonisolated static func canWriteInPlace(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }

    /// Where a save of `url` goes: the file itself, or for any other format a new PNG beside it.
    static func saveTarget(for url: URL) -> URL {
        guard !canWriteInPlace(url) else { return url }
        let dir = url.deletingLastPathComponent()
        let folder = FileManager.default.isWritableFile(atPath: dir.path) ? dir : Settings.saveFolder
        return unusedURL(in: folder, stem: url.deletingPathExtension().lastPathComponent + " edited", ext: "png")
    }

    /// A file for dragging out, in a folder of the app's own that is emptied at launch and by the next drag.
    static func dragFile(_ data: Data) -> URL? {
        let fm = FileManager.default
        let folder = dragFolder
        clearDragFolder(olderThan: 3600)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = unusedURL(in: folder, ext: "png")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.files.error("Could not write a drag file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static var dragFolder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("ScreenShot-Drag", isDirectory: true) }

    /// Keeps recent ones by default: the app that received a drop may still be reading the file.
    nonisolated static func clearDragFolder(olderThan age: TimeInterval = 0) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dragFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for f in files {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(date) >= age { try? fm.removeItem(at: f) }
        }
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
            let url = unusedURL(in: folder, ext: type.preferredFilenameExtension ?? "png")
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
                url = saveTarget(for: t)
                type = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
            } else {
                let folder = Settings.saveFolder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                type = chosenType(rendered)
                url = unusedURL(in: folder, ext: type.preferredFilenameExtension ?? "png")
            }
            // Only the visible image is reduced; the editable copy inside keeps every pixel.
            let (out, outScale) = forSaving(rendered, scale: doc.scale)
            guard let data = encode(out, scale: outScale, type: type) else { throw CocoaError(.fileWriteUnknown) }
            let state = EditState(scale: doc.scale, backdrop: doc.backdrop, objects: doc.objects)
            // Behind any auto-save still on its way, so that one can't overwrite this newer picture.
            let base = doc.image
            try EditableFile.ioQueue.sync { try EditableFile.write(rendered: data, type: type, state: state, base: base, to: url) }
            doc.fileURL = url
            doc.noteFileWritten()
            if !quiet { Toast.show("Saved \(url.lastPathComponent)") }
            NotificationCenter.default.post(name: .screenshotSaved, object: url)
            return url
        } catch {
            Toast.show("Failed to save file: \(error.localizedDescription)")
            return nil
        }
    }

}
