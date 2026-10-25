import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Text features (R6)")
struct TextFeaturesTests {
    private func text(_ s: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: s, attributes: [.font: TextFormatting.font(family: "Helvetica Neue", size: 12, bold: false, italic: false),
                                                          .foregroundColor: NSColor.black])
    }
    private func state(_ m: NSAttributedString, _ r: NSRange) -> TextFormatState {
        TextFormatting.state(of: m, selection: r, typing: m.length > 0 ? m.attributes(at: 0, effectiveRange: nil) : [:], scale: 1, defaultAlign: .left)
    }
    private func apply(_ c: FormatChange, _ m: NSMutableAttributedString, _ r: NSRange) {
        var typing: [NSAttributedString.Key: Any] = [:]
        TextFormatting.apply(c, to: m, selection: r, typing: &typing, scale: 1, defaultAlign: .left)
    }
    private func rewrite(_ c: FormatChange, _ m: NSMutableAttributedString, _ r: NSRange, force: Bool? = nil) -> NSRange {
        guard let out = TextFormatting.rewrite(c, in: m, selection: r, force: force) else { return r }
        m.replaceCharacters(in: out.range, with: out.text)
        return out.selection
    }

    @Test("Strikethrough toggles like Underline")
    func strikethrough() {
        let m = text("Hello world")
        let hello = NSRange(location: 0, length: 5)
        apply(.strikethrough, m, hello)
        #expect(state(m, hello).strikethrough && !state(m, NSRange(location: 0, length: m.length)).strikethrough)
        apply(.strikethrough, m, hello)
        #expect(!state(m, hello).strikethrough)
    }

    @Test("Font Outline sets a colored outline and No Outline removes it")
    func outline() {
        let m = text("Outlined")
        let all = NSRange(location: 0, length: m.length)
        apply(.outline(NSColor(hex: 0xFF5500)), m, all)
        #expect(state(m, all).outline?.hexString == "#FF5500")
        #expect((m.attribute(.strokeWidth, at: 0, effectiveRange: nil) as? CGFloat) == TextFormatting.outlineWidth, "the fill stays (negative width)")
        apply(.outline(nil), m, all)
        #expect(state(m, all).outline == nil && m.attribute(.strokeColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test("Justify is a paragraph alignment and round-trips through NSTextAlignment")
    func justify() {
        let m = text("A line\nAnother")
        apply(.alignment(.justified), m, NSRange(location: 0, length: 2))
        #expect(state(m, NSRange(location: 0, length: 1)).alignment == .justified)
        let second = TextFormatting.state(of: m, selection: NSRange(location: 8, length: 1), typing: [:], scale: 1, defaultAlign: .left)
        #expect(second.alignment == .left, "only the paragraph touched")
        #expect(TextAlign(NSTextAlignment.justified) == .justified && TextAlign.justified.ns == .justified)
    }

    @Test("Change Case: the five styles", arguments: [
        (TextCase.sentence, "hello WORLD. new day", "Hello world. New day"),
        (.lower, "Hello WORLD", "hello world"),
        (.upper, "Hello world", "HELLO WORLD"),
        (.capitalized, "hello big world", "Hello Big World"),
        (.toggle, "Hello World", "hELLO wORLD"),
    ])
    func cases(_ c: TextCase, _ input: String, _ expected: String) {
        #expect(c.apply(input) == expected)
    }

    @Test("Change Case keeps each letter's format, and works on the word at the caret")
    func caseKeepsFormat() {
        let m = text("hello world")
        apply(.bold, m, NSRange(location: 0, length: 5))
        let sel = rewrite(.textCase(.upper), m, NSRange(location: 0, length: m.length))
        #expect(m.string == "HELLO WORLD" && sel.length == 11)
        #expect(state(m, NSRange(location: 0, length: 5)).bold && !state(m, NSRange(location: 6, length: 5)).bold)
        let caret = rewrite(.textCase(.lower), m, NSRange(location: 8, length: 0))
        #expect(m.string == "HELLO world" && caret == NSRange(location: 8, length: 0))
    }

    @Test("Bullets add a marker to every paragraph touched and come off when all have one")
    func bullets() {
        let m = text("One\nTwo\nThree")
        var sel = rewrite(.bullets, m, NSRange(location: 0, length: m.length))
        #expect(m.string == "• One\n• Two\n• Three")
        #expect(state(m, sel).bullets)
        sel = rewrite(.bullets, m, sel)
        #expect(m.string == "One\nTwo\nThree")
        // A caret in the second paragraph: only that one, and the caret moves with its text.
        let caret = rewrite(.bullets, m, NSRange(location: 5, length: 0))
        #expect(m.string == "One\n• Two\nThree" && caret.location == 7)
    }

    @Test("Numbering counts the paragraphs and replaces bullets")
    func numbering() {
        let m = text("• One\nTwo\nThree")
        let sel = rewrite(.numbering, m, NSRange(location: 0, length: m.length))
        #expect(m.string == "1. One\n2. Two\n3. Three")
        #expect(state(m, sel).numbered && !state(m, sel).bullets)
        _ = rewrite(.numbering, m, sel)
        #expect(m.string == "One\nTwo\nThree")
        #expect(TextFormatting.numberPrefix("12. x") == "12. " && TextFormatting.numberPrefix("2026 was") == nil)
    }

    @Test("Strikethrough and Font Outline are kept with the annotation (saved and reopened)")
    func persisted() throws {
        let m = text("Saved text")
        let all = NSRange(location: 0, length: m.length)
        apply(.strikethrough, m, NSRange(location: 0, length: 5))
        apply(.outline(NSColor(hex: 0x007AFF)), m, NSRange(location: 6, length: 4))
        var a = Annotation(kind: .text, p1: .zero, p2: .zero, style: ToolStyle())
        a.setText(from: m, scale: 1)
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(Annotation.self, from: data)
        let shown = back.attributedText()
        #expect(state(shown, NSRange(location: 0, length: 5)).strikethrough)
        #expect(state(shown, NSRange(location: 6, length: 4)).outline?.hexString == "#007AFF")
        #expect(!state(shown, all).strikethrough)
    }
}
