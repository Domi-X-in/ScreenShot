import AppKit

/// Shared look of the floating thumbnail, pins and HUD: canvas, palette wells and the accent, light and dark.
enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    /// Editor backdrop behind the screenshot, with a faint dot grid.
    static let canvas = dynamic(light: NSColor(hex: 0xE8EAEF), dark: NSColor(hex: 0x17181D))
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
