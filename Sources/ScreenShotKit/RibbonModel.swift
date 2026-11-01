import AppKit

/// One command on the ribbon. The same item can be shown twice at once (in its group and in the group's flyout), so
/// the views read everything from here and redraw when it changes.
@MainActor final class RibbonItem {
    enum Kind: Equatable {
        /// 28 pt icon button (40 pt with a chevron).
        case small
        /// Icon and text in a row: Cut, Copy, Arrange…
        case label
        /// Big icon over a caption: Paste.
        case large
        /// A dropdown field showing its value: font name, font size.
        case field(width: CGFloat)
        /// Icon over a bar in the current color, with a chevron: Shape Fill, Font Color.
        case color
    }

    let id: String
    let kind: Kind
    /// Can change (Copy and Close follows its setting).
    var title: String { didSet { if title != oldValue { changed() } } }
    /// Can change (Align Text shows the current alignment).
    var icon: IconName? { didSet { if icon != oldValue { changed() } } }
    /// Runs on a click (on the main part, for a split button).
    var action: (() -> Void)?
    /// Builds the item's menu. With `split` the chevron opens it and the rest runs `action`; otherwise any click opens it.
    var menu: (() -> NSMenu)?
    var split = false
    /// The keyboard shortcut, shown in the tooltip ("Arrow (A)").
    var shortcut: String? { didSet { if shortcut != oldValue { changed() } } }
    var toolTipText: String { shortcut.map { "\(title) (\($0))" } ?? title }
    /// A large button shows its shortcut under its caption (the home window's capture buttons).
    var showsShortcut = false
    /// A field you can type in (Font Size): a click on its text opens an editor, Return sends what was typed here.
    var onTextEntry: ((String) -> Void)?
    /// A short text drawn in place of an icon on a small button ("2×", "px", "M"): choices that read better as text.
    var glyph: String?
    /// The right-click menu (the side bar's "Set as Default"); nil for none.
    var contextMenu: (() -> NSMenu?)?

    var isEnabled = true { didSet { if isEnabled != oldValue { changed() } } }
    /// A toggle that is on (Bold) or a choice that is current.
    var isOn = false { didSet { if isOn != oldValue { changed() } } }
    /// The tool in hand: drawn solid in the accent, and shown on its group's compact button.
    var isActiveTool = false { didSet { if isActiveTool != oldValue { changed() } } }
    /// A field's value.
    var text: String { didSet { if text != oldValue { changed() } } }
    /// A color button's bar; nil draws "none" (hatched).
    var barColor: NSColor? { didSet { if barColor != oldValue { changed() } } }

    weak var group: RibbonGroup?
    private let observers = NSHashTable<NSView>.weakObjects()

    init(_ id: String, kind: Kind, title: String, icon: IconName? = nil, text: String = "", barColor: NSColor? = nil,
         action: (() -> Void)? = nil, menu: (() -> NSMenu)? = nil, split: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.icon = icon
        self.text = text
        self.barColor = barColor
        self.action = action
        self.menu = menu
        self.split = split
    }

    var hasChevron: Bool { menu != nil }

    func observe(_ view: NSView) { observers.add(view) }

    private func changed() {
        for v in observers.allObjects { v.toolTip = toolTipText; v.needsDisplay = true; v.invalidateIntrinsicContentSize() }
        group?.itemChanged()
    }
}

/// One cell in a group's row: an item, or a short divider between items.
enum RibbonRowElement {
    case item(RibbonItem)
    case divider
}

/// A column of a group: one large button, or two (28 pt) or three (20 pt) rows of smaller items.
enum RibbonColumn {
    case large(RibbonItem)
    case rows([[RibbonRowElement]])
}

/// A titled group of the ribbon (Office's Clipboard, Font, Paragraph…). When the window is too narrow it folds into a
/// compact button with `compactTitle` and `compactIcon`, which opens the whole group in a flyout.
@MainActor final class RibbonGroup {
    let id: String
    let title: String
    let compactTitle: String
    let compactIcon: IconName
    let columns: [RibbonColumn]
    private let observers = NSHashTable<NSView>.weakObjects()
    /// A contextual group (Office's contextual tabs) shows only while its tool or object is in hand.
    var isHidden = false {
        didSet { if isHidden != oldValue { for v in observers.allObjects { v.needsLayout = true; v.needsDisplay = true } } }
    }

    init(_ id: String, title: String, compactTitle: String, compactIcon: IconName, columns: [RibbonColumn]) {
        self.id = id
        self.title = title
        self.compactTitle = compactTitle
        self.compactIcon = compactIcon
        self.columns = columns
        for item in items { item.group = self }
    }

    var items: [RibbonItem] {
        columns.flatMap { column -> [RibbonItem] in
            switch column {
            case let .large(item): return [item]
            case let .rows(rows): return rows.flatMap { $0.compactMap { if case let .item(i) = $0 { i } else { nil } } }
            }
        }
    }

    /// The tool in hand if it belongs to this group: the compact button shows it in the accent.
    var activeTool: RibbonItem? { items.first { $0.isActiveTool } }

    func observe(_ view: NSView) { observers.add(view) }

    func itemChanged() {
        for v in observers.allObjects { v.needsDisplay = true }
    }
}

/// How many groups fold, right to left, for the room available. Pure, so it is tested without views.
enum RibbonLayout {
    /// Width of a compact group button with its side padding.
    static let compactWidth: CGFloat = 68
    /// The divider after each expanded group that has something after it.
    static let divider: CGFloat = 1

    /// The width the ribbon needs with the last `collapsed` groups folded.
    static func width(full: [CGFloat], collapsed: Int) -> CGFloat {
        let n = full.count, c = max(0, min(n, collapsed))
        let expanded = full.prefix(n - c)
        let dividers = CGFloat(expanded.count - (c == 0 ? 1 : 0)).clamped(min: 0)
        return expanded.reduce(0, +) + dividers * divider + CGFloat(c) * compactWidth
    }

    /// The fewest folded groups that fit `available` (all of them when even that doesn't fit).
    static func collapsedCount(available: CGFloat, full: [CGFloat]) -> Int {
        for c in 0...full.count where width(full: full, collapsed: c) <= available { return c }
        return full.count
    }

    /// The widths at which each next group folds: `breakpoints[c]` is the least room for `c` folded groups.
    static func breakpoints(full: [CGFloat]) -> [CGFloat] {
        (0...full.count).map { width(full: full, collapsed: $0) }
    }
}

private extension CGFloat {
    func clamped(min lo: CGFloat) -> CGFloat { Swift.max(lo, self) }
}
