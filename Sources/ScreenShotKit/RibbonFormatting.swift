import AppKit

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, icon: IconName? = nil, checked: Bool = false, enabled: Bool = true, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: enabled ? #selector(run) : nil, keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
        if let icon { image = Icons.image(icon, size: 16) }
    }
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { MainActor.assumeIsolated { handler() } }
}

/// The new editor's formatting groups (ROADMAP, Fase 6 · R4): Font, Paragraph, Color and Arrange, plus the contextual
/// groups for the tool in hand. Font and Paragraph talk to the window's FormattingController, exactly like the old
/// formatting bar; Color and Arrange call the canvas's Shape Styles and Arrange commands. Commands the editor doesn't
/// have yet (Strikethrough, Bullets, Numbering, Change Case, Font Outline, Justify) show but stay off until R6.
@MainActor final class RibbonFormatting {
    private weak var editor: EditorWindowController?
    private var shotView: ShotView? { editor?.shotView }
    private let controller: FormattingController
    private var format = TextFormatState.inactive

    // Font
    let family: RibbonItem, size: RibbonItem, grow: RibbonItem, shrink: RibbonItem
    let bold: RibbonItem, italic: RibbonItem, underline: RibbonItem, strike: RibbonItem
    let orientation: RibbonItem, changeCase: RibbonItem
    // Paragraph
    let hAlign: RibbonItem, vAlign: RibbonItem, bullets: RibbonItem, numbering: RibbonItem
    // Color
    let fill: RibbonItem, outline: RibbonItem, fontColor: RibbonItem, fontOutline: RibbonItem
    /// The Office palettes (theme colors, standard, recent, No Fill, More Colors…); their own controls aren't shown.
    let fillPalette = ColorSplitButton(.fill), outlinePalette = ColorSplitButton(.outline), fontPalette = ColorSplitButton(.font)
    // Arrange
    let arrange: RibbonItem, align: RibbonItem, rotate: RibbonItem, flip: RibbonItem
    let fontOutlinePalette = ColorSplitButton(.outline)

    let fontGroup: RibbonGroup, paragraphGroup: RibbonGroup, colorGroup: RibbonGroup, arrangeGroup: RibbonGroup

    /// For the Clipboard group and the tool lights.
    var selectingArea: Bool { shotView?.selectingArea ?? false }
    var paintingFormat: Bool { shotView?.formatPainter != nil }
    var canCopyFormat: Bool { (shotView?.selection.count ?? 0) == 1 || paintingFormat }

    static let weights: [CGFloat] = [1, 2, 3, 4, 6, 8, 12, 16, 20]
    static let zoomSteps: [CGFloat] = [1.5, 2, 3, 4]

    init(editor: EditorWindowController, controller: FormattingController) {
        self.editor = editor
        self.controller = controller
        func item(_ id: String, _ kind: RibbonItem.Kind, _ title: String, _ icon: IconName?, shortcut: String? = nil) -> RibbonItem {
            let i = RibbonItem(id, kind: kind, title: title, icon: icon)
            i.shortcut = shortcut
            return i
        }
        family = item("family", .field(width: 124), "Font", nil)
        size = item("size", .field(width: 50), "Font Size", nil)
        grow = item("grow", .small, "Increase Font Size", .growFont, shortcut: "⇧⌘>")
        shrink = item("shrink", .small, "Decrease Font Size", .shrinkFont, shortcut: "⇧⌘<")
        bold = item("bold", .small, "Bold", .bold, shortcut: "⌘B")
        italic = item("italic", .small, "Italic", .italic, shortcut: "⌘I")
        underline = item("underline", .small, "Underline", .underline, shortcut: "⌘U")
        strike = item("strike", .small, "Strikethrough", .strike)
        orientation = item("orientation", .small, "Text Direction", .textOrient)
        changeCase = item("changeCase", .small, "Change Case", .changeCase)
        hAlign = item("hAlign", .small, "Align Text", .alignLeft)
        vAlign = item("vAlign", .small, "Align Text Vertically", .vMiddle)
        bullets = item("bullets", .small, "Bullets", .bullets)
        numbering = item("numbering", .small, "Numbering", .numbering)
        fill = item("fill", .color, "Shape Fill", .shapeFill)
        outline = item("outline", .color, "Shape Outline", .shapeOutline)
        fontColor = item("fontColor", .color, "Font Color", .fontFill)
        fontOutline = item("fontOutline", .color, "Font Outline", .fontOutline)
        arrange = item("arrange", .label, "Arrange", .arrange)
        align = item("align", .label, "Align", .align)
        rotate = item("rotate", .label, "Rotate", .rotate)
        flip = item("flip", .label, "Flip", .flip)
        fontGroup = RibbonGroup("font", title: "Font", compactTitle: "Fonts", compactIcon: .gFonts, columns: [
            .rows([[.item(family), .item(size), .item(grow), .item(shrink)],
                   [.item(bold), .item(italic), .item(underline), .item(strike), .divider, .item(orientation), .item(changeCase)]]),
        ])
        paragraphGroup = RibbonGroup("paragraph", title: "Paragraph", compactTitle: "Paragraph", compactIcon: .gParagraph, columns: [
            .rows([[.item(hAlign), .item(vAlign)], [.item(bullets), .item(numbering)]]),
        ])
        colorGroup = RibbonGroup("color", title: "Color", compactTitle: "Colors", compactIcon: .gColors, columns: [
            .rows([[.item(fill), .item(outline)], [.item(fontColor), .item(fontOutline)]]),
        ])
        arrangeGroup = RibbonGroup("arrange", title: "Arrange", compactTitle: "Arrange", compactIcon: .gArrange, columns: [
            .rows([[.item(arrange)], [.item(align)]]),
            .rows([[.item(rotate)], [.item(flip)]]),
        ])
        wire()
        controller.addObserver { [weak self] s in self?.show(s) }
        show(controller.state)
    }

    // MARK: Commands

    private func apply(_ change: FormatChange) { controller.applyFormat(change) }

    /// Changes one setting of the style shown (the selection's, or the next object's), as the old options bar did.
    private func setOption(_ change: (inout ToolStyle) -> Void) {
        guard let v = shotView else { return }
        var s = v.displayedStyle
        change(&s)
        v.setStyle(s)
    }

    private func wire() {
        // Font
        family.menu = { [weak self] in
            let m = NSMenu(title: "Font")
            for name in TextFormatting.families {
                let i = ClosureMenuItem(name, checked: self?.format.family == name) { self?.apply(.family(name)) }
                let f = name == TextFormatting.systemFamily ? NSFont.systemFont(ofSize: 13) : (NSFont(name: name, size: 13) ?? .systemFont(ofSize: 13))
                i.attributedTitle = NSAttributedString(string: name, attributes: [.font: f])
                m.addItem(i)
            }
            if let current = self?.format.family {
                m.addItem(.separator())
                m.addItem(ClosureMenuItem("Set “\(current)” as Default Font") {
                    self?.shotView?.setDefaultFamily(current)
                    Toast.show("New texts start in \(current)")
                })
            }
            return m
        }
        size.menu = { [weak self] in
            let m = NSMenu(title: "Font Size")
            for s in TextFormatting.sizePresets {
                m.addItem(ClosureMenuItem(TextFormatting.sizeLabel(s), checked: self?.format.size == s) { self?.apply(.size(s)) })
            }
            return m
        }
        grow.action = { [weak self] in self?.apply(.grow) }
        shrink.action = { [weak self] in self?.apply(.shrink) }
        bold.action = { [weak self] in self?.apply(.bold) }
        italic.action = { [weak self] in self?.apply(.italic) }
        underline.action = { [weak self] in self?.apply(.underline) }
        strike.action = { [weak self] in self?.apply(.strikethrough) }
        changeCase.menu = { [weak self] in
            let m = NSMenu(title: "Change Case")
            for c in TextCase.allCases { m.addItem(ClosureMenuItem(c.title) { self?.apply(.textCase(c)) }) }
            return m
        }
        bullets.action = { [weak self] in self?.apply(.bullets) }
        numbering.action = { [weak self] in self?.apply(.numbering) }
        size.onTextEntry = { [weak self] text in
            let t = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            guard let v = Double(t), v >= 1, v <= 1638 else { NSSound.beep(); self?.controller.refresh(); return }
            self?.apply(.size(CGFloat(v)))
        }
        fontOutlinePalette.onColor = { [weak self] c in self?.apply(.outline(c)) }
        fontOutline.menu = { [weak self] in self?.fontOutlinePalette.paletteMenu() ?? NSMenu() }
        orientation.menu = { [weak self] in self?.directionMenu() ?? NSMenu() }
        // Paragraph
        hAlign.menu = { [weak self] in
            let m = NSMenu(title: "Align Text")
            for a in TextAlign.allCases {
                let (icon, key) = Self.alignIcons[a]!
                let title = a == .justified ? "Justify" : a.rawValue.capitalized
                m.addItem(ClosureMenuItem("\(title)    \(key)", icon: icon, checked: self?.format.alignment == a) { self?.apply(.alignment(a)) })
            }
            return m
        }
        vAlign.menu = { [weak self] in
            let m = NSMenu(title: "Align Text Vertically")
            let icons: [VerticalAlign: IconName] = [.top: .vTop, .middle: .vMiddle, .bottom: .vBottom]
            for a in VerticalAlign.allCases {
                m.addItem(ClosureMenuItem(a.rawValue.capitalized, icon: icons[a], checked: self?.format.verticalAlign == a) { self?.apply(.verticalAlign(a)) })
            }
            return m
        }
        // Color
        fillPalette.onColor = { [weak self] c in self?.shotView?.applyFill(c) }
        fillPalette.extraItems = { [weak self] in self?.fillItems() ?? [] }
        outlinePalette.onColor = { [weak self] c in self?.shotView?.applyOutline(c) }
        outlinePalette.extraItems = { [weak self] in self?.outlineItems() ?? [] }
        fontPalette.onColor = { [weak self] c in
            guard let self, let c else { return }
            if self.controller.target != nil { self.apply(.color(c)) } else { self.setOption { $0.color = c } }
        }
        fill.menu = { [weak self] in self?.fillPalette.paletteMenu() ?? NSMenu() }
        outline.menu = { [weak self] in self?.outlinePalette.paletteMenu() ?? NSMenu() }
        fontColor.menu = { [weak self] in self?.fontPalette.paletteMenu() ?? NSMenu() }
        // Arrange
        arrange.menu = { [weak self] in
            let m = NSMenu(title: "Arrange")
            for (i, a) in [ArrangeAction.bringToFront, .bringForward, .sendBackward, .sendToBack].enumerated() {
                if i == 2 { m.addItem(.separator()) }
                let item = ArrangeMenu.item(a)
                item.target = self?.shotView
                m.addItem(item)
            }
            m.addItem(.separator())
            for (title, sel, key, mods) in [("Group", #selector(ShotView.groupSelection(_:)), "g", NSEvent.ModifierFlags([.command, .option])),
                                            ("Ungroup", #selector(ShotView.ungroupSelection(_:)), "g", [.command, .option, .shift])] {
                let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
                item.keyEquivalentModifierMask = mods
                item.target = self?.shotView
                m.addItem(item)
            }
            return m
        }
        align.menu = { [weak self] in self?.alignMenu() ?? NSMenu() }
        rotate.menu = { [weak self] in self?.transformMenu("Rotate", [.rotateRight, .rotateLeft]) ?? NSMenu() }
        flip.menu = { [weak self] in self?.transformMenu("Flip", [.flipVertical, .flipHorizontal]) ?? NSMenu() }
    }

    static let alignIcons: [TextAlign: (IconName, String)] = [.left: (.alignLeft, "⌘L"), .center: (.alignCenter, "⌘E"),
                                                             .right: (.alignRight, "⌘R"), .justified: (.justify, "⌘J")]
    static let vAlignIcons: [VerticalAlign: IconName] = [.top: .vTop, .middle: .vMiddle, .bottom: .vBottom]

    private func transformMenu(_ title: String, _ actions: [TransformAction]) -> NSMenu {
        let m = NSMenu(title: title)
        let icons: [TransformAction: IconName] = [.rotateRight: .rotR, .rotateLeft: .rotL, .flipVertical: .flipV, .flipHorizontal: .flipH]
        for t in actions {
            let item = ArrangeMenu.transformItem(t)
            item.image = icons[t].map { Icons.image($0, size: 16) }
            item.target = shotView
            m.addItem(item)
        }
        return m
    }

    /// Office's Align menu: horizontal, vertical, distribute, then what the objects align to.
    private func alignMenu() -> NSMenu {
        let m = NSMenu(title: "Align")
        let icons: [ArrangeAction: IconName] = [.alignLeft: .alignL, .alignCenter: .alignC, .alignRight: .alignR, .alignTop: .alignT,
                                                .alignMiddle: .alignM, .alignBottom: .alignB, .distributeHorizontally: .distH, .distributeVertically: .distV]
        for (i, group) in [Array(ArrangeAction.alignments.prefix(3)), Array(ArrangeAction.alignments.suffix(3)), ArrangeAction.distributions].enumerated() {
            if i > 0 { m.addItem(.separator()) }
            for a in group {
                let item = ArrangeMenu.item(a)
                if let icon = icons[a] { item.image = Icons.image(icon, size: 16) }
                item.target = shotView
                m.addItem(item)
            }
        }
        m.addItem(.separator())
        for (title, canvas) in [("Align to Selection", false), ("Align to Canvas", true)] {
            m.addItem(ClosureMenuItem(title, checked: Settings.alignToCanvas == canvas) { [weak self] in self?.shotView?.setAlignToCanvas(canvas) })
        }
        return m
    }

    /// Word's Text Direction menu, mapped onto the editor's quarter turns (angled text isn't available).
    private func directionMenu() -> NSMenu {
        let m = NSMenu(title: "Text Direction")
        let active = TextDirection(format.orientation)
        for d in TextDirection.allCases {
            if d == .horizontal { m.addItem(.separator()) }
            guard let o = d.orientation else {
                m.addItem(ClosureMenuItem(d.title, enabled: false) {})
                continue
            }
            let on = format.isActive && d == active
            m.addItem(ClosureMenuItem(d.title, checked: on) { [weak self] in
                // Picking the active direction again turns the text back to horizontal (Excel's rule).
                self?.apply(.orientation(on && d != .horizontal ? .horizontal : o))
            })
        }
        return m
    }

    private func fillItems() -> [NSMenuItem] {
        guard let v = shotView else { return [] }
        let st = v.shapeStyleState
        let opacity = NSMenuItem(title: "Transparency", action: nil, keyEquivalent: "")
        opacity.submenu = NSMenu(title: "Transparency")
        for f in [FillStyle.opaque, .translucent] {
            opacity.submenu?.addItem(ClosureMenuItem(f == .opaque ? "Opaque" : "Translucent", checked: st.opacity == f) { [weak v] in v?.applyFillOpacity(f) })
        }
        let setDefault = ClosureMenuItem("Set as Default Fill") { [weak self] in
            guard let s = self?.shotView?.displayedStyle else { return }
            ToolStyle.updateDefaults { $0.fill = s.fill }
            Toast.show("“\(s.fill.title)” is now the default")
        }
        return [opacity, setDefault, .separator()]
    }

    /// Shape Outline's Weight and Dashes: the stroke width and line style that used to sit in the bottom bar.
    private func outlineItems() -> [NSMenuItem] {
        guard let v = shotView else { return [] }
        let st = v.shapeStyleState
        let weight = NSMenuItem(title: "Weight", action: nil, keyEquivalent: "")
        weight.image = Icons.image(.weight, size: 16)
        weight.submenu = NSMenu(title: "Weight")
        weight.isEnabled = st.weightEnabled
        for w in Self.weights {
            let item = ClosureMenuItem("\(Int(w)) px", checked: st.weight == w, enabled: st.weightEnabled) { [weak v] in v?.applyOutlineWeight(w) }
            item.image = Self.lineSample(width: w)
            weight.submenu?.addItem(item)
        }
        let dashes = NSMenuItem(title: "Dashes", action: nil, keyEquivalent: "")
        dashes.image = Icons.image(.lineDash, size: 16)
        dashes.submenu = NSMenu(title: "Dashes")
        dashes.isEnabled = st.sketchEnabled || st.dashEnabled
        for d in DashStyle.allCases {
            let ok = d == .dashed ? st.dashEnabled : st.sketchEnabled
            dashes.submenu?.addItem(ClosureMenuItem(d.title, checked: st.dash == d, enabled: ok) { [weak v] in v?.applyDash(d) })
        }
        let setDefault = ClosureMenuItem("Set as Default Outline") { [weak self] in
            guard let s = self?.shotView?.displayedStyle else { return }
            ToolStyle.updateDefaults { $0.color = s.color; $0.width = s.width; $0.dashed = s.dashed; $0.sketch = s.sketch }
            Toast.show("Outline \(s.color.hexString), \(Int(s.width)) px is now the default")
        }
        return [weight, dashes, setDefault, .separator()]
    }

    static func lineSample(width: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: 36, height: 14), flipped: false) { r in
            NSColor.black.setFill()
            let h = max(1, min(r.height, width / 2))
            NSBezierPath(rect: CGRect(x: 0, y: (r.height - h) / 2, width: r.width, height: h)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: State

    /// Font and Paragraph follow the text in focus or selected; mixed values show blank, like Word.
    private func show(_ s: TextFormatState) {
        format = s
        let on = s.isActive
        for i in [family, size, grow, shrink, bold, italic, underline, strike, changeCase, hAlign, bullets, numbering, fontOutline] { i.isEnabled = on }
        strike.isOn = on && s.strikethrough
        bullets.isOn = on && s.bullets
        numbering.isOn = on && s.numbered
        fontOutline.barColor = on ? s.outline : nil
        fontOutlinePalette.show(current: s.outline, none: on && s.outline == nil, mixed: false)
        hAlign.icon = Self.alignIcons[on ? s.alignment ?? .left : .left]?.0
        vAlign.icon = Self.vAlignIcons[on && s.supportsVerticalAlign ? s.verticalAlign ?? .middle : .middle]
        vAlign.isEnabled = on && s.supportsVerticalAlign
        orientation.isEnabled = on && s.supportsOrientation
        family.text = on ? s.family ?? "" : ""
        size.text = on ? s.size.map(TextFormatting.sizeLabel) ?? "" : ""
        bold.isOn = on && s.bold
        italic.isOn = on && s.italic
        underline.isOn = on && s.underline
        updateFontColor()
    }

    private func updateFontColor() {
        guard let v = shotView else { return }
        let newText = v.styleTargets.isEmpty && v.tool == .text
        fontColor.isEnabled = format.isActive || newText
        fontColor.barColor = format.isActive ? format.color : (newText ? v.style.color : fontPalette.lastColor)
    }

    /// Color, Arrange and the contextual groups follow the selection and the tool in hand.
    func update() {
        guard let v = shotView else { return }
        let st = v.shapeStyleState
        fill.isEnabled = st.fillEnabled
        fill.barColor = st.noFill ? nil : st.fillMixed ? fillPalette.lastColor : st.fill
        fillPalette.show(current: st.fill, none: st.noFill, mixed: st.fillMixed)
        outline.isEnabled = st.outlineEnabled
        outline.barColor = st.noOutline ? nil : st.outlineMixed ? outlinePalette.lastColor : st.outline
        outlinePalette.show(current: st.outline, none: st.noOutline, mixed: st.outlineMixed)
        updateFontColor()

        let units = st.unitCount
        arrange.isEnabled = units >= 1
        align.isEnabled = units >= 1
        rotate.isEnabled = st.canTransform
        flip.isEnabled = st.canTransform
    }

}

/// Word and PowerPoint's Text Direction menu, mapped onto the editor's text orientations.
enum TextDirection: String, CaseIterable {
    case angleCounterclockwise, angleClockwise, vertical, rotateUp, rotateDown, horizontal

    var title: String {
        switch self {
        case .angleCounterclockwise: "Angle Counterclockwise"
        case .angleClockwise: "Angle Clockwise"
        case .vertical: "Vertical Text"
        case .rotateUp: "Rotate Text Up"
        case .rotateDown: "Rotate Text Down"
        case .horizontal: "Horizontal"
        }
    }

    /// The orientation it sets; nil for the angled options, which have no orientation yet.
    var orientation: TextOrientation? {
        switch self {
        case .angleCounterclockwise, .angleClockwise: nil
        case .vertical: .stacked
        case .rotateUp: .rotate270
        case .rotateDown: .rotate90
        case .horizontal: .horizontal
        }
    }

    init(_ o: TextOrientation?) {
        switch o {
        case .stacked: self = .vertical
        case .rotate270: self = .rotateUp
        case .rotate90: self = .rotateDown
        default: self = .horizontal
        }
    }
}
