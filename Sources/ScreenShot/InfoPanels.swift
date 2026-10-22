import AppKit

/// Shottr's color formats (ddlColorFormat), with the sample labels and templates found in its binary.
enum ColorFormat: String, CaseIterable {
    case hex, hexNoHash, cssRGBA, rgbUnit, android, uiColor, csharp, oklch

    static var current: ColorFormat {
        get { ColorFormat(rawValue: UserDefaults.standard.string(forKey: "colorFormat") ?? "") ?? .hex }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "colorFormat") }
    }

    var title: String {
        switch self {
        case .hex: "HEX #FFC200"
        case .hexNoHash: "HEX FFC200"
        case .cssRGBA: "CSS rgba(255, 194, 0, 1)"
        case .rgbUnit: "RGB (1.00, 0.76, 0.00)"
        case .android: "Android 0xFFFFC200"
        case .uiColor: "UIColor (red: 1.00, gre..."
        case .csharp: "C# Color.fromArgb()"
        case .oklch: "OKLCH"
        }
    }

    func string(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return color.hexString }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let ri = Int((r * 255).rounded()), gi = Int((g * 255).rounded()), bi = Int((b * 255).rounded())
        let hex = String(format: "%02X%02X%02X", ri, gi, bi)
        switch self {
        case .hex: return "#" + hex
        case .hexNoHash: return hex
        case .cssRGBA: return "rgba(\(ri), \(gi), \(bi), 1)"
        case .rgbUnit: return String(format: "(%.2f, %.2f, %.2f)", r, g, b)
        case .android: return "0xFF" + hex
        case .uiColor: return String(format: "UIColor(red: %.2f, green: %.2f, blue: %.2f, alpha: 1.00)", r, g, b)
        case .csharp: return "Color.fromArgb(\(ri), \(gi), \(bi));"
        case .oklch:
            let (l, ch, h) = Self.oklch(r, g, b)
            return String(format: "oklch(%.1f%% %.3f %.1f)", l * 100, ch, h)
        }
    }

    /// sRGB → OKLab → OKLCH (Björn Ottosson's reference matrices).
    static func oklch(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let lr = lin(r), lg = lin(g), lb = lin(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let C = sqrt(A * A + B * B)
        var H = atan2(B, A) * 180 / .pi
        if H < 0 { H += 360 }
        return (L, C, C < 0.0001 ? 0 : H)
    }
}

// MARK: - Popover content

/// Shottr's color helper (colorBoxClicked:): the three ways to copy a color, and the format menu.
final class ColorHelperView: NSView {
    init(onFormat: @escaping () -> Void) {
        self.onFormat = onFormat
        super.init(frame: .zero)
        let rows: [(String, String, String)] = [
            ("eyedropper", "Copy Pixel Color", "Hover mouse over any pixel and press Tab"),
            ("textformat", "Copy Text Color", "Press Shift+Tab to copy the darkest color in the 20px area around the cursor"),
            ("square.dashed", "Copy Average Color", "Select an area (Crop tool) and press C to copy its average color"),
        ]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        for (symbol, title, detail) in rows {
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!
                .withSymbolConfiguration(.init(pointSize: 22, weight: .regular))!)
            icon.contentTintColor = Palette.accent
            icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
            let t = NSTextField(labelWithString: title)
            t.font = .systemFont(ofSize: 12, weight: .medium)
            let d = NSTextField(wrappingLabelWithString: detail)
            d.font = .systemFont(ofSize: 11)
            d.textColor = .secondaryLabelColor
            d.preferredMaxLayoutWidth = 200
            let text = NSStackView(views: [t, d])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            let row = NSStackView(views: [icon, text])
            row.alignment = .top
            row.spacing = 10
            stack.addArrangedSubview(row)
        }
        let sep = NSBox()
        sep.boxType = .separator
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let label = NSTextField(labelWithString: "Color Format")
        label.font = .systemFont(ofSize: 12)
        popup.addItems(withTitles: ColorFormat.allCases.map(\.title))
        popup.selectItem(at: ColorFormat.allCases.firstIndex(of: .current) ?? 0)
        popup.target = self
        popup.action = #selector(formatChanged)
        popup.widthAnchor.constraint(equalToConstant: 166).isActive = true
        let formatRow = NSStackView(views: [label, popup])
        formatRow.spacing = 12
        stack.addArrangedSubview(formatRow)

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            widthAnchor.constraint(equalToConstant: 300),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private let popup = NSPopUpButton()
    private let onFormat: () -> Void

    @objc private func formatChanged() {
        ColorFormat.current = ColorFormat.allCases[popup.indexOfSelectedItem]
        onFormat()
    }
}

/// Shottr's resize panel (sizeBoxClicked:): W × H px with Resize, presets 25%…4×, and the px/pt switch.
final class ResizePanelView: NSView, NSTextFieldDelegate {
    private let imageSize: CGSize
    private let scale: CGFloat
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let unitCheckbox = NSButton(checkboxWithTitle: "Show Size in Logical Points", target: nil, action: nil)
    private let onResize: (CGFloat) -> Void
    private let onUnitsChanged: () -> Void
    private static let presets: [(String, CGFloat)] = [("25%", 0.25), ("33%", 1.0 / 3), ("50%", 0.5), ("1×", 1), ("2×", 2), ("4×", 4)]

    init(imageSize: CGSize, scale: CGFloat, onResize: @escaping (CGFloat) -> Void, onUnitsChanged: @escaping () -> Void) {
        self.imageSize = imageSize
        self.scale = scale
        self.onResize = onResize
        self.onUnitsChanged = onUnitsChanged
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: "Resize Image")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        for f in [widthField, heightField] {
            f.alignment = .right
            f.delegate = self
            f.widthAnchor.constraint(equalToConstant: 64).isActive = true
            f.formatter = {
                let n = NumberFormatter()
                n.allowsFloats = false
                n.minimum = 1
                return n
            }()
        }
        let times = NSTextField(labelWithString: "×")
        let unit = NSTextField(labelWithString: Settings.showPoints ? "pt" : "px")
        let resize = NSButton(title: "Resize", target: self, action: #selector(resizeClicked))
        resize.keyEquivalent = "\r"
        let fieldsRow = NSStackView(views: [widthField, times, heightField, unit, resize])
        fieldsRow.spacing = 6

        let presets = NSSegmentedControl(labels: Self.presets.map(\.0), trackingMode: .momentary, target: self, action: #selector(presetClicked(_:)))
        presets.controlSize = .small

        unitCheckbox.state = Settings.showPoints ? .on : .off
        unitCheckbox.target = self
        unitCheckbox.action = #selector(unitsChanged)
        let note = NSTextField(wrappingLabelWithString: "One logical point is two physical pixels on Retina displays. Shortcut P switches modes. Resizing can be undone with ⌘Z.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 260

        let stack = NSStackView(views: [title, fieldsRow, presets, unitCheckbox, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        fill(factor: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var unitScale: CGFloat { Settings.showPoints ? scale : 1 }

    private func fill(factor: CGFloat) {
        widthField.integerValue = Int((imageSize.width * factor / unitScale).rounded())
        heightField.integerValue = Int((imageSize.height * factor / unitScale).rounded())
    }

    /// Width and height stay proportional, like Shottr's linked fields.
    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, let v = Double(f.stringValue), v > 0 else { return }
        let ratio = imageSize.width / imageSize.height
        if f === widthField { heightField.integerValue = Int((CGFloat(v) / ratio).rounded()) } else { widthField.integerValue = Int((CGFloat(v) * ratio).rounded()) }
    }

    @objc private func presetClicked(_ sender: NSSegmentedControl) {
        let factor = Self.presets[sender.selectedSegment].1
        fill(factor: factor)
        if factor != 1 { onResize(factor) }
    }

    @objc private func resizeClicked() {
        let target = CGFloat(widthField.integerValue) * unitScale
        guard target > 1 else { return }
        onResize(target / imageSize.width)
    }

    @objc private func unitsChanged() {
        Settings.showPoints = unitCheckbox.state == .on
        fill(factor: 1)
        onUnitsChanged()
    }
}

/// Shottr's zoom box (zoomBoxClicked:): − / percentage / +, the percentage button returning to 100%.
final class ZoomPanelView: NSView {
    private let percent = NSButton(title: "100%", target: nil, action: nil)
    private let onZoomIn: () -> Void, onZoomOut: () -> Void, onActual: () -> Void, onFit: () -> Void

    init(percentText: String, zoomIn: @escaping () -> Void, zoomOut: @escaping () -> Void, actual: @escaping () -> Void, fit: @escaping () -> Void) {
        onZoomIn = zoomIn
        onZoomOut = zoomOut
        onActual = actual
        onFit = fit
        super.init(frame: .zero)
        func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
            b.bezelStyle = .circular
            b.toolTip = tip
            return b
        }
        percent.title = percentText
        percent.bezelStyle = .rounded
        percent.font = .monospacedDigitSystemFont(ofSize: 13, weight: .light)
        percent.target = self
        percent.action = #selector(actualClicked)
        percent.toolTip = "Back to 100%"
        percent.widthAnchor.constraint(equalToConstant: 84).isActive = true
        let row = NSStackView(views: [iconButton("minus", "Zoom Out (⌘−)", #selector(outClicked)), percent, iconButton("plus", "Zoom In (⌘=)", #selector(inClicked))])
        row.spacing = 12
        let fit = NSButton(title: "Fit to Window", target: self, action: #selector(fitClicked))
        fit.bezelStyle = .rounded
        let help = NSTextField(wrappingLabelWithString: "Pinch, ⌘-scroll or ⌘= / ⌘− / ⌘0.\nScroll without ⌘: Preferences › Advanced › Zoom with mouse wheel.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.preferredMaxLayoutWidth = 210
        help.setContentCompressionResistancePriority(.required, for: .vertical)
        help.widthAnchor.constraint(equalToConstant: 210).isActive = true
        let stack = NSStackView(views: [row, fit, help])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPercent(_ text: String) { percent.title = text }

    @objc private func inClicked() { onZoomIn() }
    @objc private func outClicked() { onZoomOut() }
    @objc private func actualClicked() { onActual() }
    @objc private func fitClicked() { onFit() }
}
