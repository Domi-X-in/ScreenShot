import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Everything needed to reopen a saved screenshot with its annotations still editable.
struct EditState: Codable {
    var version = 1
    var scale: CGFloat
    var backdrop: Backdrop
    var objects: [Annotation]
    /// Sidecar files only: SHA-256 of the rendered file they belong to, so a file changed elsewhere isn't "restored".
    var renderedDigest: String?
}

/// Saves the edit state inside the file: a private PNG chunk ("scED") for PNG, a hidden sidecar file for JPEG.
/// Payload = magic + UInt32 JSON length + JSON (EditState) + PNG of the unannotated base image.
enum EditableFile {
    /// Ancillary (s), private (c), reserved (E), unsafe-to-copy (D): editors that change the pixels drop it.
    private static let chunkType = Data("scED".utf8)
    private static let magic = Data("SCREENSHOT-EDIT1".utf8)
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    static func sidecarURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).screenshot-edit")
    }

    // MARK: Write

    /// Writes the rendered image; when `state` has something to keep, stores it with the base image too.
    static func write(rendered: Data, type: UTType, state: EditState?, base: CGImage, to url: URL) throws {
        // Atomic writes replace the file; keep its creation date so the recent strip's order stays put while editing.
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        defer {
            if let created { try? FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path) }
        }
        let sidecar = sidecarURL(for: url)
        guard var state, !state.objects.isEmpty || state.backdrop != .none else {
            try rendered.write(to: url, options: .atomic)
            try? FileManager.default.removeItem(at: sidecar)
            return
        }
        if type == .png {
            guard let payload = payload(state: state, base: base) else { throw CocoaError(.fileWriteUnknown) }
            try insertChunk(payload, into: rendered).write(to: url, options: .atomic)
            try? FileManager.default.removeItem(at: sidecar)
        } else {
            try rendered.write(to: url, options: .atomic)
            state.renderedDigest = digest(rendered)
            guard let payload = payload(state: state, base: base) else { throw CocoaError(.fileWriteUnknown) }
            try payload.write(to: sidecar, options: .atomic)
        }
    }

    private static func payload(state: EditState, base: CGImage) -> Data? {
        guard let json = try? JSONEncoder().encode(state),
              let png = NSBitmapImageRep(cgImage: base).representation(using: .png, properties: [:]) else { return nil }
        var d = magic
        d.append(bigEndian(UInt32(json.count)))
        d.append(json)
        d.append(png)
        return d
    }

    // MARK: Read

    struct Loaded {
        let image: CGImage
        let scale: CGFloat
        let state: EditState?
    }

    static func load(_ url: URL) -> Loaded? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let chunk = extractChunk(from: data), let (state, base) = parse(chunk) {
            return Loaded(image: base, scale: state.scale, state: state)
        }
        if let side = try? Data(contentsOf: sidecarURL(for: url)), let (state, base) = parse(side),
           state.renderedDigest == digest(data) {
            return Loaded(image: base, scale: state.scale, state: state)
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let dpi = (props?[kCGImagePropertyDPIWidth] as? Double) ?? 72
        return Loaded(image: img, scale: max(1, CGFloat(dpi / 72).rounded()), state: nil)
    }

    static func hasEdits(_ url: URL) -> Bool {
        if let data = try? Data(contentsOf: url), extractChunk(from: data) != nil { return true }
        return FileManager.default.fileExists(atPath: sidecarURL(for: url).path)
    }

    private static func parse(_ d: Data) -> (EditState, CGImage)? {
        let d = Data(d) // rebase indices to 0
        guard d.count > magic.count + 4, d.prefix(magic.count) == magic else { return nil }
        let len = Int(d[magic.count..<magic.count + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        let jsonStart = magic.count + 4
        guard d.count >= jsonStart + len,
              let state = try? JSONDecoder().decode(EditState.self, from: d[jsonStart..<jsonStart + len]) else { return nil }
        let png = d[(jsonStart + len)...]
        guard let src = CGImageSourceCreateWithData(Data(png) as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (state, img)
    }

    // MARK: PNG chunks

    private static func insertChunk(_ payload: Data, into png: Data) -> Data {
        // Drop an older edit chunk, then insert the new one right before IEND.
        let clean = removingChunk(from: png)
        guard let iend = clean.range(of: Data("IEND".utf8), options: .backwards) else { return clean }
        let chunkStart = iend.lowerBound - 4
        var chunk = bigEndian(UInt32(payload.count))
        chunk.append(chunkType)
        chunk.append(payload)
        chunk.append(bigEndian(crc32(chunkType + payload)))
        var out = Data(clean[..<chunkStart])
        out.append(chunk)
        out.append(clean[chunkStart...])
        return out
    }

    /// Walks the chunk list; returns the edit chunk's data if present.
    private static func extractChunk(from png: Data) -> Data? {
        chunks(in: png).first { $0.type == chunkType }.map { Data(png[$0.data]) }
    }

    private static func removingChunk(from png: Data) -> Data {
        var out = Data(png)
        for c in chunks(in: png).reversed() where c.type == chunkType {
            out.removeSubrange(c.whole)
        }
        return out
    }

    private static func chunks(in png: Data) -> [(type: Data, data: Range<Int>, whole: Range<Int>)] {
        let png = Data(png)
        guard png.count > 8, png.prefix(8) == pngSignature else { return [] }
        var result: [(Data, Range<Int>, Range<Int>)] = []
        var pos = 8
        while pos + 12 <= png.count {
            let len = Int(png[pos..<pos + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            let type = Data(png[pos + 4..<pos + 8])
            let end = pos + 12 + len
            guard end <= png.count else { break }
            result.append((type, pos + 8..<pos + 8 + len, pos..<end))
            if type == Data("IEND".utf8) { break }
            pos = end
        }
        return result
    }

    // MARK: Helpers

    private static func bigEndian(_ v: UInt32) -> Data {
        Data([UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)])
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    /// Posted after a screenshot is written to disk, so recent-file strips refresh.
    static let screenshotSaved = Notification.Name("ScreenShotSaved")
}
