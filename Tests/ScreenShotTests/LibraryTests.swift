import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Library")
struct LibraryTests {
    private let item = LibraryItem(url: URL(fileURLWithPath: "/tmp/ScreenShot 2026-10-21 at 15.37.33.png"),
                                   date: ISO8601DateFormatter().date(from: "2026-10-21T15:37:33Z")!)

    @Test("search matches the name, the date and the text, every word")
    func matching() {
        #expect(item.matches("", text: nil))
        #expect(item.matches("15.37", text: nil))
        #expect(item.matches("2026-10-21", text: nil))
        #expect(item.matches("october", text: nil))
        #expect(item.matches("invoice paid", text: "Invoice 4821 · PAID"))
        #expect(!item.matches("invoice refund", text: "Invoice 4821 · PAID"))
    }

    @Test("lists images only, newest first")
    func listing() throws {
        let dir = tempDir()
        for (name, offset) in [("old.png", -100.0), ("new.jpg", 0), ("notes.txt", 50)] {
            let u = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: u)
            try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(offset)], ofItemAtPath: u.path)
        }
        #expect(LibraryItem.list(in: dir).map(\.url.lastPathComponent) == ["new.jpg", "old.png"])
    }

    @Test("the text index reads a screenshot's text and keeps it on disk")
    @MainActor func textIndex() async throws {
        let dir = tempDir()
        let img = makeImage(900, 160) { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 160))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            ("Quarterly report 2026" as NSString).draw(at: CGPoint(x: 20, y: 50),
                                                       withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
        }
        let url = dir.appendingPathComponent("shot.png")
        let rep = NSBitmapImageRep(cgImage: img)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        let indexFile = dir.appendingPathComponent("index.json")
        let index = TextIndex(file: indexFile)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            index.onUpdate = { done.resume() }
            index.indexInBackground([url])
        }
        #expect(index.text(for: url)?.lowercased().contains("quarterly") == true, "got \(index.text(for: url) ?? "nil")")
        #expect(TextIndex(file: indexFile).text(for: url) == index.text(for: url), "reloaded from disk")
    }
}

@Suite("Library index queue")
struct LibraryIndexQueueTests {
    @Test("a screenshot added while indexing is running still gets read")
    @MainActor func queued() async throws {
        let dir = tempDir()
        func shot(_ name: String, _ text: String) throws -> URL {
            let img = makeImage(900, 160) { ctx in
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 160))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                (text as NSString).draw(at: CGPoint(x: 20, y: 50), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
                NSGraphicsContext.restoreGraphicsState()
            }
            let url = dir.appendingPathComponent(name)
            try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url)
            return url
        }
        let first = try (0..<4).map { try shot("old-\($0).png", "Archive item \($0)") }
        let index = TextIndex(file: dir.appendingPathComponent("index.json"))
        index.indexInBackground(first)
        let late = try shot("new.png", "Boarding pass gate 42")
        index.indexInBackground(first + [late]) // arrives while the first pass is still running
        for _ in 0..<160 where !(first + [late]).allSatisfy({ index.text(for: $0) != nil }) { try await Task.sleep(for: .milliseconds(250)) }
        #expect(index.text(for: late)?.lowercased().contains("boarding") == true, "got \(index.text(for: late) ?? "nil")")
        #expect(first.allSatisfy { index.text(for: $0) != nil }, "the earlier files are read too")
    }
}
