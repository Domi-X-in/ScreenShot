import AppKit

/// Editor canvas (Shottr's ShotView): draws the document and turns mouse/keyboard input into annotations.
final class ShotView: NSView, NSTextFieldDelegate {
    private enum Drag {
        case none
        case create
        case move(start: CGPoint, original: Annotation, index: Int)
        case crop(start: CGPoint)
        case tail(index: Int)
        case lens(start: CGPoint, original: CGPoint, index: Int)
        case resize(handle: Handle, original: Annotation, index: Int)
        case moveMany(start: CGPoint, originals: [(Int, Annotation)], clicked: UUID?)
        case marquee(start: CGPoint, base: Set<UUID>)
        case calloutCreate(start: CGPoint)
        case calloutTip(index: Int)
    }

    /// Selection handles: corners/edges of box-like objects, endpoints of line-like ones.
    enum Handle: Equatable {
        case corner(Int) // 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left
        case edge(Int) // 0 top, 1 right, 2 bottom, 3 left
        case start, end
    }

    private(set) var doc: EditorDocument
    weak var controller: EditorWindowController?

    var tool: Tool = .arrow {
        didSet {
            commitText()
            if tool != .crop { cropRect = nil }
            if tool == .crop { Toast.show("Select the area to keep, then hit Enter to crop") }
            controller?.syncToolbar()
            needsDisplay = true
        }
    }
    /// Options in use in this editor; each new editor starts from the defaults.
    var style = ToolStyle.loadDefaults()

    private var live: Annotation?
    /// Primary selected object (its kind drives the options bar). Assigning it selects just that object.
    private var selectedID: UUID? {
        didSet {
            if !keepSelection { selection = selectedID.map { [$0] } ?? [] }
            if selectedID != oldValue { counterTyping = nil; controller?.syncToolbar() }
        }
    }
    /// Everything selected (Shift-click, drag-select, ⌘A); always contains `selectedID` when set.
    private(set) var selection: Set<UUID> = []
    private var keepSelection = false
    /// Drag-select rectangle in image coordinates while it is being drawn.
    private var marqueeRect: CGRect?
    /// Whether the current mouse-down has turned into a drag (a plain click on a multi-selection narrows it).
    private var dragMoved = false
    /// Counter currently being renumbered from the keyboard; digits typed within a short pause append to it.
    private var counterTyping: (id: UUID, at: Date)?
    private var drag: Drag = .none
    private var cropRect: CGRect?
    private var textField: NSTextField?
    private var editingID: UUID?
    private var lastBackdrop: Backdrop = .ocean
    /// User zoom (canvas points per image pixel); nil fits the image to the view.
    private var zoomOverride: CGFloat?
    private var pan = CGPoint.zero
    private var hoverColor: NSColor?
    private var hoverPixel: CGPoint?
    /// Coalesces a scroll/pinch zoom gesture on a magnifier into one undo step.
    private var lastFactorEdit = Date.distantPast

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(doc: EditorDocument) {
        self.doc = doc
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    override func accessibilityLabel() -> String? {
        let kinds = doc.objects.map(\.kind.title)
        let summary = kinds.isEmpty ? "no annotations" : "\(kinds.count) annotation\(kinds.count == 1 ? "" : "s"): " + kinds.joined(separator: ", ")
        return "Screenshot \(doc.image.width) by \(doc.image.height) pixels, \(summary)"
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Geometry

    /// Room kept free at the bottom for the floating options card.
    var bottomInset: CGFloat = 68

    private var available: CGRect {
        CGRect(x: 20, y: 20, width: max(10, bounds.width - 40), height: max(10, bounds.height - 40 - bottomInset))
    }

    private var fitZoom: CGFloat {
        let c = Renderer.canvasSize(doc)
        let avail = available
        return max(0.02, min(avail.width / c.width, avail.height / c.height, 1 / doc.scale))
    }

    private var zoom: CGFloat { zoomOverride ?? fitZoom }

    private var origin: CGPoint {
        let c = Renderer.canvasSize(doc), z = zoom
        let a = available
        return CGPoint(x: (a.midX - c.width * z / 2 + pan.x).rounded(), y: (a.midY - c.height * z / 2 + pan.y).rounded())
    }

    /// Zoom as Shottr reports it: 100% means one image pixel per screen pixel.
    var zoomPercent: Int { Int((zoom * (window?.backingScaleFactor ?? doc.scale) * 100).rounded()) }

    /// Size shown in the toolbar's "Selection Size" cell: the crop selection, else the image.
    var selectionSize: CGSize { (tool == .crop ? cropRect?.size : nil) ?? doc.image.size }

    func setZoom(_ z: CGFloat?, around viewPoint: CGPoint? = nil) {
        let anchor = viewPoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let before = toImage(anchor)
        zoomOverride = z.map { max(0.05, min(40, $0)) }
        if zoomOverride == nil {
            pan = .zero
        } else {
            // Keep the image point under the anchor still.
            let after = fromImage(before)
            pan.x += anchor.x - after.x
            pan.y += anchor.y - after.y
        }
        commitText()
        needsDisplay = true
        controller?.updateInfo()
    }

    override func magnify(with event: NSEvent) {
        let at = convert(event.locationInWindow, from: nil)
        if resizeSelectedImage(by: 1 + event.magnification, at: at) { return }
        if changeMagnifierFactor(by: 1 + event.magnification, at: at) { return }
        setZoom(zoom * (1 + event.magnification), around: at)
    }

    override func scrollWheel(with event: NSEvent) {
        let plainWheelZoom = Settings.wheelZooms && !event.hasPreciseScrollingDeltas
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || plainWheelZoom {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            setZoom(zoom * (1 + delta), around: convert(event.locationInWindow, from: nil))
        } else if resizeSelectedImage(by: 1 + (event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1),
                                      at: convert(event.locationInWindow, from: nil)) {
            return
        } else if changeMagnifierFactor(by: 1 + (event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1),
                                        at: convert(event.locationInWindow, from: nil)) {
            return
        } else if zoomOverride != nil {
            pan.x += event.scrollingDeltaX
            pan.y += event.scrollingDeltaY
            repositionTextField()
            needsDisplay = true
        }
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let z = zoom, o = origin, pad = Renderer.padding(doc)
        return CGPoint(x: (p.x - o.x) / z - pad, y: (p.y - o.y) / z - pad)
    }

    private func fromImage(_ p: CGPoint) -> CGPoint {
        let z = zoom, o = origin, pad = Renderer.padding(doc)
        return CGPoint(x: (p.x + pad) * z + o.x, y: (p.y + pad) * z + o.y)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawBackdrop(dirtyRect)
        let z = zoom, o = origin
        // The screenshot floats on the canvas like a sheet of paper.
        let sheet = CGRect(origin: o, size: CGSize(width: Renderer.canvasSize(doc).width * z, height: Renderer.canvasSize(doc).height * z))
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 34, color: NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22).cgColor)
        ctx.setFillColor(Theme.canvas.cgColor)
        ctx.fill(sheet)
        ctx.restoreGState()
        if doc.hasAlpha && doc.backdrop == .none {
            // Transparent pixels show a checkerboard, like other image editors.
            let cell: CGFloat = 8
            ctx.saveGState()
            ctx.clip(to: sheet)
            ctx.setFillColor((dark ? NSColor(hex: 0x2A2B31) : NSColor.white).cgColor)
            ctx.fill(sheet)
            ctx.setFillColor((dark ? NSColor(hex: 0x33343B) : NSColor(hex: 0xE4E6EA)).cgColor)
            var y = sheet.minY, row = 0
            while y < sheet.maxY {
                var x = sheet.minX + (row % 2 == 0 ? 0 : cell)
                while x < sheet.maxX { ctx.fill(CGRect(x: x, y: y, width: cell, height: cell)); x += cell * 2 }
                y += cell; row += 1
            }
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.translateBy(x: o.x, y: o.y)
        ctx.scaleBy(x: z, y: z)
        ctx.interpolationQuality = z >= 1 ? .none : .high
        // While typing, plain text is hidden (the field shows it); a callout keeps its bubble and hides only its text.
        let editingKind = editingID.flatMap { id in doc.objects.first { $0.id == id }?.kind }
        Renderer.render(doc, in: ctx, extra: live, hiddenID: editingKind == .callout ? nil : editingID, selectedIDs: selection,
                        cropRect: tool == .crop ? cropRect : nil, hairline: 1 / z, interactive: true,
                        textHiddenID: editingKind == .callout ? editingID : nil)
        if let m = marqueeRect {
            ctx.setFillColor(Palette.accent.withAlphaComponent(0.08).cgColor)
            ctx.fill(m.offsetBy(dx: Renderer.padding(doc), dy: Renderer.padding(doc)))
            ctx.setStrokeColor(Palette.accent.cgColor)
            ctx.setLineWidth(1 / z)
            ctx.setLineDash(phase: 0, lengths: [4 / z, 3 / z])
            ctx.stroke(m.offsetBy(dx: Renderer.padding(doc), dy: Renderer.padding(doc)))
        }
        ctx.restoreGState()
        // Hairline edge keeps light screenshots distinct from a light canvas.
        ctx.setStrokeColor((dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.1)).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(sheet.insetBy(dx: -0.5, dy: -0.5))
        drawHandles(ctx)
    }

    /// Canvas color with a dot grid, from a cached pattern tile per appearance.
    private func drawBackdrop(_ dirty: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dotPattern == nil || dotPatternDark != dark {
            let tile = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
                (dark ? NSColor(hex: 0x17181D) : NSColor(hex: 0xE8EAEF)).setFill()
                NSRect(x: 0, y: 0, width: 18, height: 18).fill()
                (dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.09)).setFill()
                NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 2, height: 2)).fill()
                return true
            }
            dotPattern = NSColor(patternImage: tile)
            dotPatternDark = dark
        }
        dotPattern?.setFill()
        dirty.fill()
    }

    private var dotPattern: NSColor?
    private var dotPatternDark = false

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        repositionTextField()
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }

    private func updateCursor(at vp: CGPoint) {
        if handleHit(vp) != nil { NSCursor.crosshair.set(); return }
        if tool == .select {
            (hitIndex(toImage(vp)) != nil ? NSCursor.openHand : NSCursor.arrow).set()
        } else {
            (tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
        }
    }

    // MARK: Undo

    private var snapshot: EditorDocument.Snapshot { .init(image: doc.image, objects: doc.objects, backdrop: doc.backdrop) }

    /// Records the state before an edit; also counts as a change for auto-save.
    private func pushUndo() {
        doc.undoStack.append(snapshot)
        if doc.undoStack.count > 200 { doc.undoStack.removeFirst() }
        doc.redoStack.removeAll()
        markChanged()
    }

    /// Flags the document as edited and asks the window to auto-save shortly.
    func markChanged() {
        doc.revision += 1
        controller?.scheduleAutosave()
    }

    /// Shows another document in this canvas (thumbnail switching); its own undo history comes with it.
    func switchDocument(_ d: EditorDocument) {
        commitText()
        live = nil
        drag = .none
        cropRect = nil
        selectedID = nil
        counterTyping = nil
        zoomOverride = nil
        pan = .zero
        doc = d
        if tool == .crop { tool = .arrow }
        needsDisplay = true
    }

    private func restore(_ s: EditorDocument.Snapshot) {
        let resized = s.image.size != doc.image.size || s.backdrop != doc.backdrop
        if s.image !== doc.image { doc.image = s.image }
        doc.objects = s.objects
        doc.backdrop = s.backdrop
        selectedID = nil
        controller?.documentChanged(resized: resized)
        needsDisplay = true
        markChanged()
    }

    @objc func undo(_ sender: Any?) {
        commitText()
        guard let s = doc.undoStack.popLast() else { NSSound.beep(); return }
        doc.redoStack.append(snapshot)
        restore(s)
    }

    @objc func redo(_ sender: Any?) {
        commitText()
        guard let s = doc.redoStack.popLast() else { NSSound.beep(); return }
        doc.undoStack.append(snapshot)
        restore(s)
    }

    // MARK: Responder actions (routed from the main menu)

    /// With an object selected, copies the object (pasteable into any editor window); otherwise the whole image.
    @objc func copy(_ sender: Any?) {
        let objects = doc.objects.filter { selection.contains($0.id) }
        guard !objects.isEmpty, let data = try? JSONEncoder().encode(objects) else {
            controller?.copyImage()
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: Self.objectPasteboardType)
        Toast.show(objects.count == 1 ? "\(objects[0].kind.title) copied" : "\(objects.count) objects copied")
    }

    @objc func cut(_ sender: Any?) {
        guard selectedID != nil else { return }
        copy(sender)
        deleteSelected()
    }

    /// Pastes copied objects, or an image from the clipboard as a movable overlay.
    @objc func paste(_ sender: Any?) {
        commitText()
        let pb = NSPasteboard.general
        if let data = pb.data(forType: Self.objectPasteboardType), let objects = try? JSONDecoder().decode([Annotation].self, from: data) {
            pushUndo()
            var pasted: [UUID] = []
            defer { setSelection(Set(pasted), primary: pasted.last) }
            for var o in objects {
                o.id = UUID()
                // Same spot as the original would hide the copy; nudge it. Objects from a bigger image are pulled inside.
                if doc.objects.contains(where: { $0.p1 == o.p1 && $0.p2 == o.p2 }) { o.offset(by: CGVector(dx: 20, dy: 20)) }
                if !doc.imageRect.intersects(o.bounds) {
                    o.offset(by: CGPoint(x: doc.imageRect.midX, y: doc.imageRect.midY) - CGPoint(x: o.bounds.midX, y: o.bounds.midY))
                }
                if o.kind == .blur { o.textRects = nil }
                doc.objects.append(o)
                pasted.append(o.id)
            }
            scanTextRegions()
            needsDisplay = true
            return
        }
        guard let ns = NSImage(pasteboard: pb), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { NSSound.beep(); return }
        // Keep the pasted image at its on-screen size relative to this screenshot, shrunk to fit if needed.
        let srcScale = ns.size.width > 0 ? CGFloat(cg.width) / ns.size.width : 1
        var size = CGSize(width: CGFloat(cg.width) / srcScale * doc.scale, height: CGFloat(cg.height) / srcScale * doc.scale)
        let fit = min(1, doc.imageRect.width * 0.8 / size.width, doc.imageRect.height * 0.8 / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        let center = CGPoint(x: doc.imageRect.midX, y: doc.imageRect.midY)
        var o = Annotation(kind: .image, p1: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                           p2: CGPoint(x: center.x + size.width / 2, y: center.y + size.height / 2), color: .clear, width: 0)
        o.imageData = png
        pushUndo()
        doc.objects.append(o)
        selectedID = o.id
        needsDisplay = true
    }

    static let objectPasteboardType = NSPasteboard.PasteboardType("local.screenshot.annotations")
    @objc func saveDocument(_ sender: Any?) { controller?.saveImage() }
    @objc func saveDocumentAs(_ sender: Any?) { controller?.saveImageAs() }
    @objc func pinImage(_ sender: Any?) { controller?.pinImage() }
    @objc func delete(_ sender: Any?) { deleteSelected() }
    @objc func zoomIn(_ sender: Any?) { setZoom(zoom * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setZoom(zoom / 1.25) }
    @objc func zoomToFit(_ sender: Any?) { setZoom(nil) }

    /// 100%: one image pixel per screen pixel.
    func zoomToActualSize() { setZoom(1 / (window?.backingScaleFactor ?? doc.scale)) }
    @objc func recognizeText(_ sender: Any?) { controller?.ocrImage() }

    // MARK: Mouse

    private func constrained(_ s: CGPoint, _ p: CGPoint, _ kind: Tool, _ shift: Bool) -> CGPoint {
        guard shift else { return p }
        let dx = p.x - s.x, dy = p.y - s.y
        switch kind {
        case .arrow, .line, .ruler:
            let step = CGFloat.pi / 4
            let a = (atan2(dy, dx) / step).rounded() * step
            let l = hypot(dx, dy)
            return CGPoint(x: s.x + cos(a) * l, y: s.y + sin(a) * l)
        case .rect, .oval, .highlighter, .blur, .spotlight, .crop, .magnifier:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: s.x + (dx >= 0 ? side : -side), y: s.y + (dy >= 0 ? side : -side))
        default:
            return p
        }
    }

    /// Bubble counter whose pointer tip is under `p`; checked before the body so the tip can be grabbed.
    private func tailHandleIndex(_ p: CGPoint) -> Int? {
        doc.objects.indices.reversed().first {
            let o = doc.objects[$0]
            return o.kind == .counter && o.shape == .bubble && p.distance(to: o.tailTip) <= max(8 / zoom, o.counterRadius * 0.45)
        }
    }

    private func hitIndex(_ p: CGPoint) -> Int? {
        doc.objects.indices.reversed().first { doc.objects[$0].hit(p) }
    }

    override func mouseDown(with event: NSEvent) {
        let wasEditing = textField != nil
        dragMoved = false
        commitText()
        window?.makeFirstResponder(self)
        let p = toImage(convert(event.locationInWindow, from: nil))

        if tool == .crop {
            drag = .crop(start: p)
            cropRect = nil
            return
        }
        let vp = convert(event.locationInWindow, from: nil)
        let mods = event.modifierFlags
        if let (handle, i) = handleHit(vp) {
            pushUndo()
            drag = .resize(handle: handle, original: doc.objects[i], index: i)
            return
        }
        // Shift-click adds or removes an object from the selection.
        if mods.contains(.shift), let i = hitIndex(p) {
            var ids = selection
            let id = doc.objects[i].id
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            setSelection(ids, primary: ids.contains(id) ? id : ids.first)
            return
        }
        // ⌥-drag duplicates what is under the pointer (the whole selection if it is part of it), then drags the copies.
        if mods.contains(.option), let i = hitIndex(p) {
            let ids = selection.contains(doc.objects[i].id) ? selection : [doc.objects[i].id]
            pushUndo()
            let copies = doc.objects.filter { ids.contains($0.id) }.map { o -> Annotation in
                var c = o
                c.id = UUID()
                if c.kind == .blur { c.textRects = nil }
                return c
            }
            doc.objects.append(contentsOf: copies)
            setSelection(Set(copies.map(\.id)), primary: copies.last?.id)
            beginMoveMany(at: p)
            return
        }
        // Dragging one object of a multi-selection moves them all.
        if selection.count > 1, let i = hitIndex(p), selection.contains(doc.objects[i].id) {
            pushUndo()
            beginMoveMany(at: p, clicked: doc.objects[i].id)
            return
        }
        if let i = doc.objects.indices.reversed().first(where: { doc.objects[$0].hitLens(p) }) {
            selectedID = doc.objects[i].id
            pushUndo()
            let lens = doc.objects[i].lensRect
            drag = .lens(start: p, original: CGPoint(x: lens.midX, y: lens.midY), index: i)
            needsDisplay = true
            return
        }
        // A callout's pointer tip can be dragged anywhere.
        if let i = doc.objects.indices.reversed().first(where: {
            doc.objects[$0].kind == .callout && p.distance(to: doc.objects[$0].calloutPointer) <= max(10 / zoom, 8)
        }) {
            selectedID = doc.objects[i].id
            pushUndo()
            drag = .calloutTip(index: i)
            needsDisplay = true
            return
        }
        if let i = tailHandleIndex(p) {
            selectedID = doc.objects[i].id
            pushUndo()
            drag = .tail(index: i)
            needsDisplay = true
            return
        }
        if let i = hitIndex(p) {
            let o = doc.objects[i]
            selectedID = o.id
            if o.kind == .text || o.kind == .callout, event.clickCount == 2 || tool == .text || tool == .callout {
                beginTextEdit(id: o.id)
                return
            }
            pushUndo()
            drag = .move(start: p, original: o, index: i)
            needsDisplay = true
            return
        }
        selectedID = nil
        if wasEditing && tool == .text { needsDisplay = true; return }

        switch tool {
        case .select:
            // Drag on empty space selects everything the rectangle touches (Shift keeps the current selection).
            drag = .marquee(start: p, base: mods.contains(.shift) ? selection : [])
            marqueeRect = CGRect(origin: p, size: .zero)
        case .text:
            pushUndo()
            let a = Annotation(kind: .text, p1: CGPoint(x: p.x, y: p.y - max(12, style.width * 6) * 0.6), p2: p, style: style)
            doc.objects.append(a)
            beginTextEdit(id: a.id)
        case .callout:
            // Press where the pointer should aim, drag to where the bubble goes.
            var preview = Annotation(kind: .callout, p1: p, p2: p, style: style)
            preview.pointer = p
            live = preview
            drag = .calloutCreate(start: p)
        case .counter:
            pushUndo()
            var a = Annotation(kind: .counter, p1: p, p2: p, style: style)
            a.number = doc.nextCounter
            doc.objects.append(a)
            // Selected right away so typing digits renumbers it.
            selectedID = a.id
        default:
            live = Annotation(kind: tool, p1: p, p2: p, points: [p], style: style)
            drag = .create
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragMoved = true
        let raw = toImage(convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .none:
            return
        case .create:
            guard var l = live else { return }
            if l.kind == .freehand {
                l.points.append(raw)
            } else {
                l.p2 = constrained(l.p1, raw, l.kind, shift)
            }
            live = l
        case let .move(start, original, index):
            guard index < doc.objects.count else { return }
            var o = original
            if o.kind == .callout {
                // Moving the bubble keeps its pointer on the same target.
                o.pointer = original.calloutPointer
                o.p1 = original.p1 + (raw - start)
                o.p2 = original.p2 + (raw - start)
            } else if o.kind == .magnifier {
                // Moving the source area changes what is magnified; the lens stays where it is.
                let lens = original.lensRect
                o.p1 = original.p1 + (raw - start)
                o.p2 = original.p2 + (raw - start)
                o.lensCenter = CGPoint(x: lens.midX, y: lens.midY)
            } else {
                o.offset(by: raw - start)
                // A moved Text-mode blur conceals whatever text is under its new position.
                if o.kind == .blur, o.blurMode.textOnly { o.textRects = nil }
            }
            doc.objects[index] = o
        case let .lens(start, original, index):
            guard index < doc.objects.count else { return }
            doc.objects[index].lensCenter = original + (raw - start)
        case .calloutCreate:
            live?.p1 = raw
            live?.p2 = raw
        case let .calloutTip(index):
            guard index < doc.objects.count else { return }
            doc.objects[index].pointer = raw
        case let .crop(start):
            let end = constrained(start, raw, .crop, shift)
            cropRect = CGRect(p1: start, p2: end).integral.intersection(doc.imageRect)
            controller?.updateInfo()
        case let .resize(handle, original, index):
            guard index < doc.objects.count else { return }
            doc.objects[index] = resized(original, handle: handle, to: raw, shift: shift)
        case let .moveMany(start, originals, _):
            let d = raw - start
            for (i, o) in originals where i < doc.objects.count {
                var m = o
                m.offset(by: d)
                if m.kind == .blur, m.blurMode.textOnly { m.textRects = nil }
                doc.objects[i] = m
            }
        case let .marquee(start, base):
            let r = CGRect(p1: start, p2: raw)
            marqueeRect = r
            let hits = doc.objects.filter { $0.bounds.intersects(r) }.map(\.id)
            setSelection(base.union(hits), primary: hits.last ?? selectedID)
        case let .tail(index):
            guard index < doc.objects.count else { return }
            let c = doc.objects[index].p1
            var angle = atan2(raw.y - c.y, raw.x - c.x)
            if shift { angle = (angle / (.pi / 4)).rounded() * (.pi / 4) }
            doc.objects[index].tailAngle = angle
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            // Drags edit after their undo point was recorded, so their end is the moment to save.
            switch drag {
            case let .moveMany(_, _, clicked?) where !dragMoved:
                // Plain click on one object of a multi-selection: select just that one (nothing moved; drop the undo point).
                doc.undoStack.removeLast()
                setSelection([clicked], primary: clicked)
            case .move, .lens, .tail, .resize, .moveMany, .calloutTip: markChanged()
            case let .calloutCreate(start):
                guard var o = live else { break }
                live = nil
                if start.distance(to: o.p1) < 12 {
                    // Plain click: bubble up and to the right of the point it aims at.
                    o.p1 = CGPoint(x: start.x + o.fontSize * 1.2, y: start.y - o.fontSize * 3.4)
                    o.p2 = o.p1
                }
                pushUndo()
                doc.objects.append(o)
                selectedID = o.id
                beginTextEdit(id: o.id)
            case .marquee: marqueeRect = nil; needsDisplay = true
            default: break
            }
            drag = .none
            scanTextRegions()
        }
        if case .create = drag, let l = live {
            live = nil
            if l.isMeaningful {
                pushUndo()
                var o = l
                if o.kind == .magnifier {
                    let size = CGSize(width: o.rect.width * o.factor, height: o.rect.height * o.factor)
                    o.lensCenter = Annotation.defaultLensCenter(source: o.rect, lensSize: size, bounds: doc.imageRect)
                    selectedID = o.id
                }
                doc.objects.append(o)
            }
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
        let p = toImage(convert(event.locationInWindow, from: nil))
        let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
        let px = doc.pixels
        let inside = x >= 0 && y >= 0 && x < px.width && y < px.height
        hoverColor = inside ? px.color(x, y) : nil
        hoverPixel = inside ? CGPoint(x: x, y: y) : nil
        controller?.updateHoverColor(hoverColor)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 48:
            // Shottr: Tab copies the pixel color under the cursor; Shift+Tab the darkest color within 20 px (text color).
            if flags.contains(.shift) {
                controller?.copyColor(hoverPixel.flatMap { doc.darkestColor(around: $0) }, what: "Text color")
            } else {
                controller?.copyColor(hoverColor, what: "Pixel color")
            }
            return
        case 53: // Esc
            if cropRect != nil { cropRect = nil; needsDisplay = true }
            else if tool == .crop { tool = .arrow }
            else if selectedID != nil { selectedID = nil; needsDisplay = true }
            else { controller?.escape() }
            return
        case 36, 76: // Return
            if tool == .crop { applyCrop() }
            return
        case 51, 117: // Delete
            if Int(event.keyCode) == 51, eraseCounterDigit() { return }
            deleteSelected()
            return
        case 123, 124, 125, 126: // arrows nudge the selection
            nudgeSelected(event.keyCode, by: flags.contains(.shift) ? 10 : 1)
            return
        default:
            break
        }
        guard flags.subtracting([.shift, .capsLock, .numericPad, .function]).isEmpty,
              let c = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }
        if c.count == 1, c.first?.isNumber == true, c.first?.isASCII == true, typeCounterDigit(c) { return }
        if c == "=" || c == "+", changeMagnifierFactor(by: 1.25, at: nil) { return }
        if c == "-", changeMagnifierFactor(by: 1 / 1.25, at: nil) { return }
        if c == "k" { toggleBackdrop(); return }
        // Shottr: "Select an area and press C to copy its average color" (the crop selection here).
        if c == "c", tool == .crop, let r = cropRect {
            controller?.copyColor(doc.averageColor(in: r), what: "Average color")
            return
        }
        if c == "p" { controller?.toggleSizeUnits(); return }
        if c == "}" || c == "]" && flags.contains(.shift) { controller?.showResizePanel(); return }
        if let t = Tool.forKey(c) { tool = t } else { super.keyDown(with: event) }
    }

    // MARK: Selection

    private func setSelection(_ ids: Set<UUID>, primary: UUID?) {
        keepSelection = true
        selection = ids
        selectedID = primary.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        keepSelection = false
        controller?.syncToolbar()
        needsDisplay = true
    }

    private func beginMoveMany(at p: CGPoint, clicked: UUID? = nil) {
        let originals = doc.objects.indices.filter { selection.contains(doc.objects[$0].id) }.map { ($0, doc.objects[$0]) }
        drag = .moveMany(start: p, originals: originals, clicked: clicked)
        needsDisplay = true
    }

    override func selectAll(_ sender: Any?) {
        commitText()
        setSelection(Set(doc.objects.map(\.id)), primary: doc.objects.last?.id)
    }

    /// ⌘D: copies of the selection, offset a little, become the new selection.
    @objc func duplicate(_ sender: Any?) {
        let objects = doc.objects.filter { selection.contains($0.id) }
        guard !objects.isEmpty else { NSSound.beep(); return }
        pushUndo()
        let copies = objects.map { o -> Annotation in
            var c = o
            c.id = UUID()
            c.offset(by: CGVector(dx: 20, dy: 20))
            if c.kind == .blur { c.textRects = nil }
            return c
        }
        doc.objects.append(contentsOf: copies)
        setSelection(Set(copies.map(\.id)), primary: copies.last?.id)
        scanTextRegions()
    }

    private static let boxKinds: Set<Tool> = [.rect, .oval, .highlighter, .blur, .spotlight, .magnifier, .image]
    private static let lineKinds: Set<Tool> = [.arrow, .line, .ruler]

    /// Handles of the selected object (single selection only), in image coordinates.
    private func handles() -> [(Handle, CGPoint)] {
        guard selection.count == 1, let id = selectedID, let o = doc.objects.first(where: { $0.id == id }) else { return [] }
        if Self.lineKinds.contains(o.kind) { return [(.start, o.p1), (.end, o.p2)] }
        guard Self.boxKinds.contains(o.kind) else { return [] }
        let r = o.rect
        return [(.corner(0), CGPoint(x: r.minX, y: r.minY)), (.corner(1), CGPoint(x: r.maxX, y: r.minY)),
                (.corner(2), CGPoint(x: r.maxX, y: r.maxY)), (.corner(3), CGPoint(x: r.minX, y: r.maxY)),
                (.edge(0), CGPoint(x: r.midX, y: r.minY)), (.edge(1), CGPoint(x: r.maxX, y: r.midY)),
                (.edge(2), CGPoint(x: r.midX, y: r.maxY)), (.edge(3), CGPoint(x: r.minX, y: r.midY))]
    }

    private func handleHit(_ vp: CGPoint) -> (Handle, Int)? {
        guard let id = selectedID, let i = doc.objects.firstIndex(where: { $0.id == id }) else { return nil }
        let hit = handles().first { fromImage($0.1).distance(to: vp) <= 7 }
        return hit.map { ($0.0, i) }
    }

    /// Handles are drawn in view space so they keep the same size at any zoom.
    private func drawHandles(_ ctx: CGContext) {
        for (h, p) in handles() {
            let v = fromImage(p)
            let r = CGRect(x: v.x - 4.5, y: v.y - 4.5, width: 9, height: 9)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(Palette.accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [])
            if h == .start || h == .end {
                ctx.fillEllipse(in: r); ctx.strokeEllipse(in: r)
            } else {
                ctx.fill(r); ctx.stroke(r)
            }
        }
    }

    /// Applies a handle drag. Box corners keep the aspect ratio with Shift (always for pasted images).
    private func resized(_ original: Annotation, handle: Handle, to p: CGPoint, shift: Bool) -> Annotation {
        var o = original
        switch handle {
        case .start:
            o.p1 = constrained(original.p2, p, o.kind, shift)
            return o
        case .end:
            o.p2 = constrained(original.p1, p, o.kind, shift)
            return o
        default:
            break
        }
        let r = original.rect
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case .corner(0): minX = p.x; minY = p.y
        case .corner(1): maxX = p.x; minY = p.y
        case .corner(2): maxX = p.x; maxY = p.y
        case .corner(3): minX = p.x; maxY = p.y
        case .edge(0): minY = p.y
        case .edge(1): maxX = p.x
        case .edge(2): maxY = p.y
        case .edge(3): minX = p.x
        default: break
        }
        if case let .corner(c) = handle, shift || original.kind == .image, r.width > 0, r.height > 0 {
            // Keep proportions, anchored at the opposite corner.
            let ratio = r.width / r.height
            let anchor = [CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)][c]
            var w = abs(p.x - anchor.x), h = abs(p.y - anchor.y)
            if w / max(h, 1) > ratio { h = w / ratio } else { w = h * ratio }
            let sx: CGFloat = p.x >= anchor.x ? 1 : -1, sy: CGFloat = p.y >= anchor.y ? 1 : -1
            minX = anchor.x; maxX = anchor.x + sx * w
            minY = anchor.y; maxY = anchor.y + sy * h
        }
        let nr = CGRect(p1: CGPoint(x: minX, y: minY), p2: CGPoint(x: maxX, y: maxY))
        guard nr.width >= 4, nr.height >= 4 else { return original }
        if o.kind == .magnifier {
            // Resizing the source keeps the lens where it is.
            let lens = original.lensRect
            o.lensCenter = CGPoint(x: lens.midX, y: lens.midY)
        }
        o.p1 = nr.origin
        o.p2 = CGPoint(x: nr.maxX, y: nr.maxY)
        if o.kind == .blur, o.blurMode.textOnly { o.textRects = nil }
        return o
    }

    // MARK: Test hooks (used by SelfTest)

    func viewPoint(forImage p: CGPoint) -> CGPoint { fromImage(p) }

    // MARK: Blur / Erase Text

    /// Finds text boxes for Text-mode blur regions that have not been scanned yet (Shottr's "reconceal").
    private func scanTextRegions() {
        let image = doc.image
        for o in doc.objects where o.kind == .blur && o.blurMode.textOnly && o.textRects == nil {
            let id = o.id, region = o.rect
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let rects = EditorDocument.detectText(in: image, region: region)
                DispatchQueue.main.async {
                    guard let self, self.doc.image === image,
                          let i = self.doc.objects.firstIndex(where: { $0.id == id }), self.doc.objects[i].rect == region,
                          self.doc.objects[i].textRects == nil else { return }
                    self.doc.objects[i].textRects = rects
                    if rects.isEmpty { Toast.show("No text detected in the selected area") }
                    self.markChanged()
                    self.needsDisplay = true
                }
            }
        }
    }

    // MARK: Image overlays

    /// Scales the selected pasted image around its center when the pointer is over it.
    private func resizeSelectedImage(by multiplier: CGFloat, at viewPoint: CGPoint) -> Bool {
        guard let id = selectedID, let i = doc.objects.firstIndex(where: { $0.id == id }), doc.objects[i].kind == .image,
              doc.objects[i].hit(toImage(viewPoint)) else { return false }
        let r = doc.objects[i].rect
        let w = r.width * multiplier, h = r.height * multiplier
        guard w >= 16, h >= 16, w <= doc.imageRect.width * 4 else { return true }
        if Date().timeIntervalSince(lastFactorEdit) > 0.8 { pushUndo() }
        lastFactorEdit = Date()
        doc.objects[i].p1 = CGPoint(x: r.midX - w / 2, y: r.midY - h / 2)
        doc.objects[i].p2 = CGPoint(x: r.midX + w / 2, y: r.midY + h / 2)
        markChanged()
        needsDisplay = true
        return true
    }

    // MARK: Magnifier

    /// Changes the selected magnifier's zoom when the pointer is over it (or for keyboard input); returns false otherwise.
    private func changeMagnifierFactor(by multiplier: CGFloat, at viewPoint: CGPoint?) -> Bool {
        guard let id = selectedID, let i = doc.objects.firstIndex(where: { $0.id == id }), doc.objects[i].kind == .magnifier else { return false }
        if let vp = viewPoint, !doc.objects[i].hit(toImage(vp)) { return false }
        let range = Annotation.magnificationRange
        let f = min(range.upperBound, max(range.lowerBound, doc.objects[i].factor * multiplier))
        guard f != doc.objects[i].factor else { return true }
        if Date().timeIntervalSince(lastFactorEdit) > 0.8 { pushUndo() }
        lastFactorEdit = Date()
        // Keep the lens centered where it is while it grows or shrinks.
        let lens = doc.objects[i].lensRect
        doc.objects[i].lensCenter = CGPoint(x: lens.midX, y: lens.midY)
        doc.objects[i].factor = (f * 100).rounded() / 100
        style.magnification = doc.objects[i].factor
        controller?.syncToolbar()
        markChanged()
        needsDisplay = true
        return true
    }

    // MARK: Counters

    private var selectedCounterIndex: Int? {
        guard let id = selectedID, let i = doc.objects.firstIndex(where: { $0.id == id }), doc.objects[i].kind == .counter else { return nil }
        return i
    }

    /// Kind of the selected annotation, so the options bar can show its controls.
    var selectedKind: Tool? {
        guard let id = selectedID else { return nil }
        return doc.objects.first { $0.id == id }?.kind
    }

    /// Options-bar change: remembered for new annotations and applied to the selection.
    func setStyle(_ s: ToolStyle) {
        style = s
        if styleEditedText(s) { return }
        var changed: [(Int, Annotation)] = []
        for i in doc.objects.indices where selection.contains(doc.objects[i].id) {
            let old = doc.objects[i]
            var o = old
            o.apply(s)
            guard o.color != old.color || o.width != old.width || o.arrowStyle != old.arrowStyle || o.dashed != old.dashed
                || o.fill != old.fill || o.blurMode != old.blurMode || o.font != old.font || o.shape != old.shape
                || o.rulerInPoints != old.rulerInPoints || o.lensShape != old.lensShape || o.factor != old.factor
                || o.calloutStyle != old.calloutStyle
            else { continue }
            if o.blurMode != old.blurMode { o.textRects = nil }
            changed.append((i, o))
        }
        guard !changed.isEmpty else { return }
        pushUndo()
        for (i, o) in changed { doc.objects[i] = o }
        needsDisplay = true
        scanTextRegions()
    }

    /// Shottr's Resize: scales the image and every annotation (undoable here, unlike Shottr's "can't be undone!").
    func resizeImage(by factor: CGFloat) {
        let w = Int((CGFloat(doc.image.width) * factor).rounded()), h = Int((CGFloat(doc.image.height) * factor).rounded())
        guard factor != 1, w >= 2, h >= 2,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        commitText()
        ctx.interpolationQuality = .high
        ctx.draw(doc.image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return }
        pushUndo()
        doc.image = scaled
        func s(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * factor, y: p.y * factor) }
        for i in doc.objects.indices {
            doc.objects[i].p1 = s(doc.objects[i].p1)
            doc.objects[i].p2 = s(doc.objects[i].p2)
            doc.objects[i].points = doc.objects[i].points.map(s)
            doc.objects[i].lensCenter = doc.objects[i].lensCenter.map(s)
            doc.objects[i].pointer = doc.objects[i].pointer.map(s)
            doc.objects[i].runs = doc.objects[i].runs?.map { var r = $0; r.size *= factor; return r }
            doc.objects[i].textRects = doc.objects[i].textRects?.map { CGRect(origin: s($0.origin), size: CGSize(width: $0.width * factor, height: $0.height * factor)) }
            doc.objects[i].width *= factor
        }
        controller?.documentChanged(resized: true)
        needsDisplay = true
    }

    /// Typing digits while a counter is selected replaces its number; quick successive digits build multi-digit numbers.
    private func typeCounterDigit(_ digit: String) -> Bool {
        guard let i = selectedCounterIndex else { return false }
        let id = doc.objects[i].id
        let continuing = counterTyping.map { $0.id == id && Date().timeIntervalSince($0.at) < 1.5 } ?? false
        let text = String(((continuing ? "\(doc.objects[i].number)" : "") + digit).prefix(4))
        if !continuing { pushUndo() }
        doc.objects[i].number = Int(text) ?? doc.objects[i].number
        counterTyping = (id, Date())
        needsDisplay = true
        return true
    }

    private func eraseCounterDigit() -> Bool {
        guard let i = selectedCounterIndex, let typing = counterTyping, typing.id == doc.objects[i].id else { return false }
        let text = String("\(doc.objects[i].number)".dropLast())
        guard let n = Int(text) else { return true } // keep the last digit rather than deleting the badge
        doc.objects[i].number = n
        counterTyping = (typing.id, Date())
        needsDisplay = true
        return true
    }

    private func deleteSelected() {
        guard !selection.isEmpty else { return }
        pushUndo()
        doc.objects.removeAll { selection.contains($0.id) }
        selectedID = nil
        needsDisplay = true
    }

    private func nudgeSelected(_ keyCode: UInt16, by n: CGFloat) {
        guard !selection.isEmpty else { return }
        let d: CGVector = switch keyCode {
        case 123: CGVector(dx: -n, dy: 0)
        case 124: CGVector(dx: n, dy: 0)
        case 125: CGVector(dx: 0, dy: n)
        default: CGVector(dx: 0, dy: -n)
        }
        pushUndo()
        for i in doc.objects.indices where selection.contains(doc.objects[i].id) { doc.objects[i].offset(by: d) }
        needsDisplay = true
    }

    // MARK: Document edits

    func setBackdrop(_ b: Backdrop) {
        guard b != doc.backdrop else { return }
        commitText()
        pushUndo()
        if b != .none { lastBackdrop = b }
        doc.backdrop = b
        controller?.documentChanged(resized: true)
        needsDisplay = true
    }

    func toggleBackdrop() {
        setBackdrop(doc.backdrop == .none ? lastBackdrop : .none)
    }

    private func applyCrop() {
        guard let r = cropRect?.integral.intersection(doc.imageRect), r.width >= 2, r.height >= 2,
              let cropped = doc.image.cropping(to: r) else { return }
        pushUndo()
        doc.image = cropped
        let d = CGVector(dx: -r.minX, dy: -r.minY)
        for i in doc.objects.indices { doc.objects[i].offset(by: d) }
        cropRect = nil
        tool = .arrow
        controller?.documentChanged(resized: true)
    }

    func resetSelection() {
        cropRect = nil
        selectedID = nil
        if tool == .crop { tool = .arrow }
        needsDisplay = true
        controller?.updateInfo()
    }

    func beginCrop() { tool = .crop }

    func applyCropIfAny() { if cropRect != nil { applyCrop() } }

    // MARK: Text editing

    private func beginTextEdit(id: UUID) {
        guard let o = doc.objects.first(where: { $0.id == id }) else { return }
        editingID = id
        let tf = NSTextField(string: "")
        tf.isBordered = false
        tf.drawsBackground = true
        tf.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35)
        tf.focusRingType = .none
        // Rich field: letters selected with Shift+arrows can get their own color, size and font.
        tf.allowsEditingTextAttributes = true
        tf.font = o.font.font(size: o.fontSize * zoom)
        tf.textColor = o.baseTextColor
        if o.kind == .callout { tf.drawsBackground = false } // the bubble drawn underneath is the background
        if !o.text.isEmpty { tf.attributedStringValue = o.attributedText(scale: zoom) }
        tf.delegate = self
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        addSubview(tf)
        textField = tf
        repositionTextField()
        // Clicking an inactive editor must still route the keyboard here, not to the app that was in front.
        if window?.isKeyWindow == false {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
        window?.makeFirstResponder(tf)
        if let editor = tf.currentEditor() as? NSTextView {
            editor.typingAttributes = [.font: o.font.font(size: o.fontSize * zoom), .foregroundColor: o.baseTextColor]
        }
        needsDisplay = true
    }

    /// What the field currently holds, with styles (the live editor while typing, the field's value after).
    private func editingContent() -> NSAttributedString? {
        guard let tf = textField else { return nil }
        if let storage = (tf.currentEditor() as? NSTextView)?.textStorage { return NSAttributedString(attributedString: storage) }
        return tf.attributedStringValue
    }

    private func repositionTextField() {
        guard let tf = textField, let id = editingID, let o = doc.objects.first(where: { $0.id == id }) else { return }
        // Size from the styled content; setting the field's font here would wipe per-letter styles.
        let content = editingContent() ?? NSAttributedString()
        let size = content.length > 0 ? content.size() : .zero
        let lineHeight = max(size.height, o.fontSize * zoom * 1.2)
        let p = fromImage(o.textOrigin)
        tf.frame = CGRect(x: p.x - 2, y: p.y, width: max(80, size.width + 30), height: ceil(lineHeight * 1.08))
    }

    /// Options-bar change while typing: styles the selected letters, or the whole text when nothing is selected.
    private func styleEditedText(_ s: ToolStyle) -> Bool {
        guard let tf = textField, let id = editingID, let editor = tf.currentEditor() as? NSTextView,
              let storage = editor.textStorage, let i = doc.objects.firstIndex(where: { $0.id == id }) else { return false }
        let selected = editor.selectedRange()
        var textColor = s.color
        if doc.objects[i].kind == .callout {
            // The bubble follows the options bar; its text stays readable on filled designs.
            doc.objects[i].calloutStyle = s.callout
            if selected.length == 0 {
                doc.objects[i].color = s.color
                textColor = doc.objects[i].baseTextColor
            }
            needsDisplay = true
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: s.font.font(size: max(12, s.width * 6) * zoom), .foregroundColor: textColor]
        let range = selected.length > 0 ? selected : NSRange(location: 0, length: storage.length)
        if range.length > 0, editor.shouldChangeText(in: range, replacementString: nil) {
            storage.addAttributes(attrs, range: range)
            editor.didChangeText()
        }
        editor.typingAttributes = editor.typingAttributes.merging(attrs) { $1 }
        if selected.length == 0 {
            doc.objects[i].color = s.color
            doc.objects[i].width = s.width
            doc.objects[i].font = s.font
        }
        repositionTextField()
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        // A callout's bubble grows with the text while typing.
        if let id = editingID, let i = doc.objects.firstIndex(where: { $0.id == id }), doc.objects[i].kind == .callout {
            doc.objects[i].text = editingContent()?.string ?? ""
            needsDisplay = true
        }
        repositionTextField()
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    func commitText() {
        guard let tf = textField, let id = editingID else { return }
        let content = editingContent() ?? NSAttributedString(string: tf.stringValue)
        let z = zoom
        textField = nil
        editingID = nil
        tf.removeFromSuperview()
        if let i = doc.objects.firstIndex(where: { $0.id == id }) {
            if content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doc.objects.remove(at: i)
            } else {
                doc.objects[i].setText(from: content, scale: z)
            }
            markChanged()
        }
        if window?.firstResponder == nil || window?.firstResponder is NSText { window?.makeFirstResponder(self) }
        needsDisplay = true
    }

    var isEditingText: Bool { textField != nil }
}
