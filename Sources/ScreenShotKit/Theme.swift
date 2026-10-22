import AppKit

/// Shared look: canvas, cards and the accent, each with light and dark variants.
enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    /// Editor backdrop behind the screenshot, with a faint dot grid.
    static let canvas = dynamic(light: NSColor(hex: 0xE8EAEF), dark: NSColor(hex: 0x17181D))
    static let canvasDot = dynamic(light: NSColor.black.withAlphaComponent(0.09), dark: NSColor.white.withAlphaComponent(0.07))
    /// Floating cards (options bar, palettes).
    static let card = dynamic(light: NSColor.white.withAlphaComponent(0.92), dark: NSColor(hex: 0x26272E).withAlphaComponent(0.94))
    static let cardBorder = dynamic(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.09))
    static let paletteWell = dynamic(light: NSColor.black.withAlphaComponent(0.045), dark: NSColor.white.withAlphaComponent(0.06))
    static let hover = dynamic(light: NSColor.black.withAlphaComponent(0.07), dark: NSColor.white.withAlphaComponent(0.1))
    static let icon = dynamic(light: NSColor(hex: 0x3A3D45), dark: NSColor(hex: 0xD7D9E0))

    /// Brand gradient for the selected tool, built around Shottr's clrMain (#FF0C01).
    static let accentTop = NSColor(hex: 0xFF6A3D)
    static let accentBottom = NSColor(hex: 0xFF1E0A)

    static func accentGradientLayer() -> CAGradientLayer {
        let g = CAGradientLayer()
        g.colors = [accentTop.cgColor, accentBottom.cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 1)
        g.endPoint = CGPoint(x: 0.5, y: 0)
        return g
    }

    /// Applies a soft card shadow to a layer-backed view.
    static func cardShadow(_ v: NSView, radius: CGFloat = 14, opacity: Float = 0.18) {
        v.shadow = NSShadow()
        v.layer?.shadowColor = NSColor.black.cgColor
        v.layer?.shadowOpacity = opacity
        v.layer?.shadowRadius = radius
        v.layer?.shadowOffset = CGSize(width: 0, height: -3)
    }
}

/// Row of icon buttons in a rounded well. In `.select` mode one item stays highlighted with the accent pill;
/// in `.momentary` mode items act as buttons. `groups` lists how many items go in each group (dividers between).
final class IconPalette: NSView {
    enum Mode { case select, momentary }

    struct Item {
        let symbol: String
        let tooltip: String
    }

    var onSelect: ((Int) -> Void)?
    private let mode: Mode
    private var buttons: [PaletteButton] = []

    var selectedIndex: Int? {
        didSet { buttons.enumerated().forEach { $0.element.isSelected = $0.offset == selectedIndex } }
    }

    init(items: [Item], groups: [Int]? = nil, mode: Mode, itemWidth: CGFloat = 30) {
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = Theme.paletteWell.cgColor

        let stack = NSStackView()
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        var boundaries = Set<Int>()
        var acc = 0
        for g in (groups ?? [items.count]).dropLast() { acc += g; boundaries.insert(acc) }
        for (i, item) in items.enumerated() {
            if boundaries.contains(i) {
                let div = NSView()
                div.wantsLayer = true
                div.layer?.backgroundColor = NSColor.separatorColor.cgColor
                div.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([div.widthAnchor.constraint(equalToConstant: 1), div.heightAnchor.constraint(equalToConstant: 16)])
                stack.addArrangedSubview(div)
            }
            let b = PaletteButton(symbol: item.symbol, tooltip: item.tooltip, width: itemWidth) { [weak self] in self?.clicked(i) }
            buttons.append(b)
            stack.addArrangedSubview(b)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = Theme.paletteWell.cgColor }
    }

    private func clicked(_ i: Int) {
        if mode == .select { selectedIndex = i }
        onSelect?(i)
    }
}

/// One palette button: hover wash, accent pill when selected, a small press animation.
final class PaletteButton: NSView {
    var isSelected = false {
        didSet {
            refresh(animated: true)
            setAccessibilityValue(isSelected ? "selected" : nil)
        }
    }
    private let image = NSImageView()
    private let pill = Theme.accentGradientLayer()
    private var hovering = false { didSet { refresh(animated: true) } }
    private let action: () -> Void

    init(symbol: String, tooltip: String, width: CGFloat, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        // VoiceOver: a named button that can be pressed.
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip)
        wantsLayer = true
        layer?.cornerRadius = 7
        pill.cornerRadius = 7
        pill.opacity = 0
        pill.shadowColor = Theme.accentBottom.cgColor
        pill.shadowOpacity = 0.45
        pill.shadowRadius = 5
        pill.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(pill)
        toolTip = tooltip
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width), heightAnchor.constraint(equalToConstant: 26),
            image.centerXAnchor.constraint(equalTo: centerXAnchor), image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        refresh(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh(animated: false)
    }

    private func refresh(animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.18 : 0)
        pill.opacity = isSelected ? 1 : 0
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (hovering && !isSelected ? Theme.hover : .clear).cgColor
        }
        CATransaction.commit()
        image.contentTintColor = isSelected ? .white : Theme.icon
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        // Quick press feedback, then act.
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: frame.midX, y: frame.midY)
        let press = CABasicAnimation(keyPath: "transform.scale")
        press.fromValue = 0.88
        press.toValue = 1
        press.duration = 0.18
        press.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(press, forKey: "press")
        action()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Text pill button with an icon (used for Crop), matching the palette look.
final class PillButton: NSView {
    var isOn = false { didSet { refresh() } }
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let pill = Theme.accentGradientLayer()
    private let action: () -> Void
    private var hovering = false { didSet { refresh() } }

    init(title: String, symbol: String, tooltip: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        pill.cornerRadius = 9
        pill.opacity = 0
        layer?.addSublayer(pill)
        toolTip = tooltip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityHelp(tooltip)
        label.stringValue = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 32), widthAnchor.constraint(equalTo: stack.widthAnchor, constant: 22),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        pill.opacity = isOn ? 1 : 0
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isOn ? .clear : hovering ? Theme.hover : Theme.paletteWell).cgColor
        }
        label.textColor = isOn ? .white : Theme.icon
        icon.contentTintColor = isOn ? .white : Theme.icon
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { action() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}

/// Segmented control for options-bar choices: right-click a segment to make it the default for new annotations.
/// The current default carries a small accent dot.
final class DefaultableSegmentedControl: NSSegmentedControl {
    var defaultIndex: Int? { didSet { needsDisplay = true } }
    var onSetDefault: ((Int) -> Void)?
    var onResetDefault: (() -> Void)?

    /// Name of a segment for menus: its label, else its tooltip.
    func name(of i: Int) -> String {
        if let l = label(forSegment: i), !l.isEmpty { return l }
        return toolTip(forSegment: i) ?? "Option \(i + 1)"
    }

    /// Segment under a point in this control's coordinates (auto-width segments share the leftover space).
    func segment(at p: CGPoint) -> Int? {
        guard segmentCount > 0, bounds.contains(p) else { return nil }
        let fixed = (0..<segmentCount).map { width(forSegment: $0) }
        let autoCount = fixed.filter { $0 == 0 }.count
        let share = autoCount > 0 ? max(0, bounds.width - fixed.reduce(0, +)) / CGFloat(autoCount) : 0
        var x: CGFloat = 0
        for i in 0..<segmentCount {
            x += fixed[i] == 0 ? share : fixed[i]
            if p.x < x { return i }
        }
        return segmentCount - 1
    }

    private func segmentMidX(_ i: Int) -> CGFloat {
        let fixed = (0..<segmentCount).map { width(forSegment: $0) }
        let autoCount = fixed.filter { $0 == 0 }.count
        let share = autoCount > 0 ? max(0, bounds.width - fixed.reduce(0, +)) / CGFloat(autoCount) : 0
        let widths = fixed.map { $0 == 0 ? share : $0 }
        return widths.prefix(i).reduce(0, +) + widths[i] / 2
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = segment(at: convert(event.locationInWindow, from: nil)) else { return nil }
        let m = NSMenu()
        let set = NSMenuItem(title: "Set “\(name(of: i))” as Default", action: #selector(setDefaultClicked(_:)), keyEquivalent: "")
        set.target = self
        set.tag = i
        set.state = i == defaultIndex ? .on : .off
        m.addItem(set)
        if let d = defaultIndex, d >= 0, d < segmentCount {
            let info = NSMenuItem(title: "Current default: \(name(of: d))", action: nil, keyEquivalent: "")
            info.isEnabled = false
            m.addItem(info)
        }
        m.addItem(.separator())
        let reset = NSMenuItem(title: "Reset to Original Default", action: #selector(resetClicked), keyEquivalent: "")
        reset.target = self
        m.addItem(reset)
        return m
    }

    @objc private func setDefaultClicked(_ sender: NSMenuItem) { onSetDefault?(sender.tag) }
    @objc private func resetClicked() { onResetDefault?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let d = defaultIndex, d >= 0, d < segmentCount else { return }
        // Accent dot under the default choice.
        let x = segmentMidX(d)
        let y = isFlipped ? bounds.maxY - 3.5 : bounds.minY + 1
        let dot = NSBezierPath(ovalIn: CGRect(x: x - 1.75, y: y, width: 3.5, height: 2.5))
        Palette.accent.setFill()
        dot.fill()
    }
}
