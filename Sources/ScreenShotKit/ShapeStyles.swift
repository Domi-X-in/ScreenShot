import AppKit

/// What each kind of object takes from the top toolbar's Shape Styles and Font Color (PowerPoint's rules: a line has an
/// outline but no fill, a text box takes a font color).
enum ShapeKinds {
    /// Shape Fill: the fill of a rectangle or oval; the body of a callout, counter or highlight.
    static func takesFill(_ k: Tool) -> Bool { [.rect, .oval, .callout, .counter, .highlighter].contains(k) }
    /// Shape Outline: the stroke of shapes, lines and drawings (a callout's border is its color too).
    static func takesOutline(_ k: Tool) -> Bool { [.rect, .oval, .arrow, .line, .freehand, .ruler, .magnifier, .callout].contains(k) }
    /// Only rectangles and ovals can lose their outline or have a fill color apart from it.
    static func hasSeparateFill(_ k: Tool) -> Bool { k == .rect || k == .oval }
    /// Weight presets apply to strokes.
    static func takesWeight(_ k: Tool) -> Bool { [.rect, .oval, .arrow, .line, .freehand, .ruler, .magnifier].contains(k) }
    /// Dashed applies to rectangles, ovals and lines; hand-drawn also to arrows.
    static func takesDash(_ k: Tool) -> Bool { [.rect, .oval, .line].contains(k) }
    static func takesSketch(_ k: Tool) -> Bool { [.rect, .oval, .line, .arrow].contains(k) }
    /// Objects whose text Font Color colors.
    static func holdsText(_ o: Annotation) -> Bool { o.kind == .text || o.kind == .callout || (o.holdsTextInShape && !o.text.isEmpty) }
    /// Objects that Rotate and Flip turn (text and callout bubbles stay upright and only move with a group).
    static func turns(_ k: Tool) -> Bool { [.rect, .oval, .arrow, .line, .freehand, .highlighter, .ruler, .image, .counter, .blur, .spotlight, .magnifier].contains(k) }
}

/// Outline › Dashes.
enum DashStyle: Int, CaseIterable {
    case solid, dashed, handDrawn

    var title: String {
        switch self {
        case .solid: "Solid"
        case .dashed: "Dashed"
        case .handDrawn: "Hand-Drawn"
        }
    }

    var symbol: String {
        switch self {
        case .solid: "line.diagonal"
        case .dashed: "line.horizontal.3.decrease"
        case .handDrawn: "scribble"
        }
    }

    init(dashed: Bool, sketch: Bool) { self = sketch ? .handDrawn : dashed ? .dashed : .solid }
}

// MARK: - Groups

enum Grouping {
    /// `ids` plus every object grouped with one of them (a group is selected as a whole).
    static func expand(_ ids: Set<UUID>, in objects: [Annotation]) -> Set<UUID> {
        let groups = Set(objects.filter { ids.contains($0.id) }.compactMap(\.groupID))
        guard !groups.isEmpty else { return ids }
        return ids.union(objects.filter { $0.groupID.map(groups.contains) == true }.map(\.id))
    }

    /// The selected objects as the units Arrange works on: each group is one unit, each other object its own.
    /// Indices into `objects`, in stacking order.
    static func units(_ objects: [Annotation], selected: Set<UUID>) -> [[Int]] {
        var out: [[Int]] = []
        var groupSlot: [UUID: Int] = [:]
        for i in objects.indices where selected.contains(objects[i].id) {
            if let g = objects[i].groupID {
                if let slot = groupSlot[g] { out[slot].append(i) } else { groupSlot[g] = out.count; out.append([i]) }
            } else {
                out.append([i])
            }
        }
        return out
    }

    /// Group: the selection becomes one group (groups inside it merge, as nesting isn't kept).
    static func group(_ objects: [Annotation], selected: Set<UUID>) -> [Annotation] {
        guard units(objects, selected: selected).count >= 2 else { return objects }
        let id = UUID()
        return objects.map { var o = $0; if selected.contains(o.id) { o.groupID = id }; return o }
    }

    /// Copies (duplicate, ⌥-drag, paste) form groups of their own instead of joining the originals'.
    static func regroupCopies(_ copies: [Annotation]) -> [Annotation] {
        var fresh: [UUID: UUID] = [:]
        return copies.map { o in
            var c = o
            if let g = o.groupID { c.groupID = fresh[g] ?? { let n = UUID(); fresh[g] = n; return n }() }
            return c
        }
    }

    static func ungroup(_ objects: [Annotation], selected: Set<UUID>) -> [Annotation] {
        objects.map { var o = $0; if selected.contains(o.id) { o.groupID = nil }; return o }
    }
}

// MARK: - Rotate and flip

/// Arrange › Rotate: quarter turns and mirror images of the selected objects (a group turns around its own center).
enum TransformAction: String, CaseIterable {
    case rotateRight, rotateLeft, flipVertical, flipHorizontal

    var title: String {
        switch self {
        case .rotateRight: "Rotate Right 90°"
        case .rotateLeft: "Rotate Left 90°"
        case .flipVertical: "Flip Vertical"
        case .flipHorizontal: "Flip Horizontal"
        }
    }

    var symbol: String {
        switch self {
        case .rotateRight: "rotate.right"
        case .rotateLeft: "rotate.left"
        case .flipVertical: "arrow.up.and.down.righttriangle.up.righttriangle.down"
        case .flipHorizontal: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        }
    }

    /// Where an offset from the center goes (image coordinates, y down).
    func map(_ d: CGVector) -> CGVector {
        switch self {
        case .rotateRight: CGVector(dx: -d.dy, dy: d.dx)
        case .rotateLeft: CGVector(dx: d.dy, dy: -d.dx)
        case .flipVertical: CGVector(dx: d.dx, dy: -d.dy)
        case .flipHorizontal: CGVector(dx: -d.dx, dy: d.dy)
        }
    }
}

enum ShapeTransform {
    static func apply(_ action: TransformAction, to objects: [Annotation], selected: Set<UUID>) -> [Annotation] {
        var out = objects
        for unit in Grouping.units(objects, selected: selected) {
            guard unit.contains(where: { ShapeKinds.turns(objects[$0].kind) }) else { continue }
            let box = unit.dropFirst().reduce(objects[unit[0]].frame) { $0.union(objects[$1].frame) }
            // A lone counter turns around its badge, not around the badge and its pointer.
            let c = unit.count == 1 && objects[unit[0]].kind == .counter ? objects[unit[0]].p1 : CGPoint(x: box.midX, y: box.midY)
            for i in unit { out[i] = transformed(objects[i], action, around: c) }
        }
        return out
    }

    static func transformed(_ original: Annotation, _ action: TransformAction, around c: CGPoint) -> Annotation {
        var o = original
        func f(_ p: CGPoint) -> CGPoint {
            let d = action.map(CGVector(dx: p.x - c.x, dy: p.y - c.y))
            return CGPoint(x: c.x + d.dx, y: c.y + d.dy)
        }
        guard ShapeKinds.turns(o.kind) else {
            // Text and callout bubbles stay upright: they only move with the group (a callout's tip turns with it).
            let box = o.frame
            let moved = f(CGPoint(x: box.midX, y: box.midY))
            let pointer = o.pointer.map(f)
            o.offset(by: CGVector(dx: moved.x - box.midX, dy: moved.y - box.midY))
            if o.kind == .callout { o.pointer = pointer }
            return o
        }
        o.p1 = f(o.p1)
        o.p2 = f(o.p2)
        o.points = o.points.map(f)
        o.lensCenter = o.lensCenter.map(f)
        o.textRects = nil
        if o.kind == .counter {
            // The bubble's pointer turns too (angles in flipped coordinates: clockwise is positive).
            switch action {
            case .rotateRight: o.tailAngle += .pi / 2
            case .rotateLeft: o.tailAngle -= .pi / 2
            case .flipHorizontal: o.tailAngle = .pi - o.tailAngle
            case .flipVertical: o.tailAngle = -o.tailAngle
            }
        }
        if o.kind == .image, let data = o.imageData, let turned = turnImage(data, action) { o.imageData = turned }
        return o
    }

    /// The pasted image's pixels, turned or mirrored, as PNG.
    static func turnImage(_ data: Data, _ action: TransformAction) -> Data? {
        guard let rep = NSBitmapImageRep(data: data), let img = rep.cgImage else { return nil }
        let w = img.width, h = img.height
        let quarter = action == .rotateRight || action == .rotateLeft
        let (cw, ch) = quarter ? (h, w) : (w, h)
        guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Core Graphics is y-up here: a clockwise turn on screen is a negative angle.
        switch action {
        case .rotateRight: ctx.translateBy(x: 0, y: CGFloat(w)); ctx.rotate(by: -.pi / 2)
        case .rotateLeft: ctx.translateBy(x: CGFloat(h), y: 0); ctx.rotate(by: .pi / 2)
        case .flipHorizontal: ctx.translateBy(x: CGFloat(w), y: 0); ctx.scaleBy(x: -1, y: 1)
        case .flipVertical: ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}

// MARK: - Colors

/// Office's color palette: theme colors with tints and shades, standard colors, and recent custom colors.
enum OfficeColors {
    /// The theme row is the app's own palette (Shottr's colors), so the grid matches the rest of the editor.
    static let theme: [NSColor] = [
        NSColor(hex: 0xFFFFFF), NSColor(hex: 0x000000), NSColor(hex: 0x8E8E93), NSColor(hex: 0xFF3B30), NSColor(hex: 0xFF9500),
        NSColor(hex: 0xFFCC00), NSColor(hex: 0x34C759), NSColor(hex: 0x00C7BE), NSColor(hex: 0x007AFF), NSColor(hex: 0xAF52DE),
    ]

    /// Office's standard colors.
    static let standard: [NSColor] = [
        NSColor(hex: 0xC00000), NSColor(hex: 0xFF0000), NSColor(hex: 0xFFC000), NSColor(hex: 0xFFFF00), NSColor(hex: 0x92D050),
        NSColor(hex: 0x00B050), NSColor(hex: 0x00B0F0), NSColor(hex: 0x0070C0), NSColor(hex: 0x002060), NSColor(hex: 0x7030A0),
    ]

    /// Five variants under each theme color, as Office builds them: shades of a very light color, tints of a very dark
    /// one, and both for the rest. Positive values lighten (mix with white), negative ones darken.
    static func variantSteps(for c: NSColor) -> [CGFloat] {
        let l = luminance(c)
        if l > 0.8 { return [-0.05, -0.15, -0.25, -0.35, -0.5] }
        if l < 0.2 { return [0.5, 0.35, 0.25, 0.15, 0.05] }
        return [0.8, 0.6, 0.4, -0.25, -0.5]
    }

    static func variant(_ c: NSColor, _ step: CGFloat) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let mix: (CGFloat) -> CGFloat = { step >= 0 ? $0 + (1 - $0) * step : $0 * (1 + step) }
        return NSColor(srgbRed: mix(s.redComponent), green: mix(s.greenComponent), blue: mix(s.blueComponent), alpha: 1)
    }

    /// Rows of the theme grid: the theme colors, then their five variants.
    static var themeGrid: [[NSColor]] {
        [theme] + (0..<5).map { row in theme.map { variant($0, variantSteps(for: $0)[row]) } }
    }

    static func luminance(_ c: NSColor) -> CGFloat {
        let s = c.usingColorSpace(.sRGB) ?? c
        return 0.299 * s.redComponent + 0.587 * s.greenComponent + 0.114 * s.blueComponent
    }

    // MARK: Remembered colors

    private static let recentKey = "recentColors"

    /// Custom colors picked with More Colors…, newest first (Office's Recent Colors row).
    static var recent: [NSColor] {
        (UserDefaults.standard.stringArray(forKey: recentKey) ?? []).compactMap { NSColor(rgbaHex: $0) }
    }

    static func addRecent(_ c: NSColor) {
        let hex = c.rgbaHex
        var list = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        list.removeAll { $0 == hex }
        list.insert(hex, at: 0)
        UserDefaults.standard.set(Array(list.prefix(10)), forKey: recentKey)
    }

    /// Each split button remembers its own last color (the bar under its icon).
    static func lastUsed(_ control: String, default d: NSColor) -> NSColor {
        UserDefaults.standard.string(forKey: "lastColor." + control).flatMap { NSColor(rgbaHex: $0) } ?? d
    }

    static func setLastUsed(_ control: String, _ c: NSColor) {
        UserDefaults.standard.set(c.rgbaHex, forKey: "lastColor." + control)
    }
}
