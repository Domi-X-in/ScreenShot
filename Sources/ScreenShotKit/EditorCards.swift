import AppKit

private typealias DT = DesignTokens

/// One of the new editor's floating cards (ROADMAP, Fase 6 · R5b): the chrome color, 12 pt corners, a hairline and a
/// soft shadow. Content goes in `content`, which is clipped to the corners (the canvas, the ribbon's edges).
class CardView: NSView {
    let content = NSView()
    private let edge = CardEdge()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerRadius = DT.Radius.card
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = DT.CardShadow.offset
        layer?.shadowRadius = DT.CardShadow.radius
        content.wantsLayer = true
        content.layer?.cornerRadius = DT.Radius.card
        content.layer?.masksToBounds = true
        for v in [content, edge] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Puts `view` inside the card, filling it.
    func embed(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor), view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor), view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = DT.color(.chrome).cgColor
            content.layer?.backgroundColor = DT.color(.chrome).cgColor
        }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.shadowOpacity = DT.CardShadow.opacity(dark: dark)
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: DT.Radius.card, cornerHeight: DT.Radius.card, transform: nil)
    }

    /// The hairline, drawn over the content so clipped content never covers it.
    private final class CardEdge: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: DT.Radius.card - 0.5, yRadius: DT.Radius.card - 0.5)
            p.lineWidth = 1
            DT.color(.line).setStroke()
            p.stroke()
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The window's own background behind the cards.
final class CanvasBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DT.color(.canvas).setFill()
        dirtyRect.fill()
    }
}

/// A card that stands in for a title bar: dragging its background moves the window, and a double-click zooms or
/// minimizes it as the user's macOS setting says.
class DraggableCard: CardView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // The system's "double-click a window's title bar to…" setting.
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
            return
        }
        window?.performDrag(with: event)
    }
}

/// The home window's title card: the window's buttons on the left, the app's name in the middle.
final class WindowTitleCard: DraggableCard {
    init(title: String) {
        super.init()
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = DT.color(.ink2)
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: content.centerXAnchor), label.centerYAnchor.constraint(equalTo: content.centerYAnchor)])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Title bar")
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The title bar as a card: the window's buttons sit inside it (the empty unified toolbar keeps them centered on it),
/// then Copy image, Save, Pin, Drag and Undo/Redo. Dragging the card's background moves the window, and a double-click
/// zooms it or minimizes it as the user's macOS setting says.
final class TitleCard: DraggableCard {
    /// Room for the close, minimize and zoom buttons.
    static let windowButtonsWidth: CGFloat = 72

    init(actions: NSView, drag: NSView, history: NSView) {
        super.init()
        let lead = NSView()
        let row = NSStackView(views: [lead, actions, Self.divider(), drag, Self.divider(), history])
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(row)
        NSLayoutConstraint.activate([
            lead.widthAnchor.constraint(equalToConstant: Self.windowButtonsWidth),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            row.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Title bar")
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func divider() -> NSView {
        let v = DividerLine()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 1), v.heightAnchor.constraint(equalToConstant: 16)])
        return v
    }

    private final class DividerLine: NSView {
        override func draw(_ dirtyRect: NSRect) { DT.color(.line).setFill(); bounds.fill() }
    }
}

/// The callout style bar (R5b): a narrow card beside the canvas with the five callout designs, shown while the Callout
/// tool is in hand or a callout is selected. The current design is lit with the soft accent; a click applies it to the
/// selected callouts and to the next one.
final class CalloutStyleBar: CardView {
    static let icons: [CalloutStyle: IconName] = [.box: .calloutBox, .card: .calloutCard, .speech: .calloutSpeech,
                                                   .thought: .calloutThought, .shout: .calloutShout]
    private(set) var items: [CalloutStyle: RibbonItem] = [:]
    var onPick: ((CalloutStyle) -> Void)?

    override init() {
        super.init()
        let column = NSStackView()
        column.orientation = .vertical
        column.spacing = 4
        column.alignment = .centerX
        column.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        for style in CalloutStyle.allCases {
            let item = RibbonItem("callout.\(style.rawValue)", kind: .small, title: style.title, icon: Self.icons[style])
            item.action = { [weak self] in self?.onPick?(style) }
            items[style] = item
            let b = RibbonButton(item)
            b.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 32), b.heightAnchor.constraint(equalToConstant: 32)])
            column.addArrangedSubview(b)
        }
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Callout styles")
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Lights the current design.
    func show(current: CalloutStyle) {
        for (style, item) in items { item.isOn = style == current }
    }

    var current: CalloutStyle? { items.first { $0.value.isOn }?.key }
}
