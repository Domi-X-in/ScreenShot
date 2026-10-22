import AppKit
import ImageIO

/// Bottom strip of the editor: the 10 most recent images in the Screenshots folder, plus a button to browse older ones.
final class RecentStrip: NSView {
    static let limit = 10

    var currentURL: URL? { didSet { highlight() } }
    /// Thumbnail click: the editor shows that file in the same window.
    var onSelect: ((URL) -> Void)?
    /// Folder button: pick an older file to show in the same window.
    var onBrowse: (() -> Void)?
    private let row = NSStackView()
    private let empty = NSTextField(labelWithString: "Every screenshot you save appears here.")
    private var generation = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .top
        row.edgeInsets = NSEdgeInsets(top: 10, left: 4, bottom: 4, right: 4)

        empty.font = .systemFont(ofSize: 11)
        empty.textColor = .secondaryLabelColor

        let folder = BrowseTile { [weak self] in self?.onBrowse?() }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        let clip = FlippedClip()
        clip.drawsBackground = false
        scroll.contentView = clip
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = row

        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        for v in [scroll, folder, empty, line] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor), line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: folder.leadingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.topAnchor.constraint(equalTo: clip.topAnchor),
            row.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            folder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            folder.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .screenshotSaved, object: nil)
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.dynamic(light: NSColor(hex: 0xF4F5F8), dark: NSColor(hex: 0x1D1E24)).cgColor
    }

    /// Lists the folder off the main thread and builds thumbnails with ImageIO.
    @objc func reload() {
        generation += 1
        let gen = generation
        let folder = Settings.saveFolder
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let items = Self.recentFiles(in: folder).compactMap { url -> (URL, CGImage)? in
                Self.thumbnail(url).map { (url, $0) }
            }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.show(items)
            }
        }
    }

    static func recentFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let images = files.filter { ["png", "jpg", "jpeg", "heic", "gif", "tiff"].contains($0.pathExtension.lowercased()) }
        // Creation date (kept across auto-saves) so a file doesn't jump to the front every time it's edited.
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
        return Array(images.sorted { date($0) > date($1) }.prefix(limit))
    }

    private static func thumbnail(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 220,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private func show(_ items: [(URL, CGImage)]) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (url, thumb) in items {
            let tile = RecentTile(url: url, thumbnail: thumb) { [weak self] in self?.onSelect?($0) }
            row.addArrangedSubview(tile)
        }
        empty.isHidden = !items.isEmpty
        highlight()
    }

    private func highlight() {
        for case let tile as RecentTile in row.arrangedSubviews {
            tile.isCurrent = tile.url.standardizedFileURL == currentURL?.standardizedFileURL
        }
    }

    @objc private func browse() {
        onBrowse?()
    }
}

private final class FlippedClip: NSClipView {
    override var isFlipped: Bool { true }
}

/// One thumbnail with a relative-time caption: click shows it in this window; hover lifts it; right-click for more.
private final class RecentTile: NSView {
    let url: URL
    private let onSelect: (URL) -> Void
    var isCurrent = false { didSet { refresh() } }
    private var hovering = false { didSet { refresh() } }
    private let card = NSView()
    private let imageLayer = CALayer()
    private let caption = NSTextField(labelWithString: "")
    private static let tileHeight: CGFloat = 48

    init(url: URL, thumbnail: CGImage, onSelect: @escaping (URL) -> Void) {
        self.url = url
        self.onSelect = onSelect
        super.init(frame: .zero)
        let ratio = CGFloat(thumbnail.width) / CGFloat(max(1, thumbnail.height))
        let width = max(48, min(96, Self.tileHeight * ratio))

        // Card: shadow on the outer layer, rounded clipped image inside.
        card.wantsLayer = true
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.22
        card.layer?.shadowRadius = 4
        card.layer?.shadowOffset = CGSize(width: 0, height: -2)
        imageLayer.contents = thumbnail
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.cornerRadius = 7
        imageLayer.masksToBounds = true
        imageLayer.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        card.layer?.addSublayer(imageLayer)

        caption.font = .systemFont(ofSize: 10, weight: .medium)
        caption.textColor = .tertiaryLabelColor
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        caption.stringValue = Self.relativeDate(url)

        for v in [card, caption] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            card.topAnchor.constraint(equalTo: topAnchor), card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor), card.heightAnchor.constraint(equalToConstant: Self.tileHeight),
            caption.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 4),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -6), caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 6),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let edited = EditableFile.hasEdits(url)
        toolTip = url.lastPathComponent + (edited ? " · editable annotations" : "")
        if edited {
            let badge = NSImageView(image: NSImage(systemSymbolName: "pencil.circle.fill", accessibilityDescription: "Editable")!)
            badge.contentTintColor = Palette.accent
            badge.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -3), badge.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -3),
                badge.widthAnchor.constraint(equalToConstant: 14), badge.heightAnchor.constraint(equalToConstant: 14),
            ])
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeDate(_ url: URL) -> String {
        guard let d = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else { return "" }
        return Date().timeIntervalSince(d) < 60 ? "just now" : formatter.localizedString(for: d, relativeTo: Date())
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = card.bounds
        card.layer?.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: 7, cornerHeight: 7, transform: nil)
        CATransaction.commit()
    }

    private func refresh() {
        imageLayer.borderWidth = isCurrent ? 2 : 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            imageLayer.borderColor = (isCurrent ? Palette.accent : hovering ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
        caption.textColor = isCurrent ? Palette.accent : .tertiaryLabelColor
        // Hover lifts the card a little with a deeper shadow.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.allowsImplicitAnimation = true
            card.layer?.transform = hovering ? CATransform3DMakeTranslation(0, 3, 0) : CATransform3DIdentity
            card.layer?.shadowOpacity = hovering ? 0.35 : 0.22
            card.layer?.shadowRadius = hovering ? 7 : 4
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onSelect(url) }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Edit Here", action: #selector(open), keyEquivalent: "").target = self
        m.addItem(withTitle: "Open in New Window", action: #selector(openNewWindow), keyEquivalent: "").target = self
        m.addItem(withTitle: "Copy Image", action: #selector(copyImage), keyEquivalent: "").target = self
        m.addItem(withTitle: "Show in Finder", action: #selector(reveal), keyEquivalent: "").target = self
        return m
    }

    @objc private func open() { onSelect(url) }
    @objc private func openNewWindow() { AppLogic.shared.openFile(url) }

    @objc private func copyImage() {
        guard let loaded = EditableFile.load(url), let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rendered = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        Exporter.copy(rendered, scale: loaded.scale)
        Toast.show("Copied to the clipboard")
    }

    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}

/// "Older…" tile at the end of the strip: a dashed card that opens the folder picker.
private final class BrowseTile: NSView {
    private let action: () -> Void
    private let dash = CAShapeLayer()
    private var hovering = false { didSet { refresh() } }

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        dash.fillColor = nil
        dash.lineWidth = 1.2
        dash.lineDashPattern = [4, 3]
        layer?.addSublayer(dash)
        toolTip = "Open an older screenshot from the Screenshots folder"
        let icon = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: "Open folder")!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))!)
        icon.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: "Older…")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .tertiaryLabelColor
        for v in [icon, label] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 56), heightAnchor.constraint(equalToConstant: 66),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor), icon.centerYAnchor.constraint(equalTo: topAnchor, constant: 24),
            label.centerXAnchor.constraint(equalTo: centerXAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let r = CGRect(x: 0.6, y: bounds.height - 48.6, width: bounds.width - 1.2, height: 48)
        dash.path = CGPath(roundedRect: r, cornerWidth: 7, cornerHeight: 7, transform: nil)
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dash.strokeColor = (hovering ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor
            dash.fillColor = (hovering ? Theme.hover : NSColor.clear).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { action() }
}
