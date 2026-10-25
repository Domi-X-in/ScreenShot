import AppKit

private typealias DT = DesignTokens

/// One run of choices in the side bar (Arrow heads, Weight…), drawn with a divider before it.
struct OptionSection {
    let id: String
    let title: String
    let items: [RibbonItem]
}

/// What the side bar offers (ROADMAP, Fase 6 · R10): everything that belongs to one kind of shape — its style choices,
/// its size and its mode — for the tool in hand or the selected objects. The ribbon keeps what applies across shapes.
/// Right-click a choice to make it the default for new objects.
@MainActor final class ShapeOptions {
    private weak var editor: EditorWindowController?
    private var shotView: ShotView? { editor?.shotView }

    static let counterSizes: [(String, String, CGFloat)] = [("S", "Small", 2), ("M", "Medium", 4), ("L", "Large", 6), ("XL", "Extra Large", 9)]
    static let weights: [CGFloat] = RibbonFormatting.weights

    let callouts: [RibbonItem], heads: [RibbonItem], dashes: [DashStyle: RibbonItem], weight: RibbonItem
    let counterShapes: [RibbonItem], counterSizes: [RibbonItem], blurModes: [RibbonItem]
    let lenses: [RibbonItem], zooms: [RibbonItem], units: [RibbonItem]
    let crop: RibbonItem, cutOut: RibbonItem, autoadjust: RibbonItem, imprint: RibbonItem
    let copyArea: RibbonItem, readArea: RibbonItem, cropArea: RibbonItem, blurArea: RibbonItem
    /// Choices that follow one setting of the style: lit when it has their value.
    private var choices: [(RibbonItem, (ToolStyle) -> Bool)] = []

    init(editor: EditorWindowController) {
        self.editor = editor
        var choices: [(RibbonItem, (ToolStyle) -> Bool)] = []
        func choice<T: Equatable>(_ id: String, _ title: String, _ icon: IconName?, glyph: String? = nil, _ value: T,
                                  _ key: WritableKeyPath<ToolStyle, T>) -> RibbonItem {
            let item = RibbonItem(id, kind: .small, title: title, icon: icon)
            item.glyph = glyph
            item.action = { [weak editor] in
                guard let v = editor?.shotView else { return }
                var s = v.displayedStyle
                s[keyPath: key] = value
                v.setStyle(s)
                editor?.syncToolbar()
            }
            item.contextMenu = { [weak item] in
                Self.defaultsMenu(title, isDefault: ToolStyle.loadDefaults()[keyPath: key] == value, set: { $0[keyPath: key] = value },
                                  reset: { $0[keyPath: key] = ToolStyle()[keyPath: key] }, then: { item?.action?() })
            }
            choices.append((item, { $0[keyPath: key] == value }))
            return item
        }
        let calloutIcons: [CalloutStyle: IconName] = [.box: .calloutBox, .card: .calloutCard, .speech: .calloutSpeech,
                                                      .thought: .calloutThought, .shout: .calloutShout]
        callouts = CalloutStyle.allCases.map { choice("callout.\($0.rawValue)", $0.title, calloutIcons[$0], $0, \.callout) }
        let headIcons: [ArrowStyle: IconName] = [.tapered: .arrowFilled, .line: .arrowEnd, .double: .arrowBoth]
        heads = ArrowStyle.allCases.map { choice("arrow.\($0.rawValue)", $0.title, headIcons[$0], $0, \.arrow) }
        let counterIcons: [CounterShape: IconName] = [.circle: .counter, .square: .counterSquare, .bubble: .counterBubble]
        counterShapes = CounterShape.allCases.map { choice("counter.\($0.rawValue)", $0.title, counterIcons[$0], $0, \.counterShape) }
        counterSizes = Self.counterSizes.map { choice("counterSize.\($0.0)", "Size: \($0.1)", nil, glyph: $0.0, $0.2, \.width) }
        let blurIcons: [BlurMode: IconName] = [.blur: .blur, .blurText: .blurText, .erase: .erase, .eraseText: .eraseText]
        blurModes = BlurMode.allCases.map { choice("blur.\($0.rawValue)", $0.title, blurIcons[$0], $0, \.blur) }
        lenses = LensShape.allCases.map { choice("lens.\($0.rawValue)", "\($0.title) Lens", $0 == .oval ? .oval : .rect, $0, \.lensShape) }
        zooms = RibbonFormatting.zoomSteps.map { choice("zoom.\($0)", "Zoom \($0.formatted())×", nil, glyph: "\($0.formatted())×", $0, \.magnification) }
        units = [false, true].map { choice("units.\($0)", $0 ? "Points (pt)" : "Pixels (px)", nil, glyph: $0 ? "pt" : "px", $0, \.rulerInPoints) }
        self.choices = choices

        let dashIcons: [DashStyle: IconName] = [.solid: .lineSolid, .dashed: .lineDash, .handDrawn: .freehand]
        var dashes: [DashStyle: RibbonItem] = [:]
        for d in DashStyle.allCases {
            let item = RibbonItem("dash.\(d)", kind: .small, title: d.title, icon: dashIcons[d])
            item.action = { [weak editor] in editor?.shotView.applyDash(d); editor?.syncToolbar() }
            item.contextMenu = { [weak item] in
                Self.defaultsMenu(d.title, isDefault: DashStyle(dashed: ToolStyle.loadDefaults().dashed, sketch: ToolStyle.loadDefaults().sketch) == d,
                                  set: { $0.dashed = d == .dashed; $0.sketch = d == .handDrawn }, reset: { $0.dashed = false; $0.sketch = false },
                                  then: { item?.action?() })
            }
            dashes[d] = item
        }
        self.dashes = dashes

        weight = RibbonItem("weight", kind: .small, title: "Weight", icon: .weight)
        weight.menu = { [weak editor] in
            let m = NSMenu(title: "Weight")
            guard let v = editor?.shotView else { return m }
            let st = v.shapeStyleState
            for w in Self.weights {
                let item = ClosureMenuItem("\(Int(w)) px", checked: st.weight == w) { [weak v] in v?.applyOutlineWeight(w); editor?.syncToolbar() }
                item.image = RibbonFormatting.lineSample(width: w)
                m.addItem(item)
            }
            m.addItem(.separator())
            m.addItem(ClosureMenuItem("Set as Default Weight") {
                let w = v.displayedStyle.width
                ToolStyle.updateDefaults { $0.width = w }
                Toast.show("Weight \(Int(w)) px is now the default")
            })
            return m
        }

        crop = RibbonItem("crop.crop", kind: .small, title: "Crop: keep the selected area", icon: .crop)
        cutOut = RibbonItem("crop.cutOut", kind: .small, title: "Cut Out: remove a strip and join the rest", icon: .cut)
        autoadjust = RibbonItem("crop.autoadjust", kind: .small, title: "Autoadjust", icon: .capArea)
        autoadjust.shortcut = "F"
        imprint = RibbonItem("crop.imprint", kind: .small, title: "Imprint Size", icon: .ruler)
        imprint.shortcut = "I"
        copyArea = RibbonItem("area.copy", kind: .small, title: "Copy Area", icon: .copy)
        copyArea.shortcut = "⌘C"
        readArea = RibbonItem("area.read", kind: .small, title: "Read Text", icon: .ocr)
        readArea.shortcut = "⌘O"
        cropArea = RibbonItem("area.crop", kind: .small, title: "Crop to Area", icon: .crop)
        blurArea = RibbonItem("area.blur", kind: .small, title: "Blur Area", icon: .blur)
        crop.action = { [weak self] in self?.setCutOut(false) }
        cutOut.action = { [weak self] in self?.setCutOut(true) }
        autoadjust.action = { [weak editor] in editor?.shotView.autoadjustSelection() }
        imprint.action = { [weak editor] in editor?.shotView.imprintSelectionSize() }
        copyArea.action = { [weak editor] in editor?.shotView.copyArea() }
        readArea.action = { [weak editor] in editor?.ocrImage() }
        cropArea.action = { [weak editor] in editor?.shotView.cropToArea() }
        blurArea.action = { [weak editor] in editor?.shotView.blurArea() }
    }

    private func setCutOut(_ on: Bool) {
        guard let v = shotView else { return }
        v.cutOutMode = on
        v.window?.makeFirstResponder(v)
        editor?.syncToolbar()
    }

    /// Right-click on a choice: make it the default for new objects (and pick it now), or go back to the built-in one.
    static func defaultsMenu(_ title: String, isDefault: Bool, set: @escaping (inout ToolStyle) -> Void,
                             reset: @escaping (inout ToolStyle) -> Void, then pick: @escaping () -> Void) -> NSMenu {
        let m = NSMenu(title: "Default")
        m.addItem(ClosureMenuItem("Set “\(title)” as Default", checked: isDefault) {
            ToolStyle.updateDefaults(set)
            pick()
            Toast.show("“\(title)” is now the default")
        })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem("Reset to Original Default") { ToolStyle.updateDefaults(reset) })
        return m
    }

    // MARK: What to show

    /// The sections for one kind of object.
    private func sections(for kind: Tool) -> [OptionSection] {
        let weight = OptionSection(id: "weight", title: "Weight", items: [self.weight])
        func line(_ styles: [DashStyle]) -> OptionSection {
            OptionSection(id: "dash", title: "Line Style", items: styles.compactMap { dashes[$0] })
        }
        return switch kind {
        case .arrow: [OptionSection(id: "heads", title: "Arrow Heads", items: heads), line([.solid, .handDrawn]), weight]
        case .line, .rect, .oval: [line(DashStyle.allCases), weight]
        case .freehand: [weight]
        case .counter: [OptionSection(id: "counterShape", title: "Counter Shape", items: counterShapes),
                        OptionSection(id: "counterSize", title: "Counter Size", items: counterSizes)]
        case .callout: [OptionSection(id: "callout", title: "Callout Design", items: callouts)]
        case .blur: [OptionSection(id: "blur", title: "Blur Mode", items: blurModes)]
        case .magnifier: [OptionSection(id: "lens", title: "Lens", items: lenses), OptionSection(id: "zoom", title: "Zoom", items: zooms), weight]
        case .ruler: [OptionSection(id: "units", title: "Units", items: units), weight]
        default: []
        }
    }

    /// The tool in hand, or what the selected objects share (an arrow and a line together show just Line Style and
    /// Weight, with only the line styles both can take).
    func sections() -> [OptionSection] {
        guard let v = shotView else { return [] }
        let targets = v.styleTargets
        if targets.isEmpty {
            if v.tool == .crop {
                return v.selectingArea
                    ? [OptionSection(id: "area", title: "Selection", items: [copyArea, readArea, cropArea, blurArea])]
                    : [OptionSection(id: "cropMode", title: "Crop Mode", items: [crop, cutOut]),
                       OptionSection(id: "cropTools", title: "Crop Tools", items: [autoadjust, imprint])]
            }
            return sections(for: v.tool)
        }
        var shared: [OptionSection]?
        for kind in Set(targets.map(\.kind)) {
            let mine = sections(for: kind)
            guard let so = shared else { shared = mine; continue }
            shared = so.compactMap { s in
                guard let other = mine.first(where: { $0.id == s.id }) else { return nil }
                let items = s.items.filter { i in other.items.contains { $0 === i } }
                return items.isEmpty ? nil : OptionSection(id: s.id, title: s.title, items: items)
            }
        }
        return shared ?? []
    }

    /// Lights the current choices and turns off what doesn't apply.
    func update() {
        guard let v = shotView else { return }
        let style = v.displayedStyle
        for (item, current) in choices { item.isOn = current(style) }
        let st = v.shapeStyleState
        for (d, item) in dashes {
            item.isOn = st.dash == d
            item.isEnabled = d == .dashed ? st.dashEnabled : st.sketchEnabled
        }
        weight.isEnabled = st.weightEnabled
        crop.isOn = !v.cutOutMode
        cutOut.isOn = v.cutOutMode
        autoadjust.isEnabled = !v.cutOutMode
        imprint.isEnabled = !v.cutOutMode
        let hasArea = v.cropSelection != nil
        for i in [copyArea, readArea, cropArea, blurArea] { i.isEnabled = hasArea }
    }
}

/// The side bar (R5b, R10): a narrow card beside the canvas with the options of the tool in hand or the selection, in
/// sections divided by hairlines. Hidden when there is nothing to show; the canvas takes its room.
final class ShapeOptionsBar: CardView {
    private let column = NSStackView()
    private(set) var sections: [OptionSection] = []

    override init() {
        super.init()
        column.orientation = .vertical
        column.spacing = 4
        column.alignment = .centerX
        column.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Shape options")
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Rebuilds the buttons when the sections change (the same items keep their buttons otherwise).
    func show(_ new: [OptionSection]) {
        let same = new.count == sections.count && zip(new, sections).allSatisfy { a, b in
            a.id == b.id && a.items.count == b.items.count && zip(a.items, b.items).allSatisfy { $0 === $1 }
        }
        guard !same else { return }
        sections = new
        for v in column.arrangedSubviews { column.removeArrangedSubview(v); v.removeFromSuperview() }
        for (i, section) in new.enumerated() {
            if i > 0 { column.addArrangedSubview(Self.divider()) }
            for item in section.items {
                let b = RibbonButton(item)
                b.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: item.hasChevron ? 40 : 32),
                                             b.heightAnchor.constraint(equalToConstant: 32)])
                b.setAccessibilityLabel(item.title)
                b.toolTip = item.shortcut.map { "\(section.title): \(item.title) (\($0))" } ?? "\(section.title): \(item.title)"
                column.addArrangedSubview(b)
            }
        }
    }

    /// The buttons on show, for tests.
    var buttons: [RibbonButton] { column.arrangedSubviews.compactMap { $0 as? RibbonButton } }

    private static func divider() -> NSView {
        let v = Hairline()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 24), v.heightAnchor.constraint(equalToConstant: 1)])
        return v
    }

    private final class Hairline: NSView {
        override func draw(_ dirtyRect: NSRect) { DT.color(.line).setFill(); bounds.fill() }
    }
}
