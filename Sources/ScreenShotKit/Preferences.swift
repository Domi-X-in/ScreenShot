import AppKit
import ServiceManagement

/// Preferences window laid out after Shottr's Preferences.storyboard: icon tabs in a preference-style toolbar,
/// 520-pt panes with right-aligned labels (column ending near x=220) and controls from x=238, groups split by separators.
@MainActor final class PreferencesWindowController: NSWindowController, NSToolbarDelegate {
    private enum Pane: String, CaseIterable {
        case general, hotkeys, advanced

        var title: String {
            switch self {
            case .general: "General"
            case .hotkeys: "Hotkeys"
            case .advanced: "Advanced"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .hotkeys: "keyboard"
            case .advanced: "slider.horizontal.3"
            }
        }

        var id: NSToolbarItem.Identifier { .init(rawValue) }
    }

    private var current: Pane = .general

    init() {
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.toolbarStyle = .preference
        super.init(window: w)
        let tb = NSToolbar(identifier: "prefs")
        tb.delegate = self
        tb.displayMode = .iconAndLabel
        tb.allowsUserCustomization = false
        w.toolbar = tb
        show(.general)
    }

    required init?(coder: NSCoder) { fatalError() }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.id) }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.id) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.id) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = Pane(rawValue: id.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(paneClicked(_:))
        return item
    }

    @objc private func paneClicked(_ sender: NSToolbarItem) {
        if let p = Pane(rawValue: sender.itemIdentifier.rawValue) { show(p) }
    }

    private func show(_ pane: Pane) {
        guard let w = window else { return }
        current = pane
        w.toolbar?.selectedItemIdentifier = pane.id
        w.title = pane.title
        let view: NSView = switch pane {
        case .general: PrefPanes.general()
        case .hotkeys: PrefPanes.hotkeys()
        case .advanced: PrefPanes.advanced()
        }
        let size = view.fittingSize
        let contentRect = CGRect(origin: .zero, size: CGSize(width: 520, height: size.height))
        var frame = w.frameRect(forContentRect: contentRect)
        frame.origin = CGPoint(x: w.frame.minX, y: w.frame.maxY - frame.height)
        w.contentView = view
        w.setFrame(frame, display: true, animate: w.isVisible)
    }
}

// MARK: - Panes

@MainActor enum PrefPanes {
    static func general() -> NSView {
        let form = PrefForm()
        form.header = appHeader()
        form.row("After screenshot", [
            DefaultsCheckbox("Show", key: Keys.afterShow),
            DefaultsCheckbox("Copy", key: Keys.afterCopy),
            DefaultsCheckbox("Save", key: Keys.afterSave),
        ])
        form.row("After Area Crop, show", DefaultsRadio.group(key: Keys.afterAreaShow, options: [("Thumbnail", "thumbnail"), ("Editor", "editor")]))
        form.row("Autostart", [LoginCheckbox()])
        form.row("Appearance", DefaultsRadio.group(key: "appearance", options: [("System", "system"), ("Light", "light"), ("Dark", "dark")]))
        form.separator()
        form.row("Screenshots folder", [FolderButton()])
        form.row("Save format", DefaultsRadio.group(key: Keys.saveFormat, options: [("PNG", "png"), ("Auto (PNG/JPEG)", "auto")]))
        form.separator()
        form.row("Scrolling screenshot speed", [DefaultsSlider(key: Keys.scrollSpeed)])
        form.separator()
        form.row("Window Screenshot Background", DefaultsRadio.boolGroup(key: Keys.windowShadow, options: [("Transparent", true), ("Trim shadow", false)]))
        return form.finish()
    }

    static func hotkeys() -> NSView {
        let form = PrefForm()
        let order: [(HotkeyAction, String)] = [
            (.fullscreen, "Fullscreen screenshot"), (.area, "Area screenshot"), (.repeatArea, "Repeat area screenshot"),
            (.anyWindow, "Any window screenshot"), (.activeWindow, "Active window screenshot"),
            (.scrolling, "Scrolling screenshot"), (.scrollingManual, "Manual scrolling screenshot"),
            (.delayed, "Delayed screenshot"), (.ocr, "Instant Text/QR Recognition"),
        ]
        var recorders: [RecorderButton] = []
        for (action, title) in order {
            let r = RecorderButton(action: action) { recorders.forEach { $0.refresh() } }
            r.widthAnchor.constraint(equalToConstant: 160).isActive = true
            recorders.append(r)
            form.row(title, [r])
        }
        form.separator()
        let reset = ClosureButton(title: "Reset to Defaults") {
            HotKeyCenter.shared.resetAll()
            recorders.forEach { $0.refresh() }
        }
        form.row("", [reset])
        form.note("Click a field and type a shortcut. Delete clears it, Esc cancels.")
        return form.finish()
    }

    static func advanced() -> NSView {
        let form = PrefForm()
        form.row("OCR main language", [DefaultsPopup(key: Keys.ocrLanguage, options: [("auto", "Automatic")] + OCR.languages.map { ($0.code, $0.name) })])
        form.row("OCR line breaks", [DefaultsCheckbox("Remove line breaks", key: Keys.ocrRemoveBreaks)])
        form.row("Action when hiding with Esc", [
            DefaultsCheckbox("Copy Image", key: Keys.escCopy),
            DefaultsCheckbox("Save Image", key: Keys.escSave),
        ])
        form.row("Scrolling capture", [DefaultsCheckbox("Reverse scroll direction", key: Keys.reverseAutoscroll)])
        form.row("Zoom with mouse wheel", [DefaultsCheckbox("Scroll zooms the editor", key: "wheelZooms")])
        form.row("Default zoom level", [DefaultsCheckbox("Prefer 100%", key: "prefer100")])
        form.row("URL Scheme API", [NSTextField(labelWithString: "screenshot://grab/area, grab/fullscreen, …")])
        return form.finish()
    }
}

/// Two-column grid: right-aligned labels, left-aligned controls, separators between groups.
@MainActor final class PrefForm {
    private let grid = NSGridView()

    init() {
        grid.rowSpacing = 14
        grid.columnSpacing = 18
    }

    func row(_ label: String, _ controls: [NSView]) {
        let l = NSTextField(labelWithString: label.isEmpty ? "" : label + ":")
        l.alignment = .right
        let stack = NSStackView(views: controls)
        stack.spacing = 14
        stack.alignment = .centerY
        grid.addRow(with: [l, stack])
    }

    func separator() {
        let box = NSBox()
        box.boxType = .separator
        let r = grid.addRow(with: [box])
        r.mergeCells(in: NSRange(location: 0, length: 2))
        r.topPadding = 2
        r.bottomPadding = 2
    }

    func note(_ text: String) {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        grid.addRow(with: [NSView(), l])
    }

    /// Optional view shown above the form (the app header on General).
    var header: NSView?

    func finish() -> NSView {
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 202
        grid.rowAlignment = .firstBaseline
        let container = NSView()
        if let header {
            header.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(header)
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
                header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
                header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            ])
        }
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 520),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: header?.bottomAnchor ?? container.topAnchor, constant: header == nil ? 24 : 18),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])
        return container
    }
}

// MARK: - Defaults-bound controls

final class DefaultsCheckbox: NSButton {
    private let key: String

    init(_ title: String, key: String) {
        self.key = key
        super.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        target = self
        action = #selector(toggled)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggled() { UserDefaults.standard.set(state == .on, forKey: key) }
}

final class DefaultsRadio: NSButton {
    private var apply: () -> Void = {}

    static func group(key: String, options: [(String, String)]) -> [NSView] {
        let current = UserDefaults.standard.string(forKey: key)
        return options.map { title, value in
            let b = DefaultsRadio(title: title, on: current == value)
            b.apply = { UserDefaults.standard.set(value, forKey: key) }
            return b
        }
    }

    static func boolGroup(key: String, options: [(String, Bool)]) -> [NSView] {
        let current = UserDefaults.standard.bool(forKey: key)
        return options.map { title, value in
            let b = DefaultsRadio(title: title, on: current == value)
            b.apply = { UserDefaults.standard.set(value, forKey: key) }
            return b
        }
    }

    private init(title: String, on: Bool) {
        super.init(frame: .zero)
        setButtonType(.radio)
        self.title = title
        state = on ? .on : .off
        target = self
        action = #selector(picked)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Radios sharing a superview and action are mutually exclusive in AppKit.
    @objc private func picked() { apply() }
}

final class DefaultsPopup: NSPopUpButton {
    private let key: String
    private let values: [String]

    init(key: String, options: [(value: String, title: String)]) {
        self.key = key
        values = options.map(\.value)
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: options.map(\.title))
        selectItem(at: values.firstIndex(of: UserDefaults.standard.string(forKey: key) ?? "") ?? 0)
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() { UserDefaults.standard.set(values[indexOfSelectedItem], forKey: key) }
}

final class DefaultsSlider: NSSlider {
    private let key: String

    init(key: String) {
        self.key = key
        super.init(frame: .zero)
        minValue = 0
        maxValue = 1
        doubleValue = UserDefaults.standard.double(forKey: key)
        controlSize = .small
        target = self
        action = #selector(changed)
        widthAnchor.constraint(equalToConstant: 190).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() { UserDefaults.standard.set(doubleValue, forKey: key) }
}

final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(clicked)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { handler() }
}

/// Shottr's "Select Folder" button; shows the chosen folder as its title.
final class FolderButton: NSButton {
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(choose)
        lineBreakMode = .byTruncatingMiddle
        widthAnchor.constraint(equalToConstant: 216).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        title = (Settings.saveFolder.path as NSString).abbreviatingWithTildeInPath
        toolTip = Settings.saveFolder.path
    }

    @objc private func choose() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.message = "Pick a folder for your screenshots."
        p.directoryURL = Settings.saveFolder
        if p.runModal() == .OK, let url = p.url {
            UserDefaults.standard.set(url.path, forKey: Keys.saveFolder)
            refresh()
        }
    }
}

/// "Launch at startup" through SMAppService (Shottr bundles a LaunchAtLoginHelper login item for the same purpose).
final class LoginCheckbox: NSButton {
    init() {
        super.init(frame: .zero)
        setButtonType(.switch)
        title = "Launch at startup"
        state = SMAppService.mainApp.status == .enabled ? .on : .off
        target = self
        action = #selector(toggled)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggled() {
        do {
            if state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login change failed: %@", error.localizedDescription)
            state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}

final class RecorderButton: NSButton {
    private let hotkey: HotkeyAction
    private let onChange: () -> Void
    private var monitor: Any?

    init(action: HotkeyAction, onChange: @escaping () -> Void) {
        self.hotkey = action
        self.onChange = onChange
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        self.action = #selector(startRecording)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        title = HotKeyCenter.shared.shortcut(for: hotkey)?.display ?? "Record Shortcut"
    }

    @objc private func startRecording() {
        guard monitor == nil else { return }
        title = "Type shortcut…"
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e)
            return nil
        }
    }

    private func handle(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(e.keyCode) {
        case 53:
            stop()
        case 51, 117:
            HotKeyCenter.shared.set(nil, for: hotkey)
            stop()
        default:
            guard !mods.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return }
            let s = Shortcut(keyCode: UInt32(e.keyCode), modifiers: Shortcut.carbonModifiers(mods), key: Shortcut.keyName(e))
            HotKeyCenter.shared.set(s, for: hotkey)
            stop()
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyCenter.shared.resume()
        refresh()
        onChange()
    }
}

/// App icon, name and version above the General pane.
@MainActor private func appHeader() -> NSView {
    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 52), icon.heightAnchor.constraint(equalToConstant: 52)])
    let name = NSTextField(labelWithString: "ScreenShot")
    name.font = .systemFont(ofSize: 18, weight: .bold)
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    let tagline = NSTextField(labelWithString: "Capture, annotate and share · version \(version)")
    tagline.font = .systemFont(ofSize: 12)
    tagline.textColor = .secondaryLabelColor
    let text = NSStackView(views: [name, tagline])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 2
    let row = NSStackView(views: [icon, text])
    row.spacing = 14
    row.alignment = .centerY
    let line = NSBox()
    line.boxType = .separator
    let stack = NSStackView(views: [row, line])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 16
    line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    return stack
}
