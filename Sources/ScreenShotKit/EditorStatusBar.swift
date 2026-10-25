import AppKit

private typealias DT = DesignTokens

/// The new editor's messages (ROADMAP, Fase 6 · R5), in the bottom-left of the status bar: a chip with an icon, the
/// text, an optional action and a close button. Four states: info (tool hints, and short tips), success (copied,
/// saved: fades after 3 s), warning and error (stay until closed or replaced, and offer a way forward). The tool's hint
/// sits underneath: it shows whenever no message does.
final class NotificationBar: NSView {
    enum Kind: String {
        case info, success, warning, error

        var icon: IconName {
            switch self {
            case .info: .info
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
        }
        var ink: DesignTokens.Role {
            switch self {
            case .info: .info
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
        }
        var fill: DesignTokens.Role {
            switch self {
            case .info: .infoBackground
            case .success: .successBackground
            case .warning: .warningBackground
            case .error: .errorBackground
            }
        }
        /// How long a message stays: success and short tips fade; problems stay until dealt with.
        var duration: TimeInterval? {
            switch self {
            case .success: 3
            case .info: 4
            case .warning, .error: nil
            }
        }
    }

    struct Notice {
        var kind: Kind
        var text: String
        var actionTitle: String?
        var action: (() -> Void)?
        var duration: TimeInterval?

        init(_ kind: Kind, _ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
            self.kind = kind
            self.text = text
            self.actionTitle = actionTitle
            self.action = action
            duration = kind.duration
        }
    }

    /// The message shown, or nil while the tool's hint shows.
    private(set) var current: Notice?
    private(set) var hint = ""
    private var generation = 0

    private let chip = ChipBackground()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        label.cell?.truncatesLastVisibleLine = true
        actionButton.isBordered = false
        actionButton.target = self
        actionButton.action = #selector(actionClicked)
        actionButton.refusesFirstResponder = true
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        closeButton.isBordered = false
        closeButton.image = Icons.image(.close, size: 14)
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.refusesFirstResponder = true
        closeButton.toolTip = "Dismiss"
        closeButton.setAccessibilityLabel("Dismiss notification")
        let row = NSStackView(views: [icon, label, actionButton, closeButton])
        row.spacing = 8
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)
        row.setCustomSpacing(4, after: actionButton)
        row.translatesAutoresizingMaskIntoConstraints = false
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(row)
        addSubview(chip)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 22), closeButton.heightAnchor.constraint(equalToConstant: 22),
            row.leadingAnchor.constraint(equalTo: chip.leadingAnchor), row.trailingAnchor.constraint(equalTo: chip.trailingAnchor),
            row.topAnchor.constraint(equalTo: chip.topAnchor), row.bottomAnchor.constraint(equalTo: chip.bottomAnchor),
            chip.leadingAnchor.constraint(equalTo: leadingAnchor),
            chip.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            chip.centerYAnchor.constraint(equalTo: centerYAnchor),
            chip.heightAnchor.constraint(equalToConstant: 28),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        render()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The tool's hint, shown whenever no message is.
    func setHint(_ text: String) {
        guard text != hint else { return }
        hint = text
        if current == nil { render() }
    }

    func show(_ notice: Notice) {
        current = notice
        generation += 1
        render()
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: notice.text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        if let d = notice.duration {
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.dismiss()
            }
        }
    }

    func dismiss() {
        current = nil
        generation += 1
        render()
    }

    /// What the bar shows now: the message's kind and text, or the hint as info.
    var shownKind: Kind { current?.kind ?? .info }
    var shownText: String { current?.text ?? hint }
    var showsAction: Bool { !actionButton.isHidden }

    private func render() {
        let kind = shownKind
        chip.fillRole = kind.fill
        icon.image = Icons.image(kind.icon, size: 16, color: DT.color(kind.ink))
        label.stringValue = shownText
        label.textColor = DT.color(.ink)
        label.toolTip = shownText
        if let title = current?.actionTitle {
            actionButton.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                                                         .foregroundColor: DT.color(kind.ink)])
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
        closeButton.isHidden = current == nil
        closeButton.contentTintColor = DT.color(.ink3)
        chip.isHidden = shownText.isEmpty
        setAccessibilityLabel("\(kind.rawValue): \(shownText)")
    }

    @objc private func actionClicked() {
        let action = current?.action
        dismiss()
        action?()
    }

    @objc private func closeClicked() { dismiss() }

    #if SCREENSHOT_SELFTESTS
    var debugCloseShown: Bool { !closeButton.isHidden }
    func debugPressAction() { actionClicked() }
    func debugPressClose() { closeClicked() }
    #endif

    /// The chip's tinted, rounded background.
    private final class ChipBackground: NSView {
        var fillRole: DesignTokens.Role = .infoBackground { didSet { needsDisplay = true } }
        override func draw(_ dirtyRect: NSRect) {
            DT.color(fillRole).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: DT.Radius.large, yRadius: DT.Radius.large).fill()
        }
    }
}

/// The new editor's bottom bar: messages on the left; the color, size and zoom readouts and Backdrop on the right
/// (their function is unchanged, only restyled). Full width, under the canvas.
final class EditorStatusBar: NSView {
    let notices = NotificationBar()
    let backdropButton = BarButton(title: "Backdrop", icon: .backdrop, tooltip: "Backdrop: background, aspect ratio, padding, shadow (K toggles)")
    var onBackdropPanel: ((NSView) -> Void)?
    /// Off inside a card, which draws the background and the edge.
    var drawsChrome = true { didSet { needsDisplay = true } }

    init(info: InfoCellsView) {
        super.init(frame: .zero)
        info.applyModernStyle()
        backdropButton.onClick = { [weak self] in
            guard let self else { return }
            self.onBackdropPanel?(self.backdropButton)
        }
        notices.setContentHuggingPriority(.init(1), for: .horizontal)
        notices.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        info.setContentCompressionResistancePriority(.required, for: .horizontal)
        info.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [notices, info, backdropButton])
        row.spacing = 14
        row.alignment = .centerY
        row.distribution = .fill
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            notices.heightAnchor.constraint(equalToConstant: 28),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Status")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsChrome else { return }
        DT.color(.chrome).setFill()
        bounds.fill()
        DT.color(.line).setFill()
        CGRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    func update(tool: Tool, backdrop: Backdrop, cutOut: Bool, area: Bool = false) {
        backdropButton.isOn = backdrop.isOn
        notices.setHint(StatusBar.hint(for: tool, cutOut: cutOut, area: area))
    }
}

/// A bordered bar button with an icon and a title (Backdrop): neutral; the soft accent while its feature is on.
final class BarButton: NSView {
    var onClick: (() -> Void)?
    var isOn = false { didSet { if isOn != oldValue { needsDisplay = true; setAccessibilityValue(isOn ? "on" : "off") } } }
    private let title: String
    private let icon: IconName
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(title: String, icon: IconName, tooltip: String) {
        self.title = title
        self.icon = icon
        super.init(frame: .zero)
        toolTip = tooltip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        translatesAutoresizingMaskIntoConstraints = false
        let w = ceil((title as NSString).size(withAttributes: [.font: DT.Font.readout]).width) + 16 + 6 + 20
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: w), heightAnchor.constraint(equalToConstant: 28)])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
        (isOn ? DT.color(.accentSoft) : pressed ? DT.color(.pressed) : hovering ? DT.color(.hover) : DT.color(.panel)).setFill()
        path.fill()
        (isOn ? DT.color(.accent) : DT.color(.line)).setStroke()
        path.lineWidth = 1
        path.stroke()
        let ink = isOn ? DT.color(.accentText) : DT.color(.ink)
        Icons.image(icon, size: 16, color: isOn ? DT.color(.accentText) : DT.color(.ink2)).draw(in: CGRect(x: 10, y: (bounds.height - 16) / 2, width: 16, height: 16))
        let attrs: [NSAttributedString.Key: Any] = [.font: DT.Font.readout, .foregroundColor: ink]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: CGPoint(x: 32, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}
