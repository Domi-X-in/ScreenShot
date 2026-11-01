import AppKit

/// The editor with no screenshot at all yet (R14): the capture buttons, over the whole window.
final class EditorEmptyState: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    private(set) var items: [RibbonItem] = []

    init() {
        super.init(frame: .zero)
        let background = CanvasBackground()
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let title = NSTextField(labelWithString: "No screenshots yet")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = DesignTokens.color(.ink)
        let hint = NSTextField(labelWithString: "Take your first one, or open an image.")
        hint.font = DesignTokens.Font.caption
        hint.textColor = DesignTokens.color(.ink3)

        func large(_ id: String, _ title: String, _ icon: IconName, _ a: HotkeyAction?, action: @escaping () -> Void) -> RibbonItem {
            let i = RibbonItem(id, kind: .large, title: title, icon: icon, action: action)
            i.shortcut = a.flatMap { HotKeyCenter.shared.shortcut(for: $0)?.display }
            i.showsShortcut = i.shortcut != nil
            return i
        }
        let area = large("area", "Area", .capArea, .area) { AppLogic.shared.captureFromEditor(.area) }
        area.isOn = true // the main action
        items = [area,
                 large("window", "Window", .capWindow, .anyWindow) { AppLogic.shared.captureFromEditor(.anyWindow) },
                 large("fullscreen", "Fullscreen", .capFull, .fullscreen) { AppLogic.shared.captureFromEditor(.fullscreen) },
                 large("openImage", "Open Image", .openImage, nil) { AppLogic.shared.chooseFile() }]
        let group = RibbonGroupView(RibbonGroup("start", title: "", compactTitle: "Capture", compactIcon: .capArea, columns: items.map { .large($0) }))
        group.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([group.widthAnchor.constraint(equalToConstant: group.frame.width),
                                     group.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.ribbonHeight)])

        let stack = NSStackView(views: [title, hint, group])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(4, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
