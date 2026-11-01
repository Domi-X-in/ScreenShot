import AppKit
import UniformTypeIdentifiers

/// Screenshot editor window (ROADMAP, Fase 6): floating cards for the title bar (Copy, Save, Pin, Drag, Undo/Redo), the
/// Office-style ribbon, the canvas with the callout style bar beside it, the notification and readout bar, and the
/// recent captures.
@MainActor final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    /// The document on screen; thumbnails swap it in place.
    var doc: EditorDocument { shotView.doc }
    let shotView: ShotView
    /// Documents visited in this window, so returning to one keeps its undo history.
    private var visited: [URL: EditorDocument] = [:]
    private var autosaveTimer: Timer?
    private let saveQueue = DispatchQueue(label: "screenshot.autosave")
    private let info = InfoCellsView()
    private let recent = RecentStrip()
    /// The bottom bar: messages, readouts and Backdrop.
    private lazy var editorStatus = EditorStatusBar(info: info)
    /// The floating cards (R5b) and the side bar of shape options beside the canvas (R10).
    private var cards: (title: TitleCard, ribbon: CardView, canvas: CardView, status: CardView, recent: CardView)?
    private lazy var optionsBar = ShapeOptionsBar()
    private(set) lazy var shapeOptions = ShapeOptions(editor: self)
    private var canvasNextToBar: NSLayoutConstraint?
    private var canvasAtEdge: NSLayoutConstraint?
    /// The zoom the picture had when the side bar came in fitted, so it can fit again when the bar leaves.
    private var optionsBarHeldZoom: CGFloat?
    /// The formatting store the ribbon's Font, Paragraph, Color and Arrange groups read and write.
    let formatting = FormattingController()
    /// The Office-style ribbon and the title card's actions (ROADMAP, Fase 6).
    private(set) var editorRibbon: EditorRibbon!

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
        editorRibbon = EditorRibbon(editor: self)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        // The cards draw the title bar: the system's is see-through, and its empty toolbar only sets its height so
        // the window's buttons center on the title card.
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
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
        info.onColorBox = { [weak self] in self?.showColorPanel(from: $0) }
        info.onSizeBox = { [weak self] in self?.showResizePanel(from: $0) }
        info.onZoomBox = { [weak self] in self?.showZoomPanel(from: $0) }

        recent.onSelect = { [weak self] url in self?.switchTo(url) }
        recent.onBrowse = { LibraryWindowController.show() }
        editorStatus.onBackdropPanel = { [weak self] anchor in self?.showBackdropPanel(from: anchor) }
    }

    @objc private func settingsChanged() { editorRibbon?.updateCloseLabels() }

    /// Floating cards (R5b) on the window's background, 10 pt from the edges and from each other.
    /// Title card (with the window's buttons), ribbon, then the callout style bar and the canvas side by side, the
    /// status bar and the recent strip.
    private func buildLayout() {
        guard let win = window, let r = editorRibbon else { return }
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
        optionsBar.isHidden = true
        for v in [title, ribbon, optionsBar, canvas, status, strip] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        shotView.topInset = 10
        let nextToBar = canvas.leadingAnchor.constraint(equalTo: optionsBar.trailingAnchor, constant: m.cardGap)
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
            optionsBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m.cardInset),
            optionsBar.widthAnchor.constraint(equalToConstant: m.sideBarWidth),
            optionsBar.topAnchor.constraint(equalTo: ribbon.bottomAnchor, constant: m.cardGap),
            optionsBar.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -m.cardGap),
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

    /// Shows the side bar while the tool in hand or the selection has options of its own; the canvas takes its room
    /// otherwise.
    private func updateOptionsBar() {
        guard cards != nil else { return }
        let v = shotView
        let sections = shapeOptions.sections()
        shapeOptions.update()
        optionsBar.show(sections)
        let shows = !sections.isEmpty
        guard shows == optionsBar.isHidden else { return }
        let toggle = {
            self.optionsBar.isHidden = !shows
            self.canvasAtEdge?.isActive = !shows
            self.canvasNextToBar?.isActive = shows
        }
        // The picture stays where it is while the canvas narrows or widens: no jump, no re-zoom under the text being typed.
        if shows {
            let wasFitted = v.fitsWindow
            v.keepPictureStill(toggle)
            optionsBarHeldZoom = wasFitted ? v.currentZoom : nil
        } else {
            // Refit if the picture still fits (⌘0) or still has the zoom it had when the bar came in fitted.
            let refit = v.fitsWindow || (optionsBarHeldZoom.map { abs($0 - v.currentZoom) < 0.0001 } ?? false)
            optionsBarHeldZoom = nil
            v.keepPictureStill(restoreFit: refit, toggle)
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // The toolbar stays empty: it only gives the title bar the height the title card is centered on.
        []
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

    private func sizeWindow() {
        guard let win = window else { return }
        let screen = NSScreen.containingMouse().visibleFrame
        let c = Renderer.canvasSize(doc)
        // The new editor's cards: title 6+40, ribbon, canvas, status, strip, with 10 pt gaps and margins.
        let chrome: CGFloat = 6 + 40 + 10 + DesignTokens.Metrics.ribbonHeight + 10 + 10 + DesignTokens.Metrics.statusBarHeight + 10 + 84 + 10 + 32
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
        editorStatus.update(tool: shotView.selectedKind ?? shotView.tool, backdrop: doc.backdrop, cutOut: shotView.cutOutMode,
                            area: shotView.selectingArea)
        editorRibbon?.update(tool: shotView.tool, hasSelection: !shotView.selection.isEmpty,
                             canUndo: !doc.undoStack.isEmpty, canRedo: !doc.redoStack.isEmpty)
        updateOptionsBar()
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

    /// Shows a message in the notification bar.
    func notify(_ notice: NotificationBar.Notice) {
        editorStatus.notices.show(notice)
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

    private func cropClicked() {
        if shotView.tool == .crop { shotView.applyCropIfAny() } else { shotView.beginCrop() }
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
    @objc func saveImage() { _ = save() }

    @discardableResult
    private func save(quiet: Bool = false) -> Bool {
        guard let img = rendered() else { return false }
        let revision = doc.revision
        guard Exporter.saveEditable(doc, rendered: img, quiet: quiet) != nil else { return false }
        doc.savedRevision = revision
        window?.title = doc.fileURL?.lastPathComponent ?? "ScreenShot"
        recent.currentURL = doc.fileURL
        return true
    }

    /// The title card's Copy: copies, then (Preferences › General, on by default) closes every window but pins so the
    /// picture can be pasted in the app that was in front.
    func copyFromTitleCard() {
        guard Settings.closeAfterCopySave else { copyImage(); return }
        guard let img = rendered() else { return }
        Exporter.copy(img, scale: doc.scale)
        AppLogic.shared.closeAllWindows()
        Toast.show("Copied to the clipboard")
    }

    /// The title card's Save: saves, then closes every window but pins; a failed save leaves everything open.
    func saveFromTitleCard() {
        guard Settings.closeAfterCopySave else { saveImage(); return }
        guard save(quiet: true), let name = doc.fileURL?.lastPathComponent else { return }
        AppLogic.shared.closeAllWindows()
        Toast.show("Saved \(name)")
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
        hideEditor()
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
        hideEditor()
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
        editorRibbon?.view.owns(responder) ?? false
    }

    #if SCREENSHOT_SELFTESTS
    var debugEditorRibbon: EditorRibbon? { editorRibbon }
    var debugEditorStatus: EditorStatusBar? { editorStatus }
    var debugCards: (title: TitleCard, ribbon: CardView, canvas: CardView, status: CardView, recent: CardView)? { cards }
    var debugOptionsBar: ShapeOptionsBar { optionsBar }
    /// Shape Fill's palette in the ribbon.
    var debugFillControl: ColorSplitButton { editorRibbon.formatting.fillPalette }
    #endif

    /// Shottr's "Default zoom level: Prefer 100%"; otherwise the image fits the window.
    func applyDefaultZoom() {
        if Settings.prefer100 { shotView.zoomToActualSize() }
        updateInfo()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        syncToolbar() // Paste follows what the clipboard holds now
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
        let next: EditorDocument
        if let cached = visited[url.standardizedFileURL] {
            next = cached
        } else {
            guard let loaded = EditableFile.load(url) else { Toast.show("Image Reading Error"); return }
            next = Self.makeDocument(image: loaded.image, scale: loaded.scale, state: loaded.state, url: url)
        }
        present(next)
    }

    /// A new capture, an opened file or the clipboard, in this window (the app has one editor): the picture shown now
    /// is auto-saved first, as when the window closes.
    func show(image: CGImage, scale: CGFloat, state: EditState?, url: URL?) {
        if let url, url.standardizedFileURL == doc.fileURL?.standardizedFileURL { return }
        let next = url.flatMap { visited[$0.standardizedFileURL] } ?? Self.makeDocument(image: image, scale: scale, state: state, url: url)
        if url.flatMap({ visited[$0.standardizedFileURL] }) == nil { next.savedRevision = next.revision }
        present(next)
    }

    private func present(_ next: EditorDocument) {
        saveBeforeLeaving()
        if let current = doc.fileURL { visited[current.standardizedFileURL] = doc }
        if visited.count > 20 { visited.removeAll() }
        shotView.switchDocument(next)
        applyDefaultZoom()
        window?.title = next.fileURL?.lastPathComponent ?? "ScreenShot"
        recent.currentURL = next.fileURL
        recent.reload()
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

    /// The picture is leaving the window: a capture that was never saved gets a file now, even with no edits, so it
    /// stays in the recent strip and the Library.
    private func saveBeforeLeaving() { flushAutosave(force: doc.fileURL == nil) }

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
            url = Exporter.unusedURL(in: folder, ext: "png")
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

    /// The red button, ⌘W, Esc, Pin, Copy and Close and Save and Close only hide the editor (R13), so the Dock icon brings
    /// it back as it was, with its undo history.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideEditor()
        return false
    }

    func hideEditor() {
        saveBeforeLeaving()
        window?.orderOut(nil)
    }

    /// Back on screen as it was left; the recent strip may have new captures.
    func reveal() {
        recent.reload()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(shotView)
    }

    func windowWillClose(_ notification: Notification) {
        saveBeforeLeaving()
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
        applyStyle()
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

    /// The design tokens' readout and caption type and colors, hairline dividers.
    private func applyStyle() {
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

/// Field editor for annotation text. The ribbon owns colors: the color panel's changeColor: is ignored here, and
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
