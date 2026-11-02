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
    /// Sidecar files only (older versions): SHA-256 of the rendered file they belong to.
    var renderedDigest: String?
    /// Where the file was when last saved, so entries of deleted files can be swept from the store.
    var filePath: String?
}

/// What a file on disk may ask of the app. Everything read from a file is untrusted, whoever appears to have written it.
enum ImageLimits {
    /// Enough for a 50,000 px scrolling capture of a 6K display.
    static let maxPixels = 600_000_000
    static let maxSide = 200_000
    static let maxCoordinate: CGFloat = 1_000_000
    static let maxObjects = 10_000
    static let maxPoints = 200_000
    static let maxTextLength = 1_000_000

    static func allows(width: CGFloat, height: CGFloat) -> Bool {
        width.isFinite && height.isFinite && width >= 0 && height >= 0
            && width <= CGFloat(maxSide) && height <= CGFloat(maxSide) && width * height <= CGFloat(maxPixels)
    }

    /// Reads the size from the header, before any pixel is decoded.
    static func allows(_ src: CGImageSource) -> Bool {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return false }
        return allows(width: CGFloat(w), height: CGFloat(h))
    }

    /// The first image of `data`, unless its header asks for more pixels than the app accepts.
    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), allows(src) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

extension EditState {
    /// The state with every value in the range the app can draw: objects that can't be repaired are dropped.
    func sanitized() -> EditState {
        var s = self
        s.scale = scale.isFinite && scale >= 0.25 && scale <= 16 ? scale : 1
        s.backdrop = backdrop.sanitized()
        s.objects = objects.prefix(ImageLimits.maxObjects).compactMap { $0.sanitized() }
        return s
    }
}

extension Annotation {
    private static func valid(_ v: CGFloat) -> Bool { v.isFinite && abs(v) <= ImageLimits.maxCoordinate }
    private static func valid(_ p: CGPoint) -> Bool { valid(p.x) && valid(p.y) }

    fileprivate func sanitized() -> Annotation? {
        guard Self.valid(p1), Self.valid(p2), points.count <= ImageLimits.maxPoints, points.allSatisfy(Self.valid), width.isFinite else { return nil }
        var o = self
        o.width = min(max(width, 0), 10_000)
        o.factor = factor.isFinite ? min(max(factor, 0.1), 64) : 2
        o.tailAngle = tailAngle.isFinite ? tailAngle : 3 * .pi / 4
        o.lensCenter = lensCenter.flatMap { Self.valid($0) ? $0 : nil }
        o.pointer = pointer.flatMap { Self.valid($0) ? $0 : nil }
        o.textRects = textRects?.filter { Self.valid($0.origin) && Self.valid($0.width) && Self.valid($0.height) }
        if text.utf16.count > ImageLimits.maxTextLength { o.text = String(text.prefix(ImageLimits.maxTextLength)) }
        let length = o.text.utf16.count
        o.runs = runs?.compactMap { r in
            guard r.location >= 0, r.length >= 0, r.length <= length, r.location <= length - r.length else { return nil }
            var run = r
            run.size = r.size.isFinite ? min(max(r.size, 1), 2_000) : 12
            return run
        }
        if let data = imageData, ImageLimits.decode(data) == nil { o.imageData = nil }
        return o
    }
}

extension Backdrop {
    fileprivate func sanitized() -> Backdrop {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ fallback: CGFloat) -> CGFloat { v.isFinite ? min(max(v, lo), hi) : fallback }
        var b = self
        b.padding = clamp(padding, 0, 2, 0.07)
        b.shadow = clamp(shadow, 0, 1, 0.45)
        b.inset = clamp(inset, 0, 1, 0)
        b.outerRadius = clamp(outerRadius, 0, 1, 0)
        b.innerRadius = clamp(innerRadius, 0, 1, 0.012)
        b.offset = CGPoint(x: clamp(offset.x, -1, 1, 0), y: clamp(offset.y, -1, 1, 0))
        return b
    }
}

/// Saves the edit state apart from the image, in the app's private store, so a screenshot that is shared carries only
/// what it shows: never the original under a blur, nor the objects. Entries are named by the SHA-256 of the rendered
/// file, so they follow a renamed file, and a file changed elsewhere simply has none.
/// Payload = magic + UInt32 JSON length + JSON (EditState) + PNG of the unannotated base image.
/// Older versions kept the payload in a private PNG chunk or a hidden file next to a JPEG: those are still read, and
/// moved to the store by `migrateLegacyFiles` or the next save.
enum EditableFile {
    /// Every edit-state write runs here, in the order it was asked for, so an older save can't land on a newer one.
    static let ioQueue = DispatchQueue(label: "screenshot.autosave")

    private static let chunkType = Data("scED".utf8)
    private static let magic = Data("SCREENSHOT-EDIT1".utf8)
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let maxJSONLength = 256 * 1024 * 1024

    static let storeDirectory: URL = {
        #if SCREENSHOT_SELFTESTS
        // Tests and debug runs never touch the installed app's store.
        return FileManager.default.temporaryDirectory.appendingPathComponent("ScreenShot-debug-edit-state", isDirectory: true)
        #else
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenShot/EditState", isDirectory: true)
        #endif
    }()

    private static func storeURL(digest: String) -> URL { storeDirectory.appendingPathComponent(digest + ".screenshot-edit") }

    static func sidecarURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).screenshot-edit")
    }

    // MARK: Write

    /// Writes the rendered image; when `state` has something to keep, stores it with the base image in the store.
    static func write(rendered: Data, type: UTType, state: EditState?, base: CGImage, to url: URL) throws {
        // Atomic writes replace the file; keep its creation date so the recent strip's order stays put while editing.
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        defer {
            if let created { try? FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path) }
        }
        let old = (try? Data(contentsOf: url, options: .mappedIfSafe)).map(digest)
        let new = digest(rendered)
        var stored = false
        if var state, !state.objects.isEmpty || state.backdrop.isOn {
            state.filePath = url.standardizedFileURL.path
            guard let payload = payload(state: state, base: base) else { throw CocoaError(.fileWriteUnknown) }
            try writeToStore(payload, digest: new)
            stored = true
        }
        do {
            try rendered.write(to: url, options: .atomic)
        } catch {
            if stored && old != new { try? FileManager.default.removeItem(at: storeURL(digest: new)) }
            throw error
        }
        try? FileManager.default.removeItem(at: sidecarURL(for: url))
        if let old, old != new { try? FileManager.default.removeItem(at: storeURL(digest: old)) }
        if !stored { try? FileManager.default.removeItem(at: storeURL(digest: new)) }
    }

    /// Only the owner can read the store: it holds the originals of redacted screenshots.
    private static func writeToStore(_ payload: Data, digest: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: storeDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = storeURL(digest: digest)
        try payload.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func payload(state: EditState, base: CGImage) -> Data? {
        guard let json = try? JSONEncoder().encode(state), let png = BasePNGCache.shared.png(for: base) else { return nil }
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
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let name = digest(data)
        if let stored = try? Data(contentsOf: storeURL(digest: name), options: .mappedIfSafe), let (state, base) = parse(stored) {
            return Loaded(image: base, scale: state.scale, state: state)
        }
        if let chunk = extractChunk(from: data), let (state, base) = parse(chunk) {
            return Loaded(image: base, scale: state.scale, state: state)
        }
        if let side = try? Data(contentsOf: sidecarURL(for: url), options: .mappedIfSafe), let (state, base) = parse(side),
           state.renderedDigest == name {
            return Loaded(image: base, scale: state.scale, state: state)
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), ImageLimits.allows(src),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let dpi = (props?[kCGImagePropertyDPIWidth] as? Double) ?? 72
        let scale = dpi.isFinite ? max(1, min(16, CGFloat(dpi / 72).rounded())) : 1
        return Loaded(image: img, scale: scale, state: nil)
    }

    /// Whether the file has saved objects. Reads the whole file to name its entry: call it off the main thread.
    static func hasEdits(_ url: URL) -> Bool {
        if hasLegacyChunk(url) { return true }
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           FileManager.default.fileExists(atPath: storeURL(digest: digest(data)).path) { return true }
        return FileManager.default.fileExists(atPath: sidecarURL(for: url).path)
    }

    private static func parse(_ d: Data) -> (EditState, CGImage)? {
        let d = Data(d) // rebase indices to 0
        guard d.count > magic.count + 4, d.prefix(magic.count) == magic else { return nil }
        let len = Int(d[magic.count..<magic.count + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        let jsonStart = magic.count + 4
        guard len <= maxJSONLength, d.count >= jsonStart + len,
              let state = try? JSONDecoder().decode(EditState.self, from: d[jsonStart..<jsonStart + len]),
              let img = ImageLimits.decode(Data(d[(jsonStart + len)...])) else { return nil }
        return (state.sanitized(), img)
    }

    // MARK: Older versions

    /// Moves the edit data of files saved by older versions out of the files, into the store. A file's pixels don't
    /// change. Asked once, for the Screenshots folder; files elsewhere move when they are next saved.
    static func migrateLegacyFiles(in folder: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            switch url.pathExtension.lowercased() {
            case "png" where hasLegacyChunk(url): migrateChunk(url)
            case "jpg", "jpeg": migrateSidecar(url)
            default: break
            }
        }
    }

    private static func migrateChunk(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let clean = removingChunk(from: data)
        do {
            // A chunk that can't be read is removed all the same: what matters is that it stops travelling with the file.
            if let chunk = extractChunk(from: data), parse(chunk) != nil { try writeToStore(chunk, digest: digest(clean)) }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            try clean.write(to: url, options: .atomic)
            if let created { try? FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path) }
        } catch {
            Log.files.error("Could not migrate edit data of a saved file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func migrateSidecar(_ url: URL) {
        let side = sidecarURL(for: url)
        guard let payload = try? Data(contentsOf: side), let data = try? Data(contentsOf: url) else { return }
        let name = digest(data)
        if let (state, _) = parse(payload), state.renderedDigest == name {
            do { try writeToStore(payload, digest: name) } catch {
                Log.files.error("Could not migrate a sidecar: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        try? FileManager.default.removeItem(at: side)
    }

    // MARK: Store upkeep

    /// Removes entries whose file is gone, since each one keeps an original image on disk.
    static func sweepStore() {
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)) ?? [] {
            guard let path = storedPath(of: entry) else { continue }
            if !fm.fileExists(atPath: path) { try? fm.removeItem(at: entry) }
        }
    }

    /// The `filePath` of an entry, read from its header only. Nil for an entry saved without one.
    private static func storedPath(of entry: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: entry) else { return nil }
        defer { try? h.close() }
        let headerLength = magic.count + 4
        guard let header = try? h.read(upToCount: headerLength), header.count == headerLength else { return nil }
        let len = Int(header.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        guard len <= maxJSONLength, let json = try? h.read(upToCount: len) else { return nil }
        return (try? JSONDecoder().decode(EditState.self, from: json))?.filePath
    }

    // MARK: PNG chunks

    /// Whether a PNG has an edit chunk, walking the chunk headers without reading the image.
    static func hasLegacyChunk(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard (try? h.read(upToCount: 8)) == pngSignature else { return false }
        var pos: UInt64 = 8
        while let head = try? h.read(upToCount: 8), head.count == 8 {
            let len = head.prefix(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let type = Data(head.suffix(4))
            if type == chunkType { return true }
            if type == Data("IEND".utf8) { return false }
            pos += 12 + len
            guard (try? h.seek(toOffset: pos)) != nil else { return false }
        }
        return false
    }

    /// Walks the chunk list; returns the edit chunk's data if present.
    private static func extractChunk(from png: Data) -> Data? {
        chunks(in: png).first { $0.type == chunkType }.map { Data(Data(png)[$0.data]) }
    }

    static func removingChunk(from png: Data) -> Data {
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

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    /// Posted after a screenshot is written to disk, so recent-file strips refresh.
    static let screenshotSaved = Notification.Name("ScreenShotSaved")
}

/// The unannotated original never changes while annotating, so its PNG is encoded once and reused by every
/// auto-save (about 250 ms saved per save on a 5K screenshot). Keyed by image identity: a crop or resize makes a new
/// image and so a new entry. Thread-safe, since auto-save writes on a background queue.
final class BasePNGCache: @unchecked Sendable {
    static let shared = BasePNGCache()
    /// What the entries may hold, images and PNGs together; the newest stays even if it alone is over.
    private static let budget = 512 * 1024 * 1024
    private let lock = NSLock()
    private var entries: [(image: CGImage, png: Data)] = []
    private(set) var encodeCount = 0
    /// Encodes per image, so a check about one document isn't thrown off by others saving at the same time.
    private var encodes: [ObjectIdentifier: Int] = [:]

    func encodeCount(for image: CGImage) -> Int {
        lock.lock(); defer { lock.unlock() }
        return encodes[ObjectIdentifier(image)] ?? 0
    }

    var entryCount: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    /// Memory pressure: everything here can be encoded again.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }

    func png(for image: CGImage) -> Data? {
        lock.lock()
        if let hit = entries.first(where: { $0.image === image }) {
            lock.unlock()
            return hit.png
        }
        lock.unlock()
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        lock.lock()
        encodeCount += 1
        encodes[ObjectIdentifier(image), default: 0] += 1
        if encodes.count > 64 { encodes.removeAll() }
        entries.insert((image, png), at: 0)
        var total = entries.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height + $1.png.count }
        while entries.count > 1, entries.count > 8 || total > Self.budget {
            let last = entries.removeLast()
            total -= last.image.bytesPerRow * last.image.height + last.png.count
        }
        lock.unlock()
        return png
    }
}
