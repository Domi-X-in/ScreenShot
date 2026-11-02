import AppKit
import ImageIO
import Vision

/// A support window of the editor (R15), Shottr's screenshot Library: every image in the
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
    /// The grid's sections: Today, Yesterday, Earlier this week…
    private var sections: [(title: String, items: [LibraryItem])] = []
    private let index = TextIndex.shared

    init() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 760),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "Library"
        // The cards draw the title bar; an empty unified toolbar centers the window's buttons on the title card.
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        win.toolbarStyle = .unified
        win.toolbar = NSToolbar(identifier: "library")
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
        sections = LibraryItem.sections(shown)
        countLabel.stringValue = q.isEmpty ? "\(all.count) screenshots" : "\(shown.count) of \(all.count)"
        collection.reloadData()
    }

    // MARK: Layout

    /// Cards on the window's background: the title card, a ribbon-style bar and the day-grouped grid.
    private func build() {
        guard let win = window else { return }
        let content = CanvasBackground()
        win.contentView = content
        let m = DesignTokens.Metrics.self

        // Open · Search · Thumbnail size, as ribbon groups.
        func large(_ id: String, _ title: String, _ icon: IconName, action: @escaping () -> Void) -> RibbonItem {
            RibbonItem(id, kind: .large, title: title, icon: icon, action: action)
        }
        let open = RibbonGroupView(RibbonGroup("open", title: "Open", compactTitle: "Open", compactIcon: .openImage, columns: [
            .large(large("openImage", "Open Image", .openImage) { AppLogic.shared.chooseFile() }),
            .large(large("folder", "Show Folder", .folder) { NSWorkspace.shared.open(Settings.saveFolder) }),
        ]))

        search.placeholderString = "Search names, dates and text in screenshots"
        search.delegate = self
        search.setAccessibilityLabel("Search screenshots")
        countLabel.font = DesignTokens.Font.caption
        countLabel.textColor = DesignTokens.color(.ink3)
        let searchStack = NSStackView(views: [search, countLabel])
        searchStack.orientation = .vertical
        searchStack.alignment = .leading
        searchStack.spacing = 6
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        let searchGroup = LibraryToolbarGroup(title: "Search", content: searchStack, flexible: true)

        sizeSlider.controlSize = .small
        sizeSlider.trackFillColor = DesignTokens.color(.accent)
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.doubleValue = UserDefaults.standard.double(forKey: "libraryThumbSize").nonZero ?? 220
        sizeSlider.toolTip = "Thumbnail size"
        sizeSlider.setAccessibilityLabel("Thumbnail size")
        sizeSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let small = NSImageView(image: Icons.image(.photo, size: 12)), big = NSImageView(image: Icons.image(.photo, size: 18))
        for i in [small, big] { i.contentTintColor = DesignTokens.color(.ink3) }
        let sizeRow = NSStackView(views: [small, sizeSlider, big])
        sizeRow.spacing = 8
        let sizeGroup = LibraryToolbarGroup(title: "Thumbnail size", content: sizeRow, flexible: false)

        var bar: [NSView] = []
        for (i, g) in ([open, searchGroup, sizeGroup] as [NSView]).enumerated() {
            if i > 0 { bar.append(LibraryToolbarGroup.divider()) }
            if let gv = g as? RibbonGroupView {
                gv.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([gv.widthAnchor.constraint(equalToConstant: gv.frame.width),
                                             gv.heightAnchor.constraint(equalToConstant: m.ribbonHeight)])
            }
            bar.append(g)
        }
        let row = NSStackView(views: bar)
        row.spacing = 0
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        // The grid: sections with a day header, the new cells, no background of its own.
        layout.minimumInteritemSpacing = 18
        layout.minimumLineSpacing = 18
        layout.sectionInset = NSEdgeInsets(top: 4, left: 16, bottom: 18, right: 16)
        layout.headerReferenceSize = NSSize(width: 0, height: 40)
        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.backgroundColors = [.clear]
        collection.register(LibraryCell.self, forItemWithIdentifier: LibraryCell.id)
        collection.register(LibrarySectionHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                            withIdentifier: LibrarySectionHeader.id)
        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let title = WindowTitleCard(title: "Library"), toolbar = CardView(), grid = CardView()
        toolbar.embed(row)
        grid.embed(scroll)
        for v in [title, toolbar, grid] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
            NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m.cardInset),
                                         v.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m.cardInset)])
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: m.titleCardTop),
            title.heightAnchor.constraint(equalToConstant: m.titleBarHeight),
            toolbar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: m.cardGap),
            toolbar.heightAnchor.constraint(equalToConstant: m.ribbonHeight),
            grid.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: m.cardGap),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m.cardInset),
        ])
        win.minSize = NSSize(width: 900, height: 480)
        applySize()
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: LibrarySectionHeader.id, for: indexPath) as! LibrarySectionHeader
        if indexPath.section < sections.count {
            let s = sections[indexPath.section]
            header.show(title: s.title, count: s.items.count)
        }
        return header
    }

    #if SCREENSHOT_SELFTESTS
    /// How many screenshots the grid shows now, across its sections.
    var debugShownCount: Int { shown.count }
    var debugSectionTitles: [String] { sections.map(\.title) }
    func debugOpen(at indexPath: IndexPath) { collectionView(collection, didSelectItemsAt: [indexPath]) }
    #endif

    func controlTextDidChange(_ obj: Notification) { filter() }

    @objc private func sizeChanged() {
        UserDefaults.standard.set(sizeSlider.doubleValue, forKey: "libraryThumbSize")
        applySize()
    }

    private func applySize() {
        let w = CGFloat(sizeSlider.doubleValue)
        // A name and a size/time line under the picture.
        layout.itemSize = NSSize(width: w, height: (w * 0.62 + 52).rounded())
        layout.invalidateLayout()
    }

    // MARK: Collection view

    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        section < sections.count ? sections[section].items.count : 0
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: LibraryCell.id, for: indexPath) as! LibraryCell
        if indexPath.section < sections.count, indexPath.item < sections[indexPath.section].items.count {
            cell.configure(sections[indexPath.section].items[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let p = indexPaths.first, p.section < sections.count, p.item < sections[p.section].items.count else { return }
        collectionView.deselectAll(nil)
        let url = sections[p.section].items[p.item].url
        AppLogic.shared.openFile(url)
        // Its job is done; a file that couldn't be read leaves it open, with the error.
        if AppLogic.shared.editor?.doc.fileURL?.standardizedFileURL == url.standardizedFileURL { window?.close() }
    }
}

/// One file in the library.
struct LibraryItem: Sendable {
    let url: URL
    let date: Date

    /// The Library's day groups, newest first: Today, Yesterday, Earlier this week, Earlier this month, then one
    /// per month ("September 2026"). `items` is newest first; empty groups are left out.
    static func sections(_ items: [LibraryItem], now: Date = Date(), calendar: Calendar = .current) -> [(title: String, items: [LibraryItem])] {
        let monthFormat = DateFormatter()
        monthFormat.calendar = calendar
        monthFormat.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        func title(_ d: Date) -> String {
            if calendar.isDate(d, inSameDayAs: now) { return "Today" }
            if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) { return "Yesterday" }
            if d < now, calendar.isDate(d, equalTo: now, toGranularity: .weekOfYear) { return "Earlier this week" }
            if d < now, calendar.isDate(d, equalTo: now, toGranularity: .month) { return "Earlier this month" }
            return monthFormat.string(from: d)
        }
        var out: [(title: String, items: [LibraryItem])] = []
        for item in items {
            let t = title(item.date)
            if out.last?.title == t { out[out.count - 1].items.append(item) } else { out.append((t, [item])) }
        }
        return out
    }

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
        let haystack = [url.lastPathComponent, Self.searchDate.string(from: date), Self.localDate.string(from: date), text ?? ""].joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    private static let searchDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd MMMM EEEE"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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
        return entries[Self.key(url)]?.text
    }

    /// One key per file however its path is spelled (/var/… and /private/var/… are the same folder).
    static func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Recognizes text in files that are new or changed since they were last indexed, newest first.
    /// Files waiting to be read, newest first. Files that arrive while a pass is running join the queue, so a screenshot
    /// taken during indexing is still read (it used to be skipped until the next time the window opened).
    private var queue: [URL] = []

    @MainActor func indexInBackground(_ urls: [URL]) {
        DispatchQueue.global(qos: .utility).async { [self] in
            prune()
            // One file-system look per file, so never on the main thread or holding the lock.
            let dates = urls.map { ($0, modified($0)) }
            lock.lock()
            let waiting = Set(queue)
            let todo = dates.filter { u, date in entries[Self.key(u)]?.modified != date && !waiting.contains(u) }.map(\.0)
            queue = todo + queue
            let start = !running && !queue.isEmpty
            if start { running = true }
            lock.unlock()
            guard start else { return }
            var done = 0
            while true {
                lock.lock()
                guard !queue.isEmpty else { running = false; lock.unlock(); break }
                let url = queue.removeFirst()
                lock.unlock()
                let text = Self.recognize(url) ?? ""
                lock.lock()
                entries[Self.key(url)] = Entry(modified: modified(url), text: text)
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
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), ImageLimits.allows(src) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let req = VNRecognizeTextRequest()
        // Accurate, not fast: it runs in the background once per file, and search is only as good as what it reads.
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        VisionGate.perform([req], on: img, background: true)
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    /// Forgets the text of files that no longer exist: deleting a screenshot deletes what was read from it.
    func prune() {
        lock.lock()
        let paths = Array(entries.keys)
        lock.unlock()
        let gone = paths.filter { !FileManager.default.fileExists(atPath: $0) }
        guard !gone.isEmpty else { return }
        lock.lock()
        gone.forEach { entries[$0] = nil }
        lock.unlock()
        save()
    }

    /// Preferences › Advanced: everything read so far goes; the Library reads the files again when it next opens.
    func clear() {
        lock.lock()
        entries.removeAll()
        queue.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: file)
    }

    private func save() {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
            // It holds what the screenshots say: only the owner reads it.
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            Log.files.error("Could not save the search index: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// A thumbnail with the file's name, pixel size and time under it.
final class LibraryCell: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("LibraryCell")
    private static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 500
        return c
    }()
    /// Thumbnails read a few at a time, however fast the grid scrolls.
    private static let thumbnails: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .userInitiated
        return q
    }()
    private let thumb = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    /// The second line: pixel size and time.
    private let meta = NSTextField(labelWithString: "")
    private static let sizes = NSCache<NSURL, NSValue>()
    private var url: URL?

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 7
        thumb.layer?.masksToBounds = true
        thumb.layer?.borderWidth = 1
        thumb.layer?.borderColor = DesignTokens.color(.line).cgColor
        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.textColor = DesignTokens.color(.ink)
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingMiddle
        // The picture gives way to the caption, never the other way round.
        thumb.setContentCompressionResistancePriority(.init(1), for: .vertical)
        thumb.setContentHuggingPriority(.init(1), for: .vertical)
        caption.setContentCompressionResistancePriority(.required, for: .vertical)
        meta.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        meta.textColor = DesignTokens.color(.ink3)
        meta.lineBreakMode = .byTruncatingTail
        meta.setContentCompressionResistancePriority(.required, for: .vertical)
        let text = NSStackView(views: [caption, meta])
        text.orientation = .vertical
        text.spacing = 2
        text.alignment = .centerX
        for s in [thumb, text] as [NSView] {
            s.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(s)
        }
        NSLayoutConstraint.activate([
            thumb.topAnchor.constraint(equalTo: v.topAnchor), thumb.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            thumb.trailingAnchor.constraint(equalTo: v.trailingAnchor), thumb.bottomAnchor.constraint(equalTo: text.topAnchor, constant: -6),
            text.leadingAnchor.constraint(equalTo: v.leadingAnchor), text.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            text.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
            caption.widthAnchor.constraint(lessThanOrEqualTo: v.widthAnchor), meta.widthAnchor.constraint(lessThanOrEqualTo: v.widthAnchor),
        ])
        view = v
    }

    func configure(_ item: LibraryItem) {
        url = item.url
        // Name, then "1520 × 950 · 10:42".
        caption.stringValue = item.url.deletingPathExtension().lastPathComponent
        let time = item.date.formatted(date: .omitted, time: .shortened)
        if let s = Self.sizes.object(forKey: item.url as NSURL)?.sizeValue {
            meta.stringValue = "\(Int(s.width)) × \(Int(s.height)) · \(time)"
        } else {
            meta.stringValue = time
        }
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
        Self.thumbnails.addOperation {
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), ImageLimits.allows(src) else { return }
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            let pixels = (props?[kCGImagePropertyPixelWidth] as? Int).flatMap { w in (props?[kCGImagePropertyPixelHeight] as? Int).map { CGSize(width: w, height: $0) } }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 680,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return }
            DispatchQueue.main.async {
                let img = NSImage(cgImage: cg, size: .zero)
                Self.cache.setObject(img, forKey: u as NSURL)
                if let pixels { Self.sizes.setObject(NSValue(size: pixels), forKey: u as NSURL) }
                if self.url == u {
                    self.thumb.image = img
                    if let pixels {
                        self.meta.stringValue = "\(Int(pixels.width)) × \(Int(pixels.height)) · " + item.date.formatted(date: .omitted, time: .shortened)
                    }
                }
            }
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

/// A day header in the Library's grid: "Today  5 screenshots".
final class LibrarySectionHeader: NSView, NSCollectionViewElement {
    static let id = NSUserInterfaceItemIdentifier("LibrarySectionHeader")
    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = DesignTokens.color(.ink)
        count.font = .systemFont(ofSize: 11.5)
        count.textColor = DesignTokens.color(.ink3)
        let row = NSStackView(views: [title, count])
        row.spacing = 10
        row.alignment = .firstBaseline
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                                     row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(title t: String, count n: Int) {
        title.stringValue = t
        count.stringValue = n == 1 ? "1 screenshot" : "\(n) screenshots"
        setAccessibilityLabel("\(t), \(count.stringValue)")
    }
}

/// A non-ribbon group in the Library's bar (Search, Thumbnail size): its content and its title underneath.
final class LibraryToolbarGroup: NSView {
    init(title: String, content: NSView, flexible: Bool) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: title)
        label.font = DesignTokens.Font.groupLabel
        label.textColor = DesignTokens.color(.ink3)
        for v in [content, label] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.ribbonHeight),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: topAnchor, constant: 38),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
        setContentHuggingPriority(flexible ? .init(1) : .required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// A hairline between groups, like the ribbon's.
    static func divider() -> NSView {
        let v = NSBox()
        v.boxType = .custom
        v.borderWidth = 0
        v.fillColor = DesignTokens.color(.line)
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 1), v.heightAnchor.constraint(equalToConstant: 76)])
        return v
    }
}
