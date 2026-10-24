import AppKit

/// The per-tool options that used to sit in the bottom bar (size, arrow style, callout design, text face, counter shape,
/// and the Crop, Blur, Ruler and Magnifier options). The top toolbar places them; this object keeps their state and
/// sends style changes, exactly as before. Right-click an option to make it the default.
@MainActor final class ToolOptions: NSObject, NSMenuDelegate {
    var onChange: ((ToolStyle) -> Void)?
    var onCutOutMode: ((Bool) -> Void)?
    var onAutoadjust: (() -> Void)?
    var onImprint: (() -> Void)?
    private(set) var style = ToolStyle()

    private(set) lazy var autoadjustButton = Self.smallButton("Autoadjust", symbol: "viewfinder", tooltip: "Shrink the selection to the content (F)",
                                                              target: self, action: #selector(autoadjustClicked))
    private(set) lazy var imprintButton = Self.smallButton("Imprint Size", symbol: "ruler", tooltip: "Stamp the selection's size on the image (I)",
                                                           target: self, action: #selector(imprintClicked))
    let cropModeControl = NSSegmentedControl(labels: ["Crop", "Cut Out"], trackingMode: .selectOne, target: nil, action: nil)
    let widthSlider = NSSlider(value: 4, minValue: 1, maxValue: 20, target: nil, action: nil)
    let sizeReadout = NSTextField(labelWithString: "4")
    let arrowControl = DefaultableSegmentedControl()
    let blurControl = DefaultableSegmentedControl(labels: BlurMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    let fontControl = DefaultableSegmentedControl(labels: TextFont.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    let shapeControl = DefaultableSegmentedControl()
    let unitControl = DefaultableSegmentedControl(labels: ["PX", "PT"], trackingMode: .selectOne, target: nil, action: nil)
    let lensShapeControl = DefaultableSegmentedControl()
    let calloutControl = DefaultableSegmentedControl()
    private static let zoomSteps: [CGFloat] = [1.5, 2, 3, 4]
    let lensZoomControl = DefaultableSegmentedControl(labels: ToolOptions.zoomSteps.map { "\($0.formatted())×" }, trackingMode: .selectOne,
                                                      target: nil, action: nil)

    /// Each option control with how it reads and writes a ToolStyle, for right-click → Set as Default.
    private lazy var defaultables: [(control: DefaultableSegmentedControl, set: (inout ToolStyle, Int) -> Void, get: (ToolStyle) -> Int)] = [
        (calloutControl, { $0.callout = CalloutStyle(rawValue: $1) ?? .box }, { $0.callout.rawValue }),
        (arrowControl, { $0.arrow = ArrowStyle(rawValue: $1) ?? .tapered }, { $0.arrow.rawValue }),
        (blurControl, { $0.blur = BlurMode(rawValue: $1) ?? .blur }, { $0.blur.rawValue }),
        (fontControl, { $0.font = TextFont(rawValue: $1) ?? .sans }, { $0.font.rawValue }),
        (shapeControl, { $0.counterShape = CounterShape(rawValue: $1) ?? .circle }, { $0.counterShape.rawValue }),
        (unitControl, { $0.rulerInPoints = $1 == 1 }, { $0.rulerInPoints ? 1 : 0 }),
        (lensShapeControl, { $0.lensShape = LensShape(rawValue: $1) ?? .oval }, { $0.lensShape.rawValue }),
        (lensZoomControl, { $0.magnification = Self.zoomSteps[$1] }, { s in Self.zoomSteps.firstIndex { abs($0 - s.magnification) < 0.01 } ?? -1 }),
    ]

    override init() {
        super.init()
        sizeReadout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        sizeReadout.textColor = .secondaryLabelColor
        sizeReadout.alignment = .center
        sizeReadout.widthAnchor.constraint(equalToConstant: 20).isActive = true
        sizeReadout.toolTip = "Size"

        widthSlider.controlSize = .small
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthSlider.toolTip = "Size"
        widthSlider.setAccessibilityLabel("Size")
        widthSlider.widthAnchor.constraint(equalToConstant: 64).isActive = true

        Self.images(arrowControl, ArrowStyle.allCases.map { ($0.symbol, $0.title) })
        Self.images(shapeControl, CounterShape.allCases.map { ($0.symbol, $0.title) })
        Self.images(lensShapeControl, LensShape.allCases.map { ($0.symbol, $0.title) })
        Self.images(calloutControl, CalloutStyle.allCases.map { ($0.symbol, $0.title) })
        lensZoomControl.toolTip = "Magnification · pinch, scroll or +/− over a selected magnifier for finer steps"
        blurControl.toolTip = "Blur or Erase (fills with the surrounding color)"
        unitControl.toolTip = "One logical point is equal two physical pixels on Retina displays."
        fontControl.toolTip = "Text face for text boxes and callouts"
        for i in 0..<fontControl.segmentCount { fontControl.setWidth(48, forSegment: i) }
        arrowControl.setAccessibilityLabel("Arrow style")
        calloutControl.setAccessibilityLabel("Callout design")
        shapeControl.setAccessibilityLabel("Counter shape")
        for c in [arrowControl, blurControl, fontControl, shapeControl, unitControl, lensShapeControl, lensZoomControl, calloutControl] {
            c.controlSize = .small
            c.target = self
            c.action = #selector(optionChanged(_:))
        }

        cropModeControl.controlSize = .small
        cropModeControl.target = self
        cropModeControl.action = #selector(cropModeChanged)
        cropModeControl.setImage(NSImage(systemSymbolName: "crop", accessibilityDescription: "Crop"), forSegment: 0)
        cropModeControl.setImage(NSImage(systemSymbolName: "scissors", accessibilityDescription: "Cut Out"), forSegment: 1)
        cropModeControl.setToolTip("Keep the selected area (X)", forSegment: 0)
        cropModeControl.setToolTip("Remove a horizontal or vertical strip and join the rest (⇧X)", forSegment: 1)

        // Clicking these must never take keyboard focus away from a text box being typed in.
        for c in [widthSlider, arrowControl, blurControl, fontControl, shapeControl, unitControl, lensShapeControl, lensZoomControl, calloutControl,
                  cropModeControl] as [NSControl] {
            c.refusesFirstResponder = true
        }
        wireDefaults()
    }

    // MARK: Defaults (right-click)

    private func wireDefaults() {
        for entry in defaultables {
            let c = entry.control
            c.onSetDefault = { [weak self] i in
                guard let self else { return }
                ToolStyle.updateDefaults { entry.set(&$0, i) }
                // Use it right away too, so the choice and the default agree.
                entry.set(&self.style, i)
                self.onChange?(self.style)
                self.refreshDefaultMarks()
                Toast.show("“\(c.name(of: i))” is now the default")
            }
            c.onResetDefault = { [weak self] in
                let builtIn = entry.get(ToolStyle())
                ToolStyle.updateDefaults { entry.set(&$0, builtIn) }
                self?.refreshDefaultMarks()
                if builtIn >= 0 { Toast.show("Default reset to “\(c.name(of: builtIn))”") }
            }
        }
        widthSlider.menu = defaultMenu(for: "size")
        sizeReadout.menu = defaultMenu(for: "size")
        refreshDefaultMarks()
    }

    private func refreshDefaultMarks() {
        let d = ToolStyle.loadDefaults()
        for entry in defaultables { entry.control.defaultIndex = entry.get(d) }
        widthSlider.toolTip = "Size · default \(Int(d.width)) (right-click to change)"
    }

    /// Right-click menu for the color buttons ("color") and the size slider ("size").
    func defaultMenu(for what: String) -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        m.identifier = NSUserInterfaceItemIdentifier(what)
        return m
    }

    var currentStyle: ToolStyle { style }
    @objc func setColorDefaultAction() {
        let c = style.color
        ToolStyle.updateDefaults { $0.color = c }
        Toast.show("\(c.hexString) is now the default color")
    }

    @objc func resetColorDefaultAction() {
        ToolStyle.updateDefaults { $0.color = ToolStyle().color }
        Toast.show("Default color reset")
    }

    @objc func setSizeDefaultAction() {
        let w = style.width
        ToolStyle.updateDefaults { $0.width = w }
        refreshDefaultMarks()
        Toast.show("Size \(Int(w)) is now the default")
    }

    @objc func resetSizeDefaultAction() {
        ToolStyle.updateDefaults { $0.width = ToolStyle().width }
        refreshDefaultMarks()
        Toast.show("Default size reset")
    }

    /// Shape Fill › Set as Default: the fill (none, translucent or opaque) new shapes start with.
    @objc func setFillDefaultAction() {
        let f = style.fill
        ToolStyle.updateDefaults { $0.fill = f }
        Toast.show("“\(f.title)” is now the default")
    }

    /// Shape Outline › Set as Default: color, weight and dashes for new objects.
    @objc func setOutlineDefaultAction() {
        let s = style
        ToolStyle.updateDefaults { $0.color = s.color; $0.width = s.width; $0.dashed = s.dashed; $0.sketch = s.sketch }
        refreshDefaultMarks()
        Toast.show("This outline is now the default")
    }

    /// Fills the color/size right-click menus with the current value when they open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let d = ToolStyle.loadDefaults()
        if menu.identifier?.rawValue == "color" {
            let set = NSMenuItem(title: "Set \(currentStyle.color.hexString) as Default Color", action: #selector(setColorDefaultAction), keyEquivalent: "")
            set.target = self
            set.image = Self.swatch(currentStyle.color, size: 14)
            menu.addItem(set)
            let info = NSMenuItem(title: "Current default: \(d.color.hexString)", action: nil, keyEquivalent: "")
            info.image = Self.swatch(d.color, size: 14)
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
            let reset = NSMenuItem(title: "Reset to Original Default", action: #selector(resetColorDefaultAction), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        } else {
            let set = NSMenuItem(title: "Set Size \(Int(currentStyle.width)) as Default", action: #selector(setSizeDefaultAction), keyEquivalent: "")
            set.target = self
            menu.addItem(set)
            let info = NSMenuItem(title: "Current default: \(Int(d.width))", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
            let reset = NSMenuItem(title: "Reset to Original Default", action: #selector(resetSizeDefaultAction), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }
    }

    // MARK: Building

    private static func images(_ c: NSSegmentedControl, _ items: [(String, String)]) {
        c.segmentCount = items.count
        c.trackingMode = .selectOne
        for (i, (sym, title)) in items.enumerated() {
            c.setImage(NSImage(systemSymbolName: sym, accessibilityDescription: title), forSegment: i)
            c.setToolTip(title, forSegment: i)
            c.setWidth(24, forSegment: i)
        }
    }

    /// Color dot with a white ring and a hairline outline (an accent ring when selected).
    static func swatch(_ c: NSColor, size: CGFloat = 18, selected: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let outer = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75))
            (selected ? Palette.accent : NSColor.black.withAlphaComponent(0.18)).setStroke()
            outer.lineWidth = selected ? 1.5 : 1
            NSColor.white.setFill()
            outer.fill()
            outer.stroke()
            let inner = NSBezierPath(ovalIn: r.insetBy(dx: size * 0.16, dy: size * 0.16))
            c.setFill()
            inner.fill()
            NSColor.black.withAlphaComponent(0.12).setStroke()
            inner.lineWidth = 0.5
            inner.stroke()
            return true
        }
    }

    static func smallButton(_ title: String, symbol: String, tooltip: String, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: target, action: action)
        b.controlSize = .small
        b.bezelStyle = .rounded
        b.imagePosition = .imageLeading
        b.toolTip = tooltip
        b.refusesFirstResponder = true
        return b
    }

    // MARK: State

    /// The tool section's title when the tool (or selected object) has options of its own, else nil.
    private(set) var toolSectionTitle: String?

    func update(tool: Tool, style s: ToolStyle, cutOut: Bool = false) {
        style = s
        widthSlider.doubleValue = Double(s.width)
        sizeReadout.stringValue = "\(Int(s.width))"
        arrowControl.selectedSegment = s.arrow.rawValue
        blurControl.selectedSegment = s.blur.rawValue
        fontControl.selectedSegment = s.font.rawValue
        shapeControl.selectedSegment = s.counterShape.rawValue
        unitControl.selectedSegment = s.rulerInPoints ? 1 : 0
        lensShapeControl.selectedSegment = s.lensShape.rawValue
        calloutControl.selectedSegment = s.callout.rawValue
        lensZoomControl.selectedSegment = Self.zoomSteps.firstIndex { abs($0 - s.magnification) < 0.01 } ?? -1

        cropModeControl.selectedSegment = cutOut ? 1 : 0
        cropModeControl.isHidden = tool != .crop
        autoadjustButton.isHidden = tool != .crop || cutOut
        imprintButton.isHidden = tool != .crop || cutOut
        arrowControl.isHidden = tool != .arrow
        blurControl.isHidden = tool != .blur
        shapeControl.isHidden = tool != .counter
        unitControl.isHidden = tool != .ruler
        lensShapeControl.isHidden = tool != .magnifier
        lensZoomControl.isHidden = tool != .magnifier
        fontControl.isEnabled = tool == .text || tool == .callout
        calloutControl.isEnabled = tool == .callout
        let usesStroke = ![.blur, .spotlight, .crop, .select, .image].contains(tool)
        widthSlider.isEnabled = usesStroke
        sizeReadout.textColor = usesStroke ? .secondaryLabelColor : .tertiaryLabelColor
        toolSectionTitle = [.crop, .blur, .ruler, .magnifier].contains(tool) ? tool.title : nil
    }

    @objc private func autoadjustClicked() { onAutoadjust?() }
    @objc private func imprintClicked() { onImprint?() }

    @objc private func cropModeChanged() {
        onCutOutMode?(cropModeControl.selectedSegment == 1)
    }

    @objc private func widthChanged() {
        style.width = CGFloat(widthSlider.doubleValue.rounded())
        sizeReadout.stringValue = "\(Int(style.width))"
        onChange?(style)
    }

    @objc private func optionChanged(_ sender: NSSegmentedControl) {
        let i = sender.selectedSegment
        switch sender {
        case arrowControl: style.arrow = ArrowStyle(rawValue: i) ?? .tapered
        case blurControl: style.blur = BlurMode(rawValue: i) ?? .blur
        case fontControl: style.font = TextFont(rawValue: i) ?? .sans
        case shapeControl: style.counterShape = CounterShape(rawValue: i) ?? .circle
        case unitControl: style.rulerInPoints = i == 1
        case lensShapeControl: style.lensShape = LensShape(rawValue: i) ?? .oval
        case calloutControl: style.callout = CalloutStyle(rawValue: i) ?? .box
        case lensZoomControl: if i >= 0 { style.magnification = Self.zoomSteps[i] }
        default: break
        }
        onChange?(style)
    }

    #if SCREENSHOT_SELFTESTS
    var debugShownStyle: ToolStyle { style }
    #endif
}
