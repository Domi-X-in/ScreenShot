import AppKit

/// The top toolbar's Font and Paragraph sections (Word's Home › Font and Paragraph). They only talk to a
/// FormattingController: they show its state and send it commands. Greyed out when no text is focused or selected.
/// Buttons and menus never take the keyboard focus, so the text keeps its selection; the size box gives it back after
/// use.
@MainActor final class FormattingRibbon: NSObject, NSComboBoxDelegate {
    private let controller: FormattingController
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeBox = NSComboBox()
    private lazy var grow = button("", "Grow Font (⌘⇧>)", .grow, image: Self.sizeIcon(up: true))
    private lazy var shrink = button("", "Shrink Font (⌘⇧<)", .shrink, image: Self.sizeIcon(up: false))

    /// Word's Grow / Shrink Font icons: an A with a small caret up or down.
    private static func sizeIcon(up: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: up ? 14 : 11, weight: .semibold), .foregroundColor: NSColor.black]
            ("A" as NSString).draw(at: NSPoint(x: up ? 1 : 3, y: up ? 0 : 1), withAttributes: a)
            let p = NSBezierPath()
            let x: CGFloat = 15, y: CGFloat = 9
            if up {
                p.move(to: NSPoint(x: x - 3, y: y)); p.line(to: NSPoint(x: x, y: y + 4)); p.line(to: NSPoint(x: x + 3, y: y))
            } else {
                p.move(to: NSPoint(x: x - 3, y: y + 4)); p.line(to: NSPoint(x: x, y: y)); p.line(to: NSPoint(x: x + 3, y: y + 4))
            }
            p.lineWidth = 1.6
            NSColor.black.setStroke()
            p.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }
    /// Bold, Italic, Underline as one control whose pressed segments are highlighted (plain toggle buttons barely
    /// change in dark mode).
    private let styles = NSSegmentedControl()
    private let styleChanges: [FormatChange] = [.bold, .italic, .underline]
    private let align = NSSegmentedControl()
    private let vertical = NSSegmentedControl()
    private let direction = MenuButton(image: TextDirection.horizontal.icon, tooltip: "Text Direction")
    let fontColor = ColorSplitButton(.font)
    private var families: [String] = []
    private(set) var fontSection: NSStackView!
    private(set) var paragraphSection: NSStackView!
    /// Font Color with no text to format: the color for the next text box (the Text tool is in hand).
    var onNewTextColor: ((NSColor) -> Void)?
    /// Whether Font Color has something to color without a formatting target (set by the toolbar).
    var newTextColorEnabled = false { didSet { show(controller.state) } }
    private var lastState = TextFormatState.inactive

    init(controller: FormattingController) {
        self.controller = controller
        super.init()
        build()
        controller.onChange = { [weak self] s in self?.show(s) }
        show(.inactive)
    }

    // MARK: Building

    private func button(_ symbol: String, _ tip: String, _ change: FormatChange, image: NSImage? = nil) -> NSButton {
        let b = NSButton(image: image ?? NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: self,
                         action: #selector(sendChange(_:)))
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        b.setAccessibilityLabel(String(tip.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces))
        b.refusesFirstResponder = true
        changes[ObjectIdentifier(b)] = change
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    private var changes: [ObjectIdentifier: FormatChange] = [:]

    private func build() {
        // Font family: each name shown in its own font, like Word.
        families = TextFormatting.families
        for name in families {
            fontPopup.addItem(withTitle: name)
            let f = name == TextFormatting.systemFamily ? NSFont.systemFont(ofSize: 13) : (NSFont(name: name, size: 13)
                ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: 13) ?? .systemFont(ofSize: 13))
            fontPopup.lastItem?.attributedTitle = NSAttributedString(string: name, attributes: [.font: f])
        }
        fontPopup.target = self
        fontPopup.action = #selector(familyPicked)
        fontPopup.toolTip = "Font"
        fontPopup.setAccessibilityLabel("Font")
        fontPopup.refusesFirstResponder = true
        fontPopup.controlSize = .small
        fontPopup.widthAnchor.constraint(equalToConstant: 112).isActive = true

        // Size: Word's presets, and any value typed in (13.5).
        sizeBox.addItems(withObjectValues: TextFormatting.sizePresets.map(TextFormatting.sizeLabel))
        sizeBox.numberOfVisibleItems = 12
        sizeBox.completes = false
        sizeBox.delegate = self
        sizeBox.target = self
        sizeBox.action = #selector(sizeTyped)
        sizeBox.toolTip = "Font Size"
        sizeBox.setAccessibilityLabel("Font Size")
        sizeBox.controlSize = .small
        sizeBox.widthAnchor.constraint(equalToConstant: 52).isActive = true

        for (control, items) in [(align, [("text.alignleft", "Align Left (⌘L)"), ("text.aligncenter", "Center (⌘E)"), ("text.alignright", "Align Right (⌘R)")]),
                                 (vertical, [("align.vertical.top", "Align Top"), ("align.vertical.center", "Align Middle"),
                                             ("align.vertical.bottom", "Align Bottom")])] {
            control.segmentCount = items.count
            control.trackingMode = .selectOne
            for (i, (symbol, tip)) in items.enumerated() {
                control.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: tip), forSegment: i)
                control.setToolTip(tip, forSegment: i)
                control.setWidth(24, forSegment: i)
            }
            control.target = self
            control.action = #selector(segmentPicked(_:))
            control.refusesFirstResponder = true
            control.controlSize = .small
        }
        styles.segmentCount = 3
        styles.trackingMode = .selectAny
        for (i, (symbol, tip)) in [("bold", "Bold (⌘B)"), ("italic", "Italic (⌘I)"), ("underline", "Underline (⌘U)")].enumerated() {
            styles.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: tip), forSegment: i)
            styles.setToolTip(tip, forSegment: i)
            styles.setWidth(24, forSegment: i)
        }
        styles.target = self
        styles.action = #selector(stylePicked)
        styles.refusesFirstResponder = true
        styles.controlSize = .small
        styles.setAccessibilityLabel("Bold, Italic, Underline")
        align.setAccessibilityLabel("Paragraph alignment")
        vertical.setAccessibilityLabel("Vertical alignment")

        direction.menuProvider = { [weak self] in self?.directionMenu() ?? NSMenu() }

        fontColor.onColor = { [weak self] c in
            guard let self, let c else { return }
            if self.controller.target != nil { self.controller.applyFormat(.color(c)) } else { self.onNewTextColor?(c) }
        }

        fontSection = ToolbarShell.section("Font", [fontPopup, sizeBox, grow, shrink, styles, fontColor])
        paragraphSection = ToolbarShell.section("Paragraph", [align, vertical, direction])
    }

    // MARK: Text Direction

    private func directionMenu() -> NSMenu {
        let m = NSMenu(title: "Text Direction")
        let active = TextDirection(lastState.orientation)
        for d in TextDirection.allCases {
            if d == .horizontal { m.addItem(.separator()) }
            let item = NSMenuItem(title: d.title, action: #selector(directionPicked(_:)), keyEquivalent: "")
            item.target = self
            item.image = d.icon
            item.representedObject = d.rawValue
            item.state = lastState.isActive && d == active ? .on : .off
            if d.orientation == nil {
                // No angled text yet: the editor only turns text by quarter turns.
                item.isEnabled = false
                item.toolTip = "Angled text isn't available yet"
                item.action = nil
            }
            m.addItem(item)
        }
        return m
    }

    @objc private func directionPicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let d = TextDirection(rawValue: raw), let o = d.orientation else { return }
        // Picking the active direction again turns the text back to horizontal (Excel's rule).
        let target: TextOrientation = sender.state == .on && d != .horizontal ? .horizontal : o
        controller.applyFormat(.orientation(target))
    }

    // MARK: State

    private func show(_ s: TextFormatState) {
        lastState = s
        let on = s.isActive
        for c in [fontPopup, grow, shrink, styles, align] as [NSControl] { c.isEnabled = on }
        sizeBox.isEnabled = on
        vertical.isEnabled = on && s.supportsVerticalAlign
        direction.isEnabled = on && s.supportsOrientation
        // Mixed values show blank, like Word.
        if let f = s.family, on, let i = families.firstIndex(of: f) { fontPopup.selectItem(at: i) } else { fontPopup.select(nil) }
        if sizeBox.currentEditor() == nil { sizeBox.stringValue = on ? s.size.map(TextFormatting.sizeLabel) ?? "" : "" }
        for (i, pressed) in [s.bold, s.italic, s.underline].enumerated() { styles.setSelected(on && pressed, forSegment: i) }
        styles.setAccessibilityValue(["Bold", "Italic", "Underline"].enumerated().filter { styles.isSelected(forSegment: $0.offset) }
            .map(\.element).joined(separator: ", "))
        align.selectedSegment = on ? s.alignment.flatMap { TextAlign.allCases.firstIndex(of: $0) } ?? -1 : -1
        vertical.selectedSegment = on && s.supportsVerticalAlign ? s.verticalAlign.flatMap { VerticalAlign.allCases.firstIndex(of: $0) } ?? -1 : -1
        let shown = on && s.supportsOrientation ? TextDirection(s.orientation) : .horizontal
        direction.setFace(shown.icon)
        direction.toolTip = "Text Direction: " + (on && s.supportsOrientation && s.orientation == nil ? "mixed" : shown.title)
        fontColor.isEnabled = on || newTextColorEnabled
        fontColor.show(current: on ? s.color : nil, none: false, mixed: on && s.color == nil)
    }

    // MARK: Actions

    @objc private func sendChange(_ sender: NSButton) {
        guard let change = changes[ObjectIdentifier(sender)] else { return }
        controller.applyFormat(change)
    }

    /// The segment whose pressed state now differs from the text's is the one clicked.
    @objc private func stylePicked() {
        let current = [controller.state.bold, controller.state.italic, controller.state.underline]
        guard let i = (0..<3).first(where: { styles.isSelected(forSegment: $0) != current[$0] }) else { return }
        controller.applyFormat(styleChanges[i])
    }

    @objc private func familyPicked() {
        guard families.indices.contains(fontPopup.indexOfSelectedItem) else { return }
        controller.applyFormat(.family(families[fontPopup.indexOfSelectedItem]))
    }

    @objc private func sizeTyped() {
        let text = sizeBox.stringValue.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let v = Double(text), v >= 1, v <= 1638 else { controller.refresh(); return }
        controller.applyFormat(.size(CGFloat(v)))
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        let i = sizeBox.indexOfSelectedItem
        guard TextFormatting.sizePresets.indices.contains(i) else { return }
        controller.applyFormat(.size(TextFormatting.sizePresets[i]))
    }

    @objc private func segmentPicked(_ sender: NSSegmentedControl) {
        let i = sender.selectedSegment
        if sender === align, TextAlign.allCases.indices.contains(i) { controller.applyFormat(.alignment(TextAlign.allCases[i])) }
        if sender === vertical, VerticalAlign.allCases.indices.contains(i) { controller.applyFormat(.verticalAlign(VerticalAlign.allCases[i])) }
    }


    #if SCREENSHOT_SELFTESTS
    var debugControls: (font: NSPopUpButton, size: NSComboBox, styles: NSSegmentedControl,
                        grow: NSButton, shrink: NSButton, align: NSSegmentedControl, vertical: NSSegmentedControl, direction: MenuButton) {
        (fontPopup, sizeBox, styles, grow, shrink, align, vertical, direction)
    }

    /// The Text Direction menu as it opens now, and a pick from it.
    var debugDirectionMenu: NSMenu { directionMenu() }
    func debugPickDirection(_ d: TextDirection) {
        guard let item = directionMenu().items.first(where: { $0.representedObject as? String == d.rawValue }) else { return }
        directionPicked(item)
    }

    /// A click on the Bold, Italic or Underline segment.
    func debugClickStyle(_ i: Int) {
        styles.setSelected(!styles.isSelected(forSegment: i), forSegment: i)
        stylePicked()
    }
    #endif
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

    /// "ab" in the text color with a blue arrow showing the reading direction.
    var icon: NSImage {
        let d = self
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
            func glyphs(_ s: String, at p: CGPoint, angle: CGFloat = 0) {
                let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
                let size = a.size()
                ctx.saveGState()
                ctx.translateBy(x: p.x, y: p.y)
                ctx.rotate(by: angle)
                a.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
                ctx.restoreGState()
            }
            func arrow(_ from: CGPoint, _ to: CGPoint) {
                let path = NSBezierPath()
                path.move(to: from)
                path.line(to: to)
                let angle = atan2(to.y - from.y, to.x - from.x)
                for side: CGFloat in [-1, 1] {
                    let a = angle + .pi + side * .pi / 5
                    path.move(to: to)
                    path.line(to: CGPoint(x: to.x + 3.2 * cos(a), y: to.y + 3.2 * sin(a)))
                }
                path.lineWidth = 1.3
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                NSColor.systemBlue.setStroke()
                path.stroke()
            }
            switch d {
            case .horizontal:
                glyphs("ab", at: CGPoint(x: 8, y: 6))
                arrow(CGPoint(x: 2.5, y: 13.5), CGPoint(x: 15.5, y: 13.5))
            case .angleCounterclockwise:
                glyphs("ab", at: CGPoint(x: 7, y: 8.5), angle: -.pi / 4)
                arrow(CGPoint(x: 9, y: 15), CGPoint(x: 16.5, y: 7.5))
            case .angleClockwise:
                glyphs("ab", at: CGPoint(x: 7, y: 7.5), angle: .pi / 4)
                arrow(CGPoint(x: 9, y: 1.5), CGPoint(x: 16.5, y: 9))
            case .vertical:
                glyphs("a", at: CGPoint(x: 6, y: 4.5))
                glyphs("b", at: CGPoint(x: 6, y: 11.5))
                arrow(CGPoint(x: 13.5, y: 2), CGPoint(x: 13.5, y: 14.5))
            case .rotateUp:
                glyphs("ab", at: CGPoint(x: 6.5, y: 8), angle: -.pi / 2)
                arrow(CGPoint(x: 13.5, y: 14.5), CGPoint(x: 13.5, y: 2))
            case .rotateDown:
                glyphs("ab", at: CGPoint(x: 6.5, y: 8), angle: .pi / 2)
                arrow(CGPoint(x: 13.5, y: 2), CGPoint(x: 13.5, y: 14.5))
            }
            return true
        }
        img.accessibilityDescription = title
        return img
    }
}
