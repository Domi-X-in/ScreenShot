import AppKit

/// PowerPoint-style arrangement of the selected objects: align, distribute and stacking order.
enum ArrangeAction: String, CaseIterable {
    case alignLeft, alignCenter, alignRight, alignTop, alignMiddle, alignBottom
    case distributeHorizontally, distributeVertically
    case bringToFront, bringForward, sendBackward, sendToBack

    var title: String {
        switch self {
        case .alignLeft: "Align Left"
        case .alignCenter: "Align Center"
        case .alignRight: "Align Right"
        case .alignTop: "Align Top"
        case .alignMiddle: "Align Middle"
        case .alignBottom: "Align Bottom"
        case .distributeHorizontally: "Distribute Horizontally"
        case .distributeVertically: "Distribute Vertically"
        case .bringToFront: "Bring to Front"
        case .bringForward: "Bring Forward"
        case .sendBackward: "Send Backward"
        case .sendToBack: "Send to Back"
        }
    }

    var symbol: String {
        switch self {
        case .alignLeft: "align.horizontal.left"
        case .alignCenter: "align.horizontal.center"
        case .alignRight: "align.horizontal.right"
        case .alignTop: "align.vertical.top"
        case .alignMiddle: "align.vertical.center"
        case .alignBottom: "align.vertical.bottom"
        case .distributeHorizontally: "distribute.horizontal.center"
        case .distributeVertically: "distribute.vertical.center"
        case .bringToFront: "square.3.layers.3d.top.filled"
        case .bringForward: "square.2.layers.3d.top.filled"
        case .sendBackward: "square.2.layers.3d.bottom.filled"
        case .sendToBack: "square.3.layers.3d.bottom.filled"
        }
    }

    /// Keynote's shortcuts for stacking order (⇧⌘F / ⇧⌘B, with ⌥ for one step).
    var keyEquivalent: (String, NSEvent.ModifierFlags)? {
        switch self {
        case .bringToFront: ("f", [.command, .shift])
        case .bringForward: ("f", [.command, .shift, .option])
        case .sendBackward: ("b", [.command, .shift, .option])
        case .sendToBack: ("b", [.command, .shift])
        default: nil
        }
    }

    var isOrder: Bool { [.bringToFront, .bringForward, .sendBackward, .sendToBack].contains(self) }

    /// How many selected objects the action needs. One object aligns to the image, as PowerPoint aligns to the slide.
    var minimumSelection: Int {
        switch self {
        case .distributeHorizontally, .distributeVertically: 3
        default: 1
        }
    }

    static let alignments: [ArrangeAction] = [.alignLeft, .alignCenter, .alignRight, .alignTop, .alignMiddle, .alignBottom]
    static let distributions: [ArrangeAction] = [.distributeHorizontally, .distributeVertically]
    static let orders: [ArrangeAction] = [.bringToFront, .bringForward, .sendBackward, .sendToBack]
}

/// Menu items for the Arrange menu and the canvas's right-click menu; they act on the editor's selection.
@MainActor enum ArrangeMenu {
    static func item(_ a: ArrangeAction) -> NSMenuItem {
        let i = NSMenuItem(title: a.title, action: #selector(ShotView.arrangeFromMenu(_:)), keyEquivalent: a.keyEquivalent?.0 ?? "")
        if let (_, mods) = a.keyEquivalent { i.keyEquivalentModifierMask = mods }
        i.representedObject = a.rawValue
        i.image = NSImage(systemSymbolName: a.symbol, accessibilityDescription: nil)
        return i
    }

    static func items(includeSnap: Bool) -> [NSMenuItem] {
        var out = ArrangeAction.orders.map(item) + [.separator()]
        let align = NSMenuItem(title: "Align", action: nil, keyEquivalent: "")
        align.submenu = NSMenu(title: "Align")
        ArrangeAction.alignments.forEach { align.submenu?.addItem(item($0)) }
        let distribute = NSMenuItem(title: "Distribute", action: nil, keyEquivalent: "")
        distribute.submenu = NSMenu(title: "Distribute")
        ArrangeAction.distributions.forEach { distribute.submenu?.addItem(item($0)) }
        out += [align, distribute]
        if includeSnap {
            out += [.separator(), NSMenuItem(title: "Snap to Guides", action: #selector(ShotView.toggleSnapToGuides(_:)), keyEquivalent: "")]
        }
        return out
    }
}

enum Arrange {
    /// Applies `action` to the objects whose ids are in `selected`. `reference` is what a single object aligns to.
    static func apply(_ action: ArrangeAction, to objects: [Annotation], selected: Set<UUID>, reference: CGRect) -> [Annotation] {
        if action.isOrder { return reorder(objects, selected: selected, action) }
        var out = objects
        let idx = objects.indices.filter { selected.contains(objects[$0].id) }
        guard idx.count >= action.minimumSelection else { return objects }
        let boxes = idx.map { objects[$0].frame }
        let target = idx.count == 1 ? reference : boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }

        func move(_ i: Int, dx: CGFloat = 0, dy: CGFloat = 0) {
            guard dx != 0 || dy != 0 else { return }
            out[i].offset(by: CGVector(dx: dx, dy: dy))
            if out[i].kind == .blur { out[i].textRects = nil }
        }

        switch action {
        case .alignLeft: for (i, b) in zip(idx, boxes) { move(i, dx: target.minX - b.minX) }
        case .alignCenter: for (i, b) in zip(idx, boxes) { move(i, dx: target.midX - b.midX) }
        case .alignRight: for (i, b) in zip(idx, boxes) { move(i, dx: target.maxX - b.maxX) }
        case .alignTop: for (i, b) in zip(idx, boxes) { move(i, dy: target.minY - b.minY) }
        case .alignMiddle: for (i, b) in zip(idx, boxes) { move(i, dy: target.midY - b.midY) }
        case .alignBottom: for (i, b) in zip(idx, boxes) { move(i, dy: target.maxY - b.maxY) }
        case .distributeHorizontally, .distributeVertically:
            // Equal gaps between neighbors; the first and last objects stay where they are.
            let horizontal = action == .distributeHorizontally
            let order = zip(idx, boxes).sorted { horizontal ? $0.1.midX < $1.1.midX : $0.1.midY < $1.1.midY }
            let start = horizontal ? order.first!.1.minX : order.first!.1.minY
            let end = horizontal ? order.last!.1.maxX : order.last!.1.maxY
            let sizes = order.reduce(0) { $0 + (horizontal ? $1.1.width : $1.1.height) }
            let gap = (end - start - sizes) / CGFloat(order.count - 1)
            var cursor = start
            for (i, b) in order {
                if horizontal { move(i, dx: cursor - b.minX); cursor += b.width + gap } else { move(i, dy: cursor - b.minY); cursor += b.height + gap }
            }
        default: break
        }
        return out
    }

    /// Stacking order: later objects draw on top.
    private static func reorder(_ objects: [Annotation], selected: Set<UUID>, _ action: ArrangeAction) -> [Annotation] {
        let picked = objects.filter { selected.contains($0.id) }
        let rest = objects.filter { !selected.contains($0.id) }
        switch action {
        case .bringToFront: return rest + picked
        case .sendToBack: return picked + rest
        case .bringForward:
            // Each selected object swaps with the unselected one just above it.
            var out = objects
            for i in stride(from: out.count - 2, through: 0, by: -1) where selected.contains(out[i].id) && !selected.contains(out[i + 1].id) {
                out.swapAt(i, i + 1)
            }
            return out
        case .sendBackward:
            var out = objects
            for i in 1..<max(1, out.count) where selected.contains(out[i].id) && !selected.contains(out[i - 1].id) {
                out.swapAt(i, i - 1)
            }
            return out
        default: return objects
        }
    }
}

/// Smart guides: while an object moves, is drawn or resized, its edges and center snap to the edges and centers of the
/// other objects and of the image, and a guide line shows what it lines up with.
struct SmartGuides {
    /// A guide line in image coordinates: vertical when `vertical`, at `position`, spanning `from…to` on the other axis.
    struct Guide: Equatable {
        var vertical: Bool
        var position: CGFloat
        var from: CGFloat
        var to: CGFloat
    }

    private struct Line {
        let value: CGFloat
        let span: ClosedRange<CGFloat>
    }

    private var xs: [Line] = []
    private var ys: [Line] = []

    init(targets: [CGRect]) {
        for r in targets where r.width.isFinite && r.height.isFinite {
            for x in [r.minX, r.midX, r.maxX] { xs.append(Line(value: x, span: r.minY...r.maxY)) }
            for y in [r.minY, r.midY, r.maxY] { ys.append(Line(value: y, span: r.minX...r.maxX)) }
        }
    }

    /// The nearest line within `threshold` of any of `anchors`: the shift to apply, or 0.
    private static func best(_ anchors: [CGFloat], _ lines: [Line], _ threshold: CGFloat) -> CGFloat {
        var shift: CGFloat = 0, bestDistance = threshold
        for a in anchors {
            for l in lines where abs(l.value - a) <= bestDistance {
                bestDistance = abs(l.value - a)
                shift = l.value - a
            }
        }
        return bestDistance < threshold ? shift : 0
    }

    /// Guides for every line the rectangle now touches with an edge or its center (each line once).
    private func guides(for r: CGRect) -> [Guide] {
        var out: [Guide] = []
        for a in [r.minX, r.midX, r.maxX] {
            for l in xs where abs(l.value - a) < 0.5 {
                out.append(Guide(vertical: true, position: l.value, from: min(l.span.lowerBound, r.minY), to: max(l.span.upperBound, r.maxY)))
            }
        }
        for a in [r.minY, r.midY, r.maxY] {
            for l in ys where abs(l.value - a) < 0.5 {
                out.append(Guide(vertical: false, position: l.value, from: min(l.span.lowerBound, r.minX), to: max(l.span.upperBound, r.maxX)))
            }
        }
        // One guide per line, spanning everything that lines up on it.
        var merged: [Guide] = []
        for g in out {
            if let i = merged.firstIndex(where: { $0.vertical == g.vertical && abs($0.position - g.position) < 0.5 }) {
                merged[i].from = min(merged[i].from, g.from)
                merged[i].to = max(merged[i].to, g.to)
            } else {
                merged.append(g)
            }
        }
        return merged
    }

    /// Moves `rect` by at most `threshold` so an edge or its center lines up with a target, on each axis.
    func snap(rect: CGRect, threshold: CGFloat) -> (offset: CGVector, guides: [Guide]) {
        let dx = Self.best([rect.minX, rect.midX, rect.maxX], xs, threshold)
        let dy = Self.best([rect.minY, rect.midY, rect.maxY], ys, threshold)
        return (CGVector(dx: dx, dy: dy), guides(for: rect.offsetBy(dx: dx, dy: dy)))
    }

    /// Snaps a single dragged point (a corner being drawn or resized) to the target lines.
    func snap(point p: CGPoint, threshold: CGFloat) -> (point: CGPoint, guides: [Guide]) {
        let dx = Self.best([p.x], xs, threshold), dy = Self.best([p.y], ys, threshold)
        let q = CGPoint(x: p.x + dx, y: p.y + dy)
        return (q, guides(for: CGRect(origin: q, size: .zero)))
    }
}

/// The options bar's Arrange popover: icon buttons in three groups, the ones that need more objects disabled.
final class ArrangePanelView: NSView {
    private let onAction: (ArrangeAction) -> Void

    init(selectionCount: Int, onAction: @escaping (ArrangeAction) -> Void) {
        self.onAction = onAction
        super.init(frame: .zero)
        func group(_ title: String, _ actions: [ArrangeAction]) -> NSView {
            let label = NSTextField(labelWithString: title.uppercased())
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = .secondaryLabelColor
            let buttons = actions.map { a -> NSButton in
                let b = NSButton(image: NSImage(systemSymbolName: a.symbol, accessibilityDescription: a.title)
                    ?? NSImage(systemSymbolName: "square", accessibilityDescription: a.title)!, target: self, action: #selector(clicked(_:)))
                b.bezelStyle = .rounded
                b.identifier = NSUserInterfaceItemIdentifier(a.rawValue)
                let keys = a.keyEquivalent.map { k in
                    (k.1.contains(.option) ? "⌥" : "") + (k.1.contains(.shift) ? "⇧" : "") + "⌘" + k.0.uppercased()
                }
                b.toolTip = a.title + (keys.map { "  \($0)" } ?? "")
                b.isEnabled = selectionCount >= a.minimumSelection
                b.widthAnchor.constraint(equalToConstant: 36).isActive = true
                return b
            }
            let row = NSStackView(views: buttons)
            row.spacing = 4
            let col = NSStackView(views: [label, row])
            col.orientation = .vertical
            col.alignment = .leading
            col.spacing = 6
            return col
        }
        let note = NSTextField(wrappingLabelWithString: selectionCount == 1
            ? "One object aligns to the screenshot. Select several to align them to each other."
            : "Distribute needs three or more objects.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 250
        let stack = NSStackView(views: [group("Align", ArrangeAction.alignments), group("Distribute", ArrangeAction.distributions),
                                        group("Order", ArrangeAction.orders), note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let a = ArrangeAction(rawValue: raw) else { return }
        onAction(a)
    }
}
