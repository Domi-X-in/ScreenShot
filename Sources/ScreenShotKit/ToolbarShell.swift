import AppKit

/// The editor's floating toolbar card, shared by the top toolbar and the bottom status bar so they look the same:
/// background, rounded corners, hairline border, shadow, inner padding, dividers and muted labels.
class ToolbarShell: NSView {
    static let cornerRadius: CGFloat = 14
    static let padding = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 12)
    /// Height of the status bar; the top toolbar adds its section labels underneath.
    static let barHeight: CGFloat = 48
    static let spacing: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.borderWidth = 1
        Theme.cardShadow(self, radius: 16, opacity: 0.22)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.card.cgColor
        layer?.borderColor = Theme.cardBorder.cgColor
    }

    /// Lays `content` out edge to edge inside the padding.
    func embed(_ content: NSView, insets: NSEdgeInsets = ToolbarShell.padding) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    /// The vertical hairline between groups.
    static func divider(height: CGFloat = 26) -> NSView {
        let d = NSView()
        d.wantsLayer = true
        d.layer?.backgroundColor = NSColor.separatorColor.cgColor
        d.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([d.widthAnchor.constraint(equalToConstant: 1), d.heightAnchor.constraint(equalToConstant: height)])
        return d
    }

    /// The muted secondary label style (section names, hints).
    static func label(_ s: String, size: CGFloat = 10, weight: NSFont.Weight = .medium) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = InfoCellsView.infoColor
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    /// A labeled group: its controls in one row, its name centered underneath (Office's ribbon groups).
    static func section(_ title: String, _ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.spacing = 4
        row.alignment = .centerY
        // Same row height in every section, so the labels underneath line up.
        row.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let caption = label(title)
        caption.alignment = .center
        let stack = NSStackView(views: [row, caption])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel(title)
        return stack
    }
}

// MARK: - Split buttons

/// Office's split button: the left part runs the main command, the chevron opens a menu of related ones.
final class SplitButton: NSSegmentedControl {
    var onPrimary: (() -> Void)?
    /// Builds the dropdown each time it opens, so it shows the current state.
    var menuProvider: (() -> NSMenu)?

    init(image: NSImage, tooltip: String, menuTooltip: String) {
        super.init(frame: .zero)
        segmentCount = 2
        trackingMode = .momentary
        controlSize = .small
        segmentStyle = .texturedRounded
        setImage(image, forSegment: 0)
        setImage(NSImage(systemSymbolName: "chevron.down", accessibilityDescription: menuTooltip)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold)), forSegment: 1)
        setWidth(26, forSegment: 0)
        setWidth(12, forSegment: 1)
        setToolTip(tooltip, forSegment: 0)
        setToolTip(menuTooltip, forSegment: 1)
        setAccessibilityLabel(String(tooltip.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces))
        refusesFirstResponder = true
        target = self
        action = #selector(clicked)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() {
        if selectedSegment == 1 { openMenu() } else { onPrimary?() }
    }

    func openMenu() {
        guard let menu = menuProvider?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 3), in: self)
    }
}

/// A button that only opens a menu (Rotate, Align, Text Direction): its icon and a chevron.
final class MenuButton: NSPopUpButton {
    var menuProvider: (() -> NSMenu)?

    init(image: NSImage, tooltip: String) {
        super.init(frame: .zero, pullsDown: true)
        bezelStyle = .texturedRounded
        controlSize = .small
        imagePosition = .imageOnly
        (cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        toolTip = tooltip
        setAccessibilityLabel(tooltip.components(separatedBy: " (").first ?? tooltip)
        refusesFirstResponder = true
        setFace(image)
        widthAnchor.constraint(equalToConstant: 40).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The icon on the button (a pull-down shows its first item).
    func setFace(_ image: NSImage) {
        let face = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        face.image = image
        if menu?.items.isEmpty ?? true { menu?.addItem(face) } else { menu?.item(at: 0)?.image = image }
    }

    override func mouseDown(with event: NSEvent) {
        rebuild()
        super.mouseDown(with: event)
    }

    /// The menu's items under the face item, fresh from `menuProvider`.
    func rebuild() {
        guard let fresh = menuProvider?(), let m = menu else { return }
        let face = m.item(at: 0)
        m.removeAllItems()
        if let face { m.addItem(face) }
        for item in fresh.items { fresh.removeItem(item); m.addItem(item) }
    }
}

// MARK: - Color split buttons

/// Font Color, Shape Fill and Shape Outline: icon over a bar in the last color used (a click applies it), and a
/// dropdown with Office's palette.
final class ColorSplitButton: NSView {
    enum Kind: String {
        case font, fill, outline

        var title: String {
            switch self {
            case .font: "Font Color"
            case .fill: "Shape Fill"
            case .outline: "Shape Outline"
            }
        }

        var noneTitle: String? {
            switch self {
            case .font: nil
            case .fill: "No Fill"
            case .outline: "No Outline"
            }
        }

        var defaultColor: NSColor {
            switch self {
            case .font: NSColor(hex: 0xFF3B30)
            case .fill: NSColor(hex: 0xFFCC00)
            case .outline: NSColor(hex: 0x007AFF)
            }
        }
    }

    let kind: Kind
    let split: SplitButton
    /// Applies a color, or nil for No Fill / No Outline.
    var onColor: ((NSColor?) -> Void)?
    /// Extra items for the dropdown (Transparency, Weight, Dashes), added above More Colors….
    var extraItems: (() -> [NSMenuItem])?
    /// What the selection has now: a color, nil when mixed; `isNone` for No Fill / No Outline.
    private(set) var current: NSColor?
    private(set) var isNone = false
    private(set) var lastColor: NSColor

    init(_ kind: Kind) {
        self.kind = kind
        lastColor = OfficeColors.lastUsed(kind.rawValue, default: kind.defaultColor)
        split = SplitButton(image: NSImage(), tooltip: kind.title, menuTooltip: "\(kind.title) Options")
        super.init(frame: .zero)
        split.translatesAutoresizingMaskIntoConstraints = false
        addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: leadingAnchor), split.trailingAnchor.constraint(equalTo: trailingAnchor),
            split.topAnchor.constraint(equalTo: topAnchor), split.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        split.onPrimary = { [weak self] in
            guard let self else { return }
            self.pick(self.lastColor)
        }
        split.menuProvider = { [weak self] in self?.paletteMenu() ?? NSMenu() }
        refreshFace()
    }

    required init?(coder: NSCoder) { fatalError() }

    var isEnabled: Bool {
        get { split.isEnabled }
        set { split.isEnabled = newValue }
    }

    /// Shows the selection's color in the palette (a ring) and the tooltip.
    func show(current c: NSColor?, none: Bool, mixed: Bool) {
        current = mixed ? nil : c
        isNone = none && !mixed
        let state = mixed ? "mixed" : none ? (kind.noneTitle ?? "none") : c?.hexString
        split.setToolTip("\(kind.title): apply \(lastColor.hexString)" + (state.map { " · selection: \($0)" } ?? ""), forSegment: 0)
    }

    /// Applies a color and remembers it as this control's last color.
    func pick(_ c: NSColor) {
        lastColor = c
        OfficeColors.setLastUsed(kind.rawValue, c)
        refreshFace()
        onColor?(c)
    }

    private func refreshFace() {
        split.setImage(Self.icon(kind, bar: lastColor), forSegment: 0)
    }

    /// The icon with its color bar: "A" for Font Color, a drop for Shape Fill, a pen for Shape Outline.
    static func icon(_ kind: Kind, bar: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 16), flipped: false) { r in
            let glyphRect = CGRect(x: 0, y: 4, width: r.width, height: 12)
            switch kind {
            case .font:
                let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor]
                let s = NSAttributedString(string: "A", attributes: a)
                s.draw(at: NSPoint(x: (r.width - s.size().width) / 2, y: 2.5))
            case .fill, .outline:
                let name = kind == .fill ? "drop.fill" : "pencil.tip"
                if let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 10, weight: .medium).applying(.init(paletteColors: [.labelColor]))) {
                    let s = sym.size
                    sym.draw(in: CGRect(x: glyphRect.midX - s.width / 2, y: glyphRect.midY - s.height / 2 + 0.5, width: s.width, height: s.height))
                }
            }
            let barRect = CGRect(x: 2, y: 0.5, width: r.width - 4, height: 3)
            bar.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let outline = NSBezierPath(roundedRect: barRect.insetBy(dx: 0.25, dy: 0.25), xRadius: 1, yRadius: 1)
            outline.lineWidth = 0.5
            outline.stroke()
            return true
        }
    }

    // MARK: Palette

    private func header(_ title: String) -> NSMenuItem { NSMenuItem.sectionHeader(title: title) }

    private func gridItem(_ rows: [[NSColor]], name: String) -> NSMenuItem {
        let item = NSMenuItem()
        let grid = ColorGridView(rows: rows, selected: current) { [weak self] c in self?.pick(c) }
        grid.setAccessibilityLabel(name)
        item.view = grid
        return item
    }

    func paletteMenu() -> NSMenu {
        let m = NSMenu(title: kind.title)
        m.addItem(header("Theme Colors"))
        m.addItem(gridItem(OfficeColors.themeGrid, name: "Theme Colors"))
        m.addItem(header("Standard Colors"))
        m.addItem(gridItem([OfficeColors.standard], name: "Standard Colors"))
        let recent = OfficeColors.recent
        if !recent.isEmpty {
            m.addItem(header("Recent Colors"))
            m.addItem(gridItem([recent], name: "Recent Colors"))
        }
        m.addItem(.separator())
        if let none = kind.noneTitle {
            let item = NSMenuItem(title: none, action: #selector(noneClicked), keyEquivalent: "")
            item.target = self
            item.state = isNone ? .on : .off
            item.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
            m.addItem(item)
        }
        for item in extraItems?() ?? [] { m.addItem(item) }
        let more = NSMenuItem(title: "More Colors…", action: #selector(moreColors), keyEquivalent: "")
        more.target = self
        more.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)
        m.addItem(more)
        return m
    }

    @objc private func noneClicked() { onColor?(nil) }

    // MARK: More Colors… (the system color panel, next to this control on the editor's screen)

    private var panelCloseObserver: NSObjectProtocol?

    @objc func moreColors() {
        let panel = NSColorPanel.shared
        panel.color = current ?? lastColor
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelPicked(_:)))
        panel.isContinuous = true
        // The panel stays linked to this control only while it's open.
        if let old = panelCloseObserver { NotificationCenter.default.removeObserver(old) }
        panelCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                NSColorPanel.shared.setTarget(nil)
                NSColorPanel.shared.setAction(nil)
                if let o = self?.panelCloseObserver { NotificationCenter.default.removeObserver(o) }
                self?.panelCloseObserver = nil
            }
        }
        // macOS reopens the panel wherever it was last, which can be another display.
        if let win = window, let screen = win.screen {
            let anchor = win.convertToScreen(convert(bounds, to: nil))
            let vf = screen.visibleFrame
            var origin = CGPoint(x: anchor.minX, y: anchor.minY - panel.frame.height - 12)
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - panel.frame.width - 8)
            if origin.y < vf.minY + 8 { origin.y = min(vf.maxY - panel.frame.height - 8, anchor.maxY + 12) }
            panel.setFrameOrigin(origin)
        }
        panel.orderFront(nil)
    }

    /// The panel's action: only a color the user picks counts (the panel also fires when something else sets its color).
    @objc private func colorPanelPicked(_ sender: NSColorPanel) {
        guard sender.isVisible else { return }
        if let e = NSApp.currentEvent, e.window != nil, e.window !== sender, e.type != .keyDown { return }
        colorPanelChanged(sender)
    }

    func colorPanelChanged(_ sender: NSColorPanel) {
        let c = sender.color.usingColorSpace(.sRGB) ?? sender.color
        OfficeColors.addRecent(c)
        pick(c)
    }

    #if SCREENSHOT_SELFTESTS
    /// What the color panel does when a color is picked in it.
    func debugPickCustomColor(_ c: NSColor) {
        NSColorPanel.shared.color = c
        colorPanelChanged(NSColorPanel.shared)
    }
    #endif
}

/// A grid of color swatches inside a menu: hovering highlights one, clicking picks it and closes the menu.
final class ColorGridView: NSView {
    private let rows: [[NSColor]]
    private let selected: NSColor?
    private let onPick: (NSColor) -> Void
    private var hover: (Int, Int)?
    private static let cell: CGFloat = 18, gap: CGFloat = 4, inset: CGFloat = 14

    init(rows: [[NSColor]], selected: NSColor?, onPick: @escaping (NSColor) -> Void) {
        self.rows = rows
        self.selected = selected
        self.onPick = onPick
        let cols = rows.map(\.count).max() ?? 0
        super.init(frame: CGRect(x: 0, y: 0, width: Self.inset * 2 + CGFloat(cols) * (Self.cell + Self.gap) - Self.gap,
                                 height: CGFloat(rows.count) * (Self.cell + Self.gap) - Self.gap + 8 + (rows.count > 1 ? 3 : 0)))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func rect(_ r: Int, _ c: Int) -> CGRect {
        // The theme grid keeps a gap between its first row and the tints and shades, as Office does.
        let extra: CGFloat = rows.count > 1 && r > 0 ? 3 : 0
        return CGRect(x: Self.inset + CGFloat(c) * (Self.cell + Self.gap), y: 4 + CGFloat(r) * (Self.cell + Self.gap) + extra,
                      width: Self.cell, height: Self.cell)
    }

    private func index(at p: CGPoint) -> (Int, Int)? {
        for (r, row) in rows.enumerated() { for c in row.indices where rect(r, c).insetBy(dx: -2, dy: -2).contains(p) { return (r, c) } }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for (r, row) in rows.enumerated() {
            for (c, color) in row.enumerated() {
                let box = rect(r, c)
                color.setFill()
                box.fill()
                NSColor.black.withAlphaComponent(0.18).setStroke()
                NSBezierPath(rect: box.insetBy(dx: 0.25, dy: 0.25)).stroke()
                let isSelected = selected.map { $0.rgbaHex == color.rgbaHex } ?? false
                if isSelected || hover.map({ $0 == (r, c) }) == true {
                    let ring = NSBezierPath(rect: box.insetBy(dx: -1.5, dy: -1.5))
                    ring.lineWidth = isSelected ? 2 : 1.5
                    (isSelected ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
                    ring.stroke()
                }
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let h = index(at: convert(event.locationInWindow, from: nil))
        if h.map({ "\($0)" }) != hover.map({ "\($0)" }) {
            hover = h
            toolTip = h.map { rows[$0.0][$0.1].hexString }
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let (r, c) = index(at: convert(event.locationInWindow, from: nil)) else { return }
        let color = rows[r][c]
        enclosingMenuItem?.menu?.cancelTracking()
        onPick(color)
    }

    #if SCREENSHOT_SELFTESTS
    var debugColors: [[NSColor]] { rows }
    #endif
}
