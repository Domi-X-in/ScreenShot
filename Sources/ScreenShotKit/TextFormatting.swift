import AppKit

/// Paragraph alignment (Word's Left, Center, Right and Justify).
enum TextAlign: String, Codable, CaseIterable {
    case left, center, right, justified

    var ns: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        }
    }

    init?(_ ns: NSTextAlignment) {
        switch ns {
        case .left, .natural: self = .left
        case .center: self = .center
        case .right: self = .right
        case .justified: self = .justified
        default: return nil
        }
    }
}

/// Word's Change Case.
enum TextCase: String, CaseIterable {
    case sentence, lower, upper, capitalized, toggle

    var title: String {
        switch self {
        case .sentence: "Sentence case."
        case .lower: "lowercase"
        case .upper: "UPPERCASE"
        case .capitalized: "Capitalize Each Word"
        case .toggle: "tOGGLE cASE"
        }
    }

    func apply(_ s: String) -> String {
        switch self {
        case .lower: return s.lowercased()
        case .upper: return s.uppercased()
        case .capitalized: return s.capitalized
        case .toggle:
            return String(s.map { c -> String in
                let t = String(c)
                return t == t.uppercased() ? t.lowercased() : t.uppercased()
            }.joined())
        case .sentence:
            // Lowercase, then a capital at the start and after . ! ? or a new line.
            var out = ""
            var capitalizeNext = true
            for c in s.lowercased() {
                if capitalizeNext, c.isLetter { out += String(c).uppercased(); capitalizeNext = false; continue }
                out.append(c)
                if ".!?\n".contains(c) { capitalizeNext = true }
            }
            return out
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
    var strikethrough = false
    /// Font Outline: the letters' outline color, shared by the selection; nil with no outline or a mix.
    var outline: NSColor?
    /// Every paragraph starts with a bullet, or with a number.
    var bullets = false
    var numbered = false
    var alignment: TextAlign?
    var verticalAlign: VerticalAlign?
    var orientation: TextOrientation?
    /// Font Color of the selection; nil when it has several.
    var color: NSColor?
    /// Vertical alignment and orientation only mean something for containers with a fixed size.
    var supportsVerticalAlign = false
    var supportsOrientation = false

    static let inactive = TextFormatState()

    /// Several selected texts as one: a value they don't all share is mixed (nil), a toggle is on only if all have it,
    /// and container controls work when one of them supports them.
    static func merged(_ states: [TextFormatState]) -> TextFormatState {
        let active = states.filter(\.isActive)
        guard var s = active.first else { return .inactive }
        for o in active.dropFirst() {
            if s.family != o.family { s.family = nil }
            if s.size != o.size { s.size = nil }
            s.bold = s.bold && o.bold
            s.italic = s.italic && o.italic
            s.underline = s.underline && o.underline
            s.strikethrough = s.strikethrough && o.strikethrough
            if s.outline?.rgbaHex != o.outline?.rgbaHex { s.outline = nil }
            s.bullets = s.bullets && o.bullets
            s.numbered = s.numbered && o.numbered
            if s.alignment != o.alignment { s.alignment = nil }
            if s.color?.rgbaHex != o.color?.rgbaHex { s.color = nil }
            if o.supportsVerticalAlign {
                if !s.supportsVerticalAlign { s.verticalAlign = o.verticalAlign } else if s.verticalAlign != o.verticalAlign { s.verticalAlign = nil }
            }
            if o.supportsOrientation {
                if !s.supportsOrientation { s.orientation = o.orientation } else if s.orientation != o.orientation { s.orientation = nil }
            }
            s.supportsVerticalAlign = s.supportsVerticalAlign || o.supportsVerticalAlign
            s.supportsOrientation = s.supportsOrientation || o.supportsOrientation
        }
        return s
    }
}

/// One formatting command, as the toolbar and the keyboard shortcuts send it.
enum FormatChange: Equatable {
    case family(String)
    case size(CGFloat)
    case grow, shrink
    /// ⌘] / ⌘[: one point up or down.
    case step(CGFloat)
    case bold, italic, underline, strikethrough
    /// Font Outline: a color, or nil to remove it.
    case outline(NSColor?)
    case alignment(TextAlign)
    /// These rewrite the letters (see `TextFormatting.rewrite`).
    case textCase(TextCase)
    case bullets, numbering
    case verticalAlign(VerticalAlign)
    case orientation(TextOrientation)
    /// Font Color.
    case color(NSColor)

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

    /// Change Case, Bullets and Numbering change the text itself, not only its attributes.
    var rewritesText: Bool {
        switch self {
        case .textCase, .bullets, .numbering: true
        default: false
        }
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
        var strikes: [Bool] = []
        var outlines = Set<String>()
        var firstOutline: NSColor?
        func noteOutline(_ attrs: [NSAttributedString.Key: Any]) {
            let width = (attrs[.strokeWidth] as? CGFloat) ?? 0
            if width != 0, let c = attrs[.strokeColor] as? NSColor {
                if firstOutline == nil { firstOutline = c }
                outlines.insert(c.rgbaHex)
            } else {
                outlines.insert("none")
            }
        }
        var colors = Set<String>()
        var firstColor: NSColor?
        func note(_ c: NSColor?) {
            guard let c else { return }
            if firstColor == nil { firstColor = c }
            colors.insert(c.rgbaHex)
        }
        let sel = NSIntersectionRange(selection, NSRange(location: 0, length: storage.length))
        if selection.length > 0, sel.length > 0 {
            storage.enumerateAttributes(in: sel) { attrs, _, _ in
                if let f = attrs[.font] as? NSFont { fonts.append(f) }
                underlines.append(((attrs[.underlineStyle] as? Int) ?? 0) != 0)
                strikes.append(((attrs[.strikethroughStyle] as? Int) ?? 0) != 0)
                noteOutline(attrs)
                note(attrs[.foregroundColor] as? NSColor)
            }
        } else {
            if let f = typing[.font] as? NSFont { fonts.append(f) }
            underlines.append(((typing[.underlineStyle] as? Int) ?? 0) != 0)
            strikes.append(((typing[.strikethroughStyle] as? Int) ?? 0) != 0)
            noteOutline(typing)
            note(typing[.foregroundColor] as? NSColor)
        }
        s.strikethrough = !strikes.isEmpty && strikes.allSatisfy { $0 }
        s.outline = outlines.count == 1 && !outlines.contains("none") ? firstOutline : nil
        let paragraphs = paragraphRanges(in: storage.string as NSString, covering: selection)
            .map { (storage.string as NSString).substring(with: $0) }
        s.bullets = !paragraphs.isEmpty && storage.length > 0 && paragraphs.allSatisfy { bulletPrefix($0) != nil }
        s.numbered = !paragraphs.isEmpty && storage.length > 0 && paragraphs.allSatisfy { numberPrefix($0) != nil }
        s.color = colors.count == 1 ? firstColor : nil
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
        guard !change.isContainer, !change.rewritesText else { return }
        if case let .outline(c) = change {
            let attrs: [NSAttributedString.Key: Any] = c.map { [.strokeColor: $0, .strokeWidth: outlineWidth] } ?? [:]
            if selection.length > 0, sel.length > 0 {
                storage.removeAttribute(.strokeColor, range: sel)
                storage.removeAttribute(.strokeWidth, range: sel)
                storage.addAttributes(attrs, range: sel)
            }
            typing[.strokeColor] = c
            typing[.strokeWidth] = c == nil ? nil : outlineWidth
            return
        }
        if case let .color(c) = change {
            if selection.length > 0, sel.length > 0 { storage.addAttribute(.foregroundColor, value: c, range: sel) }
            typing[.foregroundColor] = c
            return
        }

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
            } else if change == .strikethrough {
                storage.addAttribute(.strikethroughStyle, value: current.strikethrough ? 0 : NSUnderlineStyle.single.rawValue, range: sel)
            } else {
                storage.enumerateAttribute(.font, in: sel) { value, r, _ in
                    if let f = value as? NSFont { storage.addAttribute(.font, value: transform(f), range: r) }
                }
            }
            // What is typed right after the selection continues its new format.
            let attrs = storage.attributes(at: max(sel.location, NSMaxRange(sel) - 1), effectiveRange: nil)
            for key in [NSAttributedString.Key.font, .underlineStyle, .strikethroughStyle] { typing[key] = attrs[key] }
        } else {
            // Collapsed caret: pending format, like Word.
            if change == .underline {
                typing[.underlineStyle] = current.underline ? 0 : NSUnderlineStyle.single.rawValue
            } else if change == .strikethrough {
                typing[.strikethroughStyle] = current.strikethrough ? 0 : NSUnderlineStyle.single.rawValue
            } else if let f = typing[.font] as? NSFont {
                typing[.font] = transform(f)
            }
        }
    }

    /// Font Outline's stroke: negative draws the letters' fill and the outline (a percentage of the font size).
    static let outlineWidth: CGFloat = -3

    // MARK: Rewriting the letters

    static let bullet = "• "

    /// The bullet at the start of a paragraph, if any.
    static func bulletPrefix(_ paragraph: String) -> String? { paragraph.hasPrefix(bullet) ? bullet : nil }

    /// "12. " at the start of a paragraph, if any.
    static func numberPrefix(_ paragraph: String) -> String? {
        let digits = paragraph.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        let rest = paragraph.dropFirst(digits.count)
        return rest.hasPrefix(". ") ? String(digits) + ". " : nil
    }

    /// Change Case, Bullets and Numbering: the range to replace, its new text (keeping each letter's format), and the
    /// selection afterwards. Change Case works on the selection, or on the word at the caret; Bullets and Numbering on
    /// every paragraph the selection touches, and turn off when all of them already have that marker. `force` sets the
    /// marker on (true) or off (false) whatever the paragraphs have (several selected texts follow their shared state).
    static func rewrite(_ change: FormatChange, in storage: NSAttributedString, selection: NSRange,
                        force: Bool? = nil) -> (range: NSRange, text: NSAttributedString, selection: NSRange)? {
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        switch change {
        case let .textCase(c):
            var range = NSIntersectionRange(selection, full)
            if range.length == 0 {
                guard ns.length > 0 else { return nil }
                range = storage.doubleClick(at: min(selection.location, ns.length - 1))
                guard range.length > 0, ns.substring(with: range).contains(where: \.isLetter) else { return nil }
            }
            let old = storage.attributedSubstring(from: range)
            let newString = c.apply(old.string)
            let out = NSMutableAttributedString(string: newString, attributes: old.length > 0 ? old.attributes(at: 0, effectiveRange: nil) : [:])
            if (newString as NSString).length == old.length {
                // Same length: every letter keeps its own format.
                old.enumerateAttributes(in: NSRange(location: 0, length: old.length)) { attrs, r, _ in out.setAttributes(attrs, range: r) }
            }
            let after = selection.length > 0 ? NSRange(location: range.location, length: out.length) : selection
            return (range, out, after)
        case .bullets, .numbering:
            let paragraphs = paragraphRanges(in: ns, covering: selection)
            guard let first = paragraphs.first, let last = paragraphs.last else { return nil }
            let union = NSUnionRange(first, last)
            let numbering = change == .numbering
            let texts = paragraphs.map { ns.substring(with: $0) }
            let allHave = texts.allSatisfy { (numbering ? numberPrefix($0) : bulletPrefix($0)) != nil }
            let turnOn = force ?? !allHave
            let out = NSMutableAttributedString()
            var firstShift = 0
            for (i, p) in paragraphs.enumerated() {
                var piece = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: p))
                // Either marker comes off first: a paragraph has a bullet or a number, not both.
                if let old = bulletPrefix(piece.string) ?? numberPrefix(piece.string) {
                    piece.deleteCharacters(in: NSRange(location: 0, length: (old as NSString).length))
                    if i == 0 { firstShift -= (old as NSString).length }
                }
                if turnOn {
                    let marker = numbering ? "\(i + 1). " : bullet
                    let attrs = piece.length > 0 ? piece.attributes(at: 0, effectiveRange: nil)
                        : (p.location < ns.length ? storage.attributes(at: p.location, effectiveRange: nil) : [:])
                    piece = {
                        let m = NSMutableAttributedString(string: marker, attributes: attrs)
                        m.removeAttribute(.underlineStyle, range: NSRange(location: 0, length: m.length))
                        m.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: m.length))
                        m.append(piece)
                        return m
                    }()
                    if i == 0 { firstShift += (marker as NSString).length }
                }
                out.append(piece)
            }
            let after = selection.length > 0 ? NSRange(location: union.location, length: out.length)
                : NSRange(location: max(union.location, selection.location + firstShift), length: 0)
            return (union, out, after)
        default:
            return nil
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
