import AppKit

private typealias DT = DesignTokens

/// One ribbon command, drawn from its `RibbonItem`: small icon button, icon and label, large button, dropdown field or
/// color button. States follow the design: neutral hover and pressed; the accent only for a toggle that is on
/// (soft fill), the tool in hand (solid fill, white icon) and the keyboard focus ring. Like Office's buttons it never
/// takes the keyboard focus unless Full Keyboard Access is on, so text being edited keeps its selection.
final class RibbonButton: NSView, NSTextFieldDelegate {
    let item: RibbonItem
    /// The editor over a typeable field while it's open.
    private(set) var entry: NSTextField?
    /// Row height given by the group (28 for two rows, 20 for three, 62 for a large button).
    private(set) var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }
    private(set) var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }
    private(set) var menuOpen = false { didSet { if menuOpen != oldValue { needsDisplay = true } } }

    /// Shows a menu under a view. Tests replace it to see the menu without the modal tracking loop.
    @MainActor static var presentMenu: (NSMenu, NSView) -> Void = { menu, view in
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 3), in: view)
    }

    init(_ item: RibbonItem) {
        self.item = item
        super.init(frame: .zero)
        item.observe(self)
        setAccessibilityElement(true)
        toolTip = item.shortcut.map { "\(item.title) (\($0))" } ?? item.title
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Size

    /// The button's width for its item; its height comes from the row it sits in.
    @MainActor static func width(for item: RibbonItem) -> CGFloat {
        switch item.kind {
        case .small: return item.hasChevron ? 40 : 28
        case .color: return 40
        case let .field(width): return width
        case .label:
            let text = (item.title as NSString).size(withAttributes: [.font: DT.Font.ribbonLabel]).width
            return ceil(6 + 16 + 6 + text + (item.hasChevron ? 4 + 9 : 0) + 6)
        case .large:
            let text = (item.title as NSString).size(withAttributes: [.font: DT.Font.largeCaption]).width
            return max(DT.Metrics.largeButton.width, ceil(text + 12))
        }
    }

    // MARK: Drawing

    /// The fill and ink for the current state.
    private var colors: (fill: NSColor?, ink: NSColor, text: NSColor) {
        if item.isActiveTool {
            let fill = pressed ? DT.color(.accentPressed) : hovering ? DT.color(.accentHover) : DT.color(.accent)
            return (fill, .white, .white)
        }
        if item.isOn { return (DT.color(.accentSoft), DT.color(.accentText), DT.color(.ink)) }
        if pressed || menuOpen { return (DT.color(.pressed), DT.color(.ink), DT.color(.ink)) }
        if hovering && item.isEnabled { return (DT.color(.hover), DT.color(.ink), DT.color(.ink)) }
        return (nil, DT.color(.ink2), DT.color(.ink))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        let disabled = !item.isEnabled
        if disabled { ctx.setAlpha(0.45) }
        let (fill, ink, text) = disabled ? (nil, DT.color(.ink3), DT.color(.ink3)) : colors
        let radius = item.kind == .large ? DT.Radius.large : DT.Radius.control

        if case .field = item.kind {
            let r = b.insetBy(dx: 0.5, dy: (b.height - 26) / 2 + 0.5)
            if entry != nil {
                // The editor draws the text; only the box and its chevron here.
                let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
                DT.color(.field).setFill(); path.fill()
                DT.color(.accent).setStroke(); path.lineWidth = 1; path.stroke()
                drawIcon(.chev, size: 10, color: DT.color(.ink3), at: CGPoint(x: r.maxX - 16, y: r.midY - 5))
                return
            }
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            DT.color(.field).setFill(); path.fill()
            (menuOpen ? DT.color(.accent) : hovering && !disabled ? DT.color(.ink3) : DT.color(.line)).setStroke()
            path.lineWidth = 1; path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: DT.Font.ribbonLabel, .foregroundColor: DT.color(.ink)]
            let s = item.text as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(with: CGRect(x: r.minX + 8, y: r.midY - size.height / 2, width: r.width - 30, height: size.height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            drawIcon(.chev, size: 10, color: DT.color(.ink3), at: CGPoint(x: r.maxX - 16, y: r.midY - 5))
            drawFocusRing(in: r, radius: radius)
            return
        }

        if let fill {
            fill.setFill()
            NSBezierPath(roundedRect: b, xRadius: radius, yRadius: radius).fill()
        }
        if item.isActiveTool && !disabled {
            // The deeper accent edge keeps the selected tool at 3:1 or more against the light bar (#FF5500 alone is 2.99:1).
            let edge = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
            edge.lineWidth = 1
            DT.color(.accentPressed).setStroke()
            edge.stroke()
        }
        let chevronInk = item.isActiveTool ? NSColor.white.withAlphaComponent(0.8) : DT.color(.ink3)

        switch item.kind {
        case .small:
            let iconX = item.hasChevron ? 6 : (b.width - 16) / 2
            if let icon = item.icon { drawIcon(icon, size: 16, color: ink, at: CGPoint(x: iconX, y: (b.height - 16) / 2)) }
            if item.hasChevron { drawIcon(.chev, size: 9, color: chevronInk, at: CGPoint(x: b.width - 15, y: (b.height - 9) / 2)) }
        case .label:
            if let icon = item.icon { drawIcon(icon, size: 16, color: ink, at: CGPoint(x: 6, y: (b.height - 16) / 2)) }
            let attrs: [NSAttributedString.Key: Any] = [.font: DT.Font.ribbonLabel, .foregroundColor: text]
            let s = item.title as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: 28, y: (b.height - size.height) / 2), withAttributes: attrs)
            if item.hasChevron { drawIcon(.chev, size: 9, color: chevronInk, at: CGPoint(x: 28 + size.width + 4, y: (b.height - 9) / 2)) }
        case .color:
            if let icon = item.icon { drawIcon(icon, size: 16, color: ink, at: CGPoint(x: 6, y: b.height / 2 - 11)) }
            let bar = CGRect(x: 6, y: b.height / 2 + 6, width: 16, height: 3)
            if let c = item.barColor {
                c.setFill(); NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
                NSColor.gray.withAlphaComponent(0.35).setStroke(); NSBezierPath(roundedRect: bar.insetBy(dx: 0.25, dy: 0.25), xRadius: 1, yRadius: 1).stroke()
            } else {
                drawNoneBar(bar)
            }
            drawIcon(.chev, size: 9, color: chevronInk, at: CGPoint(x: b.width - 15, y: (b.height - 9) / 2))
        case .large:
            if let icon = item.icon { drawIcon(icon, size: 26, color: ink, at: CGPoint(x: (b.width - 26) / 2, y: 7)) }
            let attrs: [NSAttributedString.Key: Any] = [.font: DT.Font.largeCaption, .foregroundColor: text]
            let s = item.title as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: (b.width - size.width) / 2, y: 36), withAttributes: attrs)
            if item.hasChevron { drawIcon(.chev, size: 10, color: chevronInk, at: CGPoint(x: (b.width - 10) / 2, y: 51)) }
        case .field:
            break
        }
        drawFocusRing(in: b, radius: radius)
    }

    private func drawIcon(_ name: IconName, size: CGFloat, color: NSColor, at p: CGPoint) {
        Icons.image(name, size: size, color: color).draw(in: CGRect(origin: p, size: CGSize(width: size, height: size)))
    }

    /// "No color": a hatched bar.
    private func drawNoneBar(_ r: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        DT.color(.ink3).setStroke()
        var x = r.minX - r.height
        while x < r.maxX {
            let p = NSBezierPath(); p.move(to: CGPoint(x: x, y: r.maxY)); p.line(to: CGPoint(x: x + r.height, y: r.minY)); p.lineWidth = 1; p.stroke()
            x += 3
        }
        NSGraphicsContext.restoreGraphicsState()
        DT.color(.line).setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    private func drawFocusRing(in r: CGRect, radius: CGFloat) {
        guard window?.firstResponder === self else { return }
        let ring = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        ring.lineWidth = 2
        DT.color(.accent).setStroke()
        ring.stroke()
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard item.isEnabled else { return }
        pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard item.isEnabled else { return }
        pressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard item.isEnabled, pressed else { pressed = false; return }
        pressed = false
        activate(at: convert(event.locationInWindow, from: nil))
    }

    /// Whether a click at `p` opens the menu: always for menu-only items; the chevron part of a split item.
    func opensMenu(at p: CGPoint?) -> Bool {
        guard item.menu != nil else { return false }
        guard item.split, let p else { return true }
        if item.kind == .large { return p.y >= bounds.height - 16 }
        return p.x >= bounds.width - 14
    }

    /// A click (at `p`), a press of Space or Return (p nil runs the main part), or the accessibility press.
    func activate(at p: CGPoint?) {
        guard item.isEnabled else { return }
        // A typeable field: its text opens the editor, its chevron the menu.
        if item.onTextEntry != nil, let p, p.x < bounds.width - 18 { beginTextEntry(); return }
        if opensMenu(at: p) { showMenu() } else { item.action?() }
    }

    // MARK: Typing in a field

    /// Opens an editor over the field with its value selected. Return applies, Esc or clicking away cancels.
    func beginTextEntry() {
        guard entry == nil, item.isEnabled, item.onTextEntry != nil else { return }
        let f = NSTextField(string: item.text)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = DT.Font.ribbonLabel
        f.textColor = DT.color(.ink)
        f.delegate = self
        f.setAccessibilityLabel(item.title)
        let h: CGFloat = 16
        f.frame = CGRect(x: 7, y: (bounds.height - h) / 2, width: bounds.width - 26, height: h)
        addSubview(f)
        entry = f
        menuOpen = true
        window?.makeFirstResponder(f)
        f.currentEditor()?.selectAll(nil)
    }

    private func entryCommitted() {
        guard let f = entry else { return }
        let text = f.stringValue
        endTextEntry()
        item.onTextEntry?(text)
    }

    private func endTextEntry() {
        guard let f = entry else { return }
        entry = nil
        menuOpen = false
        f.delegate = nil
        f.removeFromSuperview()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Return (or Enter) applies what was typed; anything else (a click elsewhere, Tab) just closes the editor.
        guard entry != nil else { return }
        let commit = (obj.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.return.rawValue
        // After AppKit has finished closing this field: the window's field editor is shared, and giving it back to the
        // text being typed any sooner would close that text too.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { if commit { self?.entryCommitted() } else { self?.endTextEntry() } }
        }
    }

    #if SCREENSHOT_SELFTESTS
    /// Types `text` into the open editor and presses Return.
    func debugType(_ text: String) {
        guard let f = entry, let editor = f.currentEditor() as? NSTextView else { return }
        editor.string = text
        editor.insertNewline(nil) // Return, as a person presses it
    }
    #endif

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { endTextEntry(); return true }
        return false
    }

    /// Whether `responder` is this field's editor (the editor's text view has the field as its delegate).
    func ownsEditor(_ responder: NSResponder) -> Bool {
        guard let f = entry else { return false }
        if responder === f { return true }
        if let t = responder as? NSTextView, t.delegate === f { return true }
        return false
    }

    func showMenu() {
        guard item.isEnabled, let make = item.menu else { return }
        menuOpen = true
        Self.presentMenu(make(), self)
        menuOpen = false
    }

    // MARK: Keyboard

    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled && item.isEnabled }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36, 76: activate(at: nil) // Space, Return, Enter
        case 125: if item.menu != nil { showMenu() } else { super.keyDown(with: event) } // ↓ opens the menu
        default: super.keyDown(with: event)
        }
    }

    // MARK: Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? { item.menu != nil && !item.split ? .popUpButton : .button }
    override func accessibilityLabel() -> String? { item.title }
    override func accessibilityValue() -> Any? {
        if case .field = item.kind { return item.text }
        if item.isActiveTool { return "selected" }
        return item.isOn ? "on" : nil
    }
    override func isAccessibilityEnabled() -> Bool { item.isEnabled }
    override func accessibilityPerformPress() -> Bool { activate(at: nil); return true }
    override func accessibilityPerformShowMenu() -> Bool { showMenu(); return item.menu != nil }
}

/// A folded group: one large button with the group's icon, its name and a chevron; a click opens the group in a
/// flyout. When the tool in hand belongs to the group, the button shows that tool's icon in the accent, so the active
/// tool stays visible.
final class CompactGroupButton: NSView {
    let group: RibbonGroup
    var onToggle: ((CompactGroupButton) -> Void)?
    var isOpen = false { didSet { if isOpen != oldValue { needsDisplay = true; setAccessibilityExpanded(isOpen) } } }
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }
    private var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }

    init(_ group: RibbonGroup) {
        self.group = group
        super.init(frame: CGRect(origin: .zero, size: DT.Metrics.compactGroupButton))
        group.observe(self)
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// The icon shown: the active tool's when it is in this group, else the group's own.
    var displayIcon: IconName { group.activeTool?.icon ?? group.compactIcon }
    var showsActiveTool: Bool { group.activeTool != nil }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let fill: NSColor? = isOpen || pressed ? DT.color(.pressed) : showsActiveTool ? DT.color(.accentSoft) : hovering ? DT.color(.hover) : nil
        let path = NSBezierPath(roundedRect: b, xRadius: DT.Radius.large, yRadius: DT.Radius.large)
        if let fill { fill.setFill(); path.fill() }
        if isOpen { DT.color(.line).setStroke(); NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: DT.Radius.large, yRadius: DT.Radius.large).stroke() }
        let iconColor = showsActiveTool ? DT.color(.accent) : DT.color(.ink2)
        Icons.image(displayIcon, size: 24, color: iconColor).draw(in: CGRect(x: (b.width - 24) / 2, y: 12, width: 24, height: 24))
        let attrs: [NSAttributedString.Key: Any] = [.font: DT.Font.largeCaption, .foregroundColor: DT.color(.ink)]
        let s = group.compactTitle as NSString
        let size = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: (b.width - size.width) / 2, y: 42), withAttributes: attrs)
        Icons.image(.chev, size: 10, color: DT.color(.ink3)).draw(in: CGRect(x: (b.width - 10) / 2, y: 60, width: 10, height: 10))
        if window?.firstResponder === self {
            let ring = NSBezierPath(roundedRect: b.insetBy(dx: 1, dy: 1), xRadius: DT.Radius.large, yRadius: DT.Radius.large)
            ring.lineWidth = 2; DT.color(.accent).setStroke(); ring.stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { onToggle?(self) }
    }

    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func keyDown(with event: NSEvent) {
        if [49, 36, 76, 125].contains(event.keyCode) { onToggle?(self) } else { super.keyDown(with: event) }
    }

    override func accessibilityLabel() -> String? {
        if let tool = group.activeTool { return "\(group.title), active tool: \(tool.title)" }
        return group.title
    }
    override func accessibilityPerformPress() -> Bool { onToggle?(self); return true }
}
