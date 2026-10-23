import AppKit
import UniformTypeIdentifiers

/// Screenshot editor window, laid out after Shottr's Main.storyboard window (MainWindowController + ViewController):
/// a unified toolbar with actions, drag-out, tool strip, Crop, adjust buttons and info cells, plus a per-tool options bar.
@MainActor final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    /// Tool palette, in groups: select · draw · text · shapes · effects · counting/measuring.
    static let tools: [Tool] = [.select, .arrow, .line, .freehand, .text, .callout, .rect, .oval, .highlighter,
                                .blur, .spotlight, .magnifier, .counter, .ruler]
    static let toolGroups = [1, 3, 2, 3, 3, 2]

    /// The document on screen; thumbnails swap it in place.
    var doc: EditorDocument { shotView.doc }
    let shotView: ShotView
    /// Documents visited in this window, so returning to one keeps its undo history.
    private var visited: [URL: EditorDocument] = [:]
    private var autosaveTimer: Timer?
    private let saveQueue = DispatchQueue(label: "screenshot.autosave")
    private lazy var toolPalette = IconPalette(
        items: Self.tools.map { .init(symbol: $0.symbol, tooltip: "\($0.title)  \($0.key == "1" ? "1 or 2" : $0.key)") },
        groups: Self.toolGroups, mode: .select, itemWidth: 29)
    // Shottr: Copy (Esc or ⌘C) · Save (⌘S) · Pin to Screen (⌘P)
    private let actionsPalette = IconPalette(items: [
        .init(symbol: "doc.on.doc", tooltip: "Copy (Esc or ⌘C)"), .init(symbol: "square.and.arrow.down", tooltip: "Save (⌘S)"),
        .init(symbol: "pin", tooltip: "Pin to Screen (⌘P)"),
    ], mode: .momentary)
    // Shottr's adjust group, limited to what this app implements: Resize, Recognize Text or QR, Reset Selection.
    private let adjustPalette = IconPalette(items: [
        .init(symbol: "arrow.up.left.and.down.right.magnifyingglass", tooltip: "Resize ( ⇧+] )"),
        .init(symbol: "text.viewfinder", tooltip: "Recognize Text or QR (⌘O) · only the selected area when using Crop"), .init(symbol: "arrow.uturn.backward", tooltip: "Reset Selection (Esc)"),
    ], mode: .momentary)
    private lazy var cropButton = PillButton(title: "Crop", symbol: "crop", tooltip: "Crop (X) — Enter applies it") { [weak self] in self?.cropClicked() }
    private let info = InfoCellsView()
    private lazy var options = OptionsBar(info: info)
    private let recent = RecentStrip()

    private enum Item {
        static let actions = NSToolbarItem.Identifier("actions")
        static let dragOut = NSToolbarItem.Identifier("dragOut")
        static let tools = NSToolbarItem.Identifier("tools")
        static let crop = NSToolbarItem.Identifier("crop")
        static let adjust = NSToolbarItem.Identifier("adjust")
        static let info = NSToolbarItem.Identifier("info")
    }

    init(image: CGImage, scale: CGFloat, state: EditState? = nil, url: URL? = nil) {
        shotView = ShotView(doc: Self.makeDocument(image: image, scale: scale, state: state, url: url))
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 640),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.title = url?.lastPathComponent ?? "ScreenShot"
        win.titleVisibility = .hidden
        win.toolbarStyle = .unified
        super.init(window: win)
        win.delegate = self
        shotView.controller = self
        buildControls()
        buildLayout()
        let toolbar = NSToolbar(identifier: "editor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        win.toolbar = toolbar
        syncToolbar()
        updateInfo()
        sizeWindow()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Controls

    private func buildControls() {
        toolPalette.onSelect = { [weak self] i in self?.toolChanged(i) }
        actionsPalette.onSelect = { [weak self] i in self?.actionClicked(i) }
        adjustPalette.onSelect = { [weak self] i in self?.adjustClicked(i) }

        info.onColorBox = { [weak self] in self?.showColorPanel(from: $0) }
        info.onSizeBox = { [weak self] in self?.showResizePanel(from: $0) }
        info.onZoomBox = { [weak self] in self?.showZoomPanel(from: $0) }

        options.onChange = { [weak self] style in self?.shotView.setStyle(style) }
        recent.onSelect = { [weak self] url in self?.switchTo(url) }
        recent.onBrowse = { LibraryWindowController.show() }
        options.onBackdropPanel = { [weak self] anchor in self?.showBackdropPanel(from: anchor) }
        options.onAutoadjust = { [weak self] in self?.shotView.autoadjustSelection() }
        options.onImprint = { [weak self] in self?.shotView.imprintSelectionSize() }
        options.onCutOutMode = { [weak self] on in
            self?.shotView.cutOutMode = on
            self?.window?.makeFirstResponder(self?.shotView)
        }
    }

    private func buildLayout() {
        guard let win = window else { return }
        let content = NSView()
        win.contentView = content
        for v in [shotView, options, recent] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            shotView.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
            shotView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            shotView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            shotView.bottomAnchor.constraint(equalTo: recent.topAnchor),
            // The options card floats over the bottom of the canvas.
            options.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            options.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            options.bottomAnchor.constraint(equalTo: recent.topAnchor, constant: -10),
            options.heightAnchor.constraint(equalToConstant: 48),
            recent.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            recent.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            recent.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            recent.heightAnchor.constraint(equalToConstant: 84),
        ])
        win.initialFirstResponder = shotView
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.actions, Item.dragOut, .flexibleSpace, Item.tools, Item.crop, Item.adjust, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Item.actions: item.view = actionsPalette; item.label = "Actions"
        case Item.dragOut:
            let drag = DragOutView { [weak self] in self?.rendered().map { ($0, self?.doc.scale ?? 2) } }
            item.view = drag
            item.label = "Drag"
        case Item.tools: item.view = toolPalette; item.label = "Tools"
        case Item.crop: item.view = cropButton; item.label = "Crop"
        case Item.adjust: item.view = adjustPalette; item.label = "Adjust"
        case Item.info: item.view = info; item.label = "Info"
        default: return nil
        }
        // When the window is narrow, the adjust buttons overflow first and the info cells stay.
        switch id {
        // The tool strip never overflows; on narrow windows the info cells go before Crop and the actions.
        case Item.tools: item.visibilityPriority = .user
        case Item.actions, Item.crop: item.visibilityPriority = .high
        case Item.adjust, Item.dragOut: item.visibilityPriority = .low
        default: break
        }
        return item
    }

    private func sizeWindow() {
        guard let win = window else { return }
        let screen = NSScreen.containingMouse().visibleFrame
        let c = Renderer.canvasSize(doc)
        let chrome: CGFloat = 52 + 68 + 84
        var w = max(1180, c.width / doc.scale + 32)
        var h = max(480, c.height / doc.scale + 32 + chrome)
        w = min(w, screen.width * 0.94)
        h = min(h, screen.height * 0.92)
        win.minSize = NSSize(width: 760, height: 430)
        win.setContentSize(NSSize(width: w, height: h))
        win.setFrameOrigin(NSPoint(x: screen.midX - win.frame.width / 2, y: screen.midY - win.frame.height / 2))
    }

    // MARK: State sync

    func syncToolbar() {
        toolPalette.selectedIndex = Self.tools.firstIndex(of: shotView.tool)
        cropButton.isOn = shotView.tool == .crop
        options.update(tool: shotView.selectedKind ?? shotView.tool, style: shotView.style, backdrop: doc.backdrop, cutOut: shotView.cutOutMode)
        updateInfo()
    }

    func documentChanged(resized: Bool) {
        syncToolbar()
        backdropPanel?.show(doc.backdrop)
        shotView.needsDisplay = true
    }

    /// The screenshot was dragged inside its backdrop: redraw without the full toolbar sync.
    func backdropChanged() {
        backdropPanel?.show(doc.backdrop)
        shotView.needsDisplay = true
    }

    func updateInfo() {
        let s = shotView.selectionSize
        let k = Settings.showPoints ? doc.scale : 1, unit = Settings.showPoints ? "pt" : "px"
        info.setSize("\(Int((s.width / k).rounded()))×\(Int((s.height / k).rounded()))\(unit)", label: shotView.tool == .crop ? "Selection Size" : "Image Size")
        info.setZoom("\(shotView.zoomPercent)%")
        zoomPanel?.setPercent("\(shotView.zoomPercent)%")
    }

    // MARK: Info panels (Shottr's color, size and zoom boxes)

    private var panelPopover: NSPopover?
    private weak var zoomPanel: ZoomPanelView?

    private func present(_ view: NSView, from anchor: NSView) {
        panelPopover?.close()
        let vc = NSViewController()
        vc.view = view
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = vc
        p.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        panelPopover = p
    }

    private weak var backdropPanel: BackdropPanelView?

    func showBackdropPanel(from anchor: NSView) {
        let panel = BackdropPanelView(backdrop: doc.backdrop) { [weak self] b in self?.shotView.setBackdrop(b) }
        backdropPanel = panel
        present(panel, from: anchor)
    }

    func showColorPanel(from anchor: NSView) {
        present(ColorHelperView { [weak self] in self?.updateInfo() }, from: anchor)
    }

    func showResizePanel(from anchor: NSView? = nil) {
        guard let anchor = anchor ?? info.sizeAnchor else { return }
        let panel = ResizePanelView(imageSize: doc.image.size, scale: doc.scale, onResize: { [weak self] factor in
            self?.panelPopover?.close()
            self?.shotView.resizeImage(by: factor)
            self?.updateInfo()
        }, onUnitsChanged: { [weak self] in self?.updateInfo() })
        present(panel, from: anchor)
    }

    func showZoomPanel(from anchor: NSView) {
        let v = shotView
        let panel = ZoomPanelView(percentText: "\(v.zoomPercent)%", zoomIn: { v.zoomIn(nil) }, zoomOut: { v.zoomOut(nil) },
                                  actual: { v.zoomToActualSize() }, fit: { v.zoomToFit(nil) })
        zoomPanel = panel
        present(panel, from: anchor)
    }

    func toggleSizeUnits() {
        Settings.showPoints.toggle()
        Toast.show(Settings.showPoints ? "Sizes in logical points (pt)" : "Sizes in pixels (px)")
        updateInfo()
    }

    func updateHoverColor(_ c: NSColor?) {
        info.setColor(c)
    }

    /// Copies a color in the format chosen in the color panel (Shottr's Color Format).
    func copyColor(_ c: NSColor?, what: String = "Color") {
        guard let c else { NSSound.beep(); return }
        let text = ColorFormat.current.string(c)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.show("\(what) copied: \(text)")
    }

    // MARK: Toolbar actions

    private func toolChanged(_ i: Int) {
        guard i >= 0, i < Self.tools.count else { return }
        shotView.tool = Self.tools[i]
        window?.makeFirstResponder(shotView)
    }

    private func actionClicked(_ i: Int) {
        switch i {
        case 0: copyImage()
        case 1: saveImage()
        default: pinImage()
        }
    }

    private func cropClicked() {
        if shotView.tool == .crop { shotView.applyCropIfAny() } else { shotView.beginCrop() }
        window?.makeFirstResponder(shotView)
    }

    private func adjustClicked(_ i: Int) {
        switch i {
        case 0: showResizePanel()
        case 1: ocrImage()
        default: shotView.resetSelection()
        }
        window?.makeFirstResponder(shotView)
    }

    // MARK: Output actions

    private func rendered() -> CGImage? {
        shotView.commitText()
        return doc.render()
    }

    @objc func copyImage() {
        guard let img = rendered() else { return }
        Exporter.copy(img, scale: doc.scale)
        Toast.show("Copied to the clipboard")
    }

    /// Saves with annotations kept editable; a document opened from a file is updated in place.
    @objc func saveImage() {
        guard let img = rendered() else { return }
        let revision = doc.revision
        if Exporter.saveEditable(doc, rendered: img) != nil {
            doc.savedRevision = revision
            window?.title = doc.fileURL?.lastPathComponent ?? "ScreenShot"
            recent.currentURL = doc.fileURL
        }
    }

    @objc func saveImageAs() {
        guard let img = rendered(), let win = window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = doc.fileURL?.lastPathComponent ?? Exporter.fileName(ext: "png")
        panel.directoryURL = doc.fileURL?.deletingLastPathComponent() ?? Settings.saveFolder
        panel.beginSheetModal(for: win) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            if Exporter.saveEditable(self.doc, rendered: img, to: url) != nil {
                win.title = url.lastPathComponent
                self.recent.currentURL = url
            }
        }
    }

    /// Saves a GIF that blinks the annotations on and off into the Screenshots folder.
    @objc func saveGIF() {
        shotView.commitText()
        guard !doc.objects.isEmpty else {
            Toast.show("Add an arrow, box or text first: the GIF blinks the annotations on and off")
            return
        }
        guard let (plain, annotated) = GIFOverlay.frames(doc), let data = GIFOverlay.encode(plain: plain, annotated: annotated) else {
            Toast.show("Couldn't make the GIF")
            return
        }
        let folder = Settings.saveFolder
        let url = folder.appendingPathComponent(Exporter.fileName(ext: "gif"))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            Toast.show("GIF saved to \(folder.lastPathComponent) and copied")
            NotificationCenter.default.post(name: .screenshotSaved, object: url)
        } catch {
            Toast.show("Failed to save the GIF: \(error.localizedDescription)")
        }
    }

    @objc func pinImage() {
        guard let img = rendered() else { return }
        Pins.pin(img, scale: doc.scale, near: window?.frame)
        close()
    }

    /// Reads the area selected with the Crop tool, or the whole screenshot when nothing is selected.
    @objc func ocrImage() {
        if let r = shotView.cropSelection, let part = doc.image.cropping(to: r) {
            OCR.run(part)
        } else {
            OCR.run(doc.image)
        }
    }

    func escape() {
        if Settings.escCopy || Settings.escSave, let img = rendered() {
            if Settings.escCopy { Exporter.copy(img, scale: doc.scale); Toast.show("Copied to the clipboard") }
            if Settings.escSave { Exporter.saveEditable(doc, rendered: img) }
        }
        close()
    }

    func windowDidResize(_ notification: Notification) { updateInfo() }

    /// Shottr's "Default zoom level: Prefer 100%"; otherwise the image fits the window.
    func applyDefaultZoom() {
        if Settings.prefer100 { shotView.zoomToActualSize() }
        updateInfo()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        recent.currentURL = doc.fileURL
        recent.reload()
    }

    // MARK: Documents and auto-save

    static func makeDocument(image: CGImage, scale: CGFloat, state: EditState?, url: URL?) -> EditorDocument {
        let d = EditorDocument(image: image, scale: scale)
        if let state {
            d.objects = state.objects
            d.backdrop = state.backdrop
        }
        d.fileURL = url
        return d
    }

    /// Thumbnail click: save what is open, then show `url` in this same window.
    func switchTo(_ url: URL) {
        guard url.standardizedFileURL != doc.fileURL?.standardizedFileURL else { return }
        // A file already open in another window is brought forward rather than shown twice.
        if let other = AppLogic.shared.editor(showing: url), other !== self {
            other.window?.makeKeyAndOrderFront(nil)
            return
        }
        let next: EditorDocument
        if let cached = visited[url.standardizedFileURL] {
            next = cached
        } else {
            guard let loaded = EditableFile.load(url) else { Toast.show("Image Reading Error"); return }
            next = Self.makeDocument(image: loaded.image, scale: loaded.scale, state: loaded.state, url: url)
        }
        // A capture that was never saved gets a file now, so it can be come back to from the strip.
        flushAutosave(force: doc.fileURL == nil)
        if let current = doc.fileURL { visited[current.standardizedFileURL] = doc }
        if visited.count > 20 { visited.removeAll() }
        shotView.switchDocument(next)
        applyDefaultZoom()
        window?.title = url.lastPathComponent
        recent.currentURL = url
        syncToolbar()
        updateInfo()
        window?.makeFirstResponder(shotView)
    }

    func scheduleAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Never end a text edit from the background: wait until the user finishes typing
                // (finishing the edit marks a change, which schedules the save).
                if self.shotView.isEditingText { self.scheduleAutosave(); return }
                self.autosave(sync: false)
            }
        }
    }

    /// Saves pending changes now (switching files, closing). `force` also writes a document with no changes yet.
    func flushAutosave(force: Bool = false) {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        // Switching files or closing ends the edit on purpose, so the typed text is part of this save.
        shotView.commitText()
        if force || doc.hasUnsavedChanges { autosave(sync: true) }
    }

    /// Writes the document with editable annotations: rendering happens here, encoding and the file write off the main thread.
    private func autosave(sync: Bool) {
        let d = doc
        guard let rendered = d.render() else { return }
        let url: URL
        if let existing = d.fileURL {
            url = existing
        } else {
            let folder = Settings.saveFolder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = folder.appendingPathComponent(Exporter.fileName(ext: "png"))
            d.fileURL = url
            window?.title = url.lastPathComponent
            recent.currentURL = url
        }
        let type: UTType = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
        let job = AutosaveJob(doc: d, rendered: rendered, base: d.image, scale: d.scale, type: type, url: url, revision: d.revision,
                              state: EditState(scale: d.scale, backdrop: d.backdrop, objects: d.objects))
        if sync {
            saveQueue.sync { job.write() }
            d.savedRevision = max(d.savedRevision, job.revision)
        } else {
            saveQueue.async { job.write() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        flushAutosave()
        AppLogic.shared.editorClosed(self)
    }
}

// MARK: - Info cells

/// Shottr's toolbar "Info" item: color swatch with "#FFFFFF / Tab to copy", "W×Hpx / Selection Size", "NN% / Zoom".
final class InfoCellsView: NSView {
    /// Shottr's colorBoxClicked: / sizeBoxClicked: / zoomBoxClicked: — each opens its panel next to the cell.
    var onColorBox: ((NSView) -> Void)?
    var onSizeBox: ((NSView) -> Void)?
    var onZoomBox: ((NSView) -> Void)?
    private(set) var color: NSColor?

    private let swatch = NSView()
    private let colorValue = InfoCellsView.valueLabel("—")
    private let colorCaption = InfoCellsView.captionLabel("Tab to copy")
    private let sizeValue = InfoCellsView.valueLabel("")
    private let sizeCaption = InfoCellsView.captionLabel("Selection Size")
    private let zoomValue = InfoCellsView.valueLabel("100%")
    private let zoomCaption = InfoCellsView.captionLabel("Zoom")

    /// Shottr's clrToolbarLabel / clrToolbarInfo asset colors (light and dark variants).
    static let labelColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0xD0D0D0) : NSColor(hex: 0x282828) }
    static let infoColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0xA2A2A2) : NSColor(hex: 0x747474) }

    private static func valueLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        l.textColor = labelColor
        return l
    }

    private static func captionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.textColor = infoColor
        return l
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 300, height: 34))
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 3
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.separatorColor.cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([swatch.widthAnchor.constraint(equalToConstant: 16), swatch.heightAnchor.constraint(equalToConstant: 16)])

        let colorText = Self.stack([colorValue, colorCaption])
        var colorCell: ClickableStack!
        colorCell = ClickableStack(views: [swatch, colorText]) { [weak self] in self?.onColorBox?(colorCell) }
        colorCell.spacing = 6
        colorCell.toolTip = "Color under the cursor · Tab copies it · click for color options"
        colorCell.setAccessibilityElement(true)
        colorCell.setAccessibilityRole(.button)
        colorCell.setAccessibilityLabel("Color under the cursor, color options")
        var sizeCell: ClickableStack!
        sizeCell = ClickableStack(views: [Self.stack([sizeValue, sizeCaption])]) { [weak self] in self?.onSizeBox?(sizeCell) }
        sizeCell.toolTip = "Click to resize the image ( ⇧+] )"
        sizeCell.setAccessibilityElement(true)
        sizeCell.setAccessibilityRole(.button)
        sizeCell.setAccessibilityLabel("Image size, resize")
        var zoomCell: ClickableStack!
        zoomCell = ClickableStack(views: [Self.stack([zoomValue, zoomCaption])]) { [weak self] in self?.onZoomBox?(zoomCell) }
        zoomCell.toolTip = "Click for zoom controls"
        zoomCell.setAccessibilityElement(true)
        zoomCell.setAccessibilityRole(.button)
        zoomCell.setAccessibilityLabel("Zoom controls")

        let row = NSStackView(views: [colorCell, Self.separator(), sizeCell, Self.separator(), zoomCell])
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 34),
            colorValue.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            sizeValue.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            zoomValue.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])
        setColor(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func stack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 0
        return s
    }

    private static func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return v
    }

    func setColor(_ c: NSColor?) {
        color = c
        colorValue.stringValue = c?.hexString ?? "—"
        swatch.layer?.backgroundColor = (c ?? .clear).cgColor
    }

    var sizeAnchor: NSView? { sizeValue.superview?.superview }
    var sizeText: String { sizeValue.stringValue }

    func setSize(_ value: String, label: String) {
        sizeValue.stringValue = value
        sizeCaption.stringValue = label
    }

    func setZoom(_ value: String) { zoomValue.stringValue = value }
}

/// Horizontal stack that runs a closure on click (Shottr's NSViewClickable).
final class ClickableStack: NSStackView {
    private let onClick: () -> Void

    init(views: [NSView], onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        setViews(views, in: .leading)
        orientation = .horizontal
        alignment = .centerY
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick() }

    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }
}

// MARK: - Drag out

/// Shottr's CtrlDragOut: drag the rendered screenshot into another app as a PNG file.
final class DragOutView: NSView, NSDraggingSource {
    private let provider: () -> (CGImage, CGFloat)?

    init(provider: @escaping () -> (CGImage, CGFloat)?) {
        self.provider = provider
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 28))
        toolTip = "Drag'n'Drop Image"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drag the image into another app")
        let icon = NSImageView(image: NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Drag image")!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))!)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 40), heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDragged(with event: NSEvent) {
        guard let (img, scale) = provider(), let data = Exporter.encode(img, scale: scale, type: .png) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Exporter.fileName(ext: "png"))
        guard (try? data.write(to: url)) != nil else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(cgImage: img, size: NSSize(width: 120, height: 120 * CGFloat(img.height) / CGFloat(max(1, img.width))))
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: p.x - 60, y: p.y - 30, width: preview.size.width, height: preview.size.height), contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

// MARK: - Options bar

/// Shottr's contextual options row: color, size, then controls for the current tool.
final class OptionsBar: NSView, NSMenuDelegate {
    var onChange: ((ToolStyle) -> Void)?
    var onBackdropPanel: ((NSView) -> Void)?
    var onCutOutMode: ((Bool) -> Void)?
    var onAutoadjust: (() -> Void)?
    var onImprint: (() -> Void)?
    private lazy var autoadjustButton = Self.smallButton("Autoadjust", symbol: "viewfinder", tooltip: "Shrink the selection to the content (F)",
                                                         target: self, action: #selector(autoadjustClicked))
    private lazy var imprintButton = Self.smallButton("Imprint Size", symbol: "ruler", tooltip: "Stamp the selection's size on the image (I)",
                                                      target: self, action: #selector(imprintClicked))
    private let cropModeControl = NSSegmentedControl(labels: ["Crop", "Cut Out"], trackingMode: .selectOne, target: nil, action: nil)
    private var style = ToolStyle()

    private let colorButton = NSButton()
    private let widthSlider = NSSlider(value: 4, minValue: 1, maxValue: 20, target: nil, action: nil)
    private let arrowControl = DefaultableSegmentedControl()
    private let dashControl = DefaultableSegmentedControl()
    private let sketchControl = DefaultableSegmentedControl()
    private let fillControl = DefaultableSegmentedControl()
    private let blurControl = DefaultableSegmentedControl(labels: BlurMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let fontControl = DefaultableSegmentedControl(labels: TextFont.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let shapeControl = DefaultableSegmentedControl()
    private let unitControl = DefaultableSegmentedControl(labels: ["PX", "PT"], trackingMode: .selectOne, target: nil, action: nil)
    private let lensShapeControl = DefaultableSegmentedControl()
    private let calloutControl = DefaultableSegmentedControl()
    private static let zoomSteps: [CGFloat] = [1.5, 2, 3, 4]
    private let lensZoomControl = DefaultableSegmentedControl(labels: OptionsBar.zoomSteps.map { "\($0.formatted())×" }, trackingMode: .selectOne,
                                                              target: nil, action: nil)

    /// Each option control with how it reads and writes a ToolStyle, for right-click → Set as Default.
    private lazy var defaultables: [(control: DefaultableSegmentedControl, set: (inout ToolStyle, Int) -> Void, get: (ToolStyle) -> Int)] = [
        (calloutControl, { $0.callout = CalloutStyle(rawValue: $1) ?? .box }, { $0.callout.rawValue }),
        (arrowControl, { $0.arrow = ArrowStyle(rawValue: $1) ?? .tapered }, { $0.arrow.rawValue }),
        (dashControl, { $0.dashed = $1 == 1 }, { $0.dashed ? 1 : 0 }),
        (sketchControl, { $0.sketch = $1 == 1 }, { $0.sketch ? 1 : 0 }),
        (fillControl, { $0.fill = FillStyle(rawValue: $1) ?? .none }, { $0.fill.rawValue }),
        (blurControl, { $0.blur = BlurMode(rawValue: $1) ?? .blur }, { $0.blur.rawValue }),
        (fontControl, { $0.font = TextFont(rawValue: $1) ?? .sans }, { $0.font.rawValue }),
        (shapeControl, { $0.counterShape = CounterShape(rawValue: $1) ?? .circle }, { $0.counterShape.rawValue }),
        (unitControl, { $0.rulerInPoints = $1 == 1 }, { $0.rulerInPoints ? 1 : 0 }),
        (lensShapeControl, { $0.lensShape = LensShape(rawValue: $1) ?? .oval }, { $0.lensShape.rawValue }),
        (lensZoomControl, { $0.magnification = Self.zoomSteps[$1] }, { s in Self.zoomSteps.firstIndex { abs($0 - s.magnification) < 0.01 } ?? -1 }),
    ]
    private var backdropButton: PillButton!
    private let hint = NSTextField(labelWithString: "")
    private let sizeReadout = NSTextField(labelWithString: "4")
    private var popover: NSPopover?

    init(info: NSView) {
        super.init(frame: .zero)
        // Floating card: rounded, bordered, softly shadowed.
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        Theme.cardShadow(self, radius: 16, opacity: 0.22)
        sizeReadout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        sizeReadout.textColor = .secondaryLabelColor
        sizeReadout.alignment = .center
        sizeReadout.widthAnchor.constraint(equalToConstant: 20).isActive = true
        sizeReadout.toolTip = "Size"

        colorButton.isBordered = false
        colorButton.imageScaling = .scaleNone
        colorButton.target = self
        colorButton.action = #selector(showColors)
        colorButton.toolTip = "Color"
        colorButton.setAccessibilityLabel("Color")
        colorButton.widthAnchor.constraint(equalToConstant: 28).isActive = true

        widthSlider.controlSize = .small
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthSlider.toolTip = "Size"
        widthSlider.setAccessibilityLabel("Size")
        widthSlider.widthAnchor.constraint(equalToConstant: 84).isActive = true

        Self.images(arrowControl, ArrowStyle.allCases.map { ($0.symbol, $0.title) })
        Self.images(dashControl, [("line.diagonal", "Solid Line"), ("line.horizontal.3.decrease", "Dashed Line")])
        Self.images(sketchControl, [("pencil.line", "Clean Strokes"), ("scribble", "Hand-Drawn Strokes")])
        Self.images(fillControl, FillStyle.allCases.map { ($0.symbol, $0.title) })
        Self.images(shapeControl, CounterShape.allCases.map { ($0.symbol, $0.title) })
        Self.images(lensShapeControl, LensShape.allCases.map { ($0.symbol, $0.title) })
        Self.images(calloutControl, CalloutStyle.allCases.map { ($0.symbol, $0.title) })
        lensZoomControl.toolTip = "Magnification · pinch, scroll or +/− over a selected magnifier for finer steps"
        blurControl.toolTip = "Blur or Erase (fills with the surrounding color)"
        unitControl.toolTip = "One logical point is equal two physical pixels on Retina displays."
        fontControl.toolTip = "Font"
        for c in [arrowControl, dashControl, sketchControl, fillControl, blurControl, fontControl, shapeControl, unitControl, lensShapeControl, lensZoomControl,
                  calloutControl] {
            c.controlSize = .small
            c.target = self
            c.action = #selector(optionChanged(_:))
        }


        backdropButton = PillButton(title: "Backdrop", symbol: "rectangle.inset.filled",
                                    tooltip: "Backdrop: background, aspect ratio, padding, shadow (K toggles)") { [weak self] in
            guard let self else { return }
            self.onBackdropPanel?(self.backdropButton)
        }

        cropModeControl.controlSize = .small
        cropModeControl.target = self
        cropModeControl.action = #selector(cropModeChanged)
        cropModeControl.setImage(NSImage(systemSymbolName: "crop", accessibilityDescription: "Crop"), forSegment: 0)
        cropModeControl.setImage(NSImage(systemSymbolName: "scissors", accessibilityDescription: "Cut Out"), forSegment: 1)
        cropModeControl.setToolTip("Keep the selected area (X)", forSegment: 0)
        cropModeControl.setToolTip("Remove a horizontal or vertical strip and join the rest (⇧X)", forSegment: 1)

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = InfoCellsView.infoColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Clicking these must never take keyboard focus away from a text box being typed in.
        for c in [colorButton, widthSlider, arrowControl, dashControl, sketchControl, fillControl, blurControl, fontControl, shapeControl, unitControl,
                  lensShapeControl, lensZoomControl, calloutControl, cropModeControl] as [NSControl] {
            c.refusesFirstResponder = true
        }
        wireDefaults()
        let left = NSStackView(views: [colorButton, widthSlider, sizeReadout, cropModeControl, autoadjustButton, imprintButton, calloutControl, arrowControl, dashControl, sketchControl, fillControl, blurControl, fontControl, shapeControl,
                                       unitControl, lensShapeControl, lensZoomControl, hint])
        left.spacing = 12
        left.alignment = .centerY
        // Shottr's info cells (color · size · zoom) sit here, always visible even on narrow screens.
        info.setContentCompressionResistancePriority(.required, for: .horizontal)
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([divider.widthAnchor.constraint(equalToConstant: 1), divider.heightAnchor.constraint(equalToConstant: 26)])
        let row = NSStackView(views: [left, divider, info, backdropButton])
        row.spacing = 14
        row.distribution = .fill
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: Defaults (right-click)

    private func wireDefaults() {
        for entry in defaultables {
            let c = entry.control
            c.onSetDefault = { [weak self] i in
                guard let self else { return }
                ToolStyle.updateDefaults { entry.set(&$0, i) }
                // Use it right away too, so the choice and the default agree.
                entry.set(&self.style, i)
                self.onChange?(self.style)
                self.refreshDefaultMarks()
                Toast.show("“\(c.name(of: i))” is now the default")
            }
            c.onResetDefault = { [weak self] in
                let builtIn = entry.get(ToolStyle())
                ToolStyle.updateDefaults { entry.set(&$0, builtIn) }
                self?.refreshDefaultMarks()
                if builtIn >= 0 { Toast.show("Default reset to “\(c.name(of: builtIn))”") }
            }
        }
        colorButton.menu = defaultMenu(for: "color")
        widthSlider.menu = defaultMenu(for: "size")
        sizeReadout.menu = defaultMenu(for: "size")
        refreshDefaultMarks()
    }

    private func refreshDefaultMarks() {
        let d = ToolStyle.loadDefaults()
        for entry in defaultables { entry.control.defaultIndex = entry.get(d) }
        colorButton.toolTip = "Color · default \(d.color.hexString) (right-click to change)"
        widthSlider.toolTip = "Size · default \(Int(d.width)) (right-click to change)"
    }

    /// Right-click menu for the color swatch and the size slider.
    private func defaultMenu(for what: String) -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        m.identifier = NSUserInterfaceItemIdentifier(what)
        return m
    }

    var currentStyle: ToolStyle { style }
    @objc func setColorDefaultAction() { setColorDefault() }
    @objc func resetColorDefaultAction() { resetColorDefault() }
    @objc func setSizeDefaultAction() { setSizeDefault() }
    @objc func resetSizeDefaultAction() { resetSizeDefault() }

    @objc private func setColorDefault() {
        let c = style.color
        ToolStyle.updateDefaults { $0.color = c }
        refreshDefaultMarks()
        Toast.show("\(c.hexString) is now the default color")
    }

    @objc private func setSizeDefault() {
        let w = style.width
        ToolStyle.updateDefaults { $0.width = w }
        refreshDefaultMarks()
        Toast.show("Size \(Int(w)) is now the default")
    }

    @objc private func resetColorDefault() {
        ToolStyle.updateDefaults { $0.color = ToolStyle().color }
        refreshDefaultMarks()
        Toast.show("Default color reset")
    }

    @objc private func resetSizeDefault() {
        ToolStyle.updateDefaults { $0.width = ToolStyle().width }
        refreshDefaultMarks()
        Toast.show("Default size reset")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.card.cgColor
        layer?.borderColor = Theme.cardBorder.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func images(_ c: NSSegmentedControl, _ items: [(String, String)]) {
        c.segmentCount = items.count
        c.trackingMode = .selectOne
        for (i, (sym, title)) in items.enumerated() {
            c.setImage(NSImage(systemSymbolName: sym, accessibilityDescription: title), forSegment: i)
            c.setToolTip(title, forSegment: i)
            c.setWidth(28, forSegment: i)
        }
    }

    /// Color dot with a white ring and a hairline outline (an accent ring when selected).
    static func swatch(_ c: NSColor, size: CGFloat = 18, selected: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let outer = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75))
            (selected ? Palette.accent : NSColor.black.withAlphaComponent(0.18)).setStroke()
            outer.lineWidth = selected ? 1.5 : 1
            NSColor.white.setFill()
            outer.fill()
            outer.stroke()
            let inner = NSBezierPath(ovalIn: r.insetBy(dx: size * 0.16, dy: size * 0.16))
            c.setFill()
            inner.fill()
            NSColor.black.withAlphaComponent(0.12).setStroke()
            inner.lineWidth = 0.5
            inner.stroke()
            return true
        }
    }

    func update(tool: Tool, style s: ToolStyle, backdrop: Backdrop, cutOut: Bool = false) {
        style = s
        colorButton.image = Self.swatch(s.color, size: 24)
        widthSlider.doubleValue = Double(s.width)
        sizeReadout.stringValue = "\(Int(s.width))"
        arrowControl.selectedSegment = s.arrow.rawValue
        dashControl.selectedSegment = s.dashed ? 1 : 0
        sketchControl.selectedSegment = s.sketch ? 1 : 0
        fillControl.selectedSegment = s.fill.rawValue
        blurControl.selectedSegment = s.blur.rawValue
        fontControl.selectedSegment = s.font.rawValue
        shapeControl.selectedSegment = s.counterShape.rawValue
        unitControl.selectedSegment = s.rulerInPoints ? 1 : 0
        lensShapeControl.selectedSegment = s.lensShape.rawValue
        calloutControl.selectedSegment = s.callout.rawValue
        lensZoomControl.selectedSegment = Self.zoomSteps.firstIndex { abs($0 - s.magnification) < 0.01 } ?? -1
        backdropButton.isOn = backdrop.isOn

        cropModeControl.selectedSegment = cutOut ? 1 : 0
        cropModeControl.isHidden = tool != .crop
        autoadjustButton.isHidden = tool != .crop || cutOut
        imprintButton.isHidden = tool != .crop || cutOut
        arrowControl.isHidden = tool != .arrow
        dashControl.isHidden = ![.rect, .oval, .line].contains(tool) || s.sketch
        sketchControl.isHidden = ![.arrow, .rect, .oval, .line].contains(tool)
        fillControl.isHidden = ![.rect, .oval].contains(tool)
        blurControl.isHidden = tool != .blur
        fontControl.isHidden = tool != .text && tool != .callout
        calloutControl.isHidden = tool != .callout
        shapeControl.isHidden = tool != .counter
        unitControl.isHidden = tool != .ruler
        lensShapeControl.isHidden = tool != .magnifier
        lensZoomControl.isHidden = tool != .magnifier
        let usesStroke = ![.blur, .spotlight, .crop, .select, .image].contains(tool)
        colorButton.isHidden = !usesStroke
        widthSlider.isHidden = !usesStroke
        sizeReadout.isHidden = !usesStroke

        switch tool {
        case .counter: hint.stringValue = "Type digits to renumber · drag the bubble tip to point it"
        case .crop where cutOut: hint.stringValue = "Drag up/down to cut rows, sideways to cut columns · Enter cuts · Esc resets"
        case .crop: hint.stringValue = "Select an area · Enter crops · ⌘O reads its text · C copies its average color · Esc resets"
        case .ruler: hint.stringValue = "Drag to measure · Shift snaps to 45° · hold 1 or 2 anywhere to measure what's under the pointer"
        case .select: hint.stringValue = "Click to select · Shift-click adds · drag empty space to select several · ⌥-drag duplicates · ⌘A all"
        case .text: hint.stringValue = "Click to type · double-click text to edit"
        case .spotlight: hint.stringValue = "Everything outside the spotlights gets dimmed"
        case .callout: hint.stringValue = "Press on the target, drag to place the bubble, type · drag the tip to re-aim"
        case .image: hint.stringValue = "Drag to move · pinch or scroll over it to resize"
        case .magnifier: hint.stringValue = "Drag over an area · drag the lens to move it · pinch, scroll or +/− to zoom"
        default: hint.stringValue = "Shift constrains · Tab copies the color under the cursor"
        }
    }

    static func smallButton(_ title: String, symbol: String, tooltip: String, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: target, action: action)
        b.controlSize = .small
        b.bezelStyle = .rounded
        b.imagePosition = .imageLeading
        b.toolTip = tooltip
        b.refusesFirstResponder = true
        return b
    }

    @objc private func autoadjustClicked() { onAutoadjust?() }
    @objc private func imprintClicked() { onImprint?() }

    @objc private func cropModeChanged() {
        onCutOutMode?(cropModeControl.selectedSegment == 1)
    }

    @objc private func widthChanged() {
        style.width = CGFloat(widthSlider.doubleValue.rounded())
        sizeReadout.stringValue = "\(Int(style.width))"
        onChange?(style)
    }

    @objc private func optionChanged(_ sender: NSSegmentedControl) {
        let i = sender.selectedSegment
        switch sender {
        case arrowControl: style.arrow = ArrowStyle(rawValue: i) ?? .tapered
        case dashControl: style.dashed = i == 1
        case sketchControl: style.sketch = i == 1
        case fillControl: style.fill = FillStyle(rawValue: i) ?? .none
        case blurControl: style.blur = BlurMode(rawValue: i) ?? .blur
        case fontControl: style.font = TextFont(rawValue: i) ?? .sans
        case shapeControl: style.counterShape = CounterShape(rawValue: i) ?? .circle
        case unitControl: style.rulerInPoints = i == 1
        case lensShapeControl: style.lensShape = LensShape(rawValue: i) ?? .oval
        case calloutControl: style.callout = CalloutStyle(rawValue: i) ?? .box
        case lensZoomControl: if i >= 0 { style.magnification = Self.zoomSteps[i] }
        default: break
        }
        onChange?(style)
    }

    // MARK: Color popover

    @objc private func showColors() {
        let vc = NSViewController()
        let grid = NSGridView()
        grid.rowSpacing = 6
        grid.columnSpacing = 6
        var row: [NSView] = []
        for (i, c) in Palette.colors.enumerated() {
            let b = NSButton(image: Self.swatch(c, size: 22, selected: c.hexString == style.color.hexString), target: self, action: #selector(pickColor(_:)))
            b.isBordered = false
            b.tag = i
            b.toolTip = c.hexString
            row.append(b)
            if row.count == 6 { grid.addRow(with: row); row = [] }
        }
        let custom = NSButton(image: NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Custom color")!, target: self, action: #selector(customColor))
        custom.isBordered = false
        custom.toolTip = "Custom color…"
        row.append(custom)
        grid.addRow(with: row)
        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        vc.view = container
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = vc
        p.show(relativeTo: colorButton.bounds, of: colorButton, preferredEdge: .maxY)
        popover = p
    }

    @objc private func pickColor(_ sender: NSButton) {
        style.color = Palette.colors[sender.tag]
        popover?.close()
        onChange?(style)
    }

    @objc private func customColor() {
        popover?.close()
        let panel = NSColorPanel.shared
        panel.color = style.color
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        style.color = sender.color.usingColorSpace(.sRGB) ?? sender.color
        onChange?(style)
    }
}

/// One auto-save: a snapshot taken on the main thread, encoded and written on the save queue.
/// Nothing in it is mutated after creation, and the document is only touched back on the main thread.
private final class AutosaveJob: @unchecked Sendable {
    let doc: EditorDocument
    let rendered: CGImage, base: CGImage
    let scale: CGFloat
    let type: UTType
    let url: URL
    let revision: Int
    let state: EditState

    init(doc: EditorDocument, rendered: CGImage, base: CGImage, scale: CGFloat, type: UTType, url: URL, revision: Int, state: EditState) {
        self.doc = doc; self.rendered = rendered; self.base = base; self.scale = scale
        self.type = type; self.url = url; self.revision = revision; self.state = state
    }

    func write() {
        guard let data = Exporter.encode(rendered, scale: scale, type: type) else { return }
        do {
            try EditableFile.write(rendered: data, type: type, state: state, base: base, to: url)
            DispatchQueue.main.async {
                self.doc.savedRevision = max(self.doc.savedRevision, self.revision)
                NotificationCenter.default.post(name: .screenshotSaved, object: self.url)
            }
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { MainActor.assumeIsolated { Toast.show("Auto-save failed: \(message)") } }
        }
    }
}

extension OptionsBar {
    /// Fills the color/size right-click menus with the current value when they open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let d = ToolStyle.loadDefaults()
        if menu.identifier?.rawValue == "color" {
            let set = NSMenuItem(title: "Set \(currentStyle.color.hexString) as Default Color", action: #selector(setColorDefaultAction), keyEquivalent: "")
            set.target = self
            set.image = OptionsBar.swatch(currentStyle.color, size: 14)
            menu.addItem(set)
            let info = NSMenuItem(title: "Current default: \(d.color.hexString)", action: nil, keyEquivalent: "")
            info.image = OptionsBar.swatch(d.color, size: 14)
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
            let reset = NSMenuItem(title: "Reset to Original Default", action: #selector(resetColorDefaultAction), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        } else {
            let set = NSMenuItem(title: "Set Size \(Int(currentStyle.width)) as Default", action: #selector(setSizeDefaultAction), keyEquivalent: "")
            set.target = self
            menu.addItem(set)
            let info = NSMenuItem(title: "Current default: \(Int(d.width))", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
            let reset = NSMenuItem(title: "Reset to Original Default", action: #selector(resetSizeDefaultAction), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }
    }
}
