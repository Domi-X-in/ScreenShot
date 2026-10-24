import AppKit

/// What the top toolbar's Shape Styles, Arrange and Align controls work on, and the commands they send. Like Office,
/// every command acts on the whole selection (a group counts as its objects), skips objects it doesn't apply to, and
/// is one undo step; with nothing selected it sets the style for the next object drawn.
extension ShotView {
    /// The selected objects, and the one being typed in.
    var styleTargets: [Annotation] {
        doc.objects.filter { selection.contains($0.id) || $0.id == editingID }
    }

    /// The kind the controls follow when nothing is selected: the tool in hand.
    private var newObjectKind: Tool? { styleTargets.isEmpty ? tool : nil }

    // MARK: State for the toolbar

    struct ShapeStyleState {
        var fillEnabled = false
        var outlineEnabled = false
        var weightEnabled = false
        var dashEnabled = false
        var sketchEnabled = false
        /// Current values; nil when the selected objects differ (mixed). `fill` is nil for No Fill, as `outline` for
        /// No Outline, so those need the `has…` flags to tell No Fill from mixed.
        var fill: NSColor?
        var fillMixed = false
        var noFill = false
        var opacity: FillStyle?
        var outline: NSColor?
        var outlineMixed = false
        var noOutline = false
        var weight: CGFloat?
        var dash: DashStyle?
        var canGroup = false
        var canUngroup = false
        var canTransform = false
        var unitCount = 0
    }

    var shapeStyleState: ShapeStyleState {
        var s = ShapeStyleState()
        let targets = styleTargets
        let units = Grouping.units(doc.objects, selected: selection).count
        s.unitCount = units
        s.canGroup = canGroup
        s.canUngroup = canUngroup
        s.canTransform = canTransform
        if let k = newObjectKind {
            // Nothing selected: the style for new objects of the current tool.
            s.fillEnabled = ShapeKinds.takesFill(k)
            s.outlineEnabled = ShapeKinds.takesOutline(k)
            s.weightEnabled = ShapeKinds.takesWeight(k)
            s.dashEnabled = ShapeKinds.takesDash(k) && !style.sketch
            s.sketchEnabled = ShapeKinds.takesSketch(k)
            let probe = Annotation(kind: k, p1: .zero, p2: .zero, style: style)
            s.noFill = ShapeKinds.hasSeparateFill(k) && style.fill == .none
            s.fill = s.noFill ? nil : Self.fillColor(of: probe)
            s.opacity = ShapeKinds.hasSeparateFill(k) ? style.fill : nil
            s.noOutline = ShapeKinds.hasSeparateFill(k) && style.noOutline
            s.outline = s.noOutline ? nil : style.color
            s.weight = style.width
            s.dash = DashStyle(dashed: style.dashed, sketch: style.sketch)
            return s
        }
        let fills = targets.filter { ShapeKinds.takesFill($0.kind) }
        let outlines = targets.filter { ShapeKinds.takesOutline($0.kind) }
        let weights = targets.filter { ShapeKinds.takesWeight($0.kind) }
        let dashes = targets.filter { ShapeKinds.takesSketch($0.kind) }
        s.fillEnabled = !fills.isEmpty
        s.outlineEnabled = !outlines.isEmpty
        s.weightEnabled = !weights.isEmpty
        s.sketchEnabled = !dashes.isEmpty
        s.dashEnabled = targets.contains { ShapeKinds.takesDash($0.kind) }
        func shared<T: Equatable>(_ values: [T]) -> T? { values.first.flatMap { f in values.allSatisfy { $0 == f } ? f : nil } }
        let fillKeys = fills.map { o -> String in
            ShapeKinds.hasSeparateFill(o.kind) && o.fill == .none ? "none" : Self.fillColor(of: o).rgbaHex
        }
        if let key = shared(fillKeys) {
            s.noFill = key == "none"
            s.fill = s.noFill ? nil : NSColor(rgbaHex: key)
        } else {
            s.fillMixed = !fills.isEmpty
        }
        s.opacity = shared(fills.filter { ShapeKinds.hasSeparateFill($0.kind) }.map(\.fill))
        let outlineKeys = outlines.map { $0.noOutline && ShapeKinds.hasSeparateFill($0.kind) ? "none" : $0.color.rgbaHex }
        if let key = shared(outlineKeys) {
            s.noOutline = key == "none"
            s.outline = s.noOutline ? nil : NSColor(rgbaHex: key)
        } else {
            s.outlineMixed = !outlines.isEmpty
        }
        s.weight = shared(weights.map(\.width))
        s.dash = shared(dashes.map { DashStyle(dashed: $0.dashed, sketch: $0.sketch) })
        return s
    }

    /// The color an object's Shape Fill shows.
    static func fillColor(of o: Annotation) -> NSColor { ShapeKinds.hasSeparateFill(o.kind) ? o.fillPaint : o.color }

    var canGroup: Bool { Grouping.units(doc.objects, selected: selection).count >= 2 }
    var canUngroup: Bool { doc.objects.contains { selection.contains($0.id) && $0.groupID != nil } }
    var canTransform: Bool { doc.objects.contains { selection.contains($0.id) && ShapeKinds.turns($0.kind) } }

    // MARK: Shape Fill and Shape Outline

    /// One undoable change to every selected object `applies` accepts, and to the style for new objects.
    private func restyle(_ applies: (Annotation) -> Bool, newStyle: (inout ToolStyle, Tool) -> Void, change: (inout Annotation) -> Void) {
        let ids = Set(styleTargets.filter(applies).map(\.id))
        if let k = newObjectKind {
            newStyle(&style, k)
            controller?.syncToolbar()
            return
        }
        guard !ids.isEmpty else { NSSound.beep(); return }
        var changed: [(Int, Annotation)] = []
        for i in doc.objects.indices where ids.contains(doc.objects[i].id) {
            var o = doc.objects[i]
            change(&o)
            if (try? JSONEncoder().encode(o)) != (try? JSONEncoder().encode(doc.objects[i])) { changed.append((i, o)) }
        }
        guard !changed.isEmpty else { controller?.syncToolbar(); return }
        pushUndo()
        for (i, o) in changed {
            let oldBase = doc.objects[i].baseTextColor
            doc.objects[i] = o
            followBaseTextColor(at: i, from: oldBase)
        }
        controller?.documentChanged(resized: false)
        needsDisplay = true
    }

    /// Letters that had the object's automatic text color (readable on a filled callout or shape) keep up with it.
    private func followBaseTextColor(at i: Int, from oldBase: NSColor) {
        let newBase = doc.objects[i].baseTextColor
        guard oldBase.rgbaHex != newBase.rgbaHex else { return }
        if doc.objects[i].id == editingID, let editor = textField?.currentEditor() as? NSTextView, let storage = editor.textStorage {
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.enumerateAttribute(.foregroundColor, in: all) { value, r, _ in
                if (value as? NSColor)?.rgbaHex == oldBase.rgbaHex { storage.addAttribute(.foregroundColor, value: newBase, range: r) }
            }
            storage.endEditing()
            if (editor.typingAttributes[.foregroundColor] as? NSColor)?.rgbaHex == oldBase.rgbaHex {
                editor.typingAttributes[.foregroundColor] = newBase
            }
            editor.needsDisplay = true
        }
        doc.objects[i].runs = doc.objects[i].runs?.map { r in
            var r = r
            if r.color == oldBase.rgbaHex { r.color = newBase.rgbaHex }
            return r
        }
    }

    /// Shape Fill: a color (filling a shape that had none), or nil for No Fill.
    func applyFill(_ c: NSColor?) {
        restyle({ ShapeKinds.takesFill($0.kind) && (c != nil || ShapeKinds.hasSeparateFill($0.kind)) }, newStyle: { s, k in
            if ShapeKinds.hasSeparateFill(k) {
                if let c { s.fillColor = c; if s.fill == .none { s.fill = .opaque } } else { s.fill = .none }
            } else if let c {
                s.color = c
            }
        }, change: { o in
            if ShapeKinds.hasSeparateFill(o.kind) {
                if let c { o.fillColor = c; if o.fill == .none { o.fill = .opaque } } else { o.fill = .none }
            } else if let c {
                o.color = c
            }
        })
    }

    /// Shape Fill › Transparency: translucent or opaque (No Fill is `applyFill(nil)`).
    func applyFillOpacity(_ f: FillStyle) {
        restyle({ ShapeKinds.hasSeparateFill($0.kind) }, newStyle: { s, _ in s.fill = f }, change: { $0.fill = f })
    }

    /// Shape Outline: a color, or nil for No Outline. A shape filled with its outline's color keeps that fill.
    func applyOutline(_ c: NSColor?) {
        restyle({ ShapeKinds.takesOutline($0.kind) && (c != nil || ShapeKinds.hasSeparateFill($0.kind)) }, newStyle: { s, k in
            if let c {
                if ShapeKinds.hasSeparateFill(k), s.fillColor == nil, s.fill != .none { s.fillColor = s.color }
                s.color = c
                s.noOutline = false
            } else {
                s.noOutline = true
            }
        }, change: { o in
            if let c {
                if ShapeKinds.hasSeparateFill(o.kind), o.fillColor == nil, o.fill != .none { o.fillColor = o.color }
                o.color = c
                o.noOutline = false
            } else {
                o.noOutline = true
            }
        })
    }

    /// Shape Outline › Weight.
    func applyOutlineWeight(_ w: CGFloat) {
        restyle({ ShapeKinds.takesWeight($0.kind) }, newStyle: { s, _ in s.width = w; s.noOutline = false }, change: { o in
            o.width = w
            o.noOutline = false
        })
    }

    /// Shape Outline › Dashes: solid, dashed or hand-drawn.
    func applyDash(_ d: DashStyle) {
        restyle({ d == .dashed ? ShapeKinds.takesDash($0.kind) : ShapeKinds.takesSketch($0.kind) }, newStyle: { s, _ in
            s.dashed = d == .dashed
            s.sketch = d == .handDrawn
        }, change: { o in
            o.dashed = d == .dashed
            o.sketch = d == .handDrawn
        })
    }

    // MARK: Group, rotate and flip

    @objc func groupSelection(_ sender: Any?) {
        commitText()
        guard canGroup else { NSSound.beep(); return }
        pushUndo()
        doc.objects = Grouping.group(doc.objects, selected: selection)
        controller?.documentChanged(resized: false)
    }

    @objc func ungroupSelection(_ sender: Any?) {
        commitText()
        guard canUngroup else { NSSound.beep(); return }
        pushUndo()
        doc.objects = Grouping.ungroup(doc.objects, selected: selection)
        controller?.documentChanged(resized: false)
    }

    @objc func transformFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = TransformAction(rawValue: raw) else { return }
        transform(t)
    }

    /// Rotate Right/Left 90°, Flip Vertical/Horizontal: each object (or group) around its own center.
    func transform(_ t: TransformAction) {
        commitText()
        guard canTransform else { NSSound.beep(); return }
        pushUndo()
        doc.objects = ShapeTransform.apply(t, to: doc.objects, selected: selection)
        controller?.documentChanged(resized: true)
        scanTextRegions()
        needsDisplay = true
    }

    /// Align › Align to Selection / Align to Canvas.
    func setAlignToCanvas(_ on: Bool) {
        Settings.alignToCanvas = on
        controller?.syncToolbar()
    }
}
