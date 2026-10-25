import AppKit
import QuartzCore

private typealias DT = DesignTokens

// The welcome guide in the new look (ROADMAP, Fase 6 · R8): three steps — Welcome (what the app does, with a short
// looping demo), Set up (Screen Recording, where screenshots go and what happens after each one, light or dark) and
// Ready (the shortcuts and the first capture). The window, navigation and resume-after-relaunch are the old guide's.

// MARK: - Window chrome

/// The window's background: the editor canvas's color with its dot grid.
final class DottedBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DT.color(.canvas).setFill()
        dirtyRect.fill()
        DT.color(.dot).setFill()
        var y = (dirtyRect.minY / 16).rounded(.down) * 16
        while y < dirtyRect.maxY {
            var x = (dirtyRect.minX / 16).rounded(.down) * 16
            while x < dirtyRect.maxX {
                NSBezierPath(ovalIn: CGRect(x: x + 7.5, y: y + 7.5, width: 1.6, height: 1.6)).fill()
                x += 16
            }
            y += 16
        }
    }
}

/// The footer band: the bars' color with a hairline on top.
final class FooterBar: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DT.color(.chrome).setFill()
        bounds.fill()
        DT.color(.lineSoft).setFill()
        CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

/// A text-only button (Back, Skip).
final class PlainButton: NSView {
    let title: String
    let onClick: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }

    init(title: String, onClick: @escaping () -> Void) {
        self.title = title
        self.onClick = onClick
        let w = ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).width) + 24
        super.init(frame: CGRect(x: 0, y: 0, width: w, height: 32))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if hovering { DT.color(.hover).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill() }
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: DT.color(.ink2)]
        let s = (title as NSString).size(withAttributes: a)
        (title as NSString).draw(at: CGPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2), withAttributes: a)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() } }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}

/// The main action: filled with the accent, near-black label (white on #FF5500 is under 4.5:1).
final class AccentButton: NSView {
    var title: String { didSet { resize(); needsDisplay = true; setAccessibilityLabel(title) } }
    let onClick: () -> Void
    var onResize: (() -> Void)?
    var icon: IconName?
    private let font: NSFont
    private var pressed = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }

    init(title: String, large: Bool = false, icon: IconName? = nil, onClick: @escaping () -> Void) {
        self.title = title
        self.onClick = onClick
        self.icon = icon
        font = .systemFont(ofSize: large ? 15 : 13, weight: .semibold)
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: large ? 44 : 32))
        resize()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func resize() {
        let w = ceil((title as NSString).size(withAttributes: [.font: font]).width) + (icon == nil ? 36 : 62)
        setFrameSize(NSSize(width: w, height: frame.height))
        onResize?()
    }

    override func draw(_ dirtyRect: NSRect) {
        (pressed ? DT.color(.accentPressed) : hovering ? DT.color(.accentHover) : DT.color(.accent)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height > 40 ? 10 : 8, yRadius: bounds.height > 40 ? 10 : 8).fill()
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: DT.onAccent]
        let s = (title as NSString).size(withAttributes: a)
        var x = (bounds.width - s.width) / 2
        if let icon {
            x += 13
            Icons.image(icon, size: 18, color: DT.onAccent, stroke: 1.8).draw(in: CGRect(x: x - 26, y: (bounds.height - 18) / 2, width: 18, height: 18))
        }
        (title as NSString).draw(at: CGPoint(x: x, y: (bounds.height - s.height) / 2), withAttributes: a)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}

/// The footer's step names: the current one in the soft accent, the ones behind in the secondary ink.
final class StepTabs: NSView {
    let titles: [String]
    let onPick: (Int) -> Void
    var selected = 0 { didSet { needsDisplay = true; setAccessibilityValue("Step \(selected + 1) of \(titles.count)") } }
    private let font = NSFont.systemFont(ofSize: 12)
    private var widths: [CGFloat] = []

    init(titles: [String], onPick: @escaping (Int) -> Void) {
        self.titles = titles
        self.onPick = onPick
        super.init(frame: .zero)
        widths = titles.map { ceil(($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width) + 20 }
        setFrameSize(NSSize(width: widths.reduce(0, +) + CGFloat(titles.count - 1) * 8, height: 24))
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Steps")
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rect(_ i: Int) -> CGRect {
        CGRect(x: widths.prefix(i).reduce(0, +) + CGFloat(i) * 8, y: 0, width: widths[i], height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, t) in titles.enumerated() {
            let r = rect(i)
            let on = i == selected
            if on { DT.color(.accentSoft).setFill(); NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill() }
            let a: [NSAttributedString.Key: Any] = [
                .font: on ? NSFont.systemFont(ofSize: 12, weight: .semibold) : font,
                .foregroundColor: on ? DT.color(.accentText) : i < selected ? DT.color(.ink2) : DT.color(.ink3),
            ]
            let s = (t as NSString).size(withAttributes: a)
            (t as NSString).draw(at: CGPoint(x: r.midX - s.width / 2, y: (r.height - s.height) / 2), withAttributes: a)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = titles.indices.first(where: { rect($0).contains(p) }) { onPick(i) }
    }
}

// MARK: - Shared page pieces

extension OnboardingPage {
    /// A plain headline in the design's ink (the new guide has no gradient titles).
    @discardableResult
    func modernTitle(_ s: String, y: CGFloat, size: CGFloat) -> NSTextField {
        text(s, y: y, size: size, weight: .bold, color: DT.color(.ink), width: 700)
    }

    @discardableResult
    func modernText(_ s: String, y: CGFloat, size: CGFloat = 14, width: CGFloat = 520, color: NSColor = DT.color(.ink2)) -> NSTextField {
        text(s, y: y, size: size, color: color, width: width)
    }
}

/// A flipped, rounded panel (cards inside the guide's pages).
class GuidePanel: NSView {
    var fill: NSColor { DT.color(.panel) }
    var edge: NSColor? { DT.color(.line) }
    var radius: CGFloat = 12
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill(); p.fill()
        if let edge { edge.setStroke(); p.lineWidth = 1; p.stroke() }
    }
}

// MARK: - 1 · Welcome

/// What the app does in three cards; a short loop lights one after another (still under Reduce Motion).
final class WelcomeStep: OnboardingPage {
    override var continueTitle: String { "Get Started" }
    private(set) var cards: [FeatureCard] = []
    private var timer: Timer?
    private(set) var active = 0
    private var parts: [NSView] = []

    override func build() {
        let mark = GuidePanel(frame: CGRect(x: (bounds.width - 60) / 2, y: 52, width: 60, height: 60))
        mark.radius = 16
        let icon = NSImageView(frame: mark.bounds.insetBy(dx: 13, dy: 13))
        icon.image = Icons.image(.statusMark, size: 34, color: DT.color(.accent), stroke: 2)
        mark.addSubview(icon)
        addSubview(mark)
        let title = modernTitle("Welcome to ScreenShot", y: 128, size: 32)
        let sub = modernText("Capture anything on your screen, mark it up beautifully and share it in seconds.", y: 178, size: 15, width: 480)
        let features: [(FeatureIllustration.Kind, String, String)] = [
            (.capture, "Capture anything", "Drag over any part of the screen, a window, or a long scrolling page."),
            (.edit, "Mark it up", "The editor opens with arrows, text, blur, callouts and more."),
            (.share, "Always one click away", "Every capture lives in the menu bar icon, or press \(HotKeyCenter.shared.shortcut(for: .area)?.display ?? "⇧⌘2") from any app."),
        ]
        let w: CGFloat = 236, gap: CGFloat = 14
        var x = (bounds.width - w * 3 - gap * 2) / 2
        for (kind, t, body) in features {
            let c = FeatureCard(frame: CGRect(x: x, y: 236, width: w, height: 222), kind: kind, title: t, body: body)
            addSubview(c)
            cards.append(c)
            x += w + gap
        }
        parts = [mark, title, sub]
        highlight(0)
    }

    func highlight(_ i: Int) {
        active = i
        for (j, c) in cards.enumerated() { c.isActive = j == i }
    }

    override func play() {
        for (i, v) in parts.enumerated() { rise(v, delay: 0.05 + Double(i) * 0.1) }
        for (i, c) in cards.enumerated() { rise(c, delay: 0.35 + Double(i) * 0.08, distance: 20) }
        guard !Self.reduceMotion else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    self.highlight((self.active + 1) % self.cards.count)
                }
            }
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }

    var isLooping: Bool { timer != nil }
}

/// One feature: a small illustration, its name and a line; the lit one wears the accent ring.
final class FeatureCard: GuidePanel {
    var isActive = false { didSet { needsDisplay = true; progress.needsDisplay = true } }
    private let progress = ProgressLine()

    init(frame: NSRect, kind: FeatureIllustration.Kind, title: String, body: String) {
        super.init(frame: frame)
        let art = FeatureIllustration(frame: CGRect(x: 8, y: 8, width: frame.width - 16, height: 118), kind: kind)
        addSubview(art)
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13.5, weight: .semibold)
        t.textColor = DT.color(.ink)
        t.frame = CGRect(x: 12, y: 134, width: frame.width - 24, height: 18)
        addSubview(t)
        let b = NSTextField(wrappingLabelWithString: body)
        b.font = .systemFont(ofSize: 12)
        b.textColor = DT.color(.ink2)
        b.frame = CGRect(x: 12, y: 156, width: frame.width - 24, height: 50)
        addSubview(b)
        progress.card = self
        progress.frame = CGRect(x: 12, y: frame.height - 10, width: frame.width - 24, height: 3)
        addSubview(progress)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(title). \(body)")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var edge: NSColor? { isActive ? DT.color(.accent) : DT.color(.line) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isActive {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
            ring.lineWidth = 2
            DT.color(.accent).setStroke()
            ring.stroke()
        }
    }

    final class ProgressLine: NSView {
        weak var card: FeatureCard?
        override func draw(_ dirtyRect: NSRect) {
            guard card?.isActive == true else { return }
            DT.color(.lineSoft).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
            DT.color(.accent).setFill()
            NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: bounds.width * 0.6, height: bounds.height), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

/// The three features drawn small: a marquee over a screen, the ribbon editor with an arrow, the menu bar menu.
final class FeatureIllustration: NSView {
    enum Kind { case capture, edit, share }
    let kind: Kind

    init(frame: NSRect, kind: Kind) {
        self.kind = kind
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let clip = NSBezierPath(roundedRect: b, xRadius: 8, yRadius: 8)
        DT.color(.canvas).setFill(); clip.fill()
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        func box(_ r: CGRect, _ c: NSColor, _ radius: CGFloat = 3) { c.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }
        let white = NSColor.white, ink = NSColor(hex: 0x2E3440), grey = NSColor(hex: 0xC9CDD5), red = NSColor(hex: 0xF23D4F)
        switch kind {
        case .capture:
            box(CGRect(x: 18, y: 16, width: b.width - 36, height: 86), white, 5)
            box(CGRect(x: 30, y: 28, width: 80, height: 8), ink)
            box(CGRect(x: 30, y: 44, width: 120, height: 5), grey)
            box(CGRect(x: 30, y: 60, width: 70, height: 30), NSColor(hex: 0xE6EEFF))
            box(CGRect(x: 110, y: 60, width: b.width - 140, height: 30), NSColor(hex: 0xF1F2F5))
            let marquee = CGRect(x: 50, y: 24, width: 150, height: 64)
            DT.color(.accent).withAlphaComponent(0.08).setFill(); marquee.fill()
            let p = NSBezierPath(rect: marquee.insetBy(dx: 0.75, dy: 0.75))
            p.lineWidth = 1.5
            p.setLineDash([4, 3], count: 2, phase: 0)
            DT.color(.accent).setStroke(); p.stroke()
            let label = "150 × 64" as NSString
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9.5, weight: .semibold), .foregroundColor: DT.onAccent]
            let s = label.size(withAttributes: a)
            box(CGRect(x: marquee.maxX - s.width - 12, y: marquee.maxY + 4, width: s.width + 12, height: 16), DT.color(.accent), 4)
            label.draw(at: CGPoint(x: marquee.maxX - s.width - 6, y: marquee.maxY + 5), withAttributes: a)
        case .edit:
            box(CGRect(x: 0, y: 0, width: b.width, height: 26), DT.color(.chrome), 0)
            var x: CGFloat = 8
            for name in [IconName.select, .line, .arrow, .rect, .callout, .counter, .blur] {
                let r = CGRect(x: x, y: 4, width: 18, height: 18)
                if name == .arrow { box(r, DT.color(.accent), 4) }
                Icons.image(name, size: 12, color: name == .arrow ? .white : DT.color(.ink2)).draw(in: r.insetBy(dx: 3, dy: 3))
                x += 20
            }
            box(CGRect(x: 46, y: 38, width: 150, height: 70), white, 4)
            let r = NSBezierPath(roundedRect: CGRect(x: 118, y: 48, width: 68, height: 40), xRadius: 4, yRadius: 4)
            r.lineWidth = 2; red.setStroke(); r.stroke()
            let a = NSBezierPath(); a.move(to: CGPoint(x: 64, y: 98)); a.line(to: CGPoint(x: 110, y: 79))
            a.lineWidth = 2.5; a.lineCapStyle = .round; a.stroke()
            let head = NSBezierPath(); head.move(to: CGPoint(x: 116, y: 76)); head.line(to: CGPoint(x: 107.6, y: 75.1)); head.line(to: CGPoint(x: 111.4, y: 82.6)); head.close()
            red.setFill(); head.fill()
            NSBezierPath(ovalIn: CGRect(x: 54, y: 84, width: 20, height: 20)).fill()
            let one = "1" as NSString
            one.draw(at: CGPoint(x: 61, y: 86), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: white])
        case .share:
            box(CGRect(x: 0, y: 0, width: b.width, height: 20), NSColor(hex: 0x121216).withAlphaComponent(0.55), 0)
            box(CGRect(x: b.width - 72, y: 2, width: 22, height: 16), white.withAlphaComponent(0.22), 4)
            Icons.image(.statusMark, size: 12, color: NSColor(hex: 0xF2F2F4)).draw(in: CGRect(x: b.width - 67, y: 4, width: 12, height: 12))
            ("10:42" as NSString).draw(at: CGPoint(x: b.width - 40, y: 4), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor(hex: 0xF2F2F4)])
            let menu = CGRect(x: b.width - 190, y: 24, width: 156, height: 64)
            box(menu, NSColor(hex: 0x25262B), 7)
            for (i, (icon, t, key)) in [(IconName.photo, "Open ScreenShot", "⌘L"), (.capArea, "Area Capture", "⇧⌘2"), (.capWindow, "Any Window", "⇧⌘7")].enumerated() {
                let row = CGRect(x: menu.minX + 3, y: menu.minY + 3 + CGFloat(i) * 19, width: menu.width - 6, height: 19)
                if i == 1 { box(row, NSColor(hex: 0x33343A), 4) }
                Icons.image(icon, size: 11, color: NSColor(hex: 0xB6B7BE)).draw(in: CGRect(x: row.minX + 6, y: row.minY + 4, width: 11, height: 11))
                (t as NSString).draw(at: CGPoint(x: row.minX + 22, y: row.minY + 3), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor(hex: 0xECECEF)])
                (key as NSString).draw(at: CGPoint(x: row.maxX - 30, y: row.minY + 3), withAttributes: [.font: NSFont.systemFont(ofSize: 9.5), .foregroundColor: NSColor(hex: 0x8E8F97)])
            }
            let chip = CGRect(x: 10, y: b.height - 30, width: 124, height: 20)
            box(chip, DT.color(.successBackground), 6)
            Icons.image(.success, size: 11, color: DT.color(.success)).draw(in: CGRect(x: chip.minX + 6, y: chip.minY + 4.5, width: 11, height: 11))
            ("Copied to clipboard" as NSString).draw(at: CGPoint(x: chip.minX + 22, y: chip.minY + 3),
                                                     withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: DT.color(.ink)])
        }
        NSGraphicsContext.restoreGraphicsState()
        DT.color(.lineSoft).setStroke()
        NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }
}

// MARK: - 2 · Set up

/// Every choice in one card: Screen Recording, where screenshots go and what happens after each, light or dark.
final class SetupStep: OnboardingPage {
    private let status = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private let statusChip = StatusChip()
    private lazy var allow = AccentButton(title: "Allow Screen Recording") { [weak self] in self?.request() }
    private let path = NSTextField(labelWithString: "")
    private(set) var afterPills: [(key: String, pill: TogglePill)] = []
    private(set) var looks: [(value: String, card: LookPreview)] = []
    private var timer: Timer?
    private var parts: [NSView] = []

    override func build() {
        let title = modernTitle("Set up ScreenShot", y: 46, size: 28)
        let sub = modernText("Three quick choices. You can change any of them later in Preferences.", y: 88)
        let card = GuidePanel(frame: CGRect(x: (bounds.width - 700) / 2, y: 128, width: 700, height: 340))
        addSubview(card)
        func number(_ n: Int, y: CGFloat) {
            let badge = GuidePanel(frame: CGRect(x: 18, y: y, width: 22, height: 22))
            badge.radius = 11
            let l = NSTextField(labelWithString: "\(n)")
            l.font = .systemFont(ofSize: 11.5, weight: .semibold)
            l.textColor = DT.color(.ink2)
            l.alignment = .center
            l.frame = CGRect(x: 0, y: 3, width: 22, height: 16)
            badge.addSubview(l)
            card.addSubview(badge)
        }
        func label(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat = 14, weight: NSFont.Weight = .semibold, color: NSColor = DT.color(.ink), width: CGFloat = 400) -> NSTextField {
            let l = NSTextField(wrappingLabelWithString: s)
            l.font = .systemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.preferredMaxLayoutWidth = width
            let h = l.sizeThatFits(CGSize(width: width, height: 200)).height
            l.frame = CGRect(x: x, y: y, width: width, height: h)
            card.addSubview(l)
            return l
        }
        func hairline(_ y: CGFloat) {
            let v = HairlineView(frame: CGRect(x: 18, y: y, width: card.frame.width - 36, height: 1))
            card.addSubview(v)
        }

        // 1 · Screen Recording.
        number(1, y: 18)
        _ = label("Let ScreenShot see your screen", x: 54, y: 18)
        _ = label("macOS asks once for Screen Recording. ScreenShot only looks when you take a screenshot, and nothing leaves your Mac. If macOS offers to quit and reopen, go ahead: setup picks up here.",
                  x: 54, y: 40, size: 12.5, weight: .regular, color: DT.color(.ink2), width: 420)
        statusChip.frame = CGRect(x: card.frame.width - 218, y: 18, width: 200, height: 24)
        card.addSubview(statusChip)
        allow.frame.origin = CGPoint(x: card.frame.width - 18 - allow.frame.width, y: 50)
        card.addSubview(allow)
        hairline(110)

        // 2 · Where screenshots go and what happens after each one.
        number(2, y: 126)
        _ = label("Save screenshots to", x: 54, y: 126)
        path.font = .systemFont(ofSize: 12.5)
        path.textColor = DT.color(.ink2)
        path.lineBreakMode = .byTruncatingMiddle
        path.frame = CGRect(x: 260, y: 128, width: 300, height: 18)
        card.addSubview(path)
        let change = BarButton(title: "Change…", icon: .folder, tooltip: "Pick a folder for your screenshots")
        change.translatesAutoresizingMaskIntoConstraints = true
        change.frame = CGRect(x: card.frame.width - 18 - 108, y: 122, width: 108, height: 28)
        change.onClick = { [weak self] in self?.choose() }
        card.addSubview(change)
        _ = label("After each screenshot", x: 54, y: 166, size: 12.5, weight: .regular, color: DT.color(.ink2), width: 160)
        var x: CGFloat = 220
        for (key, title) in [(Keys.afterShow, "Open the editor"), (Keys.afterCopy, "Copy to clipboard"), (Keys.afterSave, "Save to folder")] {
            let pill = TogglePill(title: title, on: UserDefaults.standard.bool(forKey: key)) { on in UserDefaults.standard.set(on, forKey: key) }
            pill.frame.origin = CGPoint(x: x, y: 160)
            card.addSubview(pill)
            afterPills.append((key, pill))
            x += pill.frame.width + 8
        }
        hairline(206)

        // 3 · Light or dark.
        number(3, y: 222)
        _ = label("Light or dark?", x: 54, y: 222)
        _ = label("Applies right away.", x: 54, y: 244, size: 12.5, weight: .regular, color: DT.color(.ink2), width: 200)
        var lx = card.frame.width - 18 - (3 * 100 + 2 * 14)
        for (value, name) in [("system", "System"), ("light", "Light"), ("dark", "Dark")] {
            let p = LookPreview(frame: CGRect(x: lx, y: 222, width: 100, height: 96), value: value, title: name) { [weak self] v in self?.chooseLook(v) }
            card.addSubview(p)
            looks.append((value, p))
            lx += 114
        }
        parts = [title, sub, card]
        refresh()
    }

    private var granted: Bool { CGPreflightScreenCaptureAccess() }

    private func refresh() {
        statusChip.set(granted: granted)
        allow.isHidden = granted
        path.stringValue = (Settings.saveFolder.path as NSString).abbreviatingWithTildeInPath
        path.toolTip = Settings.saveFolder.path
        for l in looks { l.card.isSelected = l.value == Settings.appearance }
    }

    private func request() {
        UserDefaults.standard.set(true, forKey: "askedScreenRecording")
        if !CGRequestScreenCaptureAccess(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func choose() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = "Use This Folder"
        p.message = "Pick a folder for your screenshots."
        p.directoryURL = Settings.saveFolder
        guard let win = window else { return }
        p.beginSheetModal(for: win) { [weak self] r in
            guard r == .OK, let url = p.url else { return }
            UserDefaults.standard.set(url.path, forKey: Keys.saveFolder)
            self?.refresh()
        }
    }

    /// Light, dark or follow macOS: every ScreenShot window, this guide included, changes at once.
    func chooseLook(_ value: String) {
        UserDefaults.standard.set(value, forKey: "appearance")
        Settings.applyAppearance()
        refresh()
    }

    #if SCREENSHOT_SELFTESTS
    var shownPath: String { path.stringValue }
    var allowShown: Bool { !allow.isHidden }
    #endif

    override func play() {
        for (i, v) in parts.enumerated() { rise(v, delay: 0.05 + Double(i) * 0.1, distance: i == 2 ? 24 : 16) }
        var was = granted
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.granted != was { was = self.granted; self.refresh() }
            }
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }
}

private final class HairlineView: NSView {
    override func draw(_ dirtyRect: NSRect) { DT.color(.line).setFill(); bounds.fill() }
}

/// Screen Recording's state: a warning until allowed, then success.
final class StatusChip: NSView {
    private(set) var granted = false
    override var isFlipped: Bool { true }

    func set(granted: Bool) {
        self.granted = granted
        setAccessibilityLabel(text)
        needsDisplay = true
    }

    private var text: String { granted ? "Screen Recording allowed" : "Not allowed yet" }

    override func draw(_ dirtyRect: NSRect) {
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: DT.color(.ink)]
        let s = (text as NSString).size(withAttributes: a)
        let w = s.width + 34
        let r = CGRect(x: bounds.width - w, y: 0, width: w, height: bounds.height)
        DT.color(granted ? .successBackground : .warningBackground).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        Icons.image(granted ? .success : .warning, size: 14, color: DT.color(granted ? .success : .warning)).draw(in: CGRect(x: r.minX + 8, y: r.midY - 7, width: 14, height: 14))
        (text as NSString).draw(at: CGPoint(x: r.minX + 26, y: r.midY - s.height / 2), withAttributes: a)
    }
}

/// An on/off choice as a pill: the soft accent with a check when on, a hairline with a cross when off.
final class TogglePill: NSView {
    let title: String
    private(set) var isOn: Bool
    private let onChange: (Bool) -> Void
    override var isFlipped: Bool { true }

    init(title: String, on: Bool, onChange: @escaping (Bool) -> Void) {
        self.title = title
        isOn = on
        self.onChange = onChange
        let w = ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12.5)]).width) + 40
        super.init(frame: CGRect(x: 0, y: 0, width: w, height: 28))
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(title)
        setAccessibilityValue(on)
    }
    required init?(coder: NSCoder) { fatalError() }

    func toggle() {
        isOn.toggle()
        setAccessibilityValue(isOn)
        needsDisplay = true
        onChange(isOn)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        if isOn { DT.color(.accentSoft).setFill(); p.fill(); DT.color(.accent).setStroke() } else { DT.color(.line).setStroke() }
        p.lineWidth = 1
        p.stroke()
        Icons.image(isOn ? .check : .close, size: 13, color: isOn ? DT.color(.ink) : DT.color(.ink2), stroke: 2).draw(in: CGRect(x: 10, y: 7.5, width: 13, height: 13))
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: isOn ? DT.color(.ink) : DT.color(.ink2)]
        (title as NSString).draw(at: CGPoint(x: 28, y: (bounds.height - (title as NSString).size(withAttributes: a).height) / 2), withAttributes: a)
    }

    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { toggle() } }
    override func accessibilityPerformPress() -> Bool { toggle(); return true }
}

/// A tiny editor in one look (System is half light, half dark); the chosen one has the accent ring and a check.
final class LookPreview: NSView {
    let value: String
    let title: String
    var isSelected = false { didSet { needsDisplay = true; setAccessibilityValue(isSelected) } }
    private let onPick: (String) -> Void
    override var isFlipped: Bool { true }

    init(frame: NSRect, value: String, title: String, onPick: @escaping (String) -> Void) {
        self.value = value
        self.title = title
        self.onPick = onPick
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let frameRect = CGRect(x: 2, y: 2, width: bounds.width - 4, height: 64)
        let shape = NSBezierPath(roundedRect: frameRect, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let lightTop = NSColor(hex: 0xF7F7F8), darkTop = NSColor(hex: 0x1C1D21), lightBody = NSColor(hex: 0xE8E8EC), darkBody = NSColor(hex: 0x141518)
        func halves(_ l: NSColor, _ d: NSColor, _ r: CGRect) {
            switch value {
            case "light": l.setFill(); r.fill()
            case "dark": d.setFill(); r.fill()
            default:
                l.setFill(); CGRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height).fill()
                d.setFill(); CGRect(x: r.midX, y: r.minY, width: r.width / 2, height: r.height).fill()
            }
        }
        halves(lightTop, darkTop, CGRect(x: frameRect.minX, y: frameRect.minY, width: frameRect.width, height: 16))
        halves(lightBody, darkBody, CGRect(x: frameRect.minX, y: frameRect.minY + 16, width: frameRect.width, height: frameRect.height - 16))
        NSColor.white.setFill()
        NSBezierPath(roundedRect: CGRect(x: frameRect.midX - 20, y: frameRect.minY + 28, width: 40, height: 22), xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        if isSelected {
            let ring = NSBezierPath(roundedRect: frameRect.insetBy(dx: -1, dy: -1), xRadius: 8, yRadius: 8)
            ring.lineWidth = 2
            DT.color(.accent).setStroke(); ring.stroke()
            let badge = CGRect(x: frameRect.maxX - 20, y: frameRect.maxY - 20, width: 16, height: 16)
            DT.color(.accent).setFill(); NSBezierPath(ovalIn: badge).fill()
            Icons.image(.check, size: 10, color: .white, stroke: 2.2).draw(in: badge.insetBy(dx: 3, dy: 3))
        } else {
            DT.color(.line).setStroke(); shape.stroke()
        }
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
                                                .foregroundColor: isSelected ? DT.color(.ink) : DT.color(.ink2)]
        let s = (title as NSString).size(withAttributes: a)
        (title as NSString).draw(at: CGPoint(x: (bounds.width - s.width) / 2, y: 72), withAttributes: a)
    }

    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onPick(value) } }
    override func accessibilityPerformPress() -> Bool { onPick(value); return true }
}

// MARK: - 3 · Ready

/// The send-off: the six shortcuts as tiles (Area outlined in the accent) and the first capture one click away.
final class ReadyStep: OnboardingPage {
    override var continueTitle: String { "Done" }
    private(set) var tiles: [NSView] = []
    private(set) lazy var firstCapture = AccentButton(title: "Take My First Screenshot", large: true, icon: .capArea) { [weak self] in
        self?.owner?.finish(capture: true)
    }
    private var parts: [NSView] = []

    override func build() {
        let check = GuidePanel(frame: CGRect(x: (bounds.width - 68) / 2, y: 44, width: 68, height: 68))
        check.radius = 34
        let mark = NSImageView(frame: check.bounds.insetBy(dx: 17, dy: 17))
        mark.image = Icons.image(.check, size: 34, color: DT.color(.accent), stroke: 3)
        check.addSubview(mark)
        addSubview(check)
        let title = modernTitle("You’re all set!", y: 124, size: 30)
        let sub = modernText("These shortcuts work from any app. Change them anytime in Preferences › Hotkeys, or use the camera icon in the menu bar.",
                             y: 168, width: 540)
        let shortcuts: [(HotkeyAction, IconName, String, String)] = [
            (.area, .capArea, "Area", "Drag over the screen"), (.fullscreen, .capFull, "Fullscreen", "The whole display"),
            (.anyWindow, .capWindow, "Window", "Click any window"), (.scrolling, .capScroll, "Scrolling", "Whole long pages"),
            (.ocr, .ocr, "Copy text", "Text or a QR code"), (.repeatArea, .capRepeat, "Repeat area", "Same area again"),
        ]
        let w: CGFloat = 256, h: CGFloat = 52, gap: CGFloat = 8
        let x0 = (bounds.width - (w * 3 + gap * 2)) / 2
        for (i, (action, icon, name, detail)) in shortcuts.enumerated() {
            let keys = HotKeyCenter.shared.shortcut(for: action)?.display ?? "—"
            let tile = ShortcutTile(frame: CGRect(x: x0 + CGFloat(i % 3) * (w + gap), y: 222 + CGFloat(i / 3) * (h + gap), width: w, height: h),
                                    icon: icon, title: name, detail: detail, keys: keys, hero: action == .area)
            addSubview(tile)
            tiles.append(tile)
        }
        firstCapture.frame.origin = CGPoint(x: (bounds.width - firstCapture.frame.width) / 2, y: 362)
        addSubview(firstCapture)
        parts = [check, title, sub]
    }

    override func play() {
        pop(parts[0], delay: 0.05)
        rise(parts[1], delay: 0.18)
        rise(parts[2], delay: 0.26)
        for (i, t) in tiles.enumerated() { rise(t, delay: 0.34 + Double(i) * 0.05, distance: 10) }
        rise(firstCapture, delay: 0.7)
    }
}

/// One shortcut: its icon, name and what it does, and its keys as keycaps.
final class ShortcutTile: GuidePanel {
    private let hero: Bool
    init(frame: NSRect, icon: IconName, title: String, detail: String, keys: String, hero: Bool) {
        self.hero = hero
        super.init(frame: frame)
        let i = NSImageView(frame: CGRect(x: 12, y: 16, width: 20, height: 20))
        i.image = Icons.image(icon, size: 20, color: hero ? DT.color(.accent) : DT.color(.ink2))
        addSubview(i)
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold)
        t.textColor = DT.color(.ink)
        t.frame = CGRect(x: 42, y: 9, width: 120, height: 17)
        addSubview(t)
        // Keycaps, right-aligned; the description gets what they leave.
        var x = frame.width - 12
        for ch in keys.reversed() {
            let cap = GuideKeycap(String(ch))
            x -= cap.frame.width
            cap.frame.origin = CGPoint(x: x, y: (frame.height - cap.frame.height) / 2)
            addSubview(cap)
            x -= 2
        }
        let d = NSTextField(labelWithString: detail)
        d.font = .systemFont(ofSize: 11.5)
        d.textColor = DT.color(.ink3)
        d.lineBreakMode = .byTruncatingTail
        d.frame = CGRect(x: 42, y: 27, width: x - 42 - 6, height: 16)
        addSubview(d)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(title): \(keys). \(detail)")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var edge: NSColor? { hero ? DT.color(.accent) : DT.color(.line) }
}

/// A key as a small cap.
final class GuideKeycap: NSView {
    private let key: String
    override var isFlipped: Bool { true }
    init(_ key: String) {
        self.key = key
        let w = max(20, ceil((key as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11.5)]).width) + 10)
        super.init(frame: CGRect(x: 0, y: 0, width: w, height: 22))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        DT.color(.chrome).setFill(); p.fill()
        DT.color(.line).setStroke(); p.stroke()
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: DT.color(.ink)]
        let s = (key as NSString).size(withAttributes: a)
        (key as NSString).draw(at: CGPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2), withAttributes: a)
    }
}
