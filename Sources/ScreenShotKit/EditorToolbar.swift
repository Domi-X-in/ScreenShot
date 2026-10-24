import AppKit

/// The editor's top toolbar, in the same card as the bottom bar: Text Workflows, Font, Paragraph, Shape Styles,
/// Arrange and Align, then the options of the tool in hand (Crop, Blur, Ruler, Magnifier). One line that scrolls
/// sideways when the window is narrow. Like Office, the controls act on the whole selection, grey out when they don't
/// apply, and show blank (mixed) values when the selected objects differ.
final class EditorToolbar: ToolbarShell {
    static let height: CGFloat = 62

    let ribbon: FormattingRibbon
    let options: ToolOptions
    weak var shotView: ShotView?

    let fill = ColorSplitButton(.fill)
    let outline = ColorSplitButton(.outline)
    private let editText = NSButton()
    private let forward = SplitButton(image: NSImage(systemSymbolName: ArrangeAction.bringForward.symbol, accessibilityDescription: nil)!,
                                      tooltip: "Bring Forward (⌥⇧⌘F)", menuTooltip: "More Bring Forward options")
    private let backward = SplitButton(image: NSImage(systemSymbolName: ArrangeAction.sendBackward.symbol, accessibilityDescription: nil)!,
                                       tooltip: "Send Backward (⌥⇧⌘B)", menuTooltip: "More Send Backward options")
    private let groupButton = NSButton()
    private let ungroupButton = NSButton()
    private let rotate = MenuButton(image: NSImage(systemSymbolName: "rotate.right", accessibilityDescription: nil)!, tooltip: "Rotate or Flip")
    private let alignButton = MenuButton(image: NSImage(systemSymbolName: "align.horizontal.left", accessibilityDescription: nil)!, tooltip: "Align")
    private let scroll = SidewaysScrollView()
    private let leftFade = EdgeFade(towardLeading: true)
    private let rightFade = EdgeFade(towardLeading: false)
    private var scrollObserver: NSObjectProtocol?
    private let row = NSStackView()
    private var toolSection: NSStackView!
    private var toolDivider: NSView!
    private var toolCaption: NSTextField?
    private var widthToContent: NSLayoutConstraint!

    init(ribbon: FormattingRibbon, options: ToolOptions) {
        self.ribbon = ribbon
        self.options = options
        super.init(frame: .zero)
        build()
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Formatting")
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Building

    private static func iconButton(_ b: NSButton, _ symbol: String, _ tip: String, _ target: AnyObject, _ action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.imagePosition = .imageOnly
        b.bezelStyle = .texturedRounded
        b.controlSize = .small
        b.toolTip = tip
        b.setAccessibilityLabel(tip.components(separatedBy: " (").first ?? tip)
        b.target = target
        b.action = action
        b.refusesFirstResponder = true
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func build() {
        Self.iconButton(editText, "character.cursor.ibeam", "Edit Text (Return)", self, #selector(editTextClicked))
        Self.iconButton(groupButton, "rectangle.3.group", "Group (⌥⌘G)", self, #selector(groupClicked))
        Self.iconButton(ungroupButton, "square.on.square.dashed", "Ungroup (⌥⇧⌘G)", self, #selector(ungroupClicked))

        // Shape Styles.
        fill.onColor = { [weak self] c in self?.shotView?.applyFill(c) }
        fill.extraItems = { [weak self] in self?.fillItems() ?? [] }
        outline.onColor = { [weak self] c in self?.shotView?.applyOutline(c) }
        outline.extraItems = { [weak self] in self?.outlineItems() ?? [] }
        outline.split.menu = options.defaultMenu(for: "color")
        ribbon.fontColor.split.menu = options.defaultMenu(for: "color")
        ribbon.onNewTextColor = { [weak self] c in
            guard let self, let v = self.shotView else { return }
            var s = v.style
            s.color = c
            v.setStyle(s)
        }

        // Arrange.
        forward.onPrimary = { [weak self] in self?.shotView?.arrange(.bringForward) }
        forward.menuProvider = { [weak self] in self?.menu([ArrangeAction.bringToFront]) ?? NSMenu() }
        backward.onPrimary = { [weak self] in self?.shotView?.arrange(.sendBackward) }
        backward.menuProvider = { [weak self] in self?.menu([ArrangeAction.sendToBack]) ?? NSMenu() }
        rotate.menuProvider = { [weak self] in self?.rotateMenu() ?? NSMenu() }
        alignButton.menuProvider = { [weak self] in self?.alignMenu() ?? NSMenu() }

        let sections: [NSView] = [
            Self.section("Text Workflows", [editText, options.fontControl, options.calloutControl]),
            ribbon.fontSection,
            ribbon.paragraphSection,
            Self.section("Shape Styles", [fill, outline, options.widthSlider, options.sizeReadout, options.arrowControl, options.shapeControl]),
            Self.section("Arrange", [forward, backward, groupButton, ungroupButton, rotate]),
            Self.section("Align", [alignButton]),
        ]
        toolSection = Self.section("Tool", [options.cropModeControl, options.autoadjustButton, options.imprintButton, options.blurControl,
                                            options.unitControl, options.lensShapeControl, options.lensZoomControl])
        toolCaption = (toolSection.views.last as? NSTextField)
        toolDivider = Self.divider(height: 40)
        var views: [NSView] = []
        for (i, s) in sections.enumerated() {
            if i > 0 { views.append(Self.divider(height: 40)) }
            views.append(s)
        }
        views += [toolDivider, toolSection]
        row.setViews(views, in: .leading)
        row.orientation = .horizontal
        row.spacing = 9
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        // One line that scrolls sideways when the window is too narrow (no wrapping).
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(row)
        scroll.documentView = doc
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        embed(scroll, insets: NSEdgeInsets(top: 6, left: 12, bottom: 2, right: 12))
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            row.topAnchor.constraint(equalTo: doc.topAnchor),
            row.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.topAnchor.constraint(equalTo: clip.topAnchor),
            doc.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            doc.heightAnchor.constraint(equalTo: clip.heightAnchor),
        ])
        // The card hugs its content; the window's width caps it (then the content scrolls). Below the window's own
        // size priority, so the toolbar never holds the window open.
        widthToContent = widthAnchor.constraint(equalTo: row.widthAnchor, constant: 24)
        widthToContent.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 10)
        widthToContent.isActive = true

        // Soft edges show there is more toolbar to scroll to.
        for f in [leftFade, rightFade] {
            f.translatesAutoresizingMaskIntoConstraints = false
            addSubview(f)
            NSLayoutConstraint.activate([
                f.topAnchor.constraint(equalTo: scroll.topAnchor), f.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
                f.widthAnchor.constraint(equalToConstant: 28),
            ])
        }
        leftFade.leadingAnchor.constraint(equalTo: scroll.leadingAnchor).isActive = true
        rightFade.trailingAnchor.constraint(equalTo: scroll.trailingAnchor).isActive = true
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.updateFades() }
        }
        updateFades()
    }

    override func layout() {
        super.layout()
        updateFades()
    }

    private func updateFades() {
        let x = scroll.contentView.bounds.minX
        let overflow = (scroll.documentView?.frame.width ?? 0) - scroll.contentView.bounds.width
        leftFade.isHidden = x <= 1
        rightFade.isHidden = overflow - x <= 1
    }

    /// Whether `responder` belongs to this toolbar (the size box's field editor counts).
    func owns(_ responder: NSResponder) -> Bool {
        if let v = responder as? NSView, v.isDescendant(of: self) { return true }
        if let t = responder as? NSTextView, let d = t.delegate as? NSView, d.isDescendant(of: self) { return true }
        return false
    }

    // MARK: State

    /// Shows the selection's state: what is enabled, current and mixed values.
    func update() {
        guard let v = shotView else { return }
        let st = v.shapeStyleState
        let targets = v.styleTargets
        fill.isEnabled = st.fillEnabled
        fill.show(current: st.fill, none: st.noFill, mixed: st.fillMixed)
        outline.isEnabled = st.outlineEnabled
        outline.show(current: st.outline, none: st.noOutline, mixed: st.outlineMixed)
        ribbon.newTextColorEnabled = targets.isEmpty && v.tool == .text
        editText.isEnabled = v.selection.count == 1 && targets.contains { $0.kind == .text || $0.kind == .callout || $0.holdsTextInShape } && !v.isEditingText
        let units = st.unitCount
        forward.isEnabled = units >= 1
        backward.isEnabled = units >= 1
        groupButton.isEnabled = st.canGroup
        ungroupButton.isEnabled = st.canUngroup
        rotate.isEnabled = st.canTransform
        alignButton.isEnabled = units >= 1
        alignButton.toolTip = "Align (" + (Settings.alignToCanvas || units == 1 ? "to the canvas" : "to the selection") + ")"
        let title = options.toolSectionTitle
        toolSection.isHidden = title == nil
        toolDivider.isHidden = title == nil
        toolCaption?.stringValue = title ?? ""
    }

    // MARK: Menus

    private func menu(_ actions: [ArrangeAction]) -> NSMenu {
        let m = NSMenu()
        for a in actions {
            let item = ArrangeMenu.item(a)
            item.target = shotView
            m.addItem(item)
        }
        return m
    }

    private func rotateMenu() -> NSMenu {
        let m = NSMenu(title: "Rotate")
        for t in TransformAction.allCases {
            if t == .flipVertical { m.addItem(.separator()) }
            let item = ArrangeMenu.transformItem(t)
            item.target = shotView
            m.addItem(item)
        }
        return m
    }

    /// Office's Align menu: horizontal, vertical, distribute, then what the objects align to.
    private func alignMenu() -> NSMenu {
        let m = NSMenu(title: "Align")
        for (i, group) in [Array(ArrangeAction.alignments.prefix(3)), Array(ArrangeAction.alignments.suffix(3)), ArrangeAction.distributions].enumerated() {
            if i > 0 { m.addItem(.separator()) }
            for a in group {
                let item = ArrangeMenu.item(a)
                item.target = shotView
                m.addItem(item)
            }
        }
        m.addItem(.separator())
        for (title, canvas) in [("Align to Selection", false), ("Align to Canvas", true)] {
            let item = NSMenuItem(title: title, action: #selector(alignTargetPicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = canvas ? 1 : 0
            item.state = Settings.alignToCanvas == canvas ? .on : .off
            item.toolTip = canvas ? "Objects line up with the screenshot's edges and center"
                : "Objects line up with each other (a single object still aligns to the screenshot)"
            m.addItem(item)
        }
        return m
    }

    @objc private func alignTargetPicked(_ sender: NSMenuItem) { shotView?.setAlignToCanvas(sender.tag == 1) }

    private func fillItems() -> [NSMenuItem] {
        guard let v = shotView else { return [] }
        let st = v.shapeStyleState
        var items: [NSMenuItem] = []
        let opacity = NSMenuItem(title: "Transparency", action: nil, keyEquivalent: "")
        opacity.submenu = NSMenu(title: "Transparency")
        for f in [FillStyle.opaque, .translucent] {
            let item = NSMenuItem(title: f == .opaque ? "Opaque" : "Translucent", action: #selector(opacityPicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = f.rawValue
            item.image = NSImage(systemSymbolName: f.symbol, accessibilityDescription: nil)
            item.state = st.opacity == f ? .on : .off
            opacity.submenu?.addItem(item)
        }
        opacity.image = NSImage(systemSymbolName: "square.lefthalf.filled", accessibilityDescription: nil)
        items.append(opacity)
        let setDefault = NSMenuItem(title: "Set as Default Fill", action: #selector(ToolOptions.setFillDefaultAction), keyEquivalent: "")
        setDefault.target = options
        items += [setDefault, .separator()]
        return items
    }

    private static let weights: [CGFloat] = [1, 2, 3, 4, 6, 8, 12, 16, 20]

    private func outlineItems() -> [NSMenuItem] {
        guard let v = shotView else { return [] }
        let st = v.shapeStyleState
        let weight = NSMenuItem(title: "Weight", action: nil, keyEquivalent: "")
        weight.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        weight.submenu = NSMenu(title: "Weight")
        weight.isEnabled = st.weightEnabled
        for w in Self.weights {
            let item = NSMenuItem(title: "\(Int(w)) px", action: st.weightEnabled ? #selector(weightPicked(_:)) : nil, keyEquivalent: "")
            item.target = self
            item.tag = Int(w)
            item.image = Self.lineSample(width: w)
            item.state = st.weight == w ? .on : .off
            weight.submenu?.addItem(item)
        }
        let dashes = NSMenuItem(title: "Dashes", action: nil, keyEquivalent: "")
        dashes.image = NSImage(systemSymbolName: "line.horizontal.3.decrease", accessibilityDescription: nil)
        dashes.submenu = NSMenu(title: "Dashes")
        dashes.isEnabled = st.sketchEnabled || st.dashEnabled
        for d in DashStyle.allCases {
            let ok = d == .dashed ? st.dashEnabled : st.sketchEnabled
            let item = NSMenuItem(title: d.title, action: ok ? #selector(dashPicked(_:)) : nil, keyEquivalent: "")
            item.target = self
            item.tag = d.rawValue
            item.image = NSImage(systemSymbolName: d.symbol, accessibilityDescription: nil)
            item.state = st.dash == d ? .on : .off
            dashes.submenu?.addItem(item)
        }
        let setDefault = NSMenuItem(title: "Set as Default Outline", action: #selector(ToolOptions.setOutlineDefaultAction), keyEquivalent: "")
        setDefault.target = options
        return [weight, dashes, setDefault, .separator()]
    }

    /// A horizontal line of the given weight, for the Weight menu.
    private static func lineSample(width: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: 36, height: 14), flipped: false) { r in
            NSColor.black.setFill()
            let h = max(1, min(r.height, width / 2))
            NSBezierPath(rect: CGRect(x: 0, y: (r.height - h) / 2, width: r.width, height: h)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc private func opacityPicked(_ sender: NSMenuItem) { shotView?.applyFillOpacity(FillStyle(rawValue: sender.tag) ?? .opaque) }
    @objc private func weightPicked(_ sender: NSMenuItem) { shotView?.applyOutlineWeight(CGFloat(sender.tag)) }
    @objc private func dashPicked(_ sender: NSMenuItem) { shotView?.applyDash(DashStyle(rawValue: sender.tag) ?? .solid) }
    @objc private func editTextClicked() { shotView?.editSelectedText(nil) }
    @objc private func groupClicked() { shotView?.groupSelection(nil) }
    @objc private func ungroupClicked() { shotView?.ungroupSelection(nil) }

    #if SCREENSHOT_SELFTESTS
    var debugControls: (editText: NSButton, forward: SplitButton, backward: SplitButton, group: NSButton, ungroup: NSButton,
                        rotate: MenuButton, align: MenuButton, toolSection: NSView) {
        (editText, forward, backward, groupButton, ungroupButton, rotate, alignButton, toolSection)
    }
    var debugAlignMenu: NSMenu { alignMenu() }
    var debugRotateMenu: NSMenu { rotateMenu() }
    var debugOutlineItems: [NSMenuItem] { outlineItems() }
    var debugFillItems: [NSMenuItem] { fillItems() }
    var debugScroll: NSScrollView { scroll }
    var debugSectionTitles: [String] {
        row.views.compactMap { ($0 as? NSStackView)?.accessibilityLabel() }.filter { !$0.isEmpty }
    }
    #endif
}

/// Top-left origin, so the toolbar's row stays pinned to the top-left of its scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The toolbar's scroll view: a plain mouse wheel (vertical) scrolls it sideways too.
private final class SidewaysScrollView: NSScrollView {
    override func scrollWheel(with e: NSEvent) {
        guard abs(e.scrollingDeltaY) > abs(e.scrollingDeltaX), let doc = documentView else { super.scrollWheel(with: e); return }
        let maxX = max(0, doc.frame.width - contentView.bounds.width)
        guard maxX > 0 else { return }
        var o = contentView.bounds.origin
        o.x = min(maxX, max(0, o.x - e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 1 : 10)))
        contentView.scroll(to: o)
        reflectScrolledClipView(contentView)
    }
}

/// A fade into the card's color at one end of the toolbar, shown while there is more to scroll to on that side.
private final class EdgeFade: NSView {
    private let towardLeading: Bool
    private let gradient = CAGradientLayer()

    init(towardLeading: Bool) {
        self.towardLeading = towardLeading
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(gradient)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        var solid = Theme.card.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { solid = Theme.card.withAlphaComponent(1).cgColor }
        let clear = solid.copy(alpha: 0) ?? solid
        gradient.colors = towardLeading ? [solid, clear] : [clear, solid]
    }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    // Clicks go through to the controls underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
