import AppKit
import CoreImage.CIFilterBuiltins
import Vision

enum Tool: String, CaseIterable, Codable {
    case select, arrow, rect, oval, line, freehand, text, highlighter, blur, counter, spotlight, magnifier, ruler, crop
    /// Pasted image overlay (Shottr's 20-image object); created by pasting, not from the tool strip.
    case image
    /// Text in a bubble with a pointer that can be aimed anywhere.
    case callout

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .rect: "Rectangle"
        case .oval: "Oval"
        case .line: "Line"
        case .freehand: "Freehand Drawing"
        case .text: "Text"
        case .highlighter: "Highlighter"
        case .blur: "Blur"
        case .counter: "Counter"
        case .spotlight: "Spotlight"
        case .magnifier: "Magnifier"
        case .ruler: "Ruler"
        case .crop: "Crop"
        case .image: "Image"
        case .callout: "Callout"
        }
    }

    var key: String {
        switch self {
        case .select: "V"
        case .arrow: "A"
        case .rect: "R"
        case .oval: "O"
        case .line: "L"
        case .freehand: "D"
        case .text: "T"
        case .highlighter: "H"
        case .blur: "B"
        case .counter: "C"
        case .spotlight: "S"
        case .magnifier: "M"
        case .ruler: "1"
        case .crop: "X"
        case .image: ""
        case .callout: "E"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .oval: "circle"
        case .line: "line.diagonal"
        case .freehand: "scribble"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .blur: "checkerboard.rectangle"
        case .counter: "1.circle"
        case .spotlight: "flashlight.on.fill"
        case .magnifier: "plus.magnifyingglass"
        case .ruler: "ruler"
        case .crop: "crop"
        case .image: "photo"
        case .callout: "text.bubble"
        }
    }

    static func forKey(_ c: String) -> Tool? {
        if c == "u" { return .ruler }
        return allCases.first { !$0.key.isEmpty && $0.key.lowercased() == c }
    }
}

/// Counter badge shapes (Shottr's shape picker: 16-shape-oval / 16-shape-rect / 16-shape-blob).
enum CounterShape: Int, CaseIterable, Codable {
    case circle, square, bubble

    var title: String {
        switch self {
        case .circle: "Circle"
        case .square: "Square"
        case .bubble: "Bubble"
        }
    }

    var symbol: String {
        switch self {
        case .circle: "circle.fill"
        case .square: "square.fill"
        case .bubble: "bubble.left.fill"
        }
    }
}

/// Shottr's arrow segment (16-arrow-shape / -line / -double; the hand-drawn variant is not reproduced).
enum ArrowStyle: Int, CaseIterable, Codable {
    case tapered, line, double

    var title: String {
        switch self {
        case .tapered: "Shaped Arrow"
        case .line: "Line Arrow"
        case .double: "Double Arrow"
        }
    }

    var symbol: String {
        switch self {
        case .tapered: "arrow.up.right"
        case .line: "arrow.right"
        case .double: "arrow.left.and.right"
        }
    }
}

/// Shottr's fill segment (16-objfill-transparent / -translucent / -opaque).
enum FillStyle: Int, CaseIterable, Codable {
    case none, translucent, opaque

    var title: String {
        switch self {
        case .none: "No Fill"
        case .translucent: "Translucent Fill"
        case .opaque: "Opaque Fill"
        }
    }

    var symbol: String {
        switch self {
        case .none: "square"
        case .translucent: "square.lefthalf.filled"
        case .opaque: "square.fill"
        }
    }
}

/// Shottr's conceal type segment (scConcealType): "Blur", "Blur Text", "Erase", "Erase Text".
/// Blur pixelates the region and softens it; Erase fills with the average surrounding color;
/// the Text variants conceal only the text lines Vision finds inside the region.
enum BlurMode: Int, CaseIterable, Codable {
    case blur, blurText, erase, eraseText

    var title: String {
        switch self {
        case .blur: "Blur"
        case .blurText: "Blur Text"
        case .erase: "Erase"
        case .eraseText: "Erase Text"
        }
    }

    var textOnly: Bool { self == .blurText || self == .eraseText }
    var erases: Bool { self == .erase || self == .eraseText }
}

/// Shottr's font segment (16-text-sans / 16-text-goofy).
enum TextFont: Int, CaseIterable, Codable {
    case sans, goofy

    var title: String { self == .sans ? "Sans" : "Goofy" }

    func font(size: CGFloat) -> NSFont {
        switch self {
        case .sans: .systemFont(ofSize: size, weight: .semibold)
        case .goofy: NSFont(name: "ChalkboardSE-Bold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
        }
    }
}

/// Current options-bar settings; new annotations copy them and edits apply them to the selection.
struct ToolStyle: Equatable {
    var color: NSColor = NSColor(hex: 0xFF3B30)
    var width: CGFloat = 4
    var arrow: ArrowStyle = .tapered
    var dashed = false
    /// Hand-drawn strokes for arrows, lines and shapes.
    var sketch = false
    var fill: FillStyle = .none
    var blur: BlurMode = .blur
    var font: TextFont = .sans
    var counterShape: CounterShape = .circle
    var rulerInPoints = false
    var lensShape: LensShape = .oval
    var magnification: CGFloat = 2
    var callout: CalloutStyle = .box

    /// Starting style for new annotations. Built-in defaults are the property defaults above
    /// (Callout: Professional · Box); right-click an option in the options bar to change one.
    static func loadDefaults() -> ToolStyle {
        var s = ToolStyle()
        guard let d = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) else { return s }
        if let v = d["color"] as? String, let c = NSColor(rgbaHex: v) { s.color = c }
        if let v = d["width"] as? Double { s.width = CGFloat(v) }
        if let v = d["arrow"] as? Int, let x = ArrowStyle(rawValue: v) { s.arrow = x }
        if let v = d["dashed"] as? Bool { s.dashed = v }
        if let v = d["sketch"] as? Bool { s.sketch = v }
        if let v = d["fill"] as? Int, let x = FillStyle(rawValue: v) { s.fill = x }
        if let v = d["blur"] as? Int, let x = BlurMode(rawValue: v) { s.blur = x }
        if let v = d["font"] as? Int, let x = TextFont(rawValue: v) { s.font = x }
        if let v = d["counterShape"] as? Int, let x = CounterShape(rawValue: v) { s.counterShape = x }
        if let v = d["rulerInPoints"] as? Bool { s.rulerInPoints = v }
        if let v = d["lensShape"] as? Int, let x = LensShape(rawValue: v) { s.lensShape = x }
        if let v = d["magnification"] as? Double, v >= 1.25 { s.magnification = CGFloat(v) }
        if let v = d["callout"] as? Int, let x = CalloutStyle(rawValue: v) { s.callout = x }
        return s
    }

    func saveAsDefaults() {
        UserDefaults.standard.set([
            "color": color.rgbaHex, "width": Double(width), "arrow": arrow.rawValue, "dashed": dashed, "sketch": sketch, "fill": fill.rawValue,
            "blur": blur.rawValue, "font": font.rawValue, "counterShape": counterShape.rawValue, "rulerInPoints": rulerInPoints,
            "lensShape": lensShape.rawValue, "magnification": Double(magnification), "callout": callout.rawValue,
        ] as [String: Any], forKey: Self.defaultsKey)
    }

    /// Changes one default and keeps the rest.
    static func updateDefaults(_ change: (inout ToolStyle) -> Void) {
        var d = loadDefaults()
        change(&d)
        d.saveAsDefaults()
    }

    static let defaultsKey = "defaultToolStyle"
}

enum Palette {
    static let colors: [NSColor] = [
        NSColor(hex: 0xFF3B30), NSColor(hex: 0xFF9500), NSColor(hex: 0xFFCC00), NSColor(hex: 0x34C759),
        NSColor(hex: 0x00C7BE), NSColor(hex: 0x007AFF), NSColor(hex: 0xAF52DE), NSColor(hex: 0xFF2D55),
        NSColor(hex: 0x000000), NSColor(hex: 0x8E8E93), NSColor(hex: 0xFFFFFF),
    ]

    /// Shottr's clrMain (Assets.car), used for selections and accents.
    static let accent = NSColor(hex: 0xFF0C01)
}

/// Shottr's shape segment (16-shape-rect / 16-shape-oval), used by the magnifier's source area and lens.
enum LensShape: Int, CaseIterable, Codable {
    case rect, oval

    var title: String { self == .rect ? "Rectangle" : "Oval" }
    var symbol: String { self == .rect ? "rectangle" : "circle" }

    func path(_ r: CGRect) -> CGPath {
        switch self {
        case .rect:
            let c = min(r.width, r.height) * 0.08
            return CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil)
        case .oval:
            return CGPath(ellipseIn: r, transform: nil)
        }
    }
}

/// Callout designs, from professional to fun.
enum CalloutStyle: Int, CaseIterable, Codable {
    case box, card, speech, thought, shout

    var title: String {
        switch self {
        case .box: "Professional · Box"
        case .card: "Professional · Card"
        case .speech: "Informal · Speech"
        case .thought: "Fun · Thought"
        case .shout: "Fun · Shout"
        }
    }

    var symbol: String {
        switch self {
        case .box: "text.bubble.fill"
        case .card: "rectangle.and.text.magnifyingglass"
        case .speech: "bubble.left"
        case .thought: "cloud"
        case .shout: "burst"
        }
    }

    /// Filled in the callout color with contrasting text; the others are white with colored border and text.
    var filled: Bool { self == .box || self == .shout }
}

/// A styled range inside a text annotation (color, size in image pixels, font), from selecting letters while typing.
struct TextRun: Codable, Equatable {
    var location: Int
    var length: Int
    var color: String // "#RRGGBBAA"
    var size: CGFloat
    var font: TextFont
}

/// One annotation. Coordinates are image pixels with a top-left origin.
struct Annotation {
    var id = UUID()
    var kind: Tool
    var p1: CGPoint
    var p2: CGPoint
    var points: [CGPoint] = []
    var color: NSColor
    var width: CGFloat
    var text = ""
    var number = 0
    var shape: CounterShape = .circle
    /// Direction of the bubble's pointer (radians, flipped coordinates); the default points down-left.
    var tailAngle: CGFloat = 3 * .pi / 4
    var arrowStyle: ArrowStyle = .tapered
    var dashed = false
    var sketch = false
    var fill: FillStyle = .none
    var blurMode: BlurMode = .blur
    var font: TextFont = .sans
    var rulerInPoints = false
    /// Magnifier: zoom factor, lens shape and where the lens sits (Shottr's factor, shape, lensX/lensY).
    var factor: CGFloat = 2
    var lensShape: LensShape = .oval
    var lensCenter: CGPoint?
    /// Blur/Erase Text: text boxes found inside the region (image coordinates); nil until scanned.
    var textRects: [CGRect]?
    /// Image overlay: PNG bytes of the pasted image, drawn into `rect`.
    var imageData: Data?
    /// Text: per-range styles on top of color/width/font; nil when the whole text has one style.
    var runs: [TextRun]?
    /// Callout: design and the point its pointer aims at (image coordinates).
    var calloutStyle: CalloutStyle = .box
    var pointer: CGPoint?

    init(kind: Tool, p1: CGPoint, p2: CGPoint, points: [CGPoint] = [], color: NSColor, width: CGFloat) {
        self.kind = kind
        self.p1 = p1
        self.p2 = p2
        self.points = points
        self.color = color
        self.width = width
    }

    init(kind: Tool, p1: CGPoint, p2: CGPoint, points: [CGPoint] = [], style s: ToolStyle) {
        self.init(kind: kind, p1: p1, p2: p2, points: points, color: s.color, width: s.width)
        apply(s)
    }

    /// Copies the options-bar settings that matter for this kind of annotation.
    mutating func apply(_ s: ToolStyle) {
        color = s.color
        width = s.width
        arrowStyle = s.arrow
        dashed = s.dashed
        sketch = s.sketch
        fill = s.fill
        blurMode = s.blur
        font = s.font
        shape = s.counterShape
        rulerInPoints = s.rulerInPoints
        lensShape = s.lensShape
        factor = s.magnification
        calloutStyle = s.callout
        // Restyling a whole text object replaces any per-letter styles.
        runs = nil
    }

    var rect: CGRect { CGRect(p1: p1, p2: p2) }
    var fontSize: CGFloat { max(12, width * 6) }
    var counterRadius: CGFloat { width * 2.5 + 10 }

    var counterFont: NSFont {
        .systemFont(ofSize: counterRadius * ("\(number)".count > 1 ? 0.95 : 1.1), weight: .bold)
    }

    /// Badge body; widens into a capsule for multi-digit numbers.
    var counterRect: CGRect {
        let r = counterRadius
        let textWidth = ("\(number)" as NSString).size(withAttributes: [.font: counterFont]).width
        let w = max(2 * r, textWidth + r * 0.9)
        return CGRect(x: p1.x - w / 2, y: p1.y - r, width: w, height: 2 * r)
    }

    var counterPath: CGPath {
        let r = counterRect
        switch shape {
        case .circle:
            return CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        case .square:
            let c = r.height * 0.22
            return CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil)
        case .bubble:
            let body = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
            return body.union(bubbleTail)
        }
    }

    /// Pointer whose sides leave the badge tangentially (no corner at the join) and sweep concavely into a softly rounded tip.
    private var bubbleTail: CGPath {
        let h = counterRect.height
        let u = CGVector(dx: cos(tailAngle), dy: sin(tailAngle))
        let n = CGVector(dx: -u.dy, dy: u.dx)
        let tip = tailTip
        let spread: CGFloat = 0.72 // radians either side of the pointer direction
        let a = counterEdgePoint(angle: tailAngle + spread)
        let b = counterEdgePoint(angle: tailAngle - spread)

        // Outline tangent at an attach point, oriented toward the other attach point.
        func tangent(_ p: CGPoint, toward q: CGPoint) -> CGVector {
            let normal = counterEdgeNormal(at: p)
            var t = CGVector(dx: -normal.dy, dy: normal.dx)
            if t.dx * (q.x - p.x) + t.dy * (q.y - p.y) < 0 { t = CGVector(dx: -t.dx, dy: -t.dy) }
            return t
        }
        let ta = tangent(a, toward: b), tb = tangent(b, toward: a)

        let tipHalf = h * 0.085
        let tipA = tip + CGVector(dx: n.dx * tipHalf, dy: n.dy * tipHalf)
        let tipB = tip + CGVector(dx: -n.dx * tipHalf, dy: -n.dy * tipHalf)
        let hug = h * 0.16 // how long each side follows the badge outline before bending out
        let sweepA = a.distance(to: tip) * 0.3, sweepB = b.distance(to: tip) * 0.3

        // Pick the side of the tip each curve should land on, so the two sides never cross.
        let aOnPositiveSide = (a.x - tip.x) * n.dx + (a.y - tip.y) * n.dy > 0
        let (endA, endB) = aOnPositiveSide ? (tipA, tipB) : (tipB, tipA)

        let path = CGMutablePath()
        path.move(to: p1)
        path.addLine(to: a)
        path.addCurve(to: endA,
                      control1: a + CGVector(dx: ta.dx * hug, dy: ta.dy * hug),
                      control2: endA + CGVector(dx: -u.dx * sweepA, dy: -u.dy * sweepA))
        path.addQuadCurve(to: endB, control: tip + CGVector(dx: u.dx * tipHalf * 1.6, dy: u.dy * tipHalf * 1.6))
        path.addCurve(to: b,
                      control1: endB + CGVector(dx: -u.dx * sweepB, dy: -u.dy * sweepB),
                      control2: b + CGVector(dx: tb.dx * hug, dy: tb.dy * hug))
        path.closeSubpath()
        return path
    }

    private func counterEdgePoint(angle: CGFloat) -> CGPoint {
        let d = counterEdgeDistance(dx: cos(angle), dy: sin(angle))
        return CGPoint(x: p1.x + cos(angle) * d, y: p1.y + sin(angle) * d)
    }

    /// Outward normal of the capsule outline at an edge point.
    private func counterEdgeNormal(at p: CGPoint) -> CGVector {
        let r = counterRect
        let straight = (r.width - r.height) / 2
        let core = CGPoint(x: max(p1.x - straight, min(p1.x + straight, p.x)), y: p1.y)
        let len = max(0.0001, p.distance(to: core))
        return CGVector(dx: (p.x - core.x) / len, dy: (p.y - core.y) / len)
    }

    /// End of the bubble's pointer; dragging it rotates the pointer around the badge without moving the number.
    var tailTip: CGPoint {
        let reach = counterEdgeDistance(dx: cos(tailAngle), dy: sin(tailAngle)) + counterRect.height * 0.3
        return CGPoint(x: p1.x + cos(tailAngle) * reach, y: p1.y + sin(tailAngle) * reach)
    }

    /// Distance from the badge center to its capsule outline along a unit direction.
    private func counterEdgeDistance(dx: CGFloat, dy: CGFloat) -> CGFloat {
        let r = counterRect
        let straight = (r.width - r.height) / 2, radius = r.height / 2
        var lo: CGFloat = 0, hi = r.width
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let x = dx * mid, y = dy * mid
            if hypot(x - max(-straight, min(straight, x)), y) < radius { lo = mid } else { hi = mid }
        }
        return lo
    }
    static let magnificationRange: ClosedRange<CGFloat> = 1.25...8

    /// The enlarged copy of the source area; sits up and to the right of it until the user drags it elsewhere.
    var lensRect: CGRect {
        let src = rect
        let size = CGSize(width: src.width * factor, height: src.height * factor)
        let c = lensCenter ?? Annotation.defaultLensCenter(source: src, lensSize: size, bounds: nil)
        return CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Places the lens beside the source without covering it, preferring the side with room inside `bounds`.
    static func defaultLensCenter(source s: CGRect, lensSize l: CGSize, bounds: CGRect?) -> CGPoint {
        let gap = max(16, min(s.width, s.height) * 0.4)
        let candidates = [
            CGPoint(x: s.maxX + gap + l.width / 2, y: s.midY - (l.height - s.height) / 4),
            CGPoint(x: s.minX - gap - l.width / 2, y: s.midY - (l.height - s.height) / 4),
            CGPoint(x: s.midX, y: s.maxY + gap + l.height / 2),
            CGPoint(x: s.midX, y: s.minY - gap - l.height / 2),
        ]
        guard let b = bounds else { return candidates[0] }
        func overflow(_ c: CGPoint) -> CGFloat {
            let r = CGRect(x: c.x - l.width / 2, y: c.y - l.height / 2, width: l.width, height: l.height)
            let inside = r.intersection(b)
            return inside.isNull ? r.width * r.height : r.width * r.height - inside.width * inside.height
        }
        return candidates.min { overflow($0) < overflow($1) } ?? candidates[0]
    }

    /// Point on a shape's outline in the direction of `toward` from its center (for the connector line).
    static func outlinePoint(of r: CGRect, shape: LensShape, toward p: CGPoint) -> CGPoint {
        let c = CGPoint(x: r.midX, y: r.midY)
        let dx = p.x - c.x, dy = p.y - c.y
        guard dx != 0 || dy != 0, r.width > 0, r.height > 0 else { return c }
        let a = r.width / 2, b = r.height / 2
        let t: CGFloat
        switch shape {
        case .oval: t = 1 / sqrt((dx * dx) / (a * a) + (dy * dy) / (b * b))
        case .rect: t = min(dx == 0 ? .infinity : a / abs(dx), dy == 0 ? .infinity : b / abs(dy))
        }
        return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    }

    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font.font(size: fontSize), .foregroundColor: color]
    }

    /// The text with its base style and per-range runs; `scale` converts image pixels to view points while editing.
    func attributedText(scale: CGFloat = 1) -> NSAttributedString {
        let m = NSMutableAttributedString(string: text.isEmpty ? " " : text,
                                          attributes: [.font: font.font(size: fontSize * scale), .foregroundColor: baseTextColor])
        for r in runs ?? [] {
            let range = NSRange(location: r.location, length: r.length)
            guard r.length > 0, NSMaxRange(range) <= m.length else { continue }
            m.addAttributes([.font: r.font.font(size: r.size * scale), .foregroundColor: NSColor(rgbaHex: r.color) ?? color], range: range)
        }
        return m
    }

    var textSize: CGSize { attributedText().size() }

    /// Takes text and per-letter styles back from the editing field (`scale` = view points per image pixel).
    mutating func setText(from attributed: NSAttributedString, scale: CGFloat) {
        text = attributed.string
        var found: [TextRun] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
            let f = attrs[.font] as? NSFont
            let c = (attrs[.foregroundColor] as? NSColor) ?? color
            let size = (((f?.pointSize ?? fontSize * scale) / scale) * 2).rounded() / 2
            let face: TextFont = f?.fontName.contains("Chalkboard") == true ? .goofy : .sans
            let run = TextRun(location: range.location, length: range.length, color: c.rgbaHex, size: size, font: face)
            if var last = found.last, last.color == run.color, last.size == run.size, last.font == run.font,
               NSMaxRange(NSRange(location: last.location, length: last.length)) == run.location {
                last.length += run.length
                found[found.count - 1] = last
            } else {
                found.append(run)
            }
        }
        if found.count <= 1, let only = found.first {
            // One style for everything: store it as the object's own style.
            color = NSColor(rgbaHex: only.color) ?? color
            font = only.font
            width = only.size / 6
            runs = nil
        } else {
            runs = found.isEmpty ? nil : found
        }
    }

    mutating func offset(by d: CGVector) {
        p1 = p1 + d
        p2 = p2 + d
        points = points.map { $0 + d }
        lensCenter = lensCenter.map { $0 + d }
        pointer = pointer.map { $0 + d }
        textRects = textRects.map { $0.map { $0.offsetBy(dx: d.dx, dy: d.dy) } }
    }

    var bounds: CGRect {
        switch kind {
        case .text:
            return CGRect(origin: p1, size: textSize)
        case .counter:
            return counterPath.boundingBoxOfPath
        case .callout:
            let shape = calloutShape()
            return shape.extras.reduce(shape.body.boundingBoxOfPath) { $0.union($1) }
                .union(CGRect(origin: calloutPointer, size: .zero)).insetBy(dx: -width, dy: -width)
        case .magnifier:
            return rect.union(lensRect).insetBy(dx: -width, dy: -width)
        case .freehand:
            guard let f = points.first else { return .zero }
            return points.reduce(CGRect(origin: f, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
                .insetBy(dx: -width, dy: -width)
        default:
            return rect.insetBy(dx: -width / 2, dy: -width / 2)
        }
    }

    func hit(_ p: CGPoint) -> Bool {
        let tol = max(8, width)
        switch kind {
        case .arrow, .line, .ruler:
            return p.distance(toSegment: p1, p2) <= tol
        case .rect, .oval:
            let outer = rect.insetBy(dx: -tol, dy: -tol), inner = rect.insetBy(dx: tol, dy: tol)
            return outer.contains(p) && !(inner.width > 0 && inner.height > 0 && inner.contains(p))
        case .freehand:
            return zip(points, points.dropFirst()).contains { p.distance(toSegment: $0, $1) <= tol }
        case .magnifier:
            return hitLens(p) || rect.insetBy(dx: -tol, dy: -tol).contains(p)
        case .callout:
            return calloutShape().body.contains(p) || calloutShape().extras.contains { $0.contains(p) }
        default:
            return bounds.contains(p)
        }
    }

    func hitLens(_ p: CGPoint) -> Bool {
        kind == .magnifier && lensShape.path(lensRect.insetBy(dx: -width, dy: -width)).contains(p)
    }

    /// Whether a finished drag produced something worth keeping.
    var isMeaningful: Bool {
        switch kind {
        case .freehand: return points.count > 2
        case .counter, .text, .image, .callout: return true
        case .magnifier: return rect.width > 4 && rect.height > 4
        default: return p1.distance(to: p2) > 3
        }
    }
}

// MARK: - Callouts

extension Annotation {
    /// Text color before per-letter styles: contrasting on filled callouts, the annotation color otherwise.
    var baseTextColor: NSColor { kind == .callout && calloutStyle.filled ? color.contrasting : color }

    /// Where the text starts: the callout's padding inside its box, or `p1` for plain text.
    var textOrigin: CGPoint {
        guard kind == .callout else { return p1 }
        let pad = calloutPadding
        return CGPoint(x: p1.x + pad.width, y: p1.y + pad.height)
    }

    private var calloutPadding: CGSize {
        let fs = fontSize
        switch calloutStyle {
        case .box, .card: return CGSize(width: fs * 0.6, height: fs * 0.38)
        case .speech: return CGSize(width: fs * 0.95, height: fs * 0.5)
        case .thought, .shout: return CGSize(width: fs * 0.7, height: fs * 0.42)
        }
    }

    /// The text box (text plus padding); fun designs draw their body around it.
    var calloutBox: CGRect {
        let t = attributedText().size(), pad = calloutPadding
        return CGRect(x: p1.x, y: p1.y, width: max(t.width, fontSize) + 2 * pad.width, height: t.height + 2 * pad.height)
    }

    /// The point the pointer aims at; new callouts point down-left of the box until re-aimed.
    var calloutPointer: CGPoint {
        pointer ?? CGPoint(x: p1.x - fontSize * 1.5, y: p1.y + calloutBox.height + fontSize * 2.5)
    }

    /// Body outline (pointer included) plus extra pieces (the thought bubble's trail).
    func calloutShape() -> (body: CGPath, extras: [CGRect]) {
        let box = calloutBox, tip = calloutPointer
        let c = CGPoint(x: box.midX, y: box.midY)
        let len = max(0.001, c.distance(to: tip))
        let u = CGVector(dx: (tip.x - c.x) / len, dy: (tip.y - c.y) / len)
        let n = CGVector(dx: -u.dy, dy: u.dx)
        let aims = !box.insetBy(dx: -4, dy: -4).contains(tip)

        switch calloutStyle {
        case .box, .card:
            let radius = min(12, box.height * 0.28)
            let body = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
            guard aims else { return (body, []) }
            // Tapered pointer from inside the box to the tip; the union hides the inner part.
            let half = min(box.width, box.height) * 0.36
            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: c.x + n.dx * half, y: c.y + n.dy * half))
            tail.addLine(to: tip)
            tail.addLine(to: CGPoint(x: c.x - n.dx * half, y: c.y - n.dy * half))
            tail.closeSubpath()
            return (body.union(tail), [])

        case .speech:
            let body = CGPath(roundedRect: box, cornerWidth: box.height / 2, cornerHeight: box.height / 2, transform: nil)
            guard aims else { return (body, []) }
            // Comic-style tail: both edges bend the same way, so it swoops toward the tip.
            let half = min(box.width, box.height) * 0.24
            let a = CGPoint(x: c.x + n.dx * half, y: c.y + n.dy * half)
            let b = CGPoint(x: c.x - n.dx * half, y: c.y - n.dy * half)
            let bend = len * 0.22
            let tail = CGMutablePath()
            tail.move(to: a)
            tail.addQuadCurve(to: tip, control: CGPoint(x: (a.x + tip.x) / 2 + n.dx * bend, y: (a.y + tip.y) / 2 + n.dy * bend))
            tail.addQuadCurve(to: b, control: CGPoint(x: (b.x + tip.x) / 2 + n.dx * bend * 0.45, y: (b.y + tip.y) / 2 + n.dy * bend * 0.45))
            tail.closeSubpath()
            return (body.union(tail), [])

        case .thought:
            // Cloud: scallops around an ellipse that encloses the text, then a trail of shrinking bubbles to the tip.
            let e = box.insetBy(dx: -box.width * 0.1, dy: -box.height * 0.22)
            let rx = e.width / 2, ry = e.height / 2
            let bump = max(box.height * 0.36, 10)
            let perimeter = 2 * CGFloat.pi * sqrt((rx * rx + ry * ry) / 2)
            let count = max(8, Int(perimeter / (bump * 1.35)))
            var cloud = CGPath(ellipseIn: e, transform: nil)
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count) * 2 * .pi
                let p = CGPoint(x: e.midX + cos(t) * rx, y: e.midY + sin(t) * ry)
                cloud = cloud.union(CGPath(ellipseIn: CGRect(x: p.x - bump, y: p.y - bump, width: 2 * bump, height: 2 * bump), transform: nil))
            }
            guard aims else { return (cloud, []) }
            let edge = Annotation.outlinePoint(of: e.insetBy(dx: -bump * 0.7, dy: -bump * 0.7), shape: .oval, toward: tip)
            let trail = [(0.22, 0.42), (0.55, 0.28), (0.85, 0.16)].map { (t, r) -> CGRect in
                let p = CGPoint(x: edge.x + (tip.x - edge.x) * t, y: edge.y + (tip.y - edge.y) * t)
                let radius = max(3, box.height * r)
                return CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius)
            }
            return (cloud, trail)

        case .shout:
            // Starburst around the text; the spike closest to the target stretches out to it.
            let grow = box.height * 0.75
            let rx = box.width / 2 + grow, ry = box.height / 2 + grow
            let spikes = 14
            let target = atan2(tip.y - c.y, tip.x - c.x)
            var best = 0
            var bestDiff = CGFloat.infinity
            for i in 0..<spikes {
                let a = CGFloat(i) / CGFloat(spikes) * 2 * .pi
                let diff = abs(atan2(sin(a - target), cos(a - target)))
                if diff < bestDiff { bestDiff = diff; best = i }
            }
            let path = CGMutablePath()
            for k in 0..<(spikes * 2) {
                let a = CGFloat(k) / CGFloat(spikes * 2) * 2 * .pi
                let outer = k % 2 == 0
                let wobble: CGFloat = outer ? (k / 2 % 3 == 0 ? 1.08 : 0.98) : 0.74
                var p = CGPoint(x: c.x + cos(a) * rx * wobble, y: c.y + sin(a) * ry * wobble)
                if outer, k / 2 == best, aims { p = tip }
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return (path, [])
        }
    }
}

// MARK: - Persistence

extension Annotation: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, p1, p2, points, color, width, text, number, shape, tailAngle, arrowStyle, dashed, sketch, fill, blurMode, font
        case rulerInPoints, factor, lensShape, lensCenter, textRects, imageData, runs, calloutStyle, pointer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try c.decode(Tool.self, forKey: .kind),
                  p1: try c.decode(CGPoint.self, forKey: .p1),
                  p2: try c.decode(CGPoint.self, forKey: .p2),
                  points: try c.decodeIfPresent([CGPoint].self, forKey: .points) ?? [],
                  color: NSColor(rgbaHex: try c.decode(String.self, forKey: .color)) ?? .systemRed,
                  width: try c.decode(CGFloat.self, forKey: .width))
        // Optional fields fall back to defaults so files from older versions still open.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
        shape = try c.decodeIfPresent(CounterShape.self, forKey: .shape) ?? .circle
        tailAngle = try c.decodeIfPresent(CGFloat.self, forKey: .tailAngle) ?? 3 * .pi / 4
        arrowStyle = try c.decodeIfPresent(ArrowStyle.self, forKey: .arrowStyle) ?? .tapered
        dashed = try c.decodeIfPresent(Bool.self, forKey: .dashed) ?? false
        sketch = try c.decodeIfPresent(Bool.self, forKey: .sketch) ?? false
        fill = try c.decodeIfPresent(FillStyle.self, forKey: .fill) ?? .none
        blurMode = try c.decodeIfPresent(BlurMode.self, forKey: .blurMode) ?? .blur
        font = try c.decodeIfPresent(TextFont.self, forKey: .font) ?? .sans
        rulerInPoints = try c.decodeIfPresent(Bool.self, forKey: .rulerInPoints) ?? false
        factor = try c.decodeIfPresent(CGFloat.self, forKey: .factor) ?? 2
        lensShape = try c.decodeIfPresent(LensShape.self, forKey: .lensShape) ?? .oval
        lensCenter = try c.decodeIfPresent(CGPoint.self, forKey: .lensCenter)
        textRects = try c.decodeIfPresent([CGRect].self, forKey: .textRects)
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        runs = try c.decodeIfPresent([TextRun].self, forKey: .runs)
        calloutStyle = try c.decodeIfPresent(CalloutStyle.self, forKey: .calloutStyle) ?? .box
        pointer = try c.decodeIfPresent(CGPoint.self, forKey: .pointer)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(p1, forKey: .p1)
        try c.encode(p2, forKey: .p2)
        if !points.isEmpty { try c.encode(points, forKey: .points) }
        try c.encode(color.rgbaHex, forKey: .color)
        try c.encode(width, forKey: .width)
        if !text.isEmpty { try c.encode(text, forKey: .text) }
        if kind == .counter {
            try c.encode(number, forKey: .number)
            try c.encode(shape, forKey: .shape)
            try c.encode(tailAngle, forKey: .tailAngle)
        }
        try c.encode(arrowStyle, forKey: .arrowStyle)
        try c.encode(dashed, forKey: .dashed)
        if sketch { try c.encode(sketch, forKey: .sketch) }
        try c.encode(fill, forKey: .fill)
        try c.encode(blurMode, forKey: .blurMode)
        try c.encode(font, forKey: .font)
        try c.encode(rulerInPoints, forKey: .rulerInPoints)
        if kind == .magnifier {
            try c.encode(factor, forKey: .factor)
            try c.encode(lensShape, forKey: .lensShape)
            try c.encodeIfPresent(lensCenter, forKey: .lensCenter)
        }
        try c.encodeIfPresent(textRects, forKey: .textRects)
        try c.encodeIfPresent(imageData, forKey: .imageData)
        try c.encodeIfPresent(runs, forKey: .runs)
        if kind == .callout {
            try c.encode(calloutStyle, forKey: .calloutStyle)
            try c.encodeIfPresent(pointer, forKey: .pointer)
        }
    }
}

final class EditorDocument {
    var image: CGImage { didSet { concealCache.removeAll(); pixelCache = nil } }
    let scale: CGFloat
    var objects: [Annotation] = []
    var backdrop = Backdrop.none { didSet { if backdrop.fill != .blurredImage { blurredCache = nil } } }
    var layout: BackdropLayout { BackdropLayout(backdrop, imageSize: image.size) }
    /// The blurred screenshot behind a "Blurred Screenshot" backdrop, made once per image.
    private var blurredCache: (image: CGImage, blurred: CGImage?)?
    var blurredBackdrop: CGImage? {
        if let c = blurredCache, c.image === image { return c.blurred }
        let b = BackdropPainter.blurred(image)
        blurredCache = (image, b)
        return b
    }
    /// File this document was opened from or last saved to; Save and auto-save write back to it.
    var fileURL: URL?

    /// Undo history lives with the document, so switching files in a window and coming back keeps it.
    struct Snapshot {
        let image: CGImage
        let objects: [Annotation]
        let backdrop: Backdrop
    }
    var undoStack: [Snapshot] = []
    var redoStack: [Snapshot] = []
    /// Bumped on every edit; auto-save writes when it differs from `savedRevision`.
    var revision = 0
    var savedRevision = 0
    var hasUnsavedChanges: Bool { revision != savedRevision }
    private var overlayCache: [UUID: CGImage] = [:]

    func overlayImage(for o: Annotation) -> CGImage? {
        if let c = overlayCache[o.id] { return c }
        guard let data = o.imageData, let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        overlayCache[o.id] = img
        return img
    }

    /// Pixelated patches keyed by region, so moving a blur re-conceals what is under it (Shottr's "reconceal").
    private var concealCache: [String: CGImage] = [:]
    private var pixelCache: PixelReader?

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }

    var imageRect: CGRect { CGRect(origin: .zero, size: image.size) }

    var hasAlpha: Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Pixelated, softened copy of `r`: blocks aligned to the region's corner and sized to it, then a light Gaussian pass.
    func concealedPatch(for region: CGRect, textLine: Bool = false) -> CGImage? {
        let r = region.integral.intersection(imageRect)
        guard r.width >= 1, r.height >= 1 else { return nil }
        let key = "\(r.minX),\(r.minY),\(r.width),\(r.height),\(textLine)"
        if let cached = concealCache[key] { return cached }
        // Text lines get blocks about half the line height so glyph shapes can't be made out; areas scale with their size.
        let block = textLine ? max(8, (r.height * 0.5).rounded()) : max(8, min(32, (min(r.width, r.height) / 10).rounded()))
        // Core Image works bottom-up. Averaging mosaic: shrink with area averaging so each block is the mean of its
        // pixels, enlarge with nearest sampling for hard blocks, then soften the block edges slightly.
        let ciRect = CGRect(x: r.minX, y: CGFloat(image.height) - r.maxY, width: r.width, height: r.height)
        let region = CIImage(cgImage: image).cropped(to: ciRect).transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
        // Edges are extended before shrinking: otherwise border blocks average in transparent pixels and the
        // patch turns see-through, letting the original text show (thin text lines are almost all border).
        let cols = max(1, (r.width / block).rounded(.up)), rows = max(1, (r.height / block).rounded(.up))
        let down = region.clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 1 / block, kCIInputAspectRatioKey: 1])
            .cropped(to: CGRect(x: 0, y: 0, width: cols, height: rows))
        let up = down.clampedToExtent().samplingNearest().transformed(by: CGAffineTransform(scaleX: block, y: block))
        let soften = CIFilter.gaussianBlur()
        soften.inputImage = up.clampedToExtent()
        soften.radius = Float(block * 0.25)
        let local = CGRect(origin: .zero, size: r.size)
        guard let out = soften.outputImage?.cropped(to: local),
              let cg = EditorDocument.ciContext.createCGImage(out, from: local) else { return nil }
        if concealCache.count > 64 { concealCache.removeAll() }
        concealCache[key] = cg
        return cg
    }

    private static let ciContext = CIContext()

    /// Text line boxes inside `region` (image coordinates), padded a little so letters are fully covered.
    static func detectText(in image: CGImage, region: CGRect) -> [CGRect] {
        let r = region.integral.intersection(CGRect(origin: .zero, size: image.size))
        guard r.width >= 8, r.height >= 8, let crop = image.cropping(to: r) else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        OCR.configure(req, language: Settings.ocrLanguage)
        VisionGate.perform([req], on: crop)
        return (req.results ?? []).map { obs in
            let b = obs.boundingBox // normalized, bottom-left origin
            let box = CGRect(x: r.minX + b.minX * r.width, y: r.minY + (1 - b.maxY) * r.height,
                             width: b.width * r.width, height: b.height * r.height)
            let pad = max(2, box.height * 0.18)
            return box.insetBy(dx: -pad, dy: -pad).intersection(r)
        }
    }

    /// Shottr's "Copy Text Color": the darkest pixel within `radius` of a point (text is usually darker than its background).
    func darkestColor(around p: CGPoint, radius: Int = 10) -> NSColor? {
        let px = pixels
        var best: (NSColor, CGFloat)?
        for y in (Int(p.y) - radius)...(Int(p.y) + radius) {
            for x in (Int(p.x) - radius)...(Int(p.x) + radius) {
                guard let c = px.color(x, y) else { continue }
                if best == nil || c.luminance < best!.1 { best = (c, c.luminance) }
            }
        }
        return best?.0
    }

    /// Shottr's "Copy Average Color": the mean color of an area (sampled on a grid for speed).
    func averageColor(in r: CGRect) -> NSColor? {
        let px = pixels
        let area = r.integral.intersection(imageRect)
        guard area.width >= 1, area.height >= 1 else { return nil }
        let step = max(1, Int(max(area.width, area.height) / 120))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, n: CGFloat = 0
        for y in stride(from: Int(area.minY), to: Int(area.maxY), by: step) {
            for x in stride(from: Int(area.minX), to: Int(area.maxX), by: step) {
                guard let c = px.color(x, y) else { continue }
                red += c.redComponent; green += c.greenComponent; blue += c.blueComponent; n += 1
            }
        }
        return n > 0 ? NSColor(srgbRed: red / n, green: green / n, blue: blue / n, alpha: 1) : nil
    }

    /// Background color around `r` for Erase: the most common color on its outline, averaged within that color group,
    /// so a region straddling two backgrounds takes the dominant one instead of a muddy mix.
    func edgeColor(around r: CGRect) -> NSColor {
        let px = pixels
        let outer = r.insetBy(dx: -2, dy: -2).integral
        var groups: [Int: (r: CGFloat, g: CGFloat, b: CGFloat, n: CGFloat)] = [:]
        func sample(_ x: Int, _ y: Int) {
            guard let c = px.color(x, y) else { return }
            let key = Int(c.redComponent * 15) << 8 | Int(c.greenComponent * 15) << 4 | Int(c.blueComponent * 15)
            var e = groups[key] ?? (0, 0, 0, 0)
            e.r += c.redComponent; e.g += c.greenComponent; e.b += c.blueComponent; e.n += 1
            groups[key] = e
        }
        let stepX = max(1, Int(outer.width) / 60), stepY = max(1, Int(outer.height) / 60)
        for x in stride(from: Int(outer.minX), through: Int(outer.maxX), by: stepX) {
            sample(x, Int(outer.minY)); sample(x, Int(outer.maxY))
        }
        for y in stride(from: Int(outer.minY), through: Int(outer.maxY), by: stepY) {
            sample(Int(outer.minX), y); sample(Int(outer.maxX), y)
        }
        guard let best = groups.values.max(by: { $0.n < $1.n }) else { return .white }
        return NSColor(srgbRed: best.r / best.n, green: best.g / best.n, blue: best.b / best.n, alpha: 1)
    }

    /// Exact sRGB pixel colors of the image (built on first use, rebuilt when the image changes).
    var pixels: PixelReader {
        if let p = pixelCache { return p }
        let p = PixelReader(image)
        pixelCache = p
        return p
    }

    /// Continues from the most recently placed counter, so typing 10 on one badge makes the next one 11.
    var nextCounter: Int { (objects.last { $0.kind == .counter }?.number ?? 0) + 1 }

    /// Flattens the image, annotations and backdrop into a single bitmap.
    func render() -> CGImage? {
        let size = Renderer.canvasSize(self)
        var space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        if space.model != .rgb { space = CGColorSpace(name: CGColorSpace.sRGB)! }
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        Renderer.render(self, in: ctx)
        return ctx.makeImage()
    }
}

enum Renderer {
    /// The screenshot's top-left corner on the canvas (moved in by the backdrop).
    static func imageOrigin(_ doc: EditorDocument) -> CGPoint { doc.layout.imageOrigin }

    static func canvasSize(_ doc: EditorDocument) -> CGSize { doc.layout.canvas }

    /// Renders into a flipped context whose units are canvas pixels.
    static func render(_ doc: EditorDocument, in ctx: CGContext, extra: Annotation? = nil, hiddenID: UUID? = nil,
                       selectedIDs: Set<UUID> = [], cropRect: CGRect? = nil, cutStrip: CutOut.Strip? = nil, hairline: CGFloat = 1, interactive: Bool = false,
                       textHiddenID: UUID? = nil) {
        let lay = doc.layout
        let size = lay.canvas
        let imgRect = doc.imageRect

        ctx.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer {
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
        }

        let b = doc.backdrop
        if b.isOn {
            if lay.outerRadius > 0 {
                ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: lay.outerRadius, cornerHeight: lay.outerRadius,
                                   transform: nil))
                ctx.clip()
            }
            BackdropPainter.paintFill(b, size: size, image: doc.image, blurred: { doc.blurredBackdrop }, in: ctx)
            let shadowColor = NSColor.black.withAlphaComponent(max(0, min(1, b.shadow))).cgColor
            let shadowOffset = CGSize(width: 0, height: -lay.shadowBlur * 0.24)
            let framed = lay.content.size != imgRect.size
            if framed {
                // Inset: a frosted frame around the screenshot, carrying the shadow.
                let ins = lay.imageOrigin.x - lay.content.minX
                let r = lay.innerRadius + ins
                let frame = CGPath(roundedRect: lay.content, cornerWidth: r, cornerHeight: r, transform: nil)
                ctx.saveGState()
                if b.shadow > 0 { ctx.setShadow(offset: shadowOffset, blur: lay.shadowBlur, color: shadowColor) }
                ctx.addPath(frame)
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.32).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
                ctx.addPath(frame)
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
                ctx.setLineWidth(max(1, ins * 0.04))
                ctx.strokePath()
            }
            ctx.translateBy(x: lay.imageOrigin.x, y: lay.imageOrigin.y)
            let radius = lay.innerRadius
            let path = CGPath(roundedRect: imgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if !framed && b.shadow > 0 {
                ctx.saveGState()
                ctx.setShadow(offset: shadowOffset, blur: lay.shadowBlur, color: shadowColor)
                if doc.hasAlpha {
                    // Window captures keep their own transparent corners and shadow; let the shadow follow the alpha.
                    ctx.drawFlipped(doc.image, in: imgRect)
                } else {
                    ctx.addPath(path)
                    ctx.setFillColor(NSColor.black.cgColor)
                    ctx.fillPath()
                }
                ctx.restoreGState()
            }
            if !doc.hasAlpha && radius > 0 {
                ctx.addPath(path)
                ctx.clip()
            }
        }

        ctx.drawFlipped(doc.image, in: imgRect)

        var objs = doc.objects.filter { $0.id != hiddenID }
        if let extra { objs.append(extra) }

        // Pixel-altering objects sit below the spotlight dimming; strokes and labels sit above it.
        let underSpotlight: Set<Tool> = [.blur, .highlighter]
        for o in objs where underSpotlight.contains(o.kind) {
            draw(o, doc: doc, ctx: ctx)
            // A Text-mode region still being scanned shows its outline on screen only.
            if interactive, o.kind == .blur, o.blurMode.textOnly, o.textRects == nil {
                ctx.saveGState()
                ctx.setStrokeColor(Palette.accent.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(1.5 * hairline)
                ctx.setLineDash(phase: 0, lengths: [4 * hairline, 3 * hairline])
                ctx.stroke(o.rect)
                ctx.restoreGState()
            }
        }

        let spots = objs.filter { $0.kind == .spotlight }
        if !spots.isEmpty {
            ctx.saveGState()
            ctx.addRect(imgRect)
            for s in spots {
                let r = s.rect
                let c = min(8, r.width / 2, r.height / 2)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil))
            }
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
        }

        for o in objs where o.kind != .spotlight && !underSpotlight.contains(o.kind) {
            draw(o, doc: doc, ctx: ctx, showText: o.id != textHiddenID)
        }

        for o in objs where selectedIDs.contains(o.id) {
            ctx.saveGState()
            ctx.setStrokeColor(Palette.accent.cgColor)
            ctx.setLineWidth(1.5 * hairline)
            ctx.setLineDash(phase: 0, lengths: [5 * hairline, 4 * hairline])
            ctx.stroke(o.bounds.insetBy(dx: -4 * hairline, dy: -4 * hairline))
            if o.kind == .magnifier {
                let lens = o.lensRect
                let label = o.factor.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(o.factor))×" : String(format: "%.2g×", o.factor)
                drawLabel(label, at: CGPoint(x: lens.maxX - 6 * hairline, y: lens.maxY - 6 * hairline), size: 12 * hairline, ctx: ctx, centered: true)
            }
            if (o.kind == .counter && o.shape == .bubble) || o.kind == .callout {
                let t = o.kind == .callout ? o.calloutPointer : o.tailTip, hr = 5 * hairline
                let handle = CGRect(x: t.x - hr, y: t.y - hr, width: 2 * hr, height: 2 * hr)
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: handle)
                ctx.strokeEllipse(in: handle)
            }
            ctx.restoreGState()
        }

        if let c = cropRect {
            ctx.saveGState()
            ctx.addRect(imgRect)
            ctx.addRect(c)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(Palette.accent.cgColor)
            ctx.setLineWidth(1.5 * hairline)
            ctx.stroke(c)
            ctx.restoreGState()
            let label = "\(Int(c.width)) × \(Int(c.height))  ↩ to crop"
            drawLabel(label, at: CGPoint(x: c.minX, y: c.maxY + 6 * hairline), size: 12 * hairline, ctx: ctx)
        }

        if let strip = cutStrip {
            // The band to remove: red tint, diagonal hatching and dashed scissor lines on both edges.
            let r = strip.rect(in: imgRect.size)
            ctx.saveGState()
            ctx.clip(to: r)
            ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.28).cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(2 * hairline)
            let step = 14 * hairline
            var x = r.minX - r.height
            while x < r.maxX {
                ctx.move(to: CGPoint(x: x, y: r.maxY))
                ctx.addLine(to: CGPoint(x: x + r.height, y: r.minY))
                x += step
            }
            ctx.strokePath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.systemRed.cgColor)
            ctx.setLineWidth(1.5 * hairline)
            ctx.setLineDash(phase: 0, lengths: [6 * hairline, 4 * hairline])
            if strip.rows {
                for y in [r.minY, r.maxY] { ctx.move(to: CGPoint(x: r.minX, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y)) }
            } else {
                for x in [r.minX, r.maxX] { ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addLine(to: CGPoint(x: x, y: r.maxY)) }
            }
            ctx.strokePath()
            ctx.restoreGState()
            let label = "✂︎ \(Int(strip.length)) px  ↩ to cut out"
            drawLabel(label, at: CGPoint(x: r.minX + 6 * hairline, y: r.minY + 6 * hairline), size: 12 * hairline, ctx: ctx)
        }
    }

    static func draw(_ o: Annotation, doc: EditorDocument, ctx: CGContext, showText: Bool = true) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(o.color.cgColor)
        ctx.setFillColor(o.color.cgColor)
        ctx.setLineWidth(o.width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if o.dashed, [.rect, .oval, .line].contains(o.kind) {
            ctx.setLineCap(.butt)
            ctx.setLineDash(phase: 0, lengths: [o.width * 2.5, o.width * 1.6])
        }

        if o.sketch, [.arrow, .line, .rect, .oval].contains(o.kind) {
            drawSketch(o, ctx: ctx)
            return
        }

        switch o.kind {
        case .arrow:
            drawArrow(o, ctx: ctx)
        case .line:
            ctx.move(to: o.p1); ctx.addLine(to: o.p2); ctx.strokePath()
        case .rect, .oval:
            let r = o.rect
            let c = min(o.width, r.width / 2, r.height / 2)
            let path = o.kind == .rect ? CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil) : CGPath(ellipseIn: r, transform: nil)
            if o.fill != .none {
                ctx.addPath(path)
                ctx.setFillColor(o.color.withAlphaComponent(o.fill == .opaque ? 1 : 0.3).cgColor)
                ctx.fillPath()
            }
            ctx.addPath(path)
            ctx.strokePath()
        case .freehand:
            guard let f = o.points.first, o.points.count > 1 else { return }
            ctx.move(to: f)
            ctx.addLines(between: o.points)
            ctx.strokePath()
        case .highlighter:
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(o.color.withAlphaComponent(0.55).cgColor)
            ctx.fill(o.rect)
        case .blur:
            let regions = o.blurMode.textOnly ? (o.textRects ?? []) : [o.rect]
            for r in regions where r.width > 0 && r.height > 0 {
                if o.blurMode.erases {
                    // Erase fills with the average color around the region (Shottr: "average").
                    ctx.setFillColor(doc.edgeColor(around: r).cgColor)
                    ctx.fill(r)
                } else if let patch = doc.concealedPatch(for: r, textLine: o.blurMode.textOnly) {
                    ctx.drawFlipped(patch, in: r.integral.intersection(doc.imageRect))
                }
            }
        case .counter:
            let path = o.counterPath
            ctx.addPath(path)
            ctx.fillPath()
            // Thin contrasting rim keeps the badge readable on backgrounds of the same color.
            ctx.addPath(path)
            ctx.setStrokeColor(o.color.contrasting.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(max(1, o.counterRadius * 0.08))
            ctx.strokePath()
            let attrs: [NSAttributedString.Key: Any] = [.font: o.counterFont, .foregroundColor: o.color.contrasting]
            let s = "\(o.number)" as NSString
            let sz = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: o.p1.x - sz.width / 2, y: o.p1.y - sz.height / 2), withAttributes: attrs)
        case .text:
            // Outline pass in each run's contrasting color, then the fill pass.
            let fill = o.attributedText()
            let outline = NSMutableAttributedString(attributedString: fill)
            fill.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: fill.length)) { value, range, _ in
                let c = (value as? NSColor) ?? o.color
                outline.addAttributes([.strokeColor: c.contrasting.withAlphaComponent(0.9), .strokeWidth: 12], range: range)
            }
            outline.draw(at: o.p1)
            fill.draw(at: o.p1)
        case .magnifier:
            drawMagnifier(o, doc: doc, ctx: ctx)
        case .ruler:
            drawRuler(o, scale: doc.scale, ctx: ctx)
        case .callout:
            drawCallout(o, ctx: ctx, showText: showText)
        case .image:
            guard let img = doc.overlayImage(for: o) else { return }
            ctx.interpolationQuality = .high
            ctx.drawFlipped(img, in: o.rect)
        default:
            break
        }
    }

    /// Hand-drawn version of an arrow, line, rectangle or oval (fills stay clean underneath the strokes).
    private static func drawSketch(_ o: Annotation, ctx: CGContext) {
        let r = o.rect
        if o.fill != .none, o.kind == .rect || o.kind == .oval {
            ctx.addPath(o.kind == .rect ? CGPath(rect: r, transform: nil) : CGPath(ellipseIn: r, transform: nil))
            ctx.setFillColor(o.color.withAlphaComponent(o.fill == .opaque ? 1 : 0.3).cgColor)
            ctx.fillPath()
        }
        let path: CGPath
        switch o.kind {
        case .oval:
            path = Sketch.ellipse(in: r, width: o.width, id: o.id)
        case .rect:
            let c = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            path = Sketch.strokes([(c[0], c[1]), (c[1], c[2]), (c[2], c[3]), (c[3], c[0])], width: o.width, id: o.id)
        case .arrow:
            path = Sketch.strokes([(o.p1, o.p2)] + Sketch.arrowHead(from: o.p1, to: o.p2, width: o.width), width: o.width, id: o.id)
        default:
            path = Sketch.strokes([(o.p1, o.p2)], width: o.width, id: o.id)
        }
        // Each pass is a little thinner than the pen, so the doubled stroke reads as one marker line.
        ctx.setLineWidth(max(1, o.width * 0.8))
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func drawArrow(_ o: Annotation, ctx: CGContext) {
        let len = o.p1.distance(to: o.p2)
        guard len > 1 else { return }
        if o.arrowStyle != .tapered {
            drawLineArrow(o, len: len, ctx: ctx)
            return
        }
        let ux = (o.p2.x - o.p1.x) / len, uy = (o.p2.y - o.p1.y) / len
        let nx = -uy, ny = ux
        let headLen = min(max(14, o.width * 4.5), len)
        let headHalf = headLen * 0.5
        let base = CGPoint(x: o.p2.x - ux * headLen * 0.85, y: o.p2.y - uy * headLen * 0.85)
        let back = CGPoint(x: o.p2.x - ux * headLen, y: o.p2.y - uy * headLen)
        let tail = o.width * 0.2, neck = o.width * 0.5

        let path = CGMutablePath()
        path.move(to: CGPoint(x: o.p1.x + nx * tail, y: o.p1.y + ny * tail))
        path.addLine(to: CGPoint(x: base.x + nx * neck, y: base.y + ny * neck))
        path.addLine(to: CGPoint(x: back.x + nx * headHalf, y: back.y + ny * headHalf))
        path.addLine(to: o.p2)
        path.addLine(to: CGPoint(x: back.x - nx * headHalf, y: back.y - ny * headHalf))
        path.addLine(to: CGPoint(x: base.x - nx * neck, y: base.y - ny * neck))
        path.addLine(to: CGPoint(x: o.p1.x - nx * tail, y: o.p1.y - ny * tail))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setLineWidth(max(1, o.width * 0.35))
        ctx.drawPath(using: .fillStroke)
    }

    private static func drawCallout(_ o: Annotation, ctx: CGContext, showText: Bool) {
        let (body, extras) = o.calloutShape()
        let border = max(1.5, o.width * 0.55)
        let shadow = NSColor.black.withAlphaComponent(0.28).cgColor
        let blur = max(6, o.fontSize * 0.45)

        func paint(_ path: CGPath, fill: CGColor, stroke: CGColor?, lineWidth: CGFloat, shadowed: Bool) {
            ctx.saveGState()
            if shadowed { ctx.setShadow(offset: CGSize(width: 0, height: -blur * 0.3), blur: blur, color: shadow) }
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
            ctx.restoreGState()
            guard let stroke else { return }
            ctx.addPath(path)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(lineWidth)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }

        switch o.calloutStyle {
        case .box:
            paint(body, fill: o.color.cgColor, stroke: nil, lineWidth: 0, shadowed: true)
        case .card:
            paint(body, fill: NSColor.white.cgColor, stroke: o.color.cgColor, lineWidth: border * 0.7, shadowed: true)
        case .speech:
            paint(body, fill: NSColor.white.cgColor, stroke: o.color.cgColor, lineWidth: border, shadowed: false)
        case .thought:
            paint(body, fill: NSColor.white.cgColor, stroke: o.color.cgColor, lineWidth: border, shadowed: false)
            for r in extras { paint(CGPath(ellipseIn: r, transform: nil), fill: NSColor.white.cgColor, stroke: o.color.cgColor, lineWidth: border, shadowed: false) }
        case .shout:
            paint(body, fill: o.color.cgColor, stroke: o.color.contrasting.withAlphaComponent(0.85).cgColor, lineWidth: border, shadowed: true)
        }
        if showText { o.attributedText().draw(at: o.textOrigin) }
    }

    /// Shottr's ObjMagnifier: source outline (lmagnifier), connector (lmagline) and an enlarged lens with a border (lmagborder).
    private static func drawMagnifier(_ o: Annotation, doc: EditorDocument, ctx: CGContext) {
        let src = o.rect, lens = o.lensRect
        guard src.width > 0, src.height > 0 else { return }
        let line = max(1.5, o.width * 0.5)
        let halo = NSColor.white.withAlphaComponent(0.9).cgColor

        // Connector between the two outlines, drawn first so the lens sits on top of it.
        if !lens.intersects(src) {
            let a = Annotation.outlinePoint(of: src, shape: o.lensShape, toward: CGPoint(x: lens.midX, y: lens.midY))
            let b = Annotation.outlinePoint(of: lens, shape: o.lensShape, toward: CGPoint(x: src.midX, y: src.midY))
            for (color, w) in [(halo, line + 2), (o.color.cgColor, line)] {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(w)
                ctx.move(to: a)
                ctx.addLine(to: b)
                ctx.strokePath()
            }
        }

        // Source area outline.
        for (color, w) in [(halo, line + 2), (o.color.cgColor, line)] {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(w)
            ctx.addPath(o.lensShape.path(src))
            ctx.strokePath()
        }

        // Lens: shadow, enlarged image, then the border.
        let lensPath = o.lensShape.path(lens)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -lens.height * 0.02), blur: max(6, lens.width * 0.05),
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(lensPath)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(lensPath)
        ctx.clip()
        ctx.interpolationQuality = o.factor >= 3 ? .none : .high
        // Map the source rect onto the lens rect.
        ctx.translateBy(x: lens.minX, y: lens.minY)
        ctx.scaleBy(x: o.factor, y: o.factor)
        ctx.translateBy(x: -src.minX, y: -src.minY)
        ctx.drawFlipped(doc.image, in: doc.imageRect)
        ctx.restoreGState()

        for (color, w) in [(halo, o.width + 3), (o.color.cgColor, o.width)] {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(w)
            ctx.addPath(lensPath)
            ctx.strokePath()
        }
    }

    /// Straight shaft with filled heads: one at the end, or both ends for the double arrow.
    private static func drawLineArrow(_ o: Annotation, len: CGFloat, ctx: CGContext) {
        let ux = (o.p2.x - o.p1.x) / len, uy = (o.p2.y - o.p1.y) / len
        let heads = o.arrowStyle == .double ? 2 : 1
        let headLen = min(max(12, o.width * 3.6), len / CGFloat(heads))
        let headHalf = headLen * 0.55
        let start = heads == 2 ? CGPoint(x: o.p1.x + ux * headLen * 0.8, y: o.p1.y + uy * headLen * 0.8) : o.p1
        let end = CGPoint(x: o.p2.x - ux * headLen * 0.8, y: o.p2.y - uy * headLen * 0.8)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        func head(tip: CGPoint, dx: CGFloat, dy: CGFloat) {
            let back = CGPoint(x: tip.x - dx * headLen, y: tip.y - dy * headLen)
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: back.x - dy * headHalf, y: back.y + dx * headHalf))
            ctx.addLine(to: CGPoint(x: back.x + dy * headHalf, y: back.y - dx * headHalf))
            ctx.closePath()
        }
        head(tip: o.p2, dx: ux, dy: uy)
        if heads == 2 { head(tip: o.p1, dx: -ux, dy: -uy) }
        ctx.setLineWidth(max(1, o.width * 0.5))
        ctx.drawPath(using: .fillStroke)
    }

    private static func drawRuler(_ o: Annotation, scale: CGFloat, ctx: CGContext) {
        let len = o.p1.distance(to: o.p2)
        guard len > 1 else { return }
        let nx = -(o.p2.y - o.p1.y) / len, ny = (o.p2.x - o.p1.x) / len
        let tick = max(6, o.width * 2)
        ctx.setLineWidth(max(1, o.width / 2))
        ctx.move(to: o.p1); ctx.addLine(to: o.p2)
        for p in [o.p1, o.p2] {
            ctx.move(to: CGPoint(x: p.x + nx * tick, y: p.y + ny * tick))
            ctx.addLine(to: CGPoint(x: p.x - nx * tick, y: p.y - ny * tick))
        }
        ctx.strokePath()
        // Shottr's PX/PT switch: points divide by the capture's backing scale.
        let k = o.rulerInPoints ? scale : 1, unit = o.rulerInPoints ? "pt" : "px"
        let dx = Int((abs(o.p2.x - o.p1.x) / k).rounded()), dy = Int((abs(o.p2.y - o.p1.y) / k).rounded())
        let total = Int((len / k).rounded())
        let text = dx == 0 || dy == 0 ? "\(total) \(unit)" : "\(total) \(unit) (\(dx)×\(dy))"
        let mid = CGPoint(x: (o.p1.x + o.p2.x) / 2 + nx * tick * 2, y: (o.p1.y + o.p2.y) / 2 + ny * tick * 2)
        drawLabel(text, at: mid, size: max(12, o.width * 3.5), ctx: ctx, centered: true)
    }

    static func drawLabel(_ text: String, at p: CGPoint, size: CGFloat, ctx: CGContext, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white]
        let s = (text as NSString).size(withAttributes: attrs)
        let padX = size * 0.5, padY = size * 0.2
        var r = CGRect(x: p.x, y: p.y, width: s.width + 2 * padX, height: s.height + 2 * padY)
        if centered { r.origin = CGPoint(x: p.x - r.width / 2, y: p.y - r.height / 2) }
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: size * 0.35, cornerHeight: size * 0.35, transform: nil))
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        (text as NSString).draw(at: CGPoint(x: r.minX + padX, y: r.minY + padY), withAttributes: attrs)
    }
}
