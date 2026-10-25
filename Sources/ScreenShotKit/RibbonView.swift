import AppKit

private typealias DT = DesignTokens

/// One expanded group: its columns (a large button, or two or three rows of items) and its title underneath.
final class RibbonGroupView: NSView {
    let group: RibbonGroup
    private(set) var buttons: [RibbonButton] = []
    private var dividers: [CGRect] = []
    private static let padding = NSEdgeInsets(top: 6, left: 8, bottom: 4, right: 8)
    private static let contentHeight: CGFloat = 62
    private static let columnGap: CGFloat = 4, itemGap: CGFloat = 2

    init(_ group: RibbonGroup) {
        self.group = group
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(group.title)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Lays the buttons out once; a group's size never changes.
    private func build() {
        var x = Self.padding.left
        let top = Self.padding.top
        for (ci, column) in group.columns.enumerated() {
            if ci > 0 { x += Self.columnGap }
            switch column {
            case let .large(item):
                let b = add(item)
                let w = RibbonButton.width(for: item)
                b.frame = CGRect(x: x, y: top, width: w, height: Self.contentHeight)
                x += w
            case let .rows(rows):
                let h: CGFloat = rows.count >= 3 ? 20 : DT.Metrics.smallButton
                let step = rows.count > 1 ? (Self.contentHeight - h) / CGFloat(rows.count - 1) : 0
                var columnWidth: CGFloat = 0
                for (ri, row) in rows.enumerated() {
                    var rx = x
                    let y = top + (rows.count == 1 ? (Self.contentHeight - h) / 2 : CGFloat(ri) * step)
                    for (ei, element) in row.enumerated() {
                        if ei > 0 { rx += Self.itemGap }
                        switch element {
                        case let .item(item):
                            let b = add(item)
                            let w = RibbonButton.width(for: item)
                            b.frame = CGRect(x: rx, y: y, width: w, height: h)
                            rx += w
                        case .divider:
                            dividers.append(CGRect(x: rx + 4, y: y + (h - 16) / 2, width: 1, height: 16))
                            rx += 9
                        }
                    }
                    columnWidth = max(columnWidth, rx - x)
                }
                x += columnWidth
            }
        }
        let titleWidth = (group.title as NSString).size(withAttributes: [.font: DT.Font.groupLabel]).width + 16
        let width = max(x + Self.padding.right, ceil(titleWidth))
        frame.size = CGSize(width: ceil(width), height: DT.Metrics.ribbonHeight)
    }

    private func add(_ item: RibbonItem) -> RibbonButton {
        let b = RibbonButton(item)
        addSubview(b)
        buttons.append(b)
        return b
    }

    /// The group's natural width (what it needs to show everything).
    var preferredWidth: CGFloat { frame.width }

    override func draw(_ dirtyRect: NSRect) {
        DT.color(.line).setFill()
        for d in dividers { d.fill() }
        let attrs: [NSAttributedString.Key: Any] = [.font: DT.Font.groupLabel, .foregroundColor: DT.color(.ink3)]
        let s = group.title as NSString
        let size = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - Self.padding.bottom - size.height), withAttributes: attrs)
    }
}

/// The Office-style ribbon: groups left to right with dividers; when the window narrows, groups fold into compact
/// buttons one at a time from the right (`RibbonLayout`). A compact button opens its group in a flyout.
final class RibbonView: NSView {
    let groups: [RibbonGroup]
    private var groupViews: [RibbonGroupView] = []
    private var compactButtons: [CompactGroupButton] = []
    private var dividerXs: [CGFloat] = []
    private var flyout: RibbonFlyout?
    private static let sidePadding: CGFloat = 8

    /// How many groups are folded right now.
    private(set) var collapsedCount = 0
    /// Off inside a card, which draws the background and the edge.
    var drawsChrome = true { didSet { needsDisplay = true } }

    init(groups: [RibbonGroup]) {
        self.groups = groups
        super.init(frame: CGRect(x: 0, y: 0, width: 800, height: DT.Metrics.ribbonHeight))
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Editing ribbon")
        for g in groups {
            g.observe(self)
            let v = RibbonGroupView(g)
            groupViews.append(v)
            addSubview(v)
            let c = CompactGroupButton(g)
            c.onToggle = { [weak self] in self?.toggleFlyout(for: $0) }
            compactButtons.append(c)
            addSubview(c)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: DT.Metrics.ribbonHeight) }

    /// The groups shown now (contextual groups come and go), in order.
    private var visibleIndices: [Int] { groups.indices.filter { !groups[$0].isHidden } }

    /// Each shown group's natural width, in order.
    var fullWidths: [CGFloat] { visibleIndices.map { groupViews[$0].preferredWidth } }

    /// The window widths (ribbon widths) at which each next group folds.
    var breakpoints: [CGFloat] { RibbonLayout.breakpoints(full: fullWidths).map { $0 + 2 * Self.sidePadding } }

    func isCompact(_ group: RibbonGroup) -> Bool {
        let shown = visibleIndices
        guard let i = groups.firstIndex(where: { $0 === group }), let k = shown.firstIndex(of: i) else { return false }
        return k >= shown.count - collapsedCount
    }

    func compactButton(for group: RibbonGroup) -> CompactGroupButton? {
        groups.firstIndex { $0 === group }.map { compactButtons[$0] }
    }

    override func layout() {
        super.layout()
        let available = bounds.width - 2 * Self.sidePadding
        let c = RibbonLayout.collapsedCount(available: available, full: fullWidths)
        if c != collapsedCount { closeFlyout() }
        collapsedCount = c
        var x = Self.sidePadding
        dividerXs = []
        let shown = visibleIndices
        let n = shown.count
        for i in groups.indices where groups[i].isHidden {
            groupViews[i].isHidden = true
            compactButtons[i].isHidden = true
            if flyout?.group === groups[i] { closeFlyout() }
        }
        for (k, i) in shown.enumerated() {
            let expanded = k < n - c
            groupViews[i].isHidden = !expanded
            compactButtons[i].isHidden = expanded
            if expanded {
                groupViews[i].frame.origin = CGPoint(x: x, y: 0)
                x += groupViews[i].frame.width
                if k < n - 1 { dividerXs.append(x); x += RibbonLayout.divider }
            } else {
                let size = DT.Metrics.compactGroupButton
                compactButtons[i].frame = CGRect(x: x + 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
                x += RibbonLayout.compactWidth
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if drawsChrome {
            DT.color(.chrome).setFill()
            bounds.fill()
            DT.color(.lineSoft).setFill()
            CGRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
        DT.color(.line).setFill()
        if drawsChrome { CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill() }
        for x in dividerXs { CGRect(x: x, y: 10, width: 1, height: bounds.height - 18).fill() }
    }

    // MARK: Flyouts

    /// Opens the group's flyout under its compact button, or closes it when it's open.
    func toggleFlyout(for button: CompactGroupButton) {
        if let open = flyout, open.group === button.group { closeFlyout(); return }
        closeFlyout()
        guard let window else { return }
        let f = RibbonFlyout(group: button.group)
        f.onClose = { [weak self, weak button] in
            button?.isOpen = false
            if self?.flyout === f { self?.flyout = nil }
        }
        flyout = f
        button.isOpen = true
        // Groups on the right half open toward the left so the flyout stays inside the window.
        f.show(under: button, in: window, alignRight: button.frame.midX > bounds.midX)
    }

    func closeFlyout() {
        flyout?.close()
        flyout = nil
    }

    /// Whether keyboard focus is in one of the ribbon's typeable fields (Font Size), so text being typed stays open.
    func owns(_ responder: NSResponder) -> Bool {
        let all = groupViews.flatMap(\.buttons) + (flyout?.groupView.buttons ?? [])
        return all.contains { $0.ownsEditor(responder) }
    }

    /// The open flyout's group, if any (for tests and VoiceOver).
    var openFlyoutGroup: RibbonGroup? { flyout?.group }
    var openFlyout: RibbonFlyout? { flyout }
}

/// A folded group shown in full on a raised panel under its compact button. Closes on a click outside, on Esc, or when
/// a command in it runs a menu or an action that moves the focus away.
final class RibbonFlyout: NSPanel {
    let group: RibbonGroup
    let groupView: RibbonGroupView
    var onClose: (() -> Void)?
    private var monitors: [Any] = []

    init(group: RibbonGroup) {
        self.group = group
        groupView = RibbonGroupView(group)
        let inset = CGSize(width: 4, height: 2)
        let size = CGSize(width: groupView.frame.width + 2 * inset.width, height: groupView.frame.height + 2 * inset.height)
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        let card = FlyoutCard(frame: CGRect(origin: .zero, size: size))
        groupView.frame.origin = CGPoint(x: inset.width, y: inset.height)
        card.addSubview(groupView)
        contentView = card
        setAccessibilityLabel(group.title)
    }

    override var canBecomeKey: Bool { false }

    func show(under anchor: NSView, in parent: NSWindow, alignRight: Bool) {
        appearance = parent.effectiveAppearance
        let a = anchor.convert(anchor.bounds, to: nil)
        let onScreen = parent.convertToScreen(a)
        var origin = CGPoint(x: alignRight ? onScreen.maxX - frame.width : onScreen.minX, y: onScreen.minY - 4 - frame.height)
        if let screen = parent.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - frame.width - 4)
            origin.y = max(origin.y, screen.minY + 4)
        }
        setFrameOrigin(origin)
        parent.addChildWindow(self, ordered: .above)
        orderFront(nil)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak anchor] e in
            guard let self else { return e }
            if e.window === self { return e }
            // A click on the compact button itself toggles it closed through its own action.
            if let anchor, e.window === anchor.window, anchor.bounds.contains(anchor.convert(e.locationInWindow, from: nil)) { return e }
            self.close()
            return e
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.close(); return nil } // Esc
            return e
        } as Any)
    }

    override func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        parent?.removeChildWindow(self)
        super.close()
        let done = onClose
        onClose = nil
        done?()
    }
}

/// The flyout's raised card: panel color, hairline, 10 pt corners.
private final class FlyoutCard: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: DT.Radius.menu, yRadius: DT.Radius.menu)
        DT.color(.panel).setFill(); path.fill()
        DT.color(.line).setStroke(); path.lineWidth = 1; path.stroke()
    }
}
