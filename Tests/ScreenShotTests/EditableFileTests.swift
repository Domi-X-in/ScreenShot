import AppKit
import Testing
import UniformTypeIdentifiers
@testable import ScreenShotKit

// In order: entries are named by the rendered picture, and these tests render the same one.
@Suite("Editable saves", .serialized)
struct EditableFileTests {
    let base = solid(400, 300, 0x3366CC)

    func objects() -> [Annotation] {
        var s = ToolStyle()
        s.width = 5
        var text = Annotation(kind: .text, p1: CGPoint(x: 20, y: 20), p2: .zero, style: s)
        text.text = "Hola"
        text.runs = [TextRun(location: 2, length: 2, color: "#007AFFFF", size: 40, font: .goofy)]
        var callout = Annotation(kind: .callout, p1: CGPoint(x: 100, y: 100), p2: .zero, style: s)
        callout.text = "Mira"
        callout.calloutStyle = .shout
        callout.pointer = CGPoint(x: 30, y: 250)
        var counter = Annotation(kind: .counter, p1: CGPoint(x: 300, y: 50), p2: .zero, style: s)
        counter.number = 7
        counter.shape = .bubble
        counter.tailAngle = 1.2
        let arrow = Annotation(kind: .arrow, p1: CGPoint(x: 10, y: 10), p2: CGPoint(x: 200, y: 150), style: s)
        return [text, callout, counter, arrow]
    }

    func encode(_ img: CGImage, _ type: UTType) -> Data {
        let d = NSMutableData()
        let dest = CGImageDestinationCreateWithData(d, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        return d as Data
    }

    @Test("PNG keeps every object, the original image and the backdrop", arguments: [UTType.png, UTType.jpeg])
    func roundTrip(type: UTType) throws {
        let url = tempDir().appendingPathComponent(type == .png ? "a.png" : "a.jpg")
        var sunset = Backdrop()
        sunset.isOn = true
        sunset.colors = ["#FA709A", "#FEE140"]
        sunset.fill = .mesh
        sunset.aspect = .r16x9
        sunset.offset = CGPoint(x: 0.5, y: -1)
        let state = EditState(scale: 2, backdrop: sunset, objects: objects())
        try EditableFile.write(rendered: encode(base, type), type: type, state: state, base: base, to: url)
        let loaded = try #require(EditableFile.load(url))
        let back = try #require(loaded.state)
        #expect(back.backdrop == sunset && loaded.scale == 2)
        #expect(back.objects.map(\.id) == state.objects.map(\.id))
        #expect(back.objects[0].runs == state.objects[0].runs && back.objects[0].text == "Hola")
        #expect(back.objects[1].calloutStyle == .shout && back.objects[1].pointer == CGPoint(x: 30, y: 250))
        #expect(back.objects[2].number == 7 && back.objects[2].shape == .bubble && back.objects[2].tailAngle == 1.2)
        #expect(loaded.image.width == 400 && loaded.image.height == 300)
        #expect(NSImage(contentsOf: url) != nil, "other apps can still open the file")
    }

    @Test("saving twice replaces the edit data instead of adding a second copy")
    func saveTwice() throws {
        let url = tempDir().appendingPathComponent("twice.png")
        let state = EditState(scale: 1, backdrop: .none, objects: objects())
        try EditableFile.write(rendered: encode(base, .png), type: .png, state: state, base: base, to: url)
        try EditableFile.write(rendered: encode(base, .png), type: .png, state: state, base: base, to: url)
        let data = try Data(contentsOf: url)
        #expect(data.ranges(of: Data("scED".utf8)).isEmpty, "the file carries only what it shows")
        #expect(EditableFile.load(url)?.state?.objects.count == 4)
    }

    @Test("a JPEG changed by another app does not bring back stale annotations")
    func staleJPEG() throws {
        let url = tempDir().appendingPathComponent("stale.jpg")
        try EditableFile.write(rendered: encode(base, .jpeg), type: .jpeg,
                               state: EditState(scale: 1, backdrop: .none, objects: objects()), base: base, to: url)
        #expect(EditableFile.load(url)?.state != nil)
        try (encode(solid(400, 300, 0xFF0000), .jpeg)).write(to: url)
        #expect(EditableFile.load(url)?.state == nil)
    }

    @Test("a plain image opens without edits, and no edits means no edit data")
    func plain() throws {
        let url = tempDir().appendingPathComponent("plain.png")
        try EditableFile.write(rendered: encode(base, .png), type: .png, state: EditState(scale: 1, backdrop: .none, objects: []), base: base, to: url)
        #expect(EditableFile.load(url)?.state == nil)
        #expect(EditableFile.hasEdits(url) == false)
    }
}

@Suite("Hardening", .serialized)
@MainActor struct HardeningTests {
    let base = solid(200, 100, 0x3366CC)

    func png(_ img: CGImage) -> Data { Exporter.encode(img, scale: 1, type: .png)! }
    func arrow(to p: CGPoint = CGPoint(x: 50, y: 50), kind: Tool = .arrow) -> Annotation {
        Annotation(kind: kind, p1: .zero, p2: p, color: .red, width: 4)
    }
    /// A PNG as older versions saved it: the edit data in a chunk before IEND.
    func legacyPNG(_ state: EditState) throws -> Data {
        var rendered = png(base)
        let payload = try #require(EditableFile.payload(state: state, base: base))
        var chunk = Data([UInt8(payload.count >> 24 & 0xFF), UInt8(payload.count >> 16 & 0xFF), UInt8(payload.count >> 8 & 0xFF), UInt8(payload.count & 0xFF)])
        chunk.append(Data("scED".utf8)); chunk.append(payload); chunk.append(Data([0, 0, 0, 0]))
        let iend = try #require(rendered.range(of: Data("IEND".utf8), options: .backwards))
        rendered.insert(contentsOf: chunk, at: iend.lowerBound - 4)
        return rendered
    }
    func withSaveFolder(_ body: (URL) throws -> Void) rethrows {
        let d = tempDir()
        UserDefaults.standard.set(d.path, forKey: Keys.saveFolder)
        defer { UserDefaults.standard.removeObject(forKey: Keys.saveFolder) }
        try body(d)
    }

    @Test("a shared file holds nothing of what a blur hides, and the app still restores it")
    func redaction() throws {
        // Unique stripes, so the original is recognizable and no other test shares the entry.
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        ctx.setFillColor(.black)
        for x in stride(from: 0, to: 400, by: 4) { ctx.fill(CGRect(x: x, y: 0, width: 2, height: 200)) }
        let secret = ctx.makeImage()!
        let doc = EditorDocument(image: secret, scale: 1)
        doc.objects = [arrow(to: CGPoint(x: 400, y: 200), kind: .blur)]
        let url = tempDir().appendingPathComponent("shared.png")
        Exporter.saveEditable(doc, rendered: try #require(doc.render()), to: url, quiet: true)
        let bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data("scED".utf8)) == nil && bytes.range(of: Data("SCREENSHOT-EDIT1".utf8)) == nil)
        #expect(!FileManager.default.fileExists(atPath: EditableFile.sidecarURL(for: url).path))
        #expect(CGImageSourceGetCount(CGImageSourceCreateWithData(bytes as CFData, nil)!) == 1)
        let loaded = try #require(EditableFile.load(url))
        #expect(loaded.state?.objects.count == 1, "editing still works on this Mac")
        #expect(PixelReader(loaded.image).color(1, 50)?.hexString == PixelReader(secret).color(1, 50)?.hexString)
    }

    @Test("store entries are private to the user, follow a rename and go when the file goes")
    func store() throws {
        let dir = tempDir(), url = dir.appendingPathComponent("a.png"), moved = dir.appendingPathComponent("b.png")
        let img = solid(120, 80, 0x123456)
        try EditableFile.write(rendered: png(img), type: .png, state: EditState(scale: 1, backdrop: .none, objects: [arrow()]), base: img, to: url)
        let entries = { (try? FileManager.default.contentsOfDirectory(at: EditableFile.storeDirectory, includingPropertiesForKeys: nil)) ?? [] }
        let before = entries().count
        for e in entries() {
            let mode = try FileManager.default.attributesOfItem(atPath: e.path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
        }
        try FileManager.default.copyItem(at: url, to: moved)
        #expect(EditableFile.load(moved)?.state != nil)
        #expect(EditableFile.hasEdits(url))
        try FileManager.default.removeItem(at: url)
        EditableFile.sweepStore()
        #expect(entries().count < before)
    }

    @Test("a file from an older version loses its chunk, keeps its pixels and stays editable")
    func migration() throws {
        let dir = tempDir(), url = dir.appendingPathComponent("old.png")
        try legacyPNG(EditState(scale: 2, backdrop: .none, objects: [arrow(), arrow()])).write(to: url)
        #expect(EditableFile.hasLegacyChunk(url))
        #expect(EditableFile.load(url)?.state?.objects.count == 2, "still opens before moving")
        EditableFile.migrateLegacyFiles(in: dir)
        #expect(!EditableFile.hasLegacyChunk(url))
        let bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data("SCREENSHOT-EDIT1".utf8)) == nil && bytes == png(base))
        #expect(EditableFile.load(url)?.state?.objects.count == 2)
    }

    @Test("saving over a GIF leaves it alone and makes a PNG beside it", arguments: ["gif", "heic", "tiff"])
    func otherFormats(ext: String) throws {
        let url = tempDir().appendingPathComponent("anim.\(ext)")
        let original = Data("original bytes".utf8)
        try original.write(to: url)
        let doc = EditorDocument(image: base, scale: 1)
        doc.fileURL = url
        doc.objects = [arrow()]
        let rendered = try #require(doc.render())
        let saved = try #require(Exporter.saveEditable(doc, rendered: rendered, quiet: true))
        #expect(try Data(contentsOf: url) == original)
        #expect(saved.lastPathComponent == "anim edited.png" && doc.fileURL == saved)
        #expect(FileManager.default.fileExists(atPath: saved.path))
    }

    @Test("two captures in the same second both stay")
    func sameSecond() throws {
        try withSaveFolder { dir in
            let a = try #require(Exporter.save(solid(10, 10, 0xFF0000), scale: 1, quiet: true))
            let b = try #require(Exporter.save(solid(10, 10, 0x00FF00), scale: 1, quiet: true))
            #expect(a != b)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 2)
            let c = Exporter.unusedURL(in: dir, ext: "png"), d = Exporter.unusedURL(in: dir, ext: "png")
            #expect(c != d, "a name handed out isn't given again before its file exists")
        }
    }

    @Test("quitting writes a capture that never had a file, with its latest edit")
    func quit() throws {
        _ = NSApplication.shared
        try withSaveFolder { dir in
            let ed = EditorWindowController(image: base, scale: 1)
            ed.doc.objects = [arrow()]
            ed.doc.revision += 1
            ed.scheduleAutosave()
            ed.saveForQuit()
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            #expect(files.count == 1)
            let file = try #require(files.first)
            #expect(EditableFile.load(file)?.state?.objects.count == 1)
        }
    }

    @Test("a manual save isn't overwritten by an older auto-save still in the queue")
    func saveOrder() throws {
        let url = tempDir().appendingPathComponent("order.png")
        let older = solid(30, 30, 0xFF0000), newer = solid(30, 30, 0x00FF00)
        let gate = DispatchSemaphore(value: 0)
        EditableFile.ioQueue.async { gate.wait() }
        let olderData = png(older)
        EditableFile.ioQueue.async { try? olderData.write(to: url) }
        let doc = EditorDocument(image: newer, scale: 1)
        doc.fileURL = url
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { gate.signal() }
        Exporter.saveEditable(doc, rendered: newer, quiet: true)
        EditableFile.ioQueue.sync {}
        let back = try #require(EditableFile.load(url))
        #expect(PixelReader(back.image).color(1, 1)?.hexString == "#00FF00")
    }

    @Test("values no drawing can use are repaired on load instead of crashing")
    func hostileFile() throws {
        var pad = Backdrop(); pad.isOn = true; pad.padding = 1e300; pad.offset = CGPoint(x: 1e300, y: -1e300)
        var run = arrow(); run.text = "hi"; run.runs = [TextRun(location: 50, length: 500, color: "#000000FF", size: 1e300, font: .sans)]
        let state = EditState(scale: 0, backdrop: pad, objects: [arrow(to: CGPoint(x: 1e300, y: 1e300)), arrow(), run])
        let url = tempDir().appendingPathComponent("hostile.png")
        try legacyPNG(state).write(to: url)
        let loaded = try #require(EditableFile.load(url))
        let s = try #require(loaded.state)
        #expect(s.scale == 1 && loaded.scale == 1)
        #expect(s.objects.count == 2, "the far-away object is dropped")
        #expect(s.objects[1].runs?.isEmpty == true)
        #expect(s.backdrop.padding <= 2 && abs(s.backdrop.offset.x) <= 1)
        let doc = EditorWindowController.makeDocument(image: loaded.image, scale: loaded.scale, state: s, url: url)
        #expect(doc.render() != nil)
    }

    @Test("garbage and truncated files are refused without a crash")
    func corrupt() throws {
        let good = try legacyPNG(EditState(scale: 1, backdrop: .none, objects: [arrow()]))
        for cut in stride(from: 0, to: good.count, by: max(1, good.count / 40)) {
            let url = tempDir().appendingPathComponent("cut.png")
            try good.prefix(cut).write(to: url)
            _ = EditableFile.load(url)
            _ = EditableFile.hasEdits(url)
        }
        var flipped = good
        if let m = flipped.range(of: Data("SCREENSHOT-EDIT1".utf8)) { flipped[m.upperBound] = 0xFF; flipped[m.upperBound + 1] = 0xFF }
        let url = tempDir().appendingPathComponent("len.png")
        try flipped.write(to: url)
        #expect(EditableFile.load(url)?.state == nil, "an impossible length isn't believed")
    }

    @Test("a canvas too large to allocate fails the render instead of crashing")
    func hugeCanvas() {
        let doc = EditorDocument(image: base, scale: 1)
        doc.objects = [arrow(to: CGPoint(x: 1e300, y: 1e300))]
        #expect(doc.render() == nil)
    }

    @Test("an image whose header asks for too many pixels is refused before decoding")
    func pixelLimit() {
        #expect(!ImageLimits.allows(width: 60_000, height: 60_000))
        #expect(!ImageLimits.allows(width: .infinity, height: 1))
        #expect(ImageLimits.allows(width: 6_000, height: 50_000))
    }

    @Test("an owned copy keeps the pixels and lets the source go")
    func ownedCopy() throws {
        weak var weakSource: CGImage?
        var kept: CGImage?
        autoreleasepool {
            let source = solid(300, 300, 0xFF0000)
            weakSource = source
            kept = source.cropping(to: CGRect(x: 0, y: 0, width: 10, height: 10))?.ownedCopy()
        }
        #expect(kept?.width == 10)
        #expect(PixelReader(try #require(kept)).color(5, 5)?.hexString == "#FF0000")
        #expect(weakSource == nil)
    }

    @Test("the undo history stays in budget, keeping its last step")
    func undoBudget() {
        let doc = EditorDocument(image: base, scale: 1)
        for _ in 0..<20 { doc.undoStack.append(.init(image: solid(1000, 1000, 0x112233), objects: [], backdrop: .none)) }
        doc.trimUndo(budget: 10 * 1000 * 1000)
        #expect(doc.undoStack.count == 2 || doc.undoStack.count == 3)
        doc.trimUndo(budget: 0)
        #expect(doc.undoStack.count == 1)
    }

    @Test("the PNG cache holds to its size limits and can be emptied")
    func pngCache() {
        for i in 0..<12 { _ = BasePNGCache.shared.png(for: solid(4, 4, UInt32(i))) }
        #expect(BasePNGCache.shared.entryCount <= 8)
        BasePNGCache.shared.clear()
        #expect(BasePNGCache.shared.entryCount == 0)
    }

    @Test("a document kept for a return visit is dropped when its file changes or goes")
    func staleDocument() throws {
        let url = tempDir().appendingPathComponent("v.png")
        try png(base).write(to: url)
        let doc = EditorWindowController.makeDocument(image: base, scale: 1, state: nil, url: url)
        #expect(doc.fileMatchesLastWrite)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -500)], ofItemAtPath: url.path)
        #expect(!doc.fileMatchesLastWrite)
        doc.noteFileWritten()
        try FileManager.default.removeItem(at: url)
        #expect(!doc.fileMatchesLastWrite)
    }

    @Test("links can't take screenshots until they are turned on")
    func linksOff() {
        UserDefaults.standard.removeObject(forKey: Keys.urlScheme)
        Settings.registerDefaults()
        #expect(!Settings.urlSchemeEnabled)
    }

    @Test("drag files are the owner's, in one folder that gets emptied")
    func dragFiles() throws {
        let url = try #require(Exporter.dragFile(Data("x".utf8)))
        #expect(url.deletingLastPathComponent().lastPathComponent == "ScreenShot-Drag")
        Exporter.clearDragFolder(olderThan: 3600)
        #expect(FileManager.default.fileExists(atPath: url.path), "a drop may still be reading it")
        Exporter.clearDragFolder()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("memory pressure keeps only the open document, and its edit reaches the file")
    func memoryPressure() throws {
        _ = NSApplication.shared
        let dir = tempDir()
        let first = dir.appendingPathComponent("first.png"), second = dir.appendingPathComponent("second.png")
        let picture = try #require(NSBitmapImageRep(cgImage: solid(40, 40, 0x336699)).representation(using: .png, properties: [:]))
        try picture.write(to: first)
        try picture.write(to: second)

        let ed = EditorWindowController(image: solid(40, 40, 0x336699), scale: 1, url: first)
        ed.switchTo(second)
        #expect(ed.visitedCount == 1, "the first document is kept for a return visit")
        _ = BasePNGCache.shared.png(for: solid(4, 4, 0x112233))
        ed.doc.objects = [Annotation(kind: .arrow, p1: CGPoint(x: 1, y: 1), p2: CGPoint(x: 30, y: 30), style: ToolStyle())]
        ed.doc.revision += 1
        ed.scheduleAutosave()

        AppLogic.shared.releaseMemory(in: ed)
        EditableFile.ioQueue.sync {}

        #expect(ed.visitedCount == 0)
        #expect(BasePNGCache.shared.entryCount == 0)
        #expect(ed.doc.fileURL?.standardizedFileURL == second.standardizedFileURL)
        #expect(ed.doc.objects.count == 1, "the open document stays as it was")
        #expect(EditableFile.load(second)?.state?.objects.count == 1, "the pending edit was written first")
    }

    @Test("crash reports from macOS are written to the log folder")
    func crashReports() throws {
        let folder = tempDir().appendingPathComponent("Logs/ScreenShot", isDirectory: true)
        CrashReports.shared.save([(stamp: 100, json: Data("{\"a\":1}".utf8)), (stamp: 100, json: Data("{\"b\":2}".utf8))], to: folder)
        #expect(try Data(contentsOf: folder.appendingPathComponent("diagnostic-100-0.json")) == Data("{\"a\":1}".utf8))
        #expect(try Data(contentsOf: folder.appendingPathComponent("diagnostic-100-1.json")) == Data("{\"b\":2}".utf8))
    }
}

@Suite("Search index privacy", .serialized)
struct TextIndexPrivacyTests {
    @Test("deleting a screenshot deletes what was read from it, and the index is private")
    func prune() throws {
        let dir = tempDir(), json = dir.appendingPathComponent("index.json"), image = dir.appendingPathComponent("a.png")
        try Data("x".utf8).write(to: image)
        let entries = [TextIndex.key(image): TextIndex.Entry(modified: Date(), text: "password123"), "/nonexistent/b.png": TextIndex.Entry(modified: Date(), text: "secret")]
        try JSONEncoder().encode(entries).write(to: json)
        let idx = TextIndex(file: json)
        idx.prune()
        #expect(idx.text(for: image) == "password123")
        let saved = try String(decoding: Data(contentsOf: json), as: UTF8.self)
        #expect(!saved.contains("secret"))
        let mode = try FileManager.default.attributesOfItem(atPath: json.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        idx.clear()
        #expect(idx.text(for: image) == nil && !FileManager.default.fileExists(atPath: json.path))
    }
}
