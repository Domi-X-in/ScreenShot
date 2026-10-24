import AppKit

/// Paragraph alignment. Justify can join later as one more case (and one more toolbar button).
enum TextAlign: String, Codable, CaseIterable {
    case left, center, right

    var ns: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }

    init?(_ ns: NSTextAlignment) {
        switch ns {
        case .left, .natural: self = .left
        case .center: self = .center
        case .right: self = .right
        default: return nil
        }
    }
}

/// Where the text sits inside a fixed-size container (a rectangle or oval).
enum VerticalAlign: String, Codable, CaseIterable {
    case top, middle, bottom
}

/// Word's Text Direction.
enum TextOrientation: String, Codable, CaseIterable {
    case horizontal, rotate90, rotate270, stacked

    var title: String {
        switch self {
        case .horizontal: "Horizontal"
        case .rotate90: "Rotate all text 90°"
        case .rotate270: "Rotate all text 270°"
        case .stacked: "Stacked"
        }
    }

    /// Clockwise turn in a top-left-origin (flipped) context.
    var rotation: CGFloat {
        switch self {
        case .rotate90: .pi / 2
        case .rotate270: -.pi / 2
        default: 0
        }
    }

    var isRotated: Bool { self == .rotate90 || self == .rotate270 }
}

/// What the formatting toolbar shows. Like Word, a nil value means the selection is mixed (the control shows blank),
/// and a toggle is on only when the whole selection has that format.
struct TextFormatState: Equatable {
    var isActive = false
    var family: String?
    var size: CGFloat?
    var bold = false
    var italic = false
    var underline = false
    var alignment: TextAlign?
    var verticalAlign: VerticalAlign?
    var orientation: TextOrientation?
    /// Vertical alignment and orientation only mean something for containers with a fixed size.
    var supportsVerticalAlign = false
    var supportsOrientation = false

    static let inactive = TextFormatState()
}

/// One formatting command, as the toolbar and the keyboard shortcuts send it.
enum FormatChange: Equatable {
    case family(String)
    case size(CGFloat)
    case grow, shrink
    /// ⌘] / ⌘[: one point up or down.
    case step(CGFloat)
    case bold, italic, underline
    case alignment(TextAlign)
    case verticalAlign(VerticalAlign)
    case orientation(TextOrientation)

    var isContainer: Bool {
        switch self {
        case .verticalAlign, .orientation: true
        default: false
        }
    }

    var isParagraph: Bool {
        if case .alignment = self { return true }
        return false
    }
}

/// The formatting logic, kept apart from any view so it can be tested: reading the format of a selection and applying
/// a change to the letters, the paragraphs, or the pending format at a collapsed caret.
enum TextFormatting {
    /// Word's font size list.
    static let sizePresets: [CGFloat] = [8, 9, 10, 10.5, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72]
    static let systemFamily = "System"

    /// The font menu's list. Set "textFontFamilies" (an array of family names) in the defaults to change it.
    static var families: [String] {
        let wanted = UserDefaults.standard.stringArray(forKey: "textFontFamilies") ?? defaultFamilies
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return wanted.filter { $0 == systemFamily || installed.contains($0) }
    }

    static let defaultFamilies = [systemFamily, "Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Georgia", "Times New Roman",
                                  "Baskerville", "American Typewriter", "Menlo", "Courier New", "Chalkboard SE", "Marker Felt",
                                  "Noteworthy"]

    // MARK: Sizes (Word's Grow Font / Shrink Font)

    /// The next preset up; past 72, the next multiple of 10.
    static func grow(_ s: CGFloat) -> CGFloat {
        if let next = sizePresets.first(where: { $0 > s + 0.01 }) { return next }
        return min(1638, (floor(s / 10) + 1) * 10)
    }

    /// The next preset down; past 72, the previous multiple of 10 (not below 72); under 8, one point at a time.
    static func shrink(_ s: CGFloat) -> CGFloat {
        if s > 72 + 0.01 { return max(72, (ceil(s / 10) - 1) * 10) }
        if let prev = sizePresets.last(where: { $0 < s - 0.01 }) { return prev }
        return max(1, ceil(s) - 1)
    }

    static func sizeLabel(_ s: CGFloat) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%g", Double(s))
    }

    // MARK: Fonts

    static func family(of f: NSFont) -> String {
        let name = f.familyName ?? ""
        return name.isEmpty || name.hasPrefix(".") ? systemFamily : name
    }

    static func isBold(_ f: NSFont) -> Bool {
        if family(of: f) == systemFamily {
            let traits = f.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            return ((traits?[.weight] as? CGFloat) ?? 0) >= NSFont.Weight.bold.rawValue - 0.01
        }
        return NSFontManager.shared.traits(of: f).contains(.boldFontMask)
    }

    static func isItalic(_ f: NSFont) -> Bool { f.fontDescriptor.symbolicTraits.contains(.italic) }

    static func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let fm = NSFontManager.shared
        var f: NSFont
        if family == systemFamily {
            f = .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        } else {
            f = fm.font(withFamily: family, traits: [], weight: 5, size: size) ?? .systemFont(ofSize: size)
            if bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        }
        if italic {
            let italicDescriptor = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(.italic))
            f = NSFont(descriptor: italicDescriptor, size: size) ?? fm.convert(f, toHaveTrait: .italicFontMask)
        }
        return f
    }

    static func changing(_ f: NSFont, family: String? = nil, size: CGFloat? = nil, bold: Bool? = nil, italic: Bool? = nil) -> NSFont {
        font(family: family ?? self.family(of: f), size: size ?? f.pointSize, bold: bold ?? isBold(f), italic: italic ?? isItalic(f))
    }

    // MARK: Reading

    /// Paragraph ranges that a selection (or a caret) touches.
    static func paragraphRanges(in string: NSString, covering range: NSRange) -> [NSRange] {
        guard string.length > 0 else { return [NSRange(location: 0, length: 0)] }
        var out: [NSRange] = []
        // A caret at the very end belongs to the last paragraph.
        var location = min(range.location, string.length - 1)
        let end = max(location + 1, min(NSMaxRange(range), string.length))
        while location < end {
            let p = string.paragraphRange(for: NSRange(location: location, length: 0))
            out.append(p)
            location = NSMaxRange(p)
        }
        return out
    }

    static func alignment(in storage: NSAttributedString, at location: Int, default def: TextAlign) -> TextAlign {
        guard storage.length > 0 else { return def }
        let i = min(max(0, location), storage.length - 1)
        let p = storage.attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle
        return p.flatMap { TextAlign($0.alignment) } ?? def
    }

    /// The format at a selection, Word style: mixed values are nil, toggles are on only when every letter has them.
    /// A collapsed caret reports the pending format (the typing attributes). Sizes are in the text's own units
    /// (`scale` = field points per unit).
    static func state(of storage: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any],
                      scale: CGFloat, defaultAlign: TextAlign) -> TextFormatState {
        var s = TextFormatState()
        s.isActive = true
        var fonts: [NSFont] = []
        var underlines: [Bool] = []
        let sel = NSIntersectionRange(selection, NSRange(location: 0, length: storage.length))
        if selection.length > 0, sel.length > 0 {
            storage.enumerateAttributes(in: sel) { attrs, _, _ in
                if let f = attrs[.font] as? NSFont { fonts.append(f) }
                underlines.append(((attrs[.underlineStyle] as? Int) ?? 0) != 0)
            }
        } else {
            if let f = typing[.font] as? NSFont { fonts.append(f) }
            underlines.append(((typing[.underlineStyle] as? Int) ?? 0) != 0)
        }
        let families = Set(fonts.map(family(of:)))
        let sizes = Set(fonts.map { (($0.pointSize / scale) * 2).rounded() / 2 })
        s.family = families.count == 1 ? families.first : nil
        s.size = sizes.count == 1 ? sizes.first : nil
        s.bold = !fonts.isEmpty && fonts.allSatisfy(isBold)
        s.italic = !fonts.isEmpty && fonts.allSatisfy(isItalic)
        s.underline = !underlines.isEmpty && underlines.allSatisfy { $0 }
        let aligns = Set(paragraphRanges(in: storage.string as NSString, covering: selection).map {
            alignment(in: storage, at: $0.location, default: (typing[.paragraphStyle] as? NSParagraphStyle).flatMap { TextAlign($0.alignment) } ?? defaultAlign)
        })
        s.alignment = aligns.count == 1 ? aligns.first : nil
        if storage.length == 0 {
            s.alignment = (typing[.paragraphStyle] as? NSParagraphStyle).flatMap { TextAlign($0.alignment) } ?? defaultAlign
        }
        return s
    }

    // MARK: Applying

    /// Applies a character or paragraph change. With a selection, character formatting goes to the selected letters;
    /// with a collapsed caret it becomes the pending format for what is typed next (`typing`). Alignment goes to every
    /// paragraph the selection touches. Container changes aren't handled here (see TextFormattingTarget).
    static func apply(_ change: FormatChange, to storage: NSMutableAttributedString, selection: NSRange,
                      typing: inout [NSAttributedString.Key: Any], scale: CGFloat, defaultAlign: TextAlign) {
        let sel = NSIntersectionRange(selection, NSRange(location: 0, length: storage.length))
        if case let .alignment(a) = change {
            for p in paragraphRanges(in: storage.string as NSString, covering: selection) where p.length > 0 {
                storage.enumerateAttribute(.paragraphStyle, in: p) { value, r, _ in
                    let ps = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                    ps.alignment = a.ns
                    storage.addAttribute(.paragraphStyle, value: ps, range: r)
                }
            }
            let ps = ((typing[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            ps.alignment = a.ns
            typing[.paragraphStyle] = ps
            return
        }
        guard !change.isContainer else { return }

        let current = state(of: storage, selection: selection, typing: typing, scale: scale, defaultAlign: defaultAlign)
        /// The new font for one run.
        func transform(_ f: NSFont) -> NSFont {
            let unit = f.pointSize / scale
            switch change {
            case let .family(name): return changing(f, family: name)
            case let .size(v): return changing(f, size: v * scale)
            case .grow: return changing(f, size: grow(unit) * scale)
            case .shrink: return changing(f, size: shrink(unit) * scale)
            case let .step(d): return changing(f, size: max(1, unit + d) * scale)
            case .bold: return changing(f, bold: !current.bold)
            case .italic: return changing(f, italic: !current.italic)
            default: return f
            }
        }
        if selection.length > 0, sel.length > 0 {
            if change == .underline {
                storage.addAttribute(.underlineStyle, value: current.underline ? 0 : NSUnderlineStyle.single.rawValue, range: sel)
            } else {
                storage.enumerateAttribute(.font, in: sel) { value, r, _ in
                    if let f = value as? NSFont { storage.addAttribute(.font, value: transform(f), range: r) }
                }
            }
            // What is typed right after the selection continues its new format.
            let attrs = storage.attributes(at: max(sel.location, NSMaxRange(sel) - 1), effectiveRange: nil)
            for key in [NSAttributedString.Key.font, .underlineStyle] { typing[key] = attrs[key] }
        } else {
            // Collapsed caret: pending format, like Word.
            if change == .underline {
                typing[.underlineStyle] = current.underline ? 0 : NSUnderlineStyle.single.rawValue
            } else if let f = typing[.font] as? NSFont {
                typing[.font] = transform(f)
            }
        }
    }

    /// Each letter on its own line, centered (Word's Stacked text direction).
    static func stacked(_ text: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ns = text.string as NSString
        var i = 0
        while i < ns.length {
            let r = ns.rangeOfComposedCharacterSequence(at: i)
            let ch = text.attributedSubstring(from: r)
            if ch.string != "\n" {
                if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: ch.attributes(at: 0, effectiveRange: nil))) }
                out.append(ch)
            } else if out.length > 0 {
                out.append(NSAttributedString(string: "\n", attributes: ch.attributes(at: 0, effectiveRange: nil)))
            }
            i = NSMaxRange(r)
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        out.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: out.length))
        return out
    }
}
