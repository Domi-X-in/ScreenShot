import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Text formatting")
struct FormattingTests {
    private func text(_ s: String, family: String = "Helvetica Neue", size: CGFloat = 12) -> NSMutableAttributedString {
        NSMutableAttributedString(string: s, attributes: [.font: TextFormatting.font(family: family, size: size, bold: false, italic: false)])
    }
    private func fonts(_ m: NSAttributedString, _ r: NSRange) -> [NSFont] {
        var out: [NSFont] = []
        m.enumerateAttribute(.font, in: r) { v, _, _ in if let f = v as? NSFont { out.append(f) } }
        return out
    }
    private func state(_ m: NSAttributedString, _ r: NSRange, typing: [NSAttributedString.Key: Any] = [:]) -> TextFormatState {
        TextFormatting.state(of: m, selection: r, typing: typing, scale: 1, defaultAlign: .left)
    }

    @Test("Grow and Shrink step through Word's size list, by tens past 72 and by one under 8")
    func stepping() {
        let up: [(CGFloat, CGFloat)] = [(8, 9), (10, 10.5), (10.5, 11), (11, 12), (12, 14), (13.5, 14), (28, 36), (48, 72), (72, 80), (80, 90), (95, 100)]
        for (a, b) in up { #expect(TextFormatting.grow(a) == b, "grow \(a)") }
        let down: [(CGFloat, CGFloat)] = [(14, 12), (13.5, 12), (11, 10.5), (9, 8), (8, 7), (7, 6), (1, 1), (80, 72), (90, 80), (95, 90), (36, 28)]
        for (a, b) in down { #expect(TextFormatting.shrink(a) == b, "shrink \(a)") }
    }

    @Test("Bold toggles on for the selection, and off when all of it is already bold")
    func boldToggle() {
        let m = text("Hello world")
        let all = NSRange(location: 0, length: m.length)
        var typing: [NSAttributedString.Key: Any] = [:]
        TextFormatting.apply(.bold, to: m, selection: all, typing: &typing, scale: 1, defaultAlign: .left)
        #expect(fonts(m, all).allSatisfy(TextFormatting.isBold))
        #expect(state(m, all).bold)
        TextFormatting.apply(.bold, to: m, selection: all, typing: &typing, scale: 1, defaultAlign: .left)
        #expect(!fonts(m, all).contains(where: TextFormatting.isBold))
    }

    @Test("a partly bold selection shows Bold off, and Bold makes all of it bold (like Word)")
    func mixedBold() {
        let m = text("Hello world")
        var typing: [NSAttributedString.Key: Any] = [:]
        TextFormatting.apply(.bold, to: m, selection: NSRange(location: 0, length: 5), typing: &typing, scale: 1, defaultAlign: .left)
        let all = NSRange(location: 0, length: m.length)
        #expect(!state(m, all).bold, "mixed shows off")
        #expect(state(m, NSRange(location: 0, length: 5)).bold)
        TextFormatting.apply(.bold, to: m, selection: all, typing: &typing, scale: 1, defaultAlign: .left)
        #expect(fonts(m, all).allSatisfy(TextFormatting.isBold))
    }

    @Test("mixed fonts and sizes show blank; one font and size show them")
    func mixedState() {
        let m = text("Hello world", family: "Georgia", size: 12)
        var typing: [NSAttributedString.Key: Any] = [:]
        TextFormatting.apply(.size(18), to: m, selection: NSRange(location: 6, length: 5), typing: &typing, scale: 1, defaultAlign: .left)
        TextFormatting.apply(.family("Menlo"), to: m, selection: NSRange(location: 0, length: 5), typing: &typing, scale: 1, defaultAlign: .left)
        let all = state(m, NSRange(location: 0, length: m.length))
        #expect(all.family == nil && all.size == nil)
        let world = state(m, NSRange(location: 6, length: 5))
        #expect(world.family == "Georgia" && world.size == 18)
        #expect(state(m, NSRange(location: 0, length: 5)).family == "Menlo")
    }

    @Test("with a collapsed caret, formatting becomes the pending format for the next letters")
    func pending() {
        let m = text("Hello")
        let caret = NSRange(location: 5, length: 0)
        var typing = m.attributes(at: 4, effectiveRange: nil)
        TextFormatting.apply(.bold, to: m, selection: caret, typing: &typing, scale: 1, defaultAlign: .left)
        TextFormatting.apply(.underline, to: m, selection: caret, typing: &typing, scale: 1, defaultAlign: .left)
        TextFormatting.apply(.size(24), to: m, selection: caret, typing: &typing, scale: 1, defaultAlign: .left)
        #expect(!fonts(m, NSRange(location: 0, length: 5)).contains(where: TextFormatting.isBold), "the existing text is untouched")
        let s = state(m, caret, typing: typing)
        #expect(s.bold && s.underline && s.size == 24, "the toolbar shows the pending format")
        m.append(NSAttributedString(string: "!", attributes: typing)) // typing a letter
        let bang = state(m, NSRange(location: 5, length: 1))
        #expect(bang.bold && bang.underline && bang.size == 24)
    }

    @Test("Grow Font on a mixed selection steps each size")
    func growMixed() {
        let m = text("ab")
        var typing: [NSAttributedString.Key: Any] = [:]
        TextFormatting.apply(.size(10), to: m, selection: NSRange(location: 0, length: 1), typing: &typing, scale: 1, defaultAlign: .left)
        TextFormatting.apply(.grow, to: m, selection: NSRange(location: 0, length: 2), typing: &typing, scale: 1, defaultAlign: .left)
        #expect(fonts(m, NSRange(location: 0, length: 2)).map(\.pointSize) == [10.5, 14])
        TextFormatting.apply(.step(-1), to: m, selection: NSRange(location: 0, length: 2), typing: &typing, scale: 1, defaultAlign: .left)
        #expect(fonts(m, NSRange(location: 0, length: 2)).map(\.pointSize) == [9.5, 13])
    }

    @Test("alignment goes to the paragraphs the selection touches")
    func paragraphs() {
        let m = text("one\ntwo\nthree")
        var typing: [NSAttributedString.Key: Any] = [:]
        TextFormatting.apply(.alignment(.center), to: m, selection: NSRange(location: 5, length: 0), typing: &typing, scale: 1, defaultAlign: .left)
        #expect(TextFormatting.alignment(in: m, at: 0, default: .left) == .left)
        #expect(TextFormatting.alignment(in: m, at: 5, default: .left) == .center)
        #expect(TextFormatting.alignment(in: m, at: 9, default: .left) == .left)
        #expect(state(m, NSRange(location: 0, length: m.length)).alignment == nil, "mixed alignment shows none")
        TextFormatting.apply(.alignment(.right), to: m, selection: NSRange(location: 2, length: 8), typing: &typing, scale: 1, defaultAlign: .left)
        #expect([0, 5, 9].map { TextFormatting.alignment(in: m, at: $0, default: .left) } == [.right, .right, .right])
    }

    @Test("Word's shortcuts map to formatting commands")
    func shortcuts() {
        func ev(_ c: String, _ mods: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                             characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: 0)!
        }
        #expect(FormattingController.change(for: ev("b", .command)) == .bold)
        #expect(FormattingController.change(for: ev("i", .command)) == .italic)
        #expect(FormattingController.change(for: ev("u", .command)) == .underline)
        #expect(FormattingController.change(for: ev("e", .command)) == .alignment(.center))
        #expect(FormattingController.change(for: ev("r", .command)) == .alignment(.right))
        #expect(FormattingController.change(for: ev("l", .command)) == .alignment(.left))
        #expect(FormattingController.change(for: ev(">", [.command, .shift])) == .grow)
        #expect(FormattingController.change(for: ev("<", [.command, .shift])) == .shrink)
        #expect(FormattingController.change(for: ev("]", .command)) == .step(1))
        #expect(FormattingController.change(for: ev("[", .command)) == .step(-1))
        #expect(FormattingController.change(for: ev("s", .command)) == nil, "⌘S stays a menu command")
    }

    @Test("formatting is saved with the object and comes back; files from before still open")
    func persistence() throws {
        var a = Annotation(kind: .rect, p1: .zero, p2: CGPoint(x: 300, y: 200), style: ToolStyle())
        let m = NSMutableAttributedString(string: "Title\nbody", attributes: [.font: TextFormatting.font(family: "Georgia", size: 30, bold: true, italic: true),
                                                                              .foregroundColor: NSColor.black])
        m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 5))
        var typing: [NSAttributedString.Key: Any] = [:]
        TextFormatting.apply(.alignment(.right), to: m, selection: NSRange(location: 7, length: 0), typing: &typing, scale: 1, defaultAlign: .center)
        a.setText(from: m, scale: 1)
        a.verticalAlign = .bottom
        a.orientation = .rotate90
        let back = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(a))
        #expect(back.runs == a.runs && back.paragraphAligns == [.center, .right] && back.verticalAlign == .bottom && back.orientation == .rotate90)
        let run = try #require(back.runs?.first)
        #expect(run.family == "Georgia" && run.bold == true && run.italic == true && run.underline == true && run.size == 30)
        // Rebuilt text has the same fonts.
        let f = back.attributedText().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(f.map(TextFormatting.family(of:)) == "Georgia" && f.map(TextFormatting.isBold) == true && f.map(TextFormatting.isItalic) == true)
        // A run saved before the toolbar existed.
        let old = ##"{"location":0,"length":5,"color":"#FF0000FF","size":24,"font":1}"##
        let legacy = try JSONDecoder().decode(TextRun.self, from: Data(old.utf8))
        #expect(legacy.isPlain && legacy.family == nil && legacy.makeFont(scale: 1).fontName.contains("Chalkboard"))
    }

    @Test("the original Sans and Goofy faces still save as before (no new fields)")
    func legacyFacesStayPlain() {
        var t = Annotation(kind: .text, p1: .zero, p2: .zero, style: ToolStyle())
        let m = NSAttributedString(string: "Hi", attributes: [.font: TextFont.goofy.font(size: 24), .foregroundColor: NSColor.red])
        t.setText(from: m, scale: 1)
        #expect(t.runs == nil && t.font == .goofy && t.width == 4, "stored as the object's own style, like before")
    }

    @Test("Stacked puts each letter on its own line; 90° turns a text box")
    func orientation() {
        #expect(TextFormatting.stacked(NSAttributedString(string: "ABC")).string == "A\nB\nC")
        var t = Annotation(kind: .text, p1: .zero, p2: .zero, style: ToolStyle())
        t.text = "Wide text"
        let flat = t.textSize
        t.orientation = .rotate90
        #expect(abs(t.textSize.width - flat.height) < 0.5 && abs(t.textSize.height - flat.width) < 0.5)
    }
}
