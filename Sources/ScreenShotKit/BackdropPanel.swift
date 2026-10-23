import AppKit

/// Shottr's backdrop panel: presets, fill, colors, aspect and the sliders, shown in a popover from the options bar.
final class BackdropPanelView: NSView {
    private var backdrop: Backdrop
    private let onChange: (Backdrop) -> Void

    private let toggle = NSSwitch()
    private let fillPopup = NSPopUpButton()
    private let aspectPopup = NSPopUpButton()
    private let well1 = NSColorWell(style: .minimal)
    private let well2 = NSColorWell(style: .minimal)
    private var sliders: [(slider: NSSlider, key: WritableKeyPath<Backdrop, CGFloat>)] = []
    private var presetButtons: [NSButton] = []

    init(backdrop: Backdrop, onChange: @escaping (Backdrop) -> Void) {
        self.backdrop = backdrop
        self.onChange = onChange
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: "Backdrop")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.setAccessibilityLabel("Backdrop on or off")
        let shortcut = NSTextField(labelWithString: "K")
        shortcut.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        shortcut.textColor = .tertiaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [title, shortcut, spacer, toggle])

        // Preset swatches, two rows of five.
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        var row: [NSView] = []
        for (i, p) in Backdrop.presets.enumerated() {
            let b = NSButton(image: Self.swatch(p.colors, selected: false), target: self, action: #selector(presetClicked(_:)))
            b.isBordered = false
            b.tag = i
            b.toolTip = p.title
            b.setAccessibilityLabel("\(p.title) colors")
            presetButtons.append(b)
            row.append(b)
            if row.count == 5 {
                let r = NSStackView(views: row)
                r.spacing = 6
                grid.addArrangedSubview(r)
                row = []
            }
        }

        fillPopup.addItems(withTitles: Backdrop.Fill.allCases.map(\.title))
        aspectPopup.addItems(withTitles: Backdrop.Aspect.allCases.map(\.title))
        for (popup, label) in [(fillPopup, "Fill"), (aspectPopup, "Aspect ratio")] {
            popup.controlSize = .small
            popup.target = self
            popup.action = #selector(popupChanged(_:))
            popup.setAccessibilityLabel(label)
        }
        for (w, label) in [(well1, "First color"), (well2, "Second color")] {
            w.target = self
            w.action = #selector(colorChanged)
            w.setAccessibilityLabel(label)
            w.widthAnchor.constraint(equalToConstant: 38).isActive = true
            w.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }

        let form = NSGridView()
        form.rowSpacing = 8
        form.columnSpacing = 10
        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: 12)
            l.textColor = .secondaryLabelColor
            l.alignment = .right
            return l
        }
        form.addRow(with: [label("Fill"), fillPopup])
        form.addRow(with: [label("Colors"), NSStackView(views: [well1, well2])])
        form.addRow(with: [label("Aspect"), aspectPopup])
        let sliderSpecs: [(String, WritableKeyPath<Backdrop, CGFloat>, Double)] = [
            ("Padding", \.padding, 0.25), ("Shadow", \.shadow, 1), ("Inset", \.inset, 0.08),
            ("Outer Radius", \.outerRadius, 0.15), ("Inner Radius", \.innerRadius, 0.06),
        ]
        for (name, key, maxValue) in sliderSpecs {
            let s = NSSlider(value: 0, minValue: 0, maxValue: maxValue, target: self, action: #selector(sliderChanged(_:)))
            s.controlSize = .small
            s.isContinuous = true
            s.setAccessibilityLabel(name)
            s.widthAnchor.constraint(equalToConstant: 170).isActive = true
            sliders.append((s, key))
            form.addRow(with: [label(name), s])
        }
        form.column(at: 0).xPlacement = .trailing

        let recenter = NSButton(title: "Recenter", target: self, action: #selector(recenterClicked))
        recenter.controlSize = .small
        recenter.toolTip = "Put the screenshot back in the middle"
        let makeDefault = NSButton(title: "Set as Default", target: self, action: #selector(defaultClicked))
        makeDefault.controlSize = .small
        makeDefault.toolTip = "K turns this backdrop on for every screenshot"
        let buttons = NSStackView(views: [recenter, makeDefault])

        let note = NSTextField(wrappingLabelWithString: "With the Select tool, drag the background to move the screenshot.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 250

        let stack = NSStackView(views: [header, grid, form, buttons, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Called when the document's backdrop changes elsewhere (K, undo, dragging the screenshot).
    func show(_ b: Backdrop) {
        backdrop = b
        refresh()
    }

    private func refresh() {
        toggle.state = backdrop.isOn ? .on : .off
        fillPopup.selectItem(at: Backdrop.Fill.allCases.firstIndex(of: backdrop.fill) ?? 0)
        aspectPopup.selectItem(at: Backdrop.Aspect.allCases.firstIndex(of: backdrop.aspect) ?? 0)
        let c = backdrop.nsColors
        well1.color = c[0]
        well2.color = c.count > 1 ? c[1] : c[0]
        for (s, key) in sliders { s.doubleValue = Double(backdrop[keyPath: key]) }
        for (i, b) in presetButtons.enumerated() {
            b.image = Self.swatch(Backdrop.presets[i].colors, selected: backdrop.isOn && backdrop.colors == Backdrop.presets[i].colors)
        }
    }

    /// Every edit turns the backdrop on: picking a color for an invisible backdrop would do nothing.
    private func apply(_ edit: (inout Backdrop) -> Void) {
        edit(&backdrop)
        backdrop.isOn = true
        refresh()
        onChange(backdrop)
    }

    @objc private func toggled() {
        backdrop.isOn = toggle.state == .on
        refresh()
        onChange(backdrop)
    }

    @objc private func presetClicked(_ sender: NSButton) {
        apply { b in
            b.colors = Backdrop.presets[sender.tag].colors
            if b.fill == .blurredImage { b.fill = .diagonal }
        }
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        apply { b in
            if sender === fillPopup { b.fill = Backdrop.Fill.allCases[i] } else { b.aspect = Backdrop.Aspect.allCases[i] }
        }
    }

    @objc private func colorChanged() {
        apply { b in b.colors = [well1.color.rgbaHex, well2.color.rgbaHex] }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let key = sliders.first(where: { $0.slider === sender })?.key else { return }
        apply { b in b[keyPath: key] = CGFloat(sender.doubleValue) }
    }

    @objc private func recenterClicked() {
        apply { b in b.offset = .zero }
    }

    @objc private func defaultClicked() {
        Backdrop.lastUsed = backdrop
        Toast.show("Backdrop set as default · K turns it on")
    }

    static func swatch(_ colors: [String], selected: Bool) -> NSImage {
        let size = NSSize(width: 40, height: 26)
        return NSImage(size: size, flipped: false) { r in
            let rect = r.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            let cols = colors.compactMap { NSColor(rgbaHex: $0) }
            NSGradient(colors: cols.count > 1 ? cols : cols + cols)?.draw(in: path, angle: -35)
            if selected {
                Palette.accent.setStroke()
                path.lineWidth = 2.5
            } else {
                NSColor.black.withAlphaComponent(0.12).setStroke()
                path.lineWidth = 1
            }
            path.stroke()
            return true
        }
    }
}
