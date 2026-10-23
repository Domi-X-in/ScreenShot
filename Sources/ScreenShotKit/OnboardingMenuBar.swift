import AppKit
import QuartzCore

/// 3 · Where the app lives: a mock desktop where the pointer opens the menu bar icon and picks Open ScreenShot,
/// then ⇧⌘2 is pressed and an area selection starts.
final class MenuBarPage: OnboardingPage {
    private var title: NSView!
    private var caption: NSView!
    private var scene: MenuBarDemoView!

    override func build() {
        title = headline("Always one click away", y: 26, size: 30)
        let keys = HotKeyCenter.shared.shortcut(for: .area)?.display ?? "⇧⌘2"
        caption = text("ScreenShot lives in the menu bar. Click its icon for every capture and Open ScreenShot, or press \(keys) from any app.",
                       y: 70, size: 14, color: NSColor.white.withAlphaComponent(0.68), width: 500)
        scene = MenuBarDemoView(frame: CGRect(x: (bounds.width - 600) / 2, y: 132, width: 600, height: 300))
        addSubview(scene)
    }

    override func play() {
        rise(title, delay: 0.05)
        rise(caption, delay: 0.15)
        rise(scene, delay: 0.25, distance: 24)
        scene.start()
    }

    override func stop() { scene.stop() }
}

/// 6 · Light, dark or follow the system: three live previews of the editor; picking one applies it right away.
final class AppearancePage: OnboardingPage {
    private var title: NSView!
    private var caption: NSView!
    private var cards: [AppearanceCard] = []

    override func build() {
        title = headline("Light or dark?", y: 30, size: 30)
        caption = text("Pick a look for ScreenShot's windows. You can change it anytime in Preferences.",
                       y: 76, size: 14, color: NSColor.white.withAlphaComponent(0.68))
        let options: [(String, String)] = [("system", "System"), ("light", "Light"), ("dark", "Dark")]
        let w: CGFloat = 200, gap: CGFloat = 22
        var x = (bounds.width - w * 3 - gap * 2) / 2
        for (value, label) in options {
            let c = AppearanceCard(frame: CGRect(x: x, y: 150, width: w, height: 186), value: value, title: label) { [weak self] v in
                self?.choose(v)
            }
            addSubview(c)
            cards.append(c)
            x += w + gap
        }
        refresh(animated: false)
    }

    private func choose(_ value: String) {
        UserDefaults.standard.set(value, forKey: "appearance")
        Settings.applyAppearance()
        // The guide stays dark on purpose; the choice shows in every other ScreenShot window.
        window?.appearance = NSAppearance(named: .darkAqua)
        refresh(animated: true)
    }

    private func refresh(animated: Bool) {
        let current = Settings.appearance
        for c in cards { c.setSelected(c.value == current, animated: animated) }
    }

    #if SCREENSHOT_SELFTESTS
    func debugChoose(_ value: String) { choose(value) }
    var selectedValue: String? { cards.first { $0.isSelected }?.value }
    #endif

    override func play() {
        rise(title, delay: 0.05)
        rise(caption, delay: 0.15)
        for (i, c) in cards.enumerated() { rise(c, delay: 0.28 + Double(i) * 0.1, distance: 26) }
    }
}

/// A miniature editor in one appearance (System is split light/dark), with a ring and check when selected.
final class AppearanceCard: NSView {
    let value: String
    private(set) var isSelected = false
    private let onPick: (String) -> Void
    private let preview = CALayer()
    private let ring = CALayer()
    private let badge = CALayer()
    private var hovering = false { didSet { lift() } }

    init(frame: NSRect, value: String, title: String, onPick: @escaping (String) -> Void) {
        self.value = value
        self.onPick = onPick
        super.init(frame: frame)
        wantsLayer = true
        let pv = CGRect(x: 0, y: 40, width: frame.width, height: frame.height - 40)
        preview.frame = pv
        preview.cornerRadius = 14
        preview.masksToBounds = true
        layer?.addSublayer(preview)
        switch value {
        case "light": Self.drawEditor(into: preview, dark: false, size: pv.size)
        case "dark": Self.drawEditor(into: preview, dark: true, size: pv.size)
        default:
            // Light on the left, dark on the right, split on a diagonal.
            let light = CALayer(), dark = CALayer()
            for l in [light, dark] { l.frame = preview.bounds; preview.addSublayer(l) }
            Self.drawEditor(into: light, dark: false, size: pv.size)
            Self.drawEditor(into: dark, dark: true, size: pv.size)
            let m = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: pv.width * 0.62, y: pv.height))
            path.addLine(to: CGPoint(x: pv.width, y: pv.height))
            path.addLine(to: CGPoint(x: pv.width, y: 0))
            path.addLine(to: CGPoint(x: pv.width * 0.38, y: 0))
            path.closeSubpath()
            m.path = path
            dark.mask = m
        }
        ring.frame = pv.insetBy(dx: -4, dy: -4)
        ring.cornerRadius = 18
        ring.borderWidth = 3
        ring.borderColor = NSColor(hex: 0xFF6A3D).cgColor
        ring.shadowColor = NSColor(hex: 0xFF4D1F).cgColor
        ring.shadowRadius = 12
        ring.shadowOpacity = 0.9
        ring.shadowOffset = .zero
        ring.opacity = 0
        layer?.addSublayer(ring)
        // Check badge at the preview's top-right corner.
        badge.frame = CGRect(x: pv.maxX - 30, y: pv.maxY - 30, width: 24, height: 24)
        badge.cornerRadius = 12
        badge.backgroundColor = NSColor(hex: 0xFF5A2A).cgColor
        let tick = CAShapeLayer()
        let t = CGMutablePath()
        t.move(to: CGPoint(x: 6.5, y: 12.5)); t.addLine(to: CGPoint(x: 10.5, y: 8.5)); t.addLine(to: CGPoint(x: 17.5, y: 16))
        tick.path = t
        tick.strokeColor = NSColor.white.cgColor
        tick.fillColor = nil
        tick.lineWidth = 2.6
        tick.lineCap = .round
        tick.lineJoin = .round
        badge.addSublayer(tick)
        badge.opacity = 0
        layer?.addSublayer(badge)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = CGRect(x: 0, y: 8, width: frame.width, height: 20)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel("\(title) appearance")
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ on: Bool, animated: Bool) {
        let changed = on != isSelected
        isSelected = on
        setAccessibilityValue(on ? 1 : 0)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.25)
        ring.opacity = on ? 1 : 0
        badge.opacity = on ? 1 : 0
        CATransaction.commit()
        if animated, on, changed {
            let s = CASpringAnimation(keyPath: "transform.scale")
            s.fromValue = 0.2
            s.toValue = 1
            s.damping = 9
            s.duration = s.settlingDuration
            badge.add(s, forKey: "pop")
        }
    }

    private func lift() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        preview.shadowColor = NSColor.black.cgColor
        preview.shadowOpacity = hovering ? 0.6 : 0
        preview.shadowRadius = 16
        preview.opacity = hovering || isSelected ? 1 : 0.88
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) { onPick(value) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        onPick(value)
        return true
    }

    /// A tiny editor window: toolbar, canvas, a screenshot with an arrow and a highlight (bottom-up coordinates).
    static func drawEditor(into root: CALayer, dark: Bool, size s: CGSize) {
        func box(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0) {
            let l = CALayer()
            l.frame = r
            l.backgroundColor = c.cgColor
            l.cornerRadius = radius
            root.addSublayer(l)
        }
        box(CGRect(origin: .zero, size: s), dark ? NSColor(hex: 0x17181D) : NSColor(hex: 0xE8EAEF))
        box(CGRect(x: 0, y: s.height - 24, width: s.width, height: 24), dark ? NSColor(hex: 0x26272E) : NSColor.white)
        for (i, c) in [NSColor(hex: 0xFF5F57), NSColor(hex: 0xFEBC2E), NSColor(hex: 0x28C840)].enumerated() {
            box(CGRect(x: 9 + CGFloat(i) * 11, y: s.height - 15, width: 7, height: 7), c, radius: 3.5)
        }
        for i in 0..<5 {
            box(CGRect(x: 58 + CGFloat(i) * 16, y: s.height - 17, width: 10, height: 10),
                (dark ? NSColor.white : NSColor.black).withAlphaComponent(i == 1 ? 0 : 0.22), radius: 3)
        }
        box(CGRect(x: 58 + 16, y: s.height - 17, width: 10, height: 10), NSColor(hex: 0xFF4D1F), radius: 3)
        let sheet = CGRect(x: 22, y: 26, width: s.width - 44, height: s.height - 62)
        box(sheet, dark ? NSColor(hex: 0x2A2B31) : NSColor.white, radius: 4)
        for (i, w) in [0.55, 0.4, 0.62].enumerated() {
            box(CGRect(x: sheet.minX + 10, y: sheet.maxY - 16 - CGFloat(i) * 12, width: sheet.width * w, height: 5),
                (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.16), radius: 2.5)
        }
        box(CGRect(x: sheet.minX + 10, y: sheet.minY + 10, width: sheet.width * 0.45, height: 22), NSColor(hex: 0xFFCC00).withAlphaComponent(0.45), radius: 3)
        let arrow = CAShapeLayer()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: sheet.maxX - 14, y: sheet.minY + 12))
        p.addLine(to: CGPoint(x: sheet.midX + 10, y: sheet.midY + 4))
        p.move(to: CGPoint(x: sheet.midX + 18, y: sheet.midY + 4)); p.addLine(to: CGPoint(x: sheet.midX + 10, y: sheet.midY + 4))
        p.addLine(to: CGPoint(x: sheet.midX + 11, y: sheet.midY - 4))
        arrow.path = p
        arrow.strokeColor = NSColor(hex: 0xFF3B30).cgColor
        arrow.fillColor = nil
        arrow.lineWidth = 3
        arrow.lineCap = .round
        arrow.lineJoin = .round
        root.addSublayer(arrow)
        box(CGRect(x: s.width * 0.18, y: 7, width: s.width * 0.64, height: 12), dark ? NSColor(hex: 0x26272E) : NSColor.white, radius: 6)
    }
}

/// The menu bar scene (bottom-up coordinates). One 9-second loop:
/// pointer → camera icon → menu drops → Open ScreenShot → the home window pops up; then ⇧⌘2 → area selection.
final class MenuBarDemoView: NSView {
    private let desktop = CAGradientLayer()
    private let camHighlight = CALayer()
    private let dropMenu = CALayer()
    private let rowHighlight = CALayer()
    private let home = CALayer()
    private let cursor = CALayer()
    private let dim = CALayer()
    private let selection = CAShapeLayer()
    private let keys = CALayer()
    private var keycaps: [CALayer] = []
    private let caption1 = CATextLayer()
    private let caption2 = CATextLayer()
    private var camCenter = CGPoint.zero
    private var openRowCenter = CGPoint.zero
    private let sel = CGRect(x: 70, y: 70, width: 230, height: 140)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func symbol(_ name: String, size: CGFloat, color: NSColor = .white) -> CGImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return nil }
        let img = NSImage(size: base.size, flipped: false) { r in
            base.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func textLayer(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
                           align: CATextLayerAlignmentMode = .left) -> CATextLayer {
        let t = CATextLayer()
        t.string = s
        t.font = NSFont.systemFont(ofSize: size, weight: weight)
        t.fontSize = size
        t.foregroundColor = color.cgColor
        t.alignmentMode = align
        t.contentsScale = 2
        return t
    }

    private func build() {
        guard let root = layer else { return }
        let b = CGRect(origin: .zero, size: frame.size)
        // Desktop with a wallpaper gradient.
        desktop.frame = b
        desktop.cornerRadius = 16
        desktop.masksToBounds = true
        desktop.colors = [NSColor(hex: 0x2B5BD6).cgColor, NSColor(hex: 0x7A3CFF).cgColor, NSColor(hex: 0xE0306E).cgColor]
        desktop.startPoint = CGPoint(x: 0, y: 0)
        desktop.endPoint = CGPoint(x: 1, y: 1)
        desktop.borderWidth = 1
        desktop.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        root.addSublayer(desktop)
        root.shadowColor = NSColor.black.cgColor
        root.shadowOpacity = 0.5
        root.shadowRadius = 26
        root.shadowOffset = CGSize(width: 0, height: -10)

        // Menu bar.
        let barH: CGFloat = 26
        let bar = CALayer()
        bar.frame = CGRect(x: 0, y: b.height - barH, width: b.width, height: barH)
        bar.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        desktop.addSublayer(bar)
        let apple = CALayer()
        apple.contents = Self.symbol("apple.logo", size: 13)
        apple.contentsGravity = .resizeAspect
        apple.frame = CGRect(x: 14, y: 5, width: 15, height: 16)
        bar.addSublayer(apple)
        var x: CGFloat = 44
        for (i, word) in ["Finder", "File", "Edit", "View", "Window"].enumerated() {
            let t = textLayer(word, size: 12.5, weight: i == 0 ? .bold : .medium)
            let w = (word as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .bold)]).width + 4
            t.frame = CGRect(x: x, y: 5, width: w, height: 17)
            bar.addSublayer(t)
            x += w + 14
        }
        let clock = textLayer("Fri 9:41", size: 12.5, weight: .medium, align: .right)
        clock.frame = CGRect(x: b.width - 84, y: 5, width: 70, height: 17)
        bar.addSublayer(clock)
        let icons = ["camera.viewfinder", "battery.75percent", "wifi"]
        var ix = b.width - 112
        for name in icons {
            let l = CALayer()
            l.contents = Self.symbol(name, size: 13)
            l.contentsGravity = .resizeAspect
            l.frame = CGRect(x: ix - 18, y: 5, width: 18, height: 16)
            if name == "camera.viewfinder" {
                camCenter = CGPoint(x: l.frame.midX, y: b.height - barH / 2)
                camHighlight.frame = CGRect(x: l.frame.minX - 6, y: 3, width: l.frame.width + 12, height: 20)
                camHighlight.cornerRadius = 5
                camHighlight.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
                bar.addSublayer(camHighlight)
            }
            bar.addSublayer(l)
            ix -= 34
        }

        // The ScreenShot menu, hanging from the icon.
        let shortcut: (HotkeyAction, String) -> String = { a, fallback in HotKeyCenter.shared.shortcut(for: a)?.display ?? fallback }
        let items: [(String, String)?] = [
            ("Open ScreenShot", "⌘L"), nil,
            ("Area Capture", shortcut(.area, "⇧⌘2")), ("Fullscreen", shortcut(.fullscreen, "⇧⌘1")),
            ("Window", shortcut(.anyWindow, "⇧⌘7")), ("Scrolling Capture", shortcut(.scrolling, "⇧⌘8")), nil,
            ("Welcome Guide…", ""), ("Preferences…", "⌘,"),
        ]
        let rowH: CGFloat = 22, menuW: CGFloat = 232
        let menuH = CGFloat(items.reduce(0) { $0 + ($1 == nil ? 9 : Int(rowH)) }) + 10
        let menuTop = b.height - barH - 2
        dropMenu.frame = CGRect(x: min(b.width - menuW - 8, camCenter.x - 30), y: menuTop - menuH, width: menuW, height: menuH)
        dropMenu.backgroundColor = NSColor(hex: 0x2A2A33).withAlphaComponent(0.96).cgColor
        dropMenu.cornerRadius = 9
        dropMenu.borderWidth = 0.5
        dropMenu.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        dropMenu.shadowColor = NSColor.black.cgColor
        dropMenu.shadowOpacity = 0.5
        dropMenu.shadowRadius = 14
        dropMenu.shadowOffset = CGSize(width: 0, height: -6)
        // Drops down from its top edge.
        dropMenu.anchorPoint = CGPoint(x: 0.5, y: 1)
        dropMenu.frame = CGRect(x: min(b.width - menuW - 8, camCenter.x - 30), y: menuTop - menuH, width: menuW, height: menuH)
        root.addSublayer(dropMenu)
        var y = menuH - 5
        for item in items {
            guard let (title, keys) = item else {
                let sep = CALayer()
                sep.frame = CGRect(x: 10, y: y - 5, width: menuW - 20, height: 1)
                sep.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
                dropMenu.addSublayer(sep)
                y -= 9
                continue
            }
            y -= rowH
            if title == "Open ScreenShot" {
                rowHighlight.frame = CGRect(x: 5, y: y, width: menuW - 10, height: rowH)
                rowHighlight.cornerRadius = 5
                rowHighlight.backgroundColor = NSColor(hex: 0x0A6CFF).cgColor
                dropMenu.addSublayer(rowHighlight)
                openRowCenter = CGPoint(x: dropMenu.frame.minX + menuW * 0.4, y: dropMenu.frame.minY + y + rowH / 2)
            }
            let t = textLayer(title, size: 12.5, weight: title == "Open ScreenShot" ? .semibold : .regular)
            t.frame = CGRect(x: 14, y: y + 3, width: 150, height: 17)
            dropMenu.addSublayer(t)
            let k = textLayer(keys, size: 12, color: NSColor.white.withAlphaComponent(0.5), align: .right)
            k.frame = CGRect(x: menuW - 74, y: y + 3, width: 60, height: 17)
            dropMenu.addSublayer(k)
        }

        // Home window that "Open ScreenShot" brings up.
        home.frame = CGRect(x: 40, y: 34, width: 280, height: 178)
        home.backgroundColor = NSColor(hex: 0x1D1E24).cgColor
        home.cornerRadius = 10
        home.borderWidth = 0.5
        home.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        home.shadowColor = NSColor.black.cgColor
        home.shadowOpacity = 0.6
        home.shadowRadius = 18
        home.shadowOffset = CGSize(width: 0, height: -8)
        root.addSublayer(home)
        let titleBar = CALayer()
        titleBar.frame = CGRect(x: 0, y: home.bounds.height - 30, width: home.bounds.width, height: 30)
        titleBar.backgroundColor = NSColor(hex: 0x26272E).cgColor
        titleBar.cornerRadius = 10
        titleBar.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        home.addSublayer(titleBar)
        for (i, c) in [NSColor(hex: 0xFF5F57), NSColor(hex: 0xFEBC2E), NSColor(hex: 0x28C840)].enumerated() {
            let d = CALayer()
            d.frame = CGRect(x: 10 + CGFloat(i) * 13, y: 10, width: 9, height: 9)
            d.cornerRadius = 4.5
            d.backgroundColor = c.cgColor
            titleBar.addSublayer(d)
        }
        for (i, label) in ["Area", "Window", "Fullscreen"].enumerated() {
            let pill = textLayer(label, size: 9.5, weight: .semibold, align: .center)
            pill.frame = CGRect(x: 56 + CGFloat(i) * 58, y: 9, width: 54, height: 13)
            pill.backgroundColor = NSColor.white.withAlphaComponent(i == 0 ? 0.25 : 0.1).cgColor
            pill.cornerRadius = 4
            titleBar.addSublayer(pill)
        }
        let colors: [UInt32] = [0x3DA9FF, 0xFF6A3D, 0xB35CFF, 0x34C759, 0xFFC83D, 0x2B5BD6]
        for (i, c) in colors.enumerated() {
            let thumb = CAGradientLayer()
            let col = CGFloat(i % 3), row = CGFloat(i / 3)
            thumb.frame = CGRect(x: 14 + col * 86, y: 80 - row * 64, width: 78, height: 54)
            thumb.cornerRadius = 6
            thumb.colors = [NSColor(hex: c).cgColor, NSColor(hex: c).blended(withFraction: 0.5, of: .black)!.cgColor]
            home.addSublayer(thumb)
        }

        // ⇧⌘2: keycaps, then the screen dims and a selection is dragged.
        dim.frame = b
        dim.backgroundColor = NSColor.black.cgColor
        dim.cornerRadius = 16
        root.addSublayer(dim)
        selection.fillColor = NSColor.white.withAlphaComponent(0.12).cgColor
        selection.strokeColor = NSColor(hex: 0xFF6A3D).cgColor
        selection.lineWidth = 2
        selection.lineDashPattern = [7, 5]
        root.addSublayer(selection)
        let labels = (HotKeyCenter.shared.shortcut(for: .area)?.display ?? "⇧⌘2").map(String.init)
        let capW: CGFloat = 46, gap: CGFloat = 10
        let total = CGFloat(labels.count) * capW + CGFloat(labels.count - 1) * gap
        keys.frame = CGRect(x: (b.width - total) / 2, y: 86, width: total, height: 52)
        root.addSublayer(keys)
        for (i, ch) in labels.enumerated() {
            let base = CALayer()
            base.frame = CGRect(x: CGFloat(i) * (capW + gap), y: 0, width: capW, height: 48)
            base.cornerRadius = 9
            base.backgroundColor = NSColor(hex: 0x0E0E13).cgColor
            base.shadowColor = NSColor.black.cgColor
            base.shadowOpacity = 0.6
            base.shadowRadius = 10
            base.shadowOffset = CGSize(width: 0, height: -4)
            keys.addSublayer(base)
            let top = CAGradientLayer()
            top.frame = CGRect(x: 0, y: 5, width: capW, height: 43)
            top.cornerRadius = 9
            top.colors = [NSColor(hex: 0x40404D).cgColor, NSColor(hex: 0x2A2A34).cgColor]
            top.borderWidth = 1
            top.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            base.addSublayer(top)
            let t = textLayer(ch, size: 20, weight: .semibold, align: .center)
            t.frame = CGRect(x: 0, y: 9, width: capW, height: 26)
            top.addSublayer(t)
            keycaps.append(top)
        }

        // Captions along the bottom of the desktop.
        for (c, s) in [(caption1, "Click the icon › Open ScreenShot"), (caption2, "…or press \(labels.joined()) from any app")] {
            c.string = s
            c.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            c.fontSize = 13
            c.foregroundColor = NSColor.white.cgColor
            c.alignmentMode = .center
            c.contentsScale = 2
            c.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
            c.cornerRadius = 12
            let w = (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width + 30
            c.frame = CGRect(x: b.width - w - 14, y: 12, width: w, height: 24)
            root.addSublayer(c)
        }

        // Pointer.
        if let arrow = NSCursor.arrow.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let size = NSCursor.arrow.image.size, hot = NSCursor.arrow.hotSpot
            cursor.contents = arrow
            cursor.bounds = CGRect(origin: .zero, size: size)
            cursor.anchorPoint = CGPoint(x: hot.x / size.width, y: 1 - hot.y / size.height)
        }
        root.addSublayer(cursor)
        showFinal()
    }

    /// The still picture (what a static snapshot or reduced motion shows): the menu open on Open ScreenShot.
    private func showFinal() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [home, dim, selection, keys, caption2] as [CALayer] { l.opacity = 0 }
        for l in [dropMenu, camHighlight, rowHighlight, cursor, caption1] as [CALayer] { l.opacity = 1 }
        cursor.position = openRowCenter
        selection.path = CGPath(rect: sel, transform: nil)
        CATransaction.commit()
    }

    func start() {
        let loop = LoopTracks(cycle: 9)
        let t = loop.add
        func pt(_ p: CGPoint) -> NSValue { NSValue(point: p) }
        let rest = CGPoint(x: 330, y: 150)
        // Part 1: the menu bar.
        t(cursor, "opacity", [(0, 0.0), (0.3, 1.0), (2.6, 1.0), (2.8, 0.0)])
        t(cursor, "position", [(0, pt(rest)), (0.3, pt(rest)), (1.1, pt(camCenter)), (1.5, pt(camCenter)), (2.1, pt(openRowCenter))])
        t(cursor, "transform.scale", [(0, 1.0), (1.15, 1.0), (1.22, 0.85), (1.3, 1.0), (2.3, 1.0), (2.37, 0.85), (2.45, 1.0)])
        t(camHighlight, "opacity", [(0, 0.0), (1.2, 0.0), (1.22, 1.0), (2.4, 1.0), (2.5, 0.0)])
        t(dropMenu, "opacity", [(0, 0.0), (1.2, 0.0), (1.3, 1.0), (2.4, 1.0), (2.6, 0.0)])
        t(dropMenu, "transform.scale.y", [(0, 0.6), (1.2, 0.6), (1.42, 1.0)])
        t(rowHighlight, "opacity", [(0, 0.0), (1.95, 0.0), (2.0, 1.0), (2.4, 1.0), (2.45, 0.0)])
        t(home, "opacity", [(0, 0.0), (2.5, 0.0), (2.75, 1.0), (4.2, 1.0), (4.5, 0.0)])
        t(home, "transform.scale", [(0, 0.85), (2.5, 0.85), (2.8, 1.04), (2.95, 1.0)])
        t(caption1, "opacity", [(0, 0.0), (0.3, 1.0), (4.2, 1.0), (4.45, 0.0)])
        // Part 2: the shortcut.
        t(caption2, "opacity", [(0, 0.0), (4.55, 0.0), (4.8, 1.0), (8.4, 1.0), (8.8, 0.0)])
        t(keys, "opacity", [(0, 0.0), (4.6, 0.0), (4.85, 1.0), (6.2, 1.0), (6.45, 0.0)])
        t(keys, "transform.scale", [(0, 0.8), (4.6, 0.8), (4.95, 1.0)])
        for (i, cap) in keycaps.enumerated() {
            let down = 5.1 + Double(i) * 0.22
            t(cap, "transform.translation.y", [(0, 0.0), (down, 0.0), (down + 0.06, -4.0), (5.95, -4.0), (6.03, 0.0)])
            t(cap, "opacity", [(0, 1.0), (down, 1.0), (down + 0.06, 0.8), (5.95, 0.8), (6.03, 1.0)])
        }
        t(dim, "opacity", [(0, 0.0), (6.1, 0.0), (6.35, 0.35), (8.4, 0.35), (8.8, 0.0)])
        let dot = CGPath(rect: CGRect(x: sel.minX, y: sel.maxY, width: 1, height: 1), transform: nil)
        t(selection, "opacity", [(0, 0.0), (6.4, 0.0), (6.42, 1.0), (8.4, 1.0), (8.8, 0.0)])
        t(selection, "path", [(0, dot), (6.4, dot), (7.3, CGPath(rect: sel, transform: nil))])
        let ants = CABasicAnimation(keyPath: "lineDashPhase")
        ants.fromValue = 0
        ants.toValue = -24
        ants.duration = 0.6
        ants.repeatCount = .infinity
        selection.add(ants, forKey: "ants")
    }

    func stop() {
        layer?.sublayers?.forEach { $0.removeAllAnimations() }
        keycaps.forEach { $0.removeAllAnimations() }
        showFinal()
    }
}
