import AppKit

/// Word-style formatting toolbar (Home › Font and Paragraph). It only talks to a FormattingController: it shows its
/// state and sends it commands. Always visible; greyed out when no text is focused or selected. Buttons and menus
/// never take the keyboard focus, so the text keeps its selection; the size box gives it back after use.
final class FormattingRibbon: NSView, NSComboBoxDelegate {
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
    private lazy var bold = toggle("bold", "Bold (⌘B)", .bold)
    private lazy var italic = toggle("italic", "Italic (⌘I)", .italic)
    private lazy var underline = toggle("underline", "Underline (⌘U)", .underline)
    private let align = NSSegmentedControl()
    private let vertical = NSSegmentedControl()
    private let direction = NSPopUpButton(frame: .zero, pullsDown: false)
    private var families: [String] = []

    init(controller: FormattingController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        build()
        controller.onChange = { [weak self] s in self?.show(s) }
        show(.inactive)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = Theme.dynamic(light: NSColor(hex: 0xF7F8FA), dark: NSColor(hex: 0x24252B)).cgColor
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
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    private func toggle(_ symbol: String, _ tip: String, _ change: FormatChange) -> NSButton {
        let b = button(symbol, tip, change)
        b.setButtonType(.pushOnPushOff)
        return b
    }

    private var changes: [ObjectIdentifier: FormatChange] = [:]

    private func caption(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 10, weight: .medium)
        l.textColor = .secondaryLabelColor
        l.alignment = .center
        return l
    }

    private func group(_ title: String, rows: [[NSView]]) -> NSView {
        let lines = rows.map { views -> NSStackView in
            let r = NSStackView(views: views)
            r.spacing = 4
            r.alignment = .centerY
            return r
        }
        let label = caption(title)
        let stack = NSStackView(views: lines + [label])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel(title)
        return stack
    }

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
        fontPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

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
        sizeBox.widthAnchor.constraint(equalToConstant: 62).isActive = true

        for (control, items) in [(align, [("text.alignleft", "Align Left (⌘L)"), ("text.aligncenter", "Center (⌘E)"), ("text.alignright", "Align Right (⌘R)")]),
                                 (vertical, [("align.vertical.top", "Align Top"), ("align.vertical.center", "Align Middle"),
                                             ("align.vertical.bottom", "Align Bottom")])] {
            control.segmentCount = items.count
            control.trackingMode = .selectOne
            for (i, (symbol, tip)) in items.enumerated() {
                control.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: tip), forSegment: i)
                control.setToolTip(tip, forSegment: i)
                control.setWidth(30, forSegment: i)
            }
            control.target = self
            control.action = #selector(segmentPicked(_:))
            control.refusesFirstResponder = true
            control.controlSize = .small
        }
        align.setAccessibilityLabel("Paragraph alignment")
        vertical.setAccessibilityLabel("Vertical alignment")

        let symbols = ["text.justify.left", "rotate.right", "rotate.left", "character.textbox"]
        for (i, o) in TextOrientation.allCases.enumerated() {
            direction.addItem(withTitle: o.title)
            direction.lastItem?.image = NSImage(systemSymbolName: symbols[i], accessibilityDescription: nil)
        }
        direction.target = self
        direction.action = #selector(directionPicked)
        direction.toolTip = "Text Direction"
        direction.setAccessibilityLabel("Text Direction")
        direction.refusesFirstResponder = true
        direction.controlSize = .small

        let font = group("Font", rows: [[fontPopup, sizeBox, grow, shrink], [bold, italic, underline]])
        let paragraph = group("Paragraph", rows: [[align, vertical], [direction]])
        let divider = NSBox()
        divider.boxType = .separator
        let row = NSStackView(views: [font, divider, paragraph])
        row.spacing = 14
        row.alignment = .top
        row.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 4, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 52),
            line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Text formatting")
    }

    /// Whether `responder` belongs to this toolbar (the size box's field editor counts).
    func owns(_ responder: NSResponder) -> Bool {
        if let v = responder as? NSView, v.isDescendant(of: self) { return true }
        if let t = responder as? NSTextView, let d = t.delegate as? NSView, d.isDescendant(of: self) { return true }
        return false
    }

    // MARK: State

    private func show(_ s: TextFormatState) {
        let on = s.isActive
        for c in [fontPopup, grow, shrink, bold, italic, underline, align] as [NSControl] { c.isEnabled = on }
        sizeBox.isEnabled = on
        vertical.isEnabled = on && s.supportsVerticalAlign
        direction.isEnabled = on && s.supportsOrientation
        // Mixed values show blank, like Word.
        if let f = s.family, on, let i = families.firstIndex(of: f) { fontPopup.selectItem(at: i) } else { fontPopup.select(nil) }
        if sizeBox.currentEditor() == nil { sizeBox.stringValue = on ? s.size.map(TextFormatting.sizeLabel) ?? "" : "" }
        bold.state = on && s.bold ? .on : .off
        italic.state = on && s.italic ? .on : .off
        underline.state = on && s.underline ? .on : .off
        for b in [bold, italic, underline] {
            // Pressed toggles take the accent color so they read at a glance, in light and dark.
            b.contentTintColor = b.state == .on ? .controlAccentColor : nil
            b.setAccessibilityValue(b.state == .on ? "on" : "off")
        }
        align.selectedSegment = on ? s.alignment.flatMap { TextAlign.allCases.firstIndex(of: $0) } ?? -1 : -1
        vertical.selectedSegment = on && s.supportsVerticalAlign ? s.verticalAlign.flatMap { VerticalAlign.allCases.firstIndex(of: $0) } ?? -1 : -1
        if on && s.supportsOrientation, let o = s.orientation, let i = TextOrientation.allCases.firstIndex(of: o) {
            direction.selectItem(at: i)
        } else {
            direction.selectItem(at: 0)
        }
    }

    // MARK: Actions

    @objc private func sendChange(_ sender: NSButton) {
        guard let change = changes[ObjectIdentifier(sender)] else { return }
        controller.applyFormat(change)
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

    @objc private func directionPicked() {
        let i = direction.indexOfSelectedItem
        guard TextOrientation.allCases.indices.contains(i) else { return }
        controller.applyFormat(.orientation(TextOrientation.allCases[i]))
    }

    #if SCREENSHOT_SELFTESTS
    var debugControls: (font: NSPopUpButton, size: NSComboBox, bold: NSButton, italic: NSButton, underline: NSButton,
                        grow: NSButton, shrink: NSButton, align: NSSegmentedControl, vertical: NSSegmentedControl, direction: NSPopUpButton) {
        (fontPopup, sizeBox, bold, italic, underline, grow, shrink, align, vertical, direction)
    }
    #endif
}
