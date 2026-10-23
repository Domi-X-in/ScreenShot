import AppKit
import ImageIO
import Vision

/// The app's home window ("Open ScreenShot") and Shottr's screenshot Library: capture buttons, then every image in the
/// Screenshots folder, newest first, with search (file name, date and the text inside the screenshot) and adjustable
/// thumbnail size. Clicking one opens it in the editor.
@MainActor final class LibraryWindowController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSSearchFieldDelegate {
    static var shared: LibraryWindowController?

    static func show() {
        if shared == nil { shared = LibraryWindowController() }
        NSApp.activate()
        shared?.reload()
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    private let collection = NSCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private let search = NSSearchField()
    private let sizeSlider = NSSlider(value: 180, minValue: 110, maxValue: 340, target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private var all: [LibraryItem] = []
    private var shown: [LibraryItem] = []
    private let index = TextIndex.shared

    init() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "ScreenShot"
        win.minSize = NSSize(width: 820, height: 380)
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("ScreenShotLibrary")
        super.init(window: win)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .screenshotSaved, object: nil)
        index.onUpdate = { [weak self] in self?.filter() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        search.placeholderString = "Search names, dates and text in screenshots"
        search.delegate = self
        search.setAccessibilityLabel("Search screenshots")
        sizeSlider.controlSize = .small
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.doubleValue = UserDefaults.standard.double(forKey: "libraryThumbSize").nonZero ?? 180
        sizeSlider.toolTip = "Thumbnail size"
        sizeSlider.setAccessibilityLabel("Thumbnail size")
        sizeSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 12)
        let small = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!)
        let big = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))!)
        for i in [small, big] { i.contentTintColor = .secondaryLabelColor }
        // Captures start from here too, so the window works as the app's home. Captures leave the app's own windows out.
        let captures = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Area")!,
            NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Window")!,
            NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: "Fullscreen")!,
        ], trackingMode: .momentary, target: self, action: #selector(capture(_:)))
        for (i, (label, action)) in [("Area", HotkeyAction.area), ("Window", .anyWindow), ("Fullscreen", .fullscreen)].enumerated() {
            captures.setLabel(label, forSegment: i)
            captures.setImageScaling(.scaleProportionallyDown, forSegment: i)
            let keys = HotKeyCenter.shared.shortcut(for: action).map { " (\($0.display))" } ?? ""
            captures.setToolTip("\(label) screenshot\(keys)", forSegment: i)
        }
        captures.setAccessibilityLabel("Take a screenshot")
        func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
            b.bezelStyle = .rounded
            b.toolTip = tip
            return b
        }
        let finder = iconButton("folder", "Show the Screenshots folder in Finder", #selector(showFolder))
        let other = iconButton("doc.badge.plus", "Open another image…", #selector(openOther))
        let prefs = iconButton("gearshape", "Preferences…", #selector(openPreferences))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [captures, search, countLabel, spacer, small, sizeSlider, big, finder, other, prefs])
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 18
        layout.sectionInset = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.backgroundColors = [Theme.dynamic(light: NSColor(hex: 0xF4F5F8), dark: NSColor(hex: 0x1D1E24))]
        collection.register(LibraryCell.self, forItemWithIdentifier: LibraryCell.id)
        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true

        for v in [bar, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor), bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        applySize()
    }

    @objc func reload() {
        let folder = Settings.saveFolder
        Task.detached(priority: .userInitiated) {
            let items = LibraryItem.list(in: folder)
            await MainActor.run {
                self.all = items
                self.filter()
                self.index.indexInBackground(items.map(\.url))
            }
        }
    }

    private func filter() {
        let q = search.stringValue
        shown = all.filter { $0.matches(q, text: index.text(for: $0.url)) }
        countLabel.stringValue = q.isEmpty ? "\(all.count) screenshots" : "\(shown.count) of \(all.count)"
        collection.reloadData()
    }

    func controlTextDidChange(_ obj: Notification) { filter() }

    @objc private func sizeChanged() {
        UserDefaults.standard.set(sizeSlider.doubleValue, forKey: "libraryThumbSize")
        applySize()
    }

    private func applySize() {
        let w = CGFloat(sizeSlider.doubleValue)
        layout.itemSize = NSSize(width: w, height: (w * 0.68 + 38).rounded())
        layout.invalidateLayout()
    }

    @objc private func showFolder() { NSWorkspace.shared.open(Settings.saveFolder) }

    @objc private func openOther() { AppLogic.shared.chooseFile() }

    @objc private func openPreferences() { (NSApp.delegate as? AppDelegate)?.showPreferences() }

    @objc private func capture(_ sender: NSSegmentedControl) {
        let actions: [HotkeyAction] = [.area, .anyWindow, .fullscreen]
        guard actions.indices.contains(sender.selectedSegment) else { return }
        AppLogic.shared.run(actions[sender.selectedSegment])
    }

    // MARK: Collection view

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { shown.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: LibraryCell.id, for: indexPath) as! LibraryCell
        cell.configure(shown[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let i = indexPaths.first?.item, i < shown.count else { return }
        collectionView.deselectAll(nil)
        AppLogic.shared.openFile(shown[i].url)
    }
}

/// One file in the library.
struct LibraryItem: Sendable {
    let url: URL
    let date: Date

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff"]

    static func list(in folder: URL) -> [LibraryItem] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        return files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .map { LibraryItem(url: $0, date: (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.date > $1.date }
    }

    /// Every word of the query must appear in the name, the date (e.g. "2026-10-21", "october") or the recognized text.
    func matches(_ query: String, text: String?) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd MMMM EEEE"
        f.locale = Locale(identifier: "en_US_POSIX")
        let haystack = [url.lastPathComponent, f.string(from: date), Self.localDate.string(from: date), text ?? ""].joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    private static let localDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()
}

/// Text recognized in each screenshot, cached on disk by path and modification date, so search works offline and fast.
final class TextIndex: @unchecked Sendable {
    static let shared = TextIndex()
    /// Called on the main thread whenever more files have been indexed.
    @MainActor var onUpdate: (() -> Void)?

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var running = false
    private let file: URL

    struct Entry: Codable {
        var modified: Date
        var text: String
    }

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ScreenShot/text-index.json")) {
        self.file = file
        if let d = try? Data(contentsOf: file), let e = try? JSONDecoder().decode([String: Entry].self, from: d) { entries = e }
    }

    func text(for url: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        return entries[url.path]?.text
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Recognizes text in files that are new or changed since they were last indexed, newest first.
    /// Files waiting to be read, newest first. Files that arrive while a pass is running join the queue, so a screenshot
    /// taken during indexing is still read (it used to be skipped until the next time the window opened).
    private var queue: [URL] = []

    @MainActor func indexInBackground(_ urls: [URL]) {
        lock.lock()
        let todo = urls.filter { u in entries[u.path]?.modified != modified(u) && !queue.contains(u) }
        queue = todo + queue
        let start = !running && !queue.isEmpty
        if start { running = true }
        lock.unlock()
        guard start else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            var done = 0
            while true {
                lock.lock()
                guard !queue.isEmpty else { running = false; lock.unlock(); break }
                let url = queue.removeFirst()
                lock.unlock()
                let text = Self.recognize(url) ?? ""
                lock.lock()
                entries[url.path] = Entry(modified: modified(url), text: text)
                let last = queue.isEmpty
                lock.unlock()
                done += 1
                if done % 8 == 0 || last {
                    save()
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.onUpdate?() } }
                }
            }
        }
    }

    static func recognize(_ url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let req = VNRecognizeTextRequest()
        // Accurate, not fast: it runs in the background once per file, and search is only as good as what it reads.
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        VisionGate.perform([req], on: img)
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func save() {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }
}

/// A thumbnail with the file's date under it.
final class LibraryCell: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("LibraryCell")
    private static let cache = NSCache<NSURL, NSImage>()
    private let thumb = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private var url: URL?

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 8
        thumb.layer?.masksToBounds = true
        thumb.layer?.borderWidth = 1
        thumb.layer?.borderColor = NSColor.separatorColor.cgColor
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingMiddle
        // The picture gives way to the caption, never the other way round.
        thumb.setContentCompressionResistancePriority(.init(1), for: .vertical)
        thumb.setContentHuggingPriority(.init(1), for: .vertical)
        caption.setContentCompressionResistancePriority(.required, for: .vertical)
        for s in [thumb, caption] as [NSView] {
            s.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(s)
        }
        NSLayoutConstraint.activate([
            thumb.topAnchor.constraint(equalTo: v.topAnchor), thumb.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            thumb.trailingAnchor.constraint(equalTo: v.trailingAnchor), thumb.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -6),
            caption.leadingAnchor.constraint(equalTo: v.leadingAnchor), caption.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
        ])
        view = v
    }

    func configure(_ item: LibraryItem) {
        url = item.url
        caption.stringValue = item.date.formatted(date: .abbreviated, time: .shortened)
        view.toolTip = item.url.lastPathComponent
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Screenshot \(item.url.deletingPathExtension().lastPathComponent)")
        if let img = Self.cache.object(forKey: item.url as NSURL) {
            thumb.image = img
            return
        }
        thumb.image = nil
        let u = item.url
        DispatchQueue.global(qos: .userInitiated).async {
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 680,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return }
            DispatchQueue.main.async {
                let img = NSImage(cgImage: cg, size: .zero)
                Self.cache.setObject(img, forKey: u as NSURL)
                if self.url == u { self.thumb.image = img }
            }
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
