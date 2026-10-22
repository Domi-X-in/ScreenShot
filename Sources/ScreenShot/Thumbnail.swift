import AppKit

/// Shottr's preview thumbnail (Preview.storyboard, 267×270): shown after an area capture when
/// "After Area Crop, show: Thumbnail" is chosen. Hides when clicking outside it.
@MainActor final class Thumbnail {
    private static var current: Thumbnail?

    private let image: CGImage
    private let scale: CGFloat
    private let panel: NSPanel
    private var monitors: [Any] = []

    static func show(_ image: CGImage, scale: CGFloat) {
        current?.dismiss()
        let t = Thumbnail(image: image, scale: scale)
        current = t
        t.panel.orderFrontRegardless()
        t.panel.makeKey()
    }

    private init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        let size = CGSize(width: 267, height: 270)
        let vf = NSScreen.containingMouse().visibleFrame
        panel = KeyPanel(contentRect: CGRect(x: vf.maxX - size.width - 20, y: vf.minY + 20, width: size.width, height: size.height),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = buildContent(size: size)

        let outside: (NSEvent) -> Void = { [weak self] _ in self?.dismiss() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: outside) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown], handler: { [weak self] e in
            guard let self else { return e }
            if e.type == .keyDown {
                return self.handleKey(e) ? nil : e
            }
            if e.window !== self.panel { self.dismiss() }
            return e
        }) { monitors.append(m) }
    }

    private func buildContent(size: CGSize) -> NSView {
        let fx = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        fx.material = .popover
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 12
        fx.layer?.masksToBounds = true

        let close = button("xmark", "Close (Esc)", #selector(closeClicked))
        let grip = GripView()
        let preview = ThumbnailImageView(image: image, scale: scale)
        preview.onDoubleClick = { [weak self] in self?.edit() }

        // Shottr's row: Edit (Enter) · Copy (⌘C) · Save (⌘S) · Upload (⌘E) · OCR or QR (⌘O) · Pin (⌘P); upload is not reproduced.
        let bar = IconPalette(items: [
            .init(symbol: "pencil", tooltip: "Edit (Enter)"), .init(symbol: "doc.on.doc", tooltip: "Copy (⌘C)"),
            .init(symbol: "square.and.arrow.down", tooltip: "Save (⌘S)"), .init(symbol: "text.viewfinder", tooltip: "OCR or QR (⌘O)"),
            .init(symbol: "pin", tooltip: "Pin (⌘P)"),
        ], mode: .momentary, itemWidth: 34)
        bar.onSelect = { [weak self] i in
            switch i {
            case 0: self?.editClicked()
            case 1: self?.copyClicked()
            case 2: self?.saveClicked()
            case 3: self?.ocrClicked()
            default: self?.pinClicked()
            }
        }

        for v in [close, grip, preview, bar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            fx.addSubview(v)
        }
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 6),
            close.topAnchor.constraint(equalTo: fx.topAnchor, constant: 6),
            grip.centerXAnchor.constraint(equalTo: fx.centerXAnchor),
            grip.topAnchor.constraint(equalTo: fx.topAnchor, constant: 6),
            grip.widthAnchor.constraint(equalToConstant: 60), grip.heightAnchor.constraint(equalToConstant: 14),
            preview.topAnchor.constraint(equalTo: fx.topAnchor, constant: 28),
            preview.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 12),
            preview.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -12),
            preview.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),
            bar.centerXAnchor.constraint(equalTo: fx.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: fx.bottomAnchor, constant: -10),
            bar.heightAnchor.constraint(equalToConstant: 32),
        ])
        return fx
    }

    private func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))!, target: self, action: action)
        b.isBordered = false
        b.toolTip = tip
        b.contentTintColor = .secondaryLabelColor
        return b
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch (cmd, e.charactersIgnoringModifiers?.lowercased() ?? "", e.keyCode) {
        case (_, _, 53): dismiss()
        case (false, _, 36), (false, _, 76): edit()
        case (true, "c", _): copyClicked()
        case (true, "s", _): saveClicked()
        case (true, "o", _): ocrClicked()
        case (true, "p", _): pinClicked()
        default: return false
        }
        return true
    }

    private func dismiss() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        panel.orderOut(nil)
        if Thumbnail.current === self { Thumbnail.current = nil }
    }

    private func edit() {
        dismiss()
        AppLogic.shared.openEditor(image, scale: scale)
    }

    @objc private func closeClicked() { dismiss() }
    @objc private func editClicked() { edit() }

    @objc private func copyClicked() {
        Exporter.copy(image, scale: scale)
        Toast.show("Copied to the clipboard")
        dismiss()
    }

    @objc private func saveClicked() {
        Exporter.save(image, scale: scale)
        dismiss()
    }

    @objc private func ocrClicked() {
        OCR.run(image)
        dismiss()
    }

    @objc private func pinClicked() {
        Pins.pin(image, scale: scale, near: nil)
        dismiss()
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shottr's preview-grip: a drag handle that moves the thumbnail.
private final class GripView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        let bar = CGRect(x: bounds.midX - 16, y: bounds.midY - 2, width: 32, height: 4)
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
    }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// Shottr's CtrlDragOutView: the preview image, draggable into other apps as a PNG.
private final class ThumbnailImageView: NSView, NSDraggingSource {
    var onDoubleClick: (() -> Void)?
    private let image: CGImage
    private let scale: CGFloat

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        toolTip = "Drag'n'Drop Image · double-click to edit"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let data = Exporter.encode(image, scale: scale, type: .png) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Exporter.fileName(ext: "png"))
        guard (try? data.write(to: url)) != nil else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(cgImage: image, size: bounds.size)
        item.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
