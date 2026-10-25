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
    private lazy var statusBar = StatusBar(info: info)
    private let options = ToolOptions()
    private lazy var recent = RecentStrip(modern: editorRibbon != nil)
    /// The new editor's bottom bar: messages, readouts and Backdrop.
    private lazy var editorStatus = EditorStatusBar(info: info)
    /// The new editor's floating cards (R5b) and the callout style bar beside the canvas.
    private var cards: (title: TitleCard, ribbon: CardView, canvas: CardView, status: CardView, recent: CardView)?
    private lazy var calloutBar = CalloutStyleBar()
    private var canvasNextToBar: NSLayoutConstraint?
    private var canvasAtEdge: NSLayoutConstraint?
    /// The zoom the picture had when the callout bar came in fitted, so it can fit again when the bar leaves.
    private var calloutBarHeldZoom: CGFloat?
    /// The formatting store and the top toolbar (Word's Font and Paragraph, PowerPoint's Shape Styles, Arrange, Align).
    let formatting = FormattingController()
    private lazy var ribbon = FormattingRibbon(controller: formatting)
    private lazy var topBar = EditorToolbar(ribbon: ribbon, options: options)
    /// The Office-style ribbon and trimmed title bar (ROADMAP, Fase 6), only with `Settings.newEditorUI` for now.
    private(set) var editorRibbon: EditorRibbon?

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
        if Settings.newEditorUI {
            editorRibbon = EditorRibbon(editor: self)
            // The cards draw the title bar: the system's is see-through, and its empty toolbar only sets its height so
            // the window's buttons center on the title card.
            win.titlebarAppearsTransparent = true
            win.titlebarSeparatorStyle = .none
        }
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
        statusBar.onBackdropPanel = { [weak self] anchor in self?.showBackdropPanel(from: anchor) }
        if editorRibbon != nil { editorStatus.onBackdropPanel = { [weak self] anchor in self?.showBackdropPanel(from: anchor) } }
        options.onAutoadjust = { [weak self] in self?.shotView.autoadjustSelection() }
        options.onImprint = { [weak self] in self?.shotView.imprintSelectionSize() }
        if editorRibbon == nil { topBar.shotView = shotView }
        options.onCutOutMode = { [weak self] on in
            self?.shotView.cutOutMode = on
            self?.window?.makeFirstResponder(self?.shotView)
        }
    }

    /// The new editor (R5b): floating cards on the window's background, 10 pt from the edges and from each other.
    /// Title card (with the window's buttons), ribbon, then the callout style bar and the canvas side by side, the
    /// status bar and the recent strip.
    private func buildCardLayout(_ r: EditorRibbon) {
        guard let win = window else { return }
        let content = CanvasBackground()
        win.contentView = content
        let m = DesignTokens.Metrics.self
        let drag = DragOutView(icon: Icons.image(.drag, size: 18, color: DesignTokens.color(.ink2))) { [weak self] in
            self?.rendered().map { ($0, self?.doc.scale ?? 2) }
        }
        let title = TitleCard(actions: EditorRibbon.titleBarGroup([r.copyImage, r.save, r.pin]), drag: drag,
                              history: EditorRibbon.titleBarGroup([r.undo, r.redo]))
        let ribbon = CardView(), canvas = CardView(), status = CardView(), strip = CardView()
        r.view.drawsChrome = false
        editorStatus.drawsChrome = false
        recent.inCard = true
        ribbon.embed(r.view)
        canvas.embed(shotView)
        status.embed(editorStatus)
        strip.embed(recent)
        calloutBar.isHidden = true
        calloutBar.onPick = { [weak self] style in
            guard let v = self?.shotView else { return }
            var s = v.displayedStyle
            s.callout = style
            v.setStyle(s)
        }
        for v in [title, ribbon, calloutBar, canvas, status, strip] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        shotView.topInset = 10
        let nextToBar = canvas.leadingAnchor.constraint(equalTo: calloutBar.trailingAnchor, constant: m.cardGap)
        let atEdge = canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m.cardInset)
        canvasNextToBar = nextToBar
        canvasAtEdge = atEdge
        func sides(_ v: NSView) -> [NSLayoutConstraint] {
            [v.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m.cardInset),
             v.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m.cardInset)]
        }
        NSLayoutConstraint.activate(sides(title) + sides(ribbon) + sides(status) + sides(strip) + [
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: m.titleCardTop),
            title.heightAnchor.constraint(equalToConstant: m.titleBarHeight),
            ribbon.topAnchor.constraint(equalTo: title.bottomAnchor, constant: m.cardGap),
            ribbon.heightAnchor.constraint(equalToConstant: m.ribbonHeight),
            calloutBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m.cardInset),
            calloutBar.widthAnchor.constraint(equalToConstant: m.sideBarWidth),
            calloutBar.topAnchor.constraint(equalTo: ribbon.bottomAnchor, constant: m.cardGap),
            calloutBar.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -m.cardGap),
            atEdge,
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m.cardInset),
            canvas.topAnchor.constraint(equalTo: ribbon.bottomAnchor, constant: m.cardGap),
            canvas.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -m.cardGap),
            status.heightAnchor.constraint(equalToConstant: m.statusBarHeight),
            status.bottomAnchor.constraint(equalTo: strip.topAnchor, constant: -m.cardGap),
            strip.heightAnchor.constraint(equalToConstant: 84),
            strip.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m.cardInset),
        ])
        cards = (title, ribbon, canvas, status, strip)
        win.initialFirstResponder = shotView
    }

    /// Shows the callout style bar while the Callout tool is in hand or a callout is selected; the canvas takes its room
    /// otherwise.
    private func updateCalloutBar() {
        guard cards != nil else { return }
        let v = shotView
        let shows = (v.selectedKind ?? v.tool) == .callout || v.styleTargets.contains { $0.kind == .callout }
        calloutBar.show(current: v.displayedStyle.callout)
        guard shows == calloutBar.isHidden else { return }
        let toggle = {
            self.calloutBar.isHidden = !shows
            self.canvasAtEdge?.isActive = !shows
            self.canvasNextToBar?.isActive = shows
        }
        // The picture stays where it is while the canvas narrows or widens: no jump, no re-zoom under the text being typed.
        if shows {
            let wasFitted = v.fitsWindow
            v.keepPictureStill(toggle)
            calloutBarHeldZoom = wasFitted ? v.currentZoom : nil
        } else {
            let refit = calloutBarHeldZoom.map { abs($0 - v.currentZoom) < 0.0001 } ?? false
            calloutBarHeldZoom = nil
            v.keepPictureStill(restoreFit: refit, toggle)
        }
    }

    private func buildLayout() {
        guard let win = window else { return }
        if let r = editorRibbon { buildCardLayout(r); return }
        let content = NSView()
        win.contentView = content
        // The canvas paints its dot background over whatever it is asked to redraw; keep that inside it, and keep the
        // toolbar above it (views don't clip to their bounds by default since macOS 14).
        shotView.clipsToBounds = true
        // The new editor has no floating formatting card: Font, Paragraph, Color and Arrange are in the ribbon.
        let floating: [NSView] = editorRibbon == nil ? [shotView, topBar, statusBar, recent] : [shotView, editorStatus, recent]
        for v in floating {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        shotView.topInset = editorRibbon == nil ? 10 + EditorToolbar.height : 10
        // With the new editor the ribbon runs full width under the title bar, and the canvas starts below it.
        var top = content.safeAreaLayoutGuide.topAnchor
        if let ribbonView = editorRibbon?.view {
            ribbonView.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(ribbonView)
            NSLayoutConstraint.activate([
                ribbonView.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
                ribbonView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                ribbonView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                ribbonView.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.ribbonHeight),
            ])
            top = ribbonView.bottomAnchor
        }
        if editorRibbon == nil {
            NSLayoutConstraint.activate([
                // Both cards float over the canvas: the toolbar at the top, hugging its content, the status bar at the bottom.
                topBar.topAnchor.constraint(equalTo: top, constant: 8),
                topBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                topBar.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
                topBar.heightAnchor.constraint(equalToConstant: EditorToolbar.height),
            ])
        }
        if editorRibbon == nil {
            NSLayoutConstraint.activate([
                shotView.bottomAnchor.constraint(equalTo: recent.topAnchor),
                statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                statusBar.bottomAnchor.constraint(equalTo: recent.topAnchor, constant: -10),
                statusBar.heightAnchor.constraint(equalToConstant: ToolbarShell.barHeight),
            ])
        } else {
            // The new status bar is a full-width band between the canvas and the recent strip, not a floating card.
            NSLayoutConstraint.activate([
                shotView.bottomAnchor.constraint(equalTo: editorStatus.topAnchor),
                editorStatus.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                editorStatus.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                editorStatus.bottomAnchor.constraint(equalTo: recent.topAnchor),
                editorStatus.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.statusBarHeight),
            ])
        }
        NSLayoutConstraint.activate([
            shotView.topAnchor.constraint(equalTo: top),
            shotView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            shotView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            recent.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            recent.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            recent.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            recent.heightAnchor.constraint(equalToConstant: 84),
        ])
        win.initialFirstResponder = shotView
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // The new editor's toolbar stays empty: it only gives the title bar the height the title card is centered on.
        if editorRibbon != nil { return [] }
        return [Item.actions, Item.dragOut, .flexibleSpace, Item.tools, Item.crop, Item.adjust, .flexibleSpace]
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
        // The new editor's cards: title 6+40, ribbon, canvas, status, strip, with 10 pt gaps and margins.
        let chrome: CGFloat = editorRibbon == nil ? 52 + 18 + 68 + 84 + EditorToolbar.height
            : 6 + 40 + 10 + DesignTokens.Metrics.ribbonHeight + 10 + 10 + DesignTokens.Metrics.statusBarHeight + 10 + 84 + 10 + 32
        var w = max(1380, c.width / doc.scale + 32)
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
        options.update(tool: shotView.selectedKind ?? shotView.tool, style: shotView.displayedStyle, cutOut: shotView.cutOutMode)
        if editorRibbon == nil {
            statusBar.update(tool: shotView.selectedKind ?? shotView.tool, backdrop: doc.backdrop, cutOut: shotView.cutOutMode)
        } else {
            editorStatus.update(tool: shotView.selectedKind ?? shotView.tool, backdrop: doc.backdrop, cutOut: shotView.cutOutMode,
                                area: shotView.selectingArea)
        }
        if editorRibbon == nil { topBar.update() }
        editorRibbon?.update(tool: shotView.tool, hasSelection: !shotView.selection.isEmpty,
                             canUndo: !doc.undoStack.isEmpty, canRedo: !doc.redoStack.isEmpty)
        updateCalloutBar()
        // The formatting toolbar follows focus, selection and the caret.
        formatting.attach(shotView.formattingTarget())
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

    #if SCREENSHOT_SELFTESTS
    var debugInfo: InfoCellsView { info }
    var debugRecent: RecentStrip { recent }
    #endif

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

    /// Shows a message in the new editor's notification bar. Returns false for the old editor (which uses Toast's HUD).
    @discardableResult
    func notify(_ notice: NotificationBar.Notice) -> Bool {
        guard editorRibbon != nil else { return false }
        editorStatus.notices.show(notice)
        return true
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

    /// A tool picked in the ribbon: Crop starts a crop, or applies the one in progress, as the old Crop button did.
    func pickTool(_ t: Tool) {
        if t == .crop {
            if shotView.selectingArea { shotView.beginCrop() } else { cropClicked() }
            return
        }
        shotView.tool = t
        window?.makeFirstResponder(shotView)
    }

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

    /// Annotation text fields get a field editor that ignores the color panel's direct changeColor:. The options bar
    /// receives the panel's color and applies it properly: to the bubble or shape and the letters, or to the
    /// selected letters only. Without this, the panel colored only the letters and could hide them on the bubble.
    private let annotationFieldEditor: AnnotationFieldEditor = {
        let t = AnnotationFieldEditor()
        t.isFieldEditor = true
        t.allowsUndo = true
        return t
    }()

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        (client as? NSTextField)?.superview === shotView ? annotationFieldEditor : nil
    }

    /// Whether keyboard focus is in the formatting toolbar (its size box), so text being typed stays open.
    func isFormattingControl(_ responder: NSResponder) -> Bool {
        if let r = editorRibbon { return r.view.owns(responder) }
        return topBar.owns(responder)
    }

    #if SCREENSHOT_SELFTESTS
    var debugRibbon: FormattingRibbon { ribbon }
    var debugOptions: ToolOptions { options }
    var debugTopBar: EditorToolbar { topBar }
    var debugStatusBar: StatusBar { statusBar }
    var debugEditorRibbon: EditorRibbon? { editorRibbon }
    var debugEditorStatus: EditorStatusBar? { editorRibbon == nil ? nil : editorStatus }
    var debugCards: (title: TitleCard, ribbon: CardView, canvas: CardView, status: CardView, recent: CardView)? { cards }
    var debugCalloutBar: CalloutStyleBar? { cards == nil ? nil : calloutBar }
    /// Whether the old floating formatting bar is in the window.
    var debugTopBarShown: Bool { editorRibbon == nil }
    /// Shape Fill's palette: the ribbon's in the new editor, the formatting bar's otherwise.
    var debugFillControl: ColorSplitButton { editorRibbon?.formatting.fillPalette ?? topBar.fill }
    #endif

    /// Shottr's "Default zoom level: Prefer 100%"; otherwise the image fits the window.
    func applyDefaultZoom() {
        if Settings.prefer100 { shotView.zoomToActualSize() }
        updateInfo()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if editorRibbon != nil { syncToolbar() } // Paste follows what the clipboard holds now
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
        editorRibbon?.updateHistory(canUndo: !doc.undoStack.isEmpty, canRedo: !doc.redoStack.isEmpty)
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
    private var separators: [NSView] = []

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

        separators = [Self.separator(), Self.separator()]
        let row = NSStackView(views: [colorCell, separators[0], sizeCell, separators[1], zoomCell])
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

    /// The new editor's look: the design tokens' readout and caption type and colors, hairline dividers.
    func applyModernStyle() {
        for l in [colorValue, sizeValue, zoomValue] {
            l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            l.textColor = DesignTokens.color(.ink)
        }
        for l in [colorCaption, sizeCaption, zoomCaption] {
            l.font = DesignTokens.Font.caption
            l.textColor = DesignTokens.color(.ink3)
        }
        for case let s as NSBox in separators {
            s.boxType = .custom
            s.borderWidth = 0
            s.fillColor = DesignTokens.color(.line)
            s.widthAnchor.constraint(equalToConstant: 1).isActive = true
        }
        swatch.layer?.cornerRadius = 4
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

    /// `icon` replaces the SF Symbol hand (the new editor passes its own icon family's Drag icon).
    init(icon: NSImage? = nil, provider: @escaping () -> (CGImage, CGFloat)?) {
        self.provider = provider
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 28))
        toolTip = "Drag'n'Drop Image"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drag the image into another app")
        let icon = NSImageView(image: icon ?? NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Drag image")!
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

// MARK: - Status bar

/// The bottom bar: a hint for the tool in hand, Shottr's info cells (color under the pointer · Tab copies it, image
/// size, zoom) and the Backdrop button. Shape and text controls live in the top toolbar.
final class StatusBar: ToolbarShell {
    var onBackdropPanel: ((NSView) -> Void)?
    private var backdropButton: PillButton!
    private let hint = ToolbarShell.label("", size: 11, weight: .regular)

    init(info: NSView) {
        super.init(frame: .zero)
        backdropButton = PillButton(title: "Backdrop", symbol: "rectangle.inset.filled",
                                    tooltip: "Backdrop: background, aspect ratio, padding, shadow (K toggles)") { [weak self] in
            guard let self else { return }
            self.onBackdropPanel?(self.backdropButton)
        }
        // The hint gives way first on narrow windows.
        hint.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Shottr's info cells (color · size · zoom) sit here, always visible even on narrow screens.
        info.setContentCompressionResistancePriority(.required, for: .horizontal)
        info.setContentHuggingPriority(.required, for: .horizontal)
        backdropButton.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [hint, Self.divider(), info, backdropButton])
        row.spacing = Self.spacing
        row.distribution = .fill
        row.alignment = .centerY
        embed(row)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(tool: Tool, backdrop: Backdrop, cutOut: Bool) {
        backdropButton.isOn = backdrop.isOn
        hint.stringValue = Self.hint(for: tool, cutOut: cutOut)
        hint.toolTip = hint.stringValue
    }

    /// A tip for the tool in hand.
    static func hint(for tool: Tool, cutOut: Bool, area: Bool = false) -> String {
        if tool == .crop && area { return "Drag over an area · ⌘C or Enter copies it · Esc clears the selection" }
        return switch tool {
        case .counter: "Type digits to renumber · drag the bubble tip to point it"
        case .crop where cutOut: "Drag up/down to cut rows, sideways to cut columns · Enter cuts · Esc resets"
        case .crop: "Select an area · Enter crops · ⌘O reads its text · C copies its average color · Esc resets"
        case .ruler: "Drag to measure · Shift snaps to 45° · hold 1 or 2 anywhere to measure what's under the pointer"
        case .select: "Click to select · Shift-click adds · drag empty space to select several · ⌥-drag duplicates · ⌘A all"
        case .text: "Click to type · double-click text to edit"
        case .spotlight: "Everything outside the spotlights gets dimmed"
        case .callout: "Press on the target, drag to place the bubble, type · drag the tip to re-aim"
        case .image: "Drag to move · pinch or scroll over it to resize"
        case .magnifier: "Drag over an area · drag the lens to move it · pinch, scroll or +/− to zoom"
        default: "Shift constrains · Tab copies the color under the cursor"
        }
    }

    #if SCREENSHOT_SELFTESTS
    var debugHint: String { hint.stringValue }
    #endif
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

/// Field editor for annotation text. The options bar owns colors: the color panel's changeColor: is ignored here, and
/// the text never pushes its letters' color into the panel (the panel would announce it as a pick, and the bubble or
/// shape would take it, e.g. black after deleting all the text).
final class AnnotationFieldEditor: NSTextView {
    /// Word's formatting shortcuts (⌘B, ⌘I, ⌘U, ⌘L/E/R, ⌘⇧> <, ⌘] [) while typing; they go through the formatting store,
    /// so the toolbar updates too. Other ⌘ keys reach the menus as usual.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, let change = FormattingController.change(for: event),
           let formatting = (window?.windowController as? EditorWindowController)?.formatting, formatting.target != nil {
            formatting.applyFormat(change)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func changeColor(_ sender: Any?) {}
    override func updateFontPanel() {}
    override var usesFontPanel: Bool {
        get { false }
        set {}
    }
}
