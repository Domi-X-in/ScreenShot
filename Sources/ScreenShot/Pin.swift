import AppKit

/// Floating always-on-top screenshots (Shottr's PinWindowController).
@MainActor enum Pins {
    private static var windows: [PinWindow] = []

    static func pin(_ img: CGImage, scale: CGFloat, near: NSRect?) {
        let screen = NSScreen.containingMouse().visibleFrame
        var size = CGSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
        let fit = min(1, screen.width * 0.8 / size.width, screen.height * 0.8 / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        let center = near.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: screen.midX, y: screen.midY)
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let w = PinWindow(image: img, scale: scale, frame: frame)
        windows.append(w)
        w.makeKeyAndOrderFront(nil)
    }

    static func remove(_ w: PinWindow) {
        windows.removeAll { $0 === w }
    }
}

final class PinWindow: NSPanel {
    let image: CGImage
    let scale: CGFloat

    init(image: CGImage, scale: CGFloat, frame: CGRect) {
        self.image = image
        self.scale = scale
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = frame.size
        contentView = PinView(image: image)
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        Pins.remove(self)
    }
}

/// Pinned image with Shottr's hover bar (drag-out, edit, copy) and close button (Pin.storyboard).
final class PinView: NSView {
    private let image: CGImage
    private let hoverBar = NSVisualEffectView()
    private let closeButton = NSButton()
    private var semiTransparent = false

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
        toolTip = "Scroll to resize · ⌥Scroll for opacity · Double-click or Esc to close"
        buildHoverBar()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setHover(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func barButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.isBordered = false
        b.contentTintColor = .white
        b.toolTip = tip
        b.widthAnchor.constraint(equalToConstant: 24).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return b
    }

    private func buildHoverBar() {
        hoverBar.material = .hudWindow
        hoverBar.appearance = NSAppearance(named: .vibrantDark)
        hoverBar.state = .active
        hoverBar.wantsLayer = true
        hoverBar.layer?.cornerRadius = 8
        let drag = PinDragHandle(image: image)
        let stack = NSStackView(views: [drag, barButton("pencil", "Edit", #selector(editPin)), barButton("doc.on.doc", "Copy (⌘C)", #selector(copyPin))])
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        hoverBar.addSubview(stack)
        hoverBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverBar)

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.contentTintColor = NSColor.black.withAlphaComponent(0.65)
        closeButton.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        closeButton.target = self
        closeButton.action = #selector(closePin)
        closeButton.toolTip = "Close"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: hoverBar.leadingAnchor), stack.trailingAnchor.constraint(equalTo: hoverBar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: hoverBar.topAnchor), stack.bottomAnchor.constraint(equalTo: hoverBar.bottomAnchor),
            hoverBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            hoverBar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])
    }

    private func setHover(_ on: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            hoverBar.animator().alphaValue = on ? 1 : 0
            closeButton.animator().alphaValue = on ? 1 : 0
        }
    }

    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var pin: PinWindow? { window as? PinWindow }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.close(); return }
        window?.makeKey()
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let w = window else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.08
        if event.modifierFlags.contains(.option) {
            w.alphaValue = max(0.15, min(1, w.alphaValue + delta))
            return
        }
        let f = w.frame
        let factor = max(0.5, min(1.5, 1 + delta))
        let size = CGSize(width: f.width * factor, height: f.height * factor)
        if size.width < 60 || size.height < 40 { return }
        resizeWindow(to: size)
    }

    private func resizeWindow(to size: CGSize) {
        guard let w = window else { return }
        let f = w.frame
        let s = CGSize(width: size.width.rounded(), height: size.height.rounded())
        w.setFrame(CGRect(x: f.midX - s.width / 2, y: f.midY - s.height / 2, width: s.width, height: s.height), display: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.close() } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, event.modifierFlags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers {
        case "c": copyPin(); return true
        case "w": window?.close(); return true
        case "s": savePin(); return true
        default: return false
        }
    }

    /// Shottr's pin menu: Edit, Copy, 50%, 100%, 200%, Semi-transparent, Close.
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Edit", action: #selector(editPin), keyEquivalent: "").target = self
        m.addItem(withTitle: "Copy", action: #selector(copyPin), keyEquivalent: "c").target = self
        m.addItem(withTitle: "Save", action: #selector(savePin), keyEquivalent: "s").target = self
        m.addItem(.separator())
        for (title, f) in [("50%", 0.5), ("100%", 1.0), ("200%", 2.0)] {
            let item = NSMenuItem(title: title, action: #selector(zoomPin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = f
            m.addItem(item)
        }
        let semi = NSMenuItem(title: "Semi-transparent", action: #selector(toggleSemi), keyEquivalent: "")
        semi.target = self
        semi.state = semiTransparent ? .on : .off
        m.addItem(semi)
        m.addItem(.separator())
        m.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "w").target = self
        return m
    }

    @objc private func zoomPin(_ sender: NSMenuItem) {
        guard let f = sender.representedObject as? Double else { return }
        let scale = pin?.scale ?? 2
        resizeWindow(to: CGSize(width: CGFloat(image.width) / scale * f, height: CGFloat(image.height) / scale * f))
    }

    @objc private func toggleSemi() {
        semiTransparent.toggle()
        window?.alphaValue = semiTransparent ? 0.5 : 1
    }

    @objc private func copyPin() {
        Exporter.copy(image, scale: pin?.scale ?? 2)
        Toast.show("Copied to the clipboard")
    }

    @objc private func savePin() { Exporter.save(image, scale: pin?.scale ?? 2) }

    @objc private func editPin() {
        AppLogic.shared.openEditor(image, scale: pin?.scale ?? 2)
        window?.close()
    }

    @objc private func closePin() { window?.close() }
}

/// Drag handle in the pin's hover bar: drags the image out as a PNG file.
final class PinDragHandle: NSView, NSDraggingSource {
    private let image: CGImage

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        toolTip = "Drag'n'Drop Image"
        let icon = NSImageView(image: NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Drag image")!)
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 28), heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let scale = (window as? PinWindow)?.scale ?? 2
        guard let data = Exporter.encode(image, scale: scale, type: .png) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Exporter.fileName(ext: "png"))
        guard (try? data.write(to: url)) != nil else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(cgImage: image, size: NSSize(width: 100, height: 100 * CGFloat(image.height) / CGFloat(max(1, image.width))))
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(origin: p, size: preview.size), contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
