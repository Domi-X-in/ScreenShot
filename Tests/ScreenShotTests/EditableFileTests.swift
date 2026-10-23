import AppKit
import Testing
import UniformTypeIdentifiers
@testable import ScreenShotKit

@Suite("Editable saves")
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
        #expect(data.ranges(of: Data("scED".utf8)).count == 1)
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
