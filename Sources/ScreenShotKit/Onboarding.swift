import AppKit
import QuartzCore

/// First-run welcome guide: what the app does, Screen Recording permission, the Screenshots folder and what happens
/// after a capture, the shortcuts, and a send-off. Shown once (Keys.onboardingDone); the menu bar menu reopens it.
/// If macOS quits the app to apply the permission, the guide resumes on the page it was on.
@MainActor final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static var shared: OnboardingWindowController?

    static var isDone: Bool { UserDefaults.standard.bool(forKey: Keys.onboardingDone) }

    static func show(from page: Int? = nil) {
        if shared == nil { shared = OnboardingWindowController() }
        NSApp.activate()
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        shared?.go(to: page ?? UserDefaults.standard.integer(forKey: Keys.onboardingPage), animated: false)
    }

    static let size = CGSize(width: 780, height: 540)
    private let pages: [OnboardingPage.Type] = [WelcomePage.self, DemoPage.self, PermissionPage.self, FolderPage.self,
                                                 ShortcutsPage.self, DonePage.self]
    private(set) var index = -1
    private let stage = NSView()
    private var current: OnboardingPage?
    private let dots = PageDots()
    private lazy var back = TextButton(title: "Back") { [weak self] in self?.go(to: (self?.index ?? 1) - 1) }
    private lazy var skip = TextButton(title: "Skip") { [weak self] in self?.finish(capture: false) }
    private lazy var next = GlowButton(title: "Continue") { [weak self] in self?.advance() }

    init() {
        let win = NSWindow(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        // Always dark: the aurora and glows are designed for it, whatever the app's appearance.
        win.appearance = NSAppearance(named: .darkAqua)
        win.title = "Welcome to ScreenShot"
        win.center()
        super.init(window: win)
        win.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        let aurora = AuroraView(frame: content.bounds)
        aurora.autoresizingMask = [.width, .height]
        content.addSubview(aurora)

        stage.frame = CGRect(x: 0, y: 76, width: Self.size.width, height: Self.size.height - 76)
        stage.wantsLayer = true
        content.addSubview(stage)

        let bar = NSView(frame: CGRect(x: 0, y: 0, width: Self.size.width, height: 76))
        content.addSubview(bar)
        back.frame.origin = CGPoint(x: 28, y: 24)
        dots.frame = CGRect(x: (Self.size.width - 140) / 2, y: 33, width: 140, height: 10)
        dots.count = pages.count
        next.frame = CGRect(x: Self.size.width - 28 - 168, y: 18, width: 168, height: 40)
        for v in [back, dots, next] as [NSView] { bar.addSubview(v) }
        skip.frame.origin = CGPoint(x: Self.size.width - 28 - skip.frame.width, y: Self.size.height - 40)
        content.addSubview(skip)
    }

    // MARK: Navigation

    private func advance() {
        if index == pages.count - 1 { finish(capture: false) } else { go(to: index + 1) }
    }

    func go(to i: Int, animated: Bool = true) {
        let i = max(0, min(pages.count - 1, i))
        guard i != index else { return }
        let forward = i > index
        index = i
        UserDefaults.standard.set(i, forKey: Keys.onboardingPage)
        let page = pages[i].init(frame: stage.bounds)
        page.owner = self
        if animated {
            let t = CATransition()
            t.type = .push
            t.subtype = forward ? .fromRight : .fromLeft
            t.duration = 0.45
            t.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            stage.layer?.add(t, forKey: "page")
        }
        current?.removeFromSuperview()
        current?.stop()
        stage.addSubview(page)
        current = page
        page.play()

        dots.selected = i
        back.isHidden = i == 0
        skip.isHidden = i == pages.count - 1
        next.title = page.continueTitle
        next.isHidden = page.hidesContinue
    }

    /// Ends the guide; `capture` starts an area screenshot right after, so the first one is one click away.
    func finish(capture: Bool) {
        UserDefaults.standard.set(true, forKey: Keys.onboardingDone)
        UserDefaults.standard.set(0, forKey: Keys.onboardingPage)
        // The permission page asked already; don't ask again on the next launch.
        UserDefaults.standard.set(true, forKey: "askedScreenRecording")
        current?.stop()
        window?.orderOut(nil)
        Self.shared = nil
        if capture { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { AppLogic.shared.run(.area) } }
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window counts as "seen": the menu bar menu brings the guide back.
        UserDefaults.standard.set(true, forKey: Keys.onboardingDone)
        UserDefaults.standard.set(0, forKey: Keys.onboardingPage)
        current?.stop()
        Self.shared = nil
    }

    #if SCREENSHOT_SELFTESTS
    var pageCount: Int { pages.count }
    var currentPage: OnboardingPage? { current }
    func pressContinue() { advance() }
    #endif
}

// MARK: - Pages

/// One page of the guide: a flipped canvas laid out top-down; `play` runs its entrance animation.
class OnboardingPage: NSView {
    weak var owner: OnboardingWindowController?
    var continueTitle: String { "Continue" }
    var hidesContinue: Bool { false }

    required override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func build() {}
    func play() {}
    func stop() {}

    // Layout helpers, all top-down in page coordinates.

    @discardableResult
    func text(_ s: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
              width: CGFloat = 560, x: CGFloat? = nil, align: NSTextAlignment = .center) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.alignment = align
        l.isSelectable = false
        l.preferredMaxLayoutWidth = width
        let h = l.sizeThatFits(CGSize(width: width, height: 400)).height
        l.frame = CGRect(x: x ?? (bounds.width - width) / 2, y: y, width: width, height: h)
        addSubview(l)
        return l
    }

    /// Gradient-filled headline (the text masks a warm gradient).
    @discardableResult
    func headline(_ s: String, y: CGFloat, size: CGFloat = 34) -> NSView {
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let w = ceil((s as NSString).size(withAttributes: [.font: font]).width) + 8
        let h = ceil(size * 1.3)
        let v = NSView(frame: CGRect(x: (bounds.width - w) / 2, y: y, width: w, height: h))
        v.wantsLayer = true
        let g = CAGradientLayer()
        g.frame = v.bounds
        g.colors = [NSColor.white.cgColor, NSColor(hex: 0xFFD3C2).cgColor, NSColor(hex: 0xFF8A5C).cgColor]
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        let mask = CATextLayer()
        mask.string = s
        mask.font = font
        mask.fontSize = size
        mask.alignmentMode = .center
        mask.frame = v.bounds
        mask.contentsScale = 2
        g.mask = mask
        v.layer?.addSublayer(g)
        v.setAccessibilityElement(true)
        v.setAccessibilityRole(.staticText)
        v.setAccessibilityLabel(s)
        addSubview(v)
        return v
    }

    /// Fades a view in while it rises a little, after `delay`.
    func rise(_ v: NSView, delay: CFTimeInterval, distance: CGFloat = 16) {
        v.wantsLayer = true
        guard let l = v.layer else { return }
        let start = CACurrentMediaTime() + delay
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        // "Lower on screen" is +y in a flipped layer tree and -y in a bottom-up one.
        move.fromValue = (l.superlayer?.contentsAreFlipped() ?? false) ? distance : -distance
        move.toValue = 0
        for a in [fade, move] {
            a.beginTime = start
            a.duration = 0.6
            a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            a.fillMode = .backwards
            l.add(a, forKey: a.keyPath)
        }
    }

    /// Springy pop from small to full size.
    func pop(_ v: NSView, delay: CFTimeInterval) {
        v.wantsLayer = true
        guard let l = v.layer else { return }
        // Scale around the center.
        l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        l.position = CGPoint(x: v.frame.midX, y: v.frame.midY)
        let s = CASpringAnimation(keyPath: "transform.scale")
        s.fromValue = 0.3
        s.toValue = 1
        s.damping = 11
        s.stiffness = 180
        s.mass = 1
        s.duration = s.settlingDuration
        s.beginTime = CACurrentMediaTime() + delay
        s.fillMode = .backwards
        l.add(s, forKey: "pop")
        let f = CABasicAnimation(keyPath: "opacity")
        f.fromValue = 0
        f.toValue = 1
        f.duration = 0.25
        f.beginTime = s.beginTime
        f.fillMode = .backwards
        l.add(f, forKey: "popFade")
    }

    /// A round glass badge with an SF Symbol, used as each page's hero icon.
    func heroIcon(_ symbol: String, y: CGFloat, tint: NSColor, size: CGFloat = 92) -> NSView {
        let v = NSView(frame: CGRect(x: (bounds.width - size) / 2, y: y, width: size, height: size))
        v.wantsLayer = true
        let disc = CAGradientLayer()
        disc.frame = v.bounds
        disc.cornerRadius = size / 2
        disc.colors = [tint.withAlphaComponent(0.95).cgColor, tint.blended(withFraction: 0.45, of: .black)!.cgColor]
        disc.startPoint = CGPoint(x: 0.2, y: 1)
        disc.endPoint = CGPoint(x: 0.8, y: 0)
        disc.shadowColor = tint.cgColor
        disc.shadowOpacity = 0.7
        disc.shadowRadius = 26
        disc.shadowOffset = .zero
        disc.borderWidth = 1
        disc.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        v.layer?.addSublayer(disc)
        let img = NSImageView(frame: v.bounds.insetBy(dx: size * 0.24, dy: size * 0.24))
        img.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size * 0.4, weight: .semibold))
        img.contentTintColor = .white
        v.addSubview(img)
        addSubview(v)
        return v
    }
}

/// 1 · Welcome: the icon drops in with a glowing halo, the headline and three promises rise in.
final class WelcomePage: OnboardingPage {
    private let icon = NSImageView()
    private let haloHost = NSView()
    private let halo = CAGradientLayer()
    private var chips: [NSView] = []
    private var title: NSView!
    private var subtitle: NSView!

    override var continueTitle: String { "Get Started" }

    override func build() {
        let size: CGFloat = 132
        let frame = CGRect(x: (bounds.width - size) / 2, y: 54, width: size, height: size)
        haloHost.frame = frame.insetBy(dx: -34, dy: -34)
        haloHost.wantsLayer = true
        addSubview(haloHost)
        halo.frame = haloHost.bounds.insetBy(dx: -30, dy: -30)
        halo.type = .radial
        halo.colors = [NSColor(hex: 0xFF5A2A).withAlphaComponent(0.75).cgColor, NSColor(hex: 0xFF5A2A).withAlphaComponent(0.28).cgColor,
                       NSColor(hex: 0xFF5A2A).withAlphaComponent(0).cgColor]
        halo.locations = [0, 0.45, 1]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        haloHost.layer?.addSublayer(halo)
        icon.frame = frame
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        // Warm glow that follows the icon's shape.
        let glow = NSShadow()
        glow.shadowColor = NSColor(hex: 0xFF5A2A).withAlphaComponent(0.85)
        glow.shadowBlurRadius = 38
        glow.shadowOffset = .zero
        icon.shadow = glow

        title = headline("Welcome to ScreenShot", y: 212, size: 38)
        subtitle = text("Capture anything on your screen, mark it up beautifully and share it in seconds.",
                        y: 268, size: 16, color: NSColor.white.withAlphaComponent(0.72), width: 460)

        let items: [(String, String, NSColor)] = [
            ("viewfinder", "Capture anything", NSColor(hex: 0xFF6A3D)),
            ("pencil.and.scribble", "Annotate beautifully", NSColor(hex: 0xB35CFF)),
            ("paperplane.fill", "Share instantly", NSColor(hex: 0x3DA9FF)),
        ]
        let w: CGFloat = 196, gap: CGFloat = 16
        var x = (bounds.width - (w * 3 + gap * 2)) / 2
        for (symbol, label, tint) in items {
            let chip = FeatureChip(symbol: symbol, title: label, tint: tint)
            chip.frame = CGRect(x: x, y: 340, width: w, height: 54)
            addSubview(chip)
            chips.append(chip)
            x += w + gap
        }
    }

    override func play() {
        pop(icon, delay: 0.05)
        // The halo breathes.
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.92
        breathe.toValue = 1.08
        breathe.duration = 2.4
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        halo.add(breathe, forKey: "breathe")
        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = 0.55
        glow.toValue = 1
        glow.duration = 2.4
        glow.autoreverses = true
        glow.repeatCount = .infinity
        halo.add(glow, forKey: "glow")
        rise(title, delay: 0.3)
        rise(subtitle, delay: 0.42)
        for (i, c) in chips.enumerated() { rise(c, delay: 0.6 + Double(i) * 0.12, distance: 22) }
    }

    override func stop() { halo.removeAllAnimations() }
}

/// 2 · A looping demo: a selection is dragged over a mock window, then an arrow, a counter and a label appear.
final class DemoPage: OnboardingPage {
    private var demo: CaptureDemoView!
    private var title: NSView!
    private var caption: NSView!

    override func build() {
        title = headline("Grab it, mark it up, done", y: 30, size: 30)
        caption = text("Drag over anything to capture it. The editor opens with arrows, text, blur, callouts and more.",
                       y: 76, size: 14, color: NSColor.white.withAlphaComponent(0.68), width: 480)
        // The scene is laid out for its size when it's made, so it gets its frame up front.
        demo = CaptureDemoView(frame: CGRect(x: (bounds.width - 520) / 2, y: 128, width: 520, height: 300))
        addSubview(demo)
    }

    override func play() {
        rise(title, delay: 0.05)
        rise(caption, delay: 0.15)
        rise(demo, delay: 0.25, distance: 24)
        demo.start()
    }

    override func stop() { demo.stop() }
}

/// 3 · Screen Recording: live status that turns green the moment access is granted.
final class PermissionPage: OnboardingPage {
    private var icon: NSView!
    private var title: NSView!
    private var body: NSView!
    private let status = StatusPill()
    private lazy var grant = GlowButton(title: "Allow Screen Recording", small: true) { [weak self] in self?.request() }
    private var note: NSView!
    private var timer: Timer?

    override func build() {
        icon = heroIcon("record.circle", y: 40, tint: NSColor(hex: 0xFF4D3A))
        title = headline("Let ScreenShot see your screen", y: 154, size: 30)
        body = text("macOS asks once for Screen Recording permission. ScreenShot only looks at your screen when you take a screenshot, and nothing leaves your Mac.",
                    y: 200, size: 14, color: NSColor.white.withAlphaComponent(0.7), width: 470)
        status.frame = CGRect(x: (bounds.width - 220) / 2, y: 274, width: 220, height: 34)
        addSubview(status)
        grant.frame = CGRect(x: (bounds.width - 240) / 2, y: 326, width: 240, height: 38)
        addSubview(grant)
        note = text("If macOS offers to quit and reopen ScreenShot, go ahead: this guide picks up right here.",
                    y: 382, size: 12, color: NSColor.white.withAlphaComponent(0.5), width: 420)
        refresh(animated: false)
    }

    private var granted: Bool { CGPreflightScreenCaptureAccess() }

    private func refresh(animated: Bool) {
        status.set(granted: granted, animated: animated)
        grant.isHidden = granted
        note.isHidden = granted
    }

    private func request() {
        UserDefaults.standard.set(true, forKey: "askedScreenRecording")
        // The first request shows macOS's prompt; after a refusal only System Settings can change it.
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    override func play() {
        pop(icon, delay: 0.05)
        rise(title, delay: 0.2)
        rise(body, delay: 0.3)
        rise(status, delay: 0.42)
        rise(grant, delay: 0.5)
        var was = granted
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = self.granted
                if now != was { self.refresh(animated: true); was = now }
            }
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// 4 · Where screenshots go and what happens after each one.
final class FolderPage: OnboardingPage {
    private var icon: NSView!
    private var title: NSView!
    private let card = GlassCard()
    private let path = NSTextField(labelWithString: "")
    private var toggles: [NSView] = []

    override func build() {
        icon = heroIcon("folder.fill", y: 28, tint: NSColor(hex: 0x3DA9FF), size: 84)
        title = headline("Your screenshots, your way", y: 130, size: 30)

        card.frame = CGRect(x: (bounds.width - 520) / 2, y: 184, width: 520, height: 222)
        addSubview(card)
        let folderLabel = NSTextField(labelWithString: "SAVE SCREENSHOTS TO")
        folderLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        folderLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        folderLabel.frame = CGRect(x: 22, y: 184, width: 300, height: 16)
        card.addSubview(folderLabel)
        let well = NSView(frame: CGRect(x: 22, y: 140, width: 476, height: 38))
        well.wantsLayer = true
        well.layer?.cornerRadius = 9
        well.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        well.layer?.borderWidth = 1
        well.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        card.addSubview(well)
        let folderIcon = NSImageView(frame: CGRect(x: 10, y: 9, width: 20, height: 20))
        folderIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        folderIcon.contentTintColor = NSColor(hex: 0x6CC0FF)
        well.addSubview(folderIcon)
        path.font = .monospacedSystemFont(ofSize: 12.5, weight: .medium)
        path.textColor = .white
        path.lineBreakMode = .byTruncatingMiddle
        path.frame = CGRect(x: 38, y: 10, width: 330, height: 18)
        well.addSubview(path)
        let change = GlowButton(title: "Change…", small: true, quiet: true) { [weak self] in self?.choose() }
        change.frame = CGRect(x: 380, y: 4, width: 90, height: 30)
        well.addSubview(change)

        let after = NSTextField(labelWithString: "AFTER EACH SCREENSHOT")
        after.font = folderLabel.font
        after.textColor = folderLabel.textColor
        after.frame = CGRect(x: 22, y: 108, width: 300, height: 16)
        card.addSubview(after)
        let options: [(String, String, String)] = [
            ("macwindow", "Open the editor", Keys.afterShow),
            ("doc.on.clipboard", "Copy to the clipboard", Keys.afterCopy),
            ("square.and.arrow.down", "Save to the folder", Keys.afterSave),
        ]
        var y: CGFloat = 72
        for (symbol, label, key) in options {
            let row = ToggleRow(symbol: symbol, title: label, key: key)
            row.frame = CGRect(x: 22, y: y, width: 476, height: 28)
            card.addSubview(row)
            toggles.append(row)
            y -= 32
        }
        refreshPath()
    }

    private func refreshPath() {
        path.stringValue = (Settings.saveFolder.path as NSString).abbreviatingWithTildeInPath
        path.toolTip = Settings.saveFolder.path
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
            self?.refreshPath()
            if let w = self?.path.superview { self?.pop(w, delay: 0) }
        }
    }

    #if SCREENSHOT_SELFTESTS
    var shownPath: String { path.stringValue }
    #endif

    override func play() {
        pop(icon, delay: 0.05)
        rise(title, delay: 0.18)
        rise(card, delay: 0.3, distance: 24)
        for (i, t) in toggles.enumerated() { rise(t, delay: 0.5 + Double(i) * 0.08, distance: 10) }
    }
}

/// 5 · Shortcuts as keycaps that pop in one after another, and where the app lives.
final class ShortcutsPage: OnboardingPage {
    private var title: NSView!
    private var caption: NSView!
    private var rows: [NSView] = []
    private let menuBar = MenuBarHint()

    override func build() {
        title = headline("Shortcuts that stick", y: 26, size: 30)
        caption = text("Use them from any app. You can change them in Preferences › Hotkeys.",
                       y: 70, size: 14, color: NSColor.white.withAlphaComponent(0.66))
        let actions: [(HotkeyAction, String, String)] = [
            (.area, "Area", "Drag over part of the screen"),
            (.fullscreen, "Fullscreen", "The whole display"),
            (.anyWindow, "Window", "Click any window"),
            (.scrolling, "Scrolling", "Long pages in one image"),
            (.ocr, "Copy text", "Recognize text or a QR code"),
        ]
        let colW: CGFloat = 330, rowH: CGFloat = 56
        for (i, (action, name, detail)) in actions.enumerated() {
            let col = i < 3 ? 0 : 1
            let r = i < 3 ? i : i - 3
            let row = ShortcutRow(keys: HotKeyCenter.shared.shortcut(for: action)?.display ?? "—", title: name, detail: detail)
            row.frame = CGRect(x: (bounds.width - colW * 2 - 20) / 2 + CGFloat(col) * (colW + 20), y: 112 + CGFloat(r) * rowH,
                               width: colW, height: rowH - 8)
            addSubview(row)
            rows.append(row)
        }
        menuBar.frame = CGRect(x: (bounds.width - 330) / 2 + 175, y: 112 + 2 * rowH, width: 330, height: rowH - 8)
        menuBar.frame.origin.x = (bounds.width - 330 * 2 - 20) / 2 + 350
        addSubview(menuBar)
    }

    override func play() {
        rise(title, delay: 0.05)
        rise(caption, delay: 0.15)
        for (i, r) in rows.enumerated() { pop(r, delay: 0.25 + Double(i) * 0.09) }
        rise(menuBar, delay: 0.75)
        menuBar.start()
    }

    override func stop() { menuBar.stop() }
}

/// 6 · Confetti, a check that draws itself, and the first screenshot one click away.
final class DonePage: OnboardingPage {
    private var check: CheckmarkView!
    private var title: NSView!
    private var body: NSView!
    private lazy var tryIt = GlowButton(title: "Take My First Screenshot") { [weak self] in self?.owner?.finish(capture: true) }
    private var confetti: CAEmitterLayer?
    private let confettiHost = PassThroughView()

    override var continueTitle: String { "Finish" }

    override func build() {
        check = CheckmarkView(frame: CGRect(x: (bounds.width - 108) / 2, y: 52, width: 108, height: 108))
        addSubview(check)
        title = headline("You're all set!", y: 184, size: 38)
        let keys = HotKeyCenter.shared.shortcut(for: .area)?.display ?? "the menu bar icon"
        body = text("Press \(keys) anytime to grab part of your screen, or use the camera icon in the menu bar.",
                    y: 240, size: 15, color: NSColor.white.withAlphaComponent(0.72), width: 440)
        tryIt.frame = CGRect(x: (bounds.width - 270) / 2, y: 312, width: 270, height: 44)
        addSubview(tryIt)
        confettiHost.frame = bounds
        confettiHost.wantsLayer = true
        addSubview(confettiHost)
    }

    override func play() {
        check.draw(delay: 0.15)
        rise(title, delay: 0.45)
        rise(body, delay: 0.55)
        pop(tryIt, delay: 0.7)
        burst()
    }

    override func stop() { confetti?.removeFromSuperlayer() }

    /// Paper confetti falling from above the page for a moment.
    private func burst() {
        let e = CAEmitterLayer()
        e.emitterPosition = CGPoint(x: bounds.width / 2, y: bounds.height + 20)
        e.emitterSize = CGSize(width: bounds.width, height: 1)
        e.emitterShape = .line
        e.beginTime = CACurrentMediaTime()
        let colors: [NSColor] = [NSColor(hex: 0xFF6A3D), NSColor(hex: 0xFFC83D), NSColor(hex: 0x3DA9FF), NSColor(hex: 0xB35CFF),
                                 NSColor(hex: 0x34C759), .white]
        e.emitterCells = colors.flatMap { c in [Self.cell(c, rect: true), Self.cell(c, rect: false)] }
        confettiHost.layer?.addSublayer(e)
        confetti = e
        // A short burst, then the pieces finish falling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { e.birthRate = 0 }
    }

    private static func cell(_ color: NSColor, rect: Bool) -> CAEmitterCell {
        let c = CAEmitterCell()
        let size = rect ? CGSize(width: 9, height: 5) : CGSize(width: 6, height: 6)
        c.contents = NSImage(size: size, flipped: false) { r in
            NSColor.white.setFill()
            (rect ? NSBezierPath(rect: r) : NSBezierPath(ovalIn: r)).fill()
            return true
        }.cgImage(forProposedRect: nil, context: nil, hints: nil)
        c.color = color.cgColor
        c.birthRate = 7
        c.lifetime = 6
        c.velocity = 160
        c.velocityRange = 90
        c.emissionLongitude = -.pi / 2 // downward in the layer's bottom-up space
        c.emissionRange = .pi / 5
        c.yAcceleration = -120
        c.spin = 3
        c.spinRange = 6
        c.scale = 1
        c.scaleRange = 0.5
        c.alphaSpeed = -0.12
        return c
    }
}

// MARK: - Building blocks

/// A view that never takes clicks (decorations over controls).
final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Dark background with slowly drifting colored glows (an aurora) and a faint dot grid.
final class AuroraView: NSView {
    private var blobs: [CAGradientLayer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let base = CAGradientLayer()
        base.colors = [NSColor(hex: 0x0C0B14).cgColor, NSColor(hex: 0x151022).cgColor, NSColor(hex: 0x1D0F14).cgColor]
        base.startPoint = CGPoint(x: 0, y: 1)
        base.endPoint = CGPoint(x: 1, y: 0)
        base.frame = bounds
        base.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(base)
        let specs: [(NSColor, CGPoint, CGFloat, CGPoint, Double)] = [
            (NSColor(hex: 0xFF4D1F), CGPoint(x: 0.82, y: 0.86), 520, CGPoint(x: -120, y: -60), 11),
            (NSColor(hex: 0x7A3CFF), CGPoint(x: 0.12, y: 0.2), 560, CGPoint(x: 140, y: 80), 13),
            (NSColor(hex: 0xE0306E), CGPoint(x: 0.2, y: 0.95), 420, CGPoint(x: 90, y: -110), 9),
            (NSColor(hex: 0x1E7BFF), CGPoint(x: 0.95, y: 0.1), 380, CGPoint(x: -100, y: 70), 15),
        ]
        for (color, center, size, drift, duration) in specs {
            let g = CAGradientLayer()
            g.type = .radial
            g.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor]
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            g.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            g.position = CGPoint(x: bounds.width * center.x, y: bounds.height * center.y)
            layer?.addSublayer(g)
            let a = CABasicAnimation(keyPath: "position")
            a.byValue = NSValue(point: drift)
            a.duration = duration
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            g.add(a, forKey: "drift")
            blobs.append(g)
        }
        let dots = CALayer()
        dots.frame = bounds
        dots.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        let tile = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            NSColor.white.withAlphaComponent(0.05).setFill()
            NSBezierPath(ovalIn: NSRect(x: 10, y: 10, width: 1.6, height: 1.6)).fill()
            return true
        }
        dots.backgroundColor = NSColor(patternImage: tile).cgColor
        layer?.addSublayer(dots)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // lets the window be dragged by its background
}

/// Primary button: warm gradient pill with a soft glow; `quiet` is a translucent secondary style.
final class GlowButton: NSView {
    var title: String { didSet { label.stringValue = title; setAccessibilityLabel(title) } }
    private let label = NSTextField(labelWithString: "")
    private let fill = CAGradientLayer()
    private let action: () -> Void
    private let quiet: Bool
    private var hovering = false { didSet { refresh() } }

    init(title: String, small: Bool = false, quiet: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.action = action
        self.quiet = quiet
        super.init(frame: .zero)
        wantsLayer = true
        fill.colors = quiet ? [NSColor.white.withAlphaComponent(0.14).cgColor, NSColor.white.withAlphaComponent(0.1).cgColor]
                            : [NSColor(hex: 0xFF7A45).cgColor, NSColor(hex: 0xFF2A12).cgColor]
        fill.startPoint = CGPoint(x: 0.5, y: 1)
        fill.endPoint = CGPoint(x: 0.5, y: 0)
        fill.borderWidth = 1
        fill.borderColor = NSColor.white.withAlphaComponent(quiet ? 0.14 : 0.28).cgColor
        if !quiet {
            fill.shadowColor = NSColor(hex: 0xFF3B1A).cgColor
            fill.shadowOpacity = 0.55
            fill.shadowRadius = 14
            fill.shadowOffset = CGSize(width: 0, height: -2)
        }
        layer?.addSublayer(fill)
        label.stringValue = title
        label.font = .systemFont(ofSize: small ? 13 : 14.5, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        fill.frame = bounds
        fill.cornerRadius = bounds.height / 2
        let h = label.intrinsicContentSize.height
        label.frame = CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        fill.shadowRadius = hovering && !quiet ? 22 : 14
        fill.shadowOpacity = hovering && !quiet ? 0.85 : (quiet ? 0 : 0.55)
        fill.opacity = hovering && quiet ? 1.35 : 1
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.97, y: 0.97))
    }

    override func mouseUp(with event: NSEvent) {
        layer?.setAffineTransform(.identity)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Plain text button for Back and Skip.
final class TextButton: NSButton {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        isBordered = false
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ])
        target = self
        action = #selector(clicked)
        sizeToFit()
        frame.size.width += 16
        frame.size.height = 28
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { handler() }
}

/// Page indicator: the current page is a wider, glowing capsule; changes slide smoothly.
final class PageDots: NSView {
    var count = 0 { didSet { rebuild() } }
    var selected = 0 { didSet { place(animated: true) } }
    private var dots: [CALayer] = []

    private func rebuild() {
        wantsLayer = true
        dots.forEach { $0.removeFromSuperlayer() }
        dots = (0..<count).map { _ in
            let d = CALayer()
            d.cornerRadius = 4
            layer?.addSublayer(d)
            return d
        }
        place(animated: false)
        setAccessibilityElement(true)
        setAccessibilityRole(.valueIndicator)
    }

    private func place(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
        let wide: CGFloat = 26, dot: CGFloat = 8, gap: CGFloat = 8
        let total = wide + CGFloat(max(0, count - 1)) * dot + CGFloat(max(0, count - 1)) * gap
        var x = (bounds.width - total) / 2
        for (i, d) in dots.enumerated() {
            let w = i == selected ? wide : dot
            d.frame = CGRect(x: x, y: (bounds.height - dot) / 2, width: w, height: dot)
            d.backgroundColor = (i == selected ? NSColor(hex: 0xFF6A3D) : NSColor.white.withAlphaComponent(0.25)).cgColor
            d.shadowColor = NSColor(hex: 0xFF4D1F).cgColor
            d.shadowOpacity = i == selected ? 0.9 : 0
            d.shadowRadius = 6
            d.shadowOffset = .zero
            x += w + gap
        }
        CATransaction.commit()
        setAccessibilityValue("Step \(selected + 1) of \(count)")
    }
}

/// Frosted glass panel.
final class GlassCard: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 24
        layer?.shadowOffset = CGSize(width: 0, height: -8)
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class FeatureChip: GlassCardLike {
    init(symbol: String, title: String, tint: NSColor) {
        super.init(radius: 14)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))!)
        icon.contentTintColor = tint
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 13.5, weight: .semibold)
        l.textColor = .white
        let s = NSStackView(views: [icon, l])
        s.spacing = 10
        s.translatesAutoresizingMaskIntoConstraints = false
        addSubview(s)
        NSLayoutConstraint.activate([s.centerXAnchor.constraint(equalTo: centerXAnchor), s.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Translucent rounded rectangle (lighter than GlassCard: no blur, for small pieces).
class GlassCardLike: NSView {
    init(radius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// "Not allowed yet" (amber) or "Allowed" (green), cross-fading and popping when it changes.
final class StatusPill: GlassCardLike {
    private let dot = CALayer()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(radius: 17)
        dot.cornerRadius = 5
        layer?.addSublayer(dot)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = label.intrinsicContentSize.height
        label.frame = CGRect(x: 20, y: (bounds.height - h) / 2, width: bounds.width - 30, height: h)
        dot.frame = CGRect(x: 18, y: (bounds.height - 10) / 2, width: 10, height: 10)
    }

    func set(granted: Bool, animated: Bool) {
        let color = granted ? NSColor(hex: 0x34C759) : NSColor(hex: 0xFFB020)
        label.stringValue = granted ? "Screen Recording allowed" : "Not allowed yet"
        setAccessibilityLabel(label.stringValue)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        dot.backgroundColor = color.cgColor
        dot.shadowColor = color.cgColor
        dot.shadowOpacity = 1
        dot.shadowRadius = 6
        dot.shadowOffset = .zero
        layer?.borderColor = color.withAlphaComponent(0.5).cgColor
        CATransaction.commit()
        if animated, granted, let l = layer {
            let s = CASpringAnimation(keyPath: "transform.scale")
            s.fromValue = 1.15
            s.toValue = 1
            s.damping = 9
            s.duration = s.settlingDuration
            l.add(s, forKey: "celebrate")
        }
    }
}

/// An option with a switch, bound to a defaults key.
final class ToggleRow: NSView {
    private let key: String
    private let toggle = NSSwitch()

    init(symbol: String, title: String, key: String) {
        self.key = key
        super.init(frame: .zero)
        let icon = NSImageView(frame: CGRect(x: 0, y: 4, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        addSubview(icon)
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 13.5)
        l.textColor = .white
        l.frame = CGRect(x: 30, y: 5, width: 300, height: 18)
        addSubview(l)
        toggle.controlSize = .small
        toggle.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        toggle.target = self
        toggle.action = #selector(changed)
        toggle.setAccessibilityLabel(title)
        toggle.frame = CGRect(x: 440, y: 4, width: 36, height: 20)
        addSubview(toggle)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() { UserDefaults.standard.set(toggle.state == .on, forKey: key) }
}

/// A shortcut drawn as raised keycaps next to its name.
final class ShortcutRow: GlassCardLike {
    init(keys: String, title: String, detail: String) {
        super.init(radius: 12)
        var x: CGFloat = 12
        for ch in keys.map(String.init) {
            let cap = Keycap(ch)
            cap.frame = CGRect(x: x, y: 9, width: max(30, cap.intrinsicContentSize.width), height: 30)
            addSubview(cap)
            x += cap.frame.width + 5
        }
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 14, weight: .semibold)
        t.textColor = .white
        t.frame = CGRect(x: max(x + 10, 150), y: 24, width: 170, height: 18)
        addSubview(t)
        let d = NSTextField(labelWithString: detail)
        d.font = .systemFont(ofSize: 11.5)
        d.textColor = NSColor.white.withAlphaComponent(0.55)
        d.frame = CGRect(x: t.frame.minX, y: 7, width: 180, height: 16)
        addSubview(d)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(title): \(keys)")
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// One key with a top face, a darker base and a highlight edge.
final class Keycap: NSView {
    private let text: String

    init(_ text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]).width
        return NSSize(width: w + 18, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor(hex: 0x0E0E13).setFill()
        NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
        let top = NSRect(x: r.minX, y: r.minY + 3, width: r.width, height: r.height - 3)
        NSGradient(starting: NSColor(hex: 0x3A3A46), ending: NSColor(hex: 0x272731))?.draw(in: NSBezierPath(roundedRect: top, xRadius: 7, yRadius: 7), angle: -90)
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let edge = NSBezierPath(roundedRect: top.insetBy(dx: 0.5, dy: 0.5), xRadius: 6.5, yRadius: 6.5)
        edge.lineWidth = 1
        edge.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white]
        let s = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: top.midX - s.width / 2, y: top.midY - s.height / 2), withAttributes: attrs)
    }
}

/// A sliver of menu bar with the app's camera icon and a bouncing arrow pointing at it.
final class MenuBarHint: GlassCardLike {
    init() {
        super.init(radius: 12)
        let bar = NSView(frame: CGRect(x: 12, y: 12, width: 132, height: 24))
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 6
        bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        addSubview(bar)
        let symbols = ["wifi", "battery.75percent", "camera.viewfinder"]
        for (i, s) in symbols.enumerated() {
            let v = NSImageView(frame: CGRect(x: 10 + CGFloat(i) * 40, y: 3, width: 20, height: 18))
            v.image = NSImage(systemSymbolName: s, accessibilityDescription: nil)
            v.contentTintColor = i == 2 ? NSColor(hex: 0xFF8A5C) : NSColor.white.withAlphaComponent(0.6)
            bar.addSubview(v)
        }
        let t = NSTextField(labelWithString: "Everything else")
        t.font = .systemFont(ofSize: 14, weight: .semibold)
        t.textColor = .white
        t.frame = CGRect(x: 158, y: 24, width: 170, height: 18)
        addSubview(t)
        let d = NSTextField(labelWithString: "lives in the menu bar")
        d.font = .systemFont(ofSize: 11.5)
        d.textColor = NSColor.white.withAlphaComponent(0.55)
        d.frame = CGRect(x: 158, y: 7, width: 170, height: 16)
        addSubview(d)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Everything else lives in the menu bar, under the camera icon")
    }

    required init?(coder: NSCoder) { fatalError() }

    func start() {
        guard let cam = subviews.first?.subviews.last else { return }
        cam.wantsLayer = true
        guard let l = cam.layer else { return }
        l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        l.position = CGPoint(x: cam.frame.midX, y: cam.frame.midY)
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1
        pulse.toValue = 1.25
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.add(pulse, forKey: "pulse")
    }

    func stop() { subviews.first?.subviews.last?.layer?.removeAllAnimations() }
}

/// A check mark that draws itself inside a glowing green ring.
final class CheckmarkView: NSView {
    private let ring = CAShapeLayer()
    private let tick = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let b = CGRect(origin: .zero, size: frame.size)
        let green = NSColor(hex: 0x34C759)
        let disc = CALayer()
        disc.frame = b.insetBy(dx: 6, dy: 6)
        disc.cornerRadius = disc.frame.width / 2
        disc.backgroundColor = green.withAlphaComponent(0.16).cgColor
        disc.shadowColor = green.cgColor
        disc.shadowOpacity = 0.8
        disc.shadowRadius = 24
        disc.shadowOffset = .zero
        layer?.addSublayer(disc)
        ring.path = CGPath(ellipseIn: b.insetBy(dx: 6, dy: 6), transform: nil)
        let tickPath = CGMutablePath()
        tickPath.move(to: CGPoint(x: b.width * 0.3, y: b.height * 0.5))
        tickPath.addLine(to: CGPoint(x: b.width * 0.45, y: b.height * 0.35))
        tickPath.addLine(to: CGPoint(x: b.width * 0.72, y: b.height * 0.66))
        tick.path = tickPath
        for s in [ring, tick] {
            s.frame = b
            s.fillColor = nil
            s.strokeColor = green.cgColor
            s.lineCap = .round
            s.lineJoin = .round
            layer?.addSublayer(s)
        }
        ring.lineWidth = 4
        tick.lineWidth = 7
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Done")
    }

    required init?(coder: NSCoder) { fatalError() }

    func draw(delay: CFTimeInterval) {
        for (s, d, dur) in [(ring, delay, 0.55), (tick, delay + 0.4, 0.35)] {
            let a = CABasicAnimation(keyPath: "strokeEnd")
            a.fromValue = 0
            a.toValue = 1
            a.duration = dur
            a.beginTime = CACurrentMediaTime() + d
            a.fillMode = .backwards
            a.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            s.add(a, forKey: "draw")
        }
    }
}

/// The capture demo: a mock window; a crosshair drags a selection (marching ants and a size pill), then an arrow
/// draws itself, a counter badge pops and a label slides in. Repeats every few seconds.
final class CaptureDemoView: NSView {
    private let mockWindow = CALayer()
    private let selection = CAShapeLayer()
    private let sizePill = CATextLayer()
    private let crosshair = CAShapeLayer()
    private let arrow = CAShapeLayer()
    private let badge = CALayer()
    private let note = CATextLayer()
    private let flash = CALayer()
    private let sel = CGRect(x: 150, y: 70, width: 250, height: 150) // bottom-up layer coordinates

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        buildScene()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildScene() {
        guard let root = layer else { return }
        let b = CGRect(origin: .zero, size: frame.size)
        // Mock app mockWindow.
        mockWindow.frame = b
        mockWindow.cornerRadius = 16
        mockWindow.backgroundColor = NSColor(hex: 0x1B1B24).withAlphaComponent(0.92).cgColor
        mockWindow.borderWidth = 1
        mockWindow.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        mockWindow.shadowColor = NSColor.black.cgColor
        mockWindow.shadowOpacity = 0.5
        mockWindow.shadowRadius = 30
        mockWindow.shadowOffset = CGSize(width: 0, height: -12)
        root.addSublayer(mockWindow)
        for (i, c) in [NSColor(hex: 0xFF5F57), NSColor(hex: 0xFEBC2E), NSColor(hex: 0x28C840)].enumerated() {
            let d = CALayer()
            d.frame = CGRect(x: 16 + CGFloat(i) * 18, y: b.height - 24, width: 11, height: 11)
            d.cornerRadius = 5.5
            d.backgroundColor = c.cgColor
            mockWindow.addSublayer(d)
        }
        // Content: a chart card and some text lines.
        let card = CAGradientLayer()
        card.frame = CGRect(x: 170, y: 88, width: 210, height: 112)
        card.cornerRadius = 10
        card.colors = [NSColor(hex: 0x3DA9FF).cgColor, NSColor(hex: 0x7A3CFF).cgColor]
        card.startPoint = CGPoint(x: 0, y: 0)
        card.endPoint = CGPoint(x: 1, y: 1)
        mockWindow.addSublayer(card)
        for (i, h) in [34.0, 58, 44, 76, 62].enumerated() {
            let bar = CALayer()
            bar.frame = CGRect(x: 192 + CGFloat(i) * 34, y: 104, width: 20, height: h)
            bar.cornerRadius = 4
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            mockWindow.addSublayer(bar)
        }
        for (i, w) in [120.0, 90, 104, 70].enumerated() {
            let line = CALayer()
            line.frame = CGRect(x: 26, y: 196 - CGFloat(i) * 24, width: w, height: 9)
            line.cornerRadius = 4.5
            line.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            mockWindow.addSublayer(line)
        }
        let wide = CALayer()
        wide.frame = CGRect(x: 26, y: 34, width: 470, height: 9)
        wide.cornerRadius = 4.5
        wide.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        mockWindow.addSublayer(wide)

        // Selection with marching ants.
        selection.fillColor = NSColor(hex: 0xFF4D1F).withAlphaComponent(0.1).cgColor
        selection.strokeColor = NSColor(hex: 0xFF6A3D).cgColor
        selection.lineWidth = 2
        selection.lineDashPattern = [7, 5]
        root.addSublayer(selection)
        sizePill.fontSize = 11
        sizePill.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        sizePill.foregroundColor = NSColor.white.cgColor
        sizePill.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        sizePill.cornerRadius = 9
        sizePill.alignmentMode = .center
        sizePill.contentsScale = 2
        sizePill.string = "500 × 300"
        sizePill.frame = CGRect(x: sel.midX - 44, y: sel.minY - 28, width: 88, height: 18)
        root.addSublayer(sizePill)
        // Crosshair cursor.
        let ch = CGMutablePath()
        ch.move(to: CGPoint(x: -9, y: 0)); ch.addLine(to: CGPoint(x: 9, y: 0))
        ch.move(to: CGPoint(x: 0, y: -9)); ch.addLine(to: CGPoint(x: 0, y: 9))
        crosshair.path = ch
        crosshair.strokeColor = NSColor.white.cgColor
        crosshair.lineWidth = 2
        crosshair.shadowColor = NSColor.black.cgColor
        crosshair.shadowOpacity = 0.8
        crosshair.shadowRadius = 2
        crosshair.shadowOffset = .zero
        root.addSublayer(crosshair)
        // Annotations.
        let ap = CGMutablePath()
        ap.move(to: CGPoint(x: 70, y: 250))
        ap.addQuadCurve(to: CGPoint(x: 178, y: 186), control: CGPoint(x: 110, y: 186))
        ap.move(to: CGPoint(x: 162, y: 198)); ap.addLine(to: CGPoint(x: 178, y: 186)); ap.addLine(to: CGPoint(x: 162, y: 176))
        arrow.path = ap
        arrow.strokeColor = NSColor(hex: 0xFF3B30).cgColor
        arrow.fillColor = nil
        arrow.lineWidth = 4.5
        arrow.lineCap = .round
        arrow.lineJoin = .round
        root.addSublayer(arrow)
        badge.frame = CGRect(x: 378, y: 186, width: 30, height: 30)
        badge.cornerRadius = 15
        badge.backgroundColor = NSColor(hex: 0xFF3B30).cgColor
        badge.borderWidth = 2
        badge.borderColor = NSColor.white.cgColor
        let n = CATextLayer()
        n.string = "1"
        n.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        n.fontSize = 15
        n.alignmentMode = .center
        n.foregroundColor = NSColor.white.cgColor
        n.frame = CGRect(x: 0, y: 5, width: 30, height: 20)
        n.contentsScale = 2
        badge.addSublayer(n)
        root.addSublayer(badge)
        note.string = "Ship it! 🚀"
        note.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        note.fontSize = 14
        note.foregroundColor = NSColor.white.cgColor
        note.backgroundColor = NSColor(hex: 0x007AFF).cgColor
        note.cornerRadius = 8
        note.alignmentMode = .center
        note.contentsScale = 2
        note.frame = CGRect(x: 300, y: 236, width: 110, height: 26)
        root.addSublayer(note)
        flash.frame = sel
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        root.addSublayer(flash)
        reset(final: true)
    }

    /// Final frame (everything visible) is the model state, so a still snapshot shows the finished demo.
    private func reset(final: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selection.path = CGPath(rect: sel, transform: nil)
        crosshair.position = CGPoint(x: sel.maxX, y: sel.minY)
        for l in [selection, sizePill, arrow, badge, note] as [CALayer] { l.opacity = final ? 1 : 0 }
        crosshair.opacity = 0
        CATransaction.commit()
    }

    func start() {
        reset(final: false)
        let t0 = CACurrentMediaTime() + 0.2
        let cycle = 5.6
        /// One looping keyframe animation from (time, value) pairs; the value holds until the next pair.
        func track(_ l: CALayer, _ key: String, _ points: [(Double, Any)]) {
            let a = CAKeyframeAnimation(keyPath: key)
            var pts = points
            if let last = pts.last, last.0 < cycle { pts.append((cycle, last.1)) }
            a.values = pts.map(\.1)
            a.keyTimes = pts.map { NSNumber(value: $0.0 / cycle) }
            a.duration = cycle
            a.beginTime = t0
            a.repeatCount = .infinity
            a.fillMode = .both
            a.calculationMode = .linear
            a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(1, pts.count - 1))
            l.add(a, forKey: key)
        }
        let start = CGPoint(x: sel.minX, y: sel.maxY), end = CGPoint(x: sel.maxX, y: sel.minY)
        let dot = CGPath(rect: CGRect(x: start.x, y: start.y, width: 1, height: 1), transform: nil)
        let full = CGPath(rect: sel, transform: nil)
        // 0–0.5 s the crosshair arrives, 0.6–1.6 s it drags the selection out, 1.8 s "capture" flash.
        track(crosshair, "opacity", [(0, 0.0), (0.25, 1.0), (1.8, 1.0), (2.0, 0.0)])
        track(crosshair, "position", [(0, NSValue(point: CGPoint(x: start.x - 60, y: start.y + 30))), (0.5, NSValue(point: start)),
                                      (0.6, NSValue(point: start)), (1.6, NSValue(point: end))])
        track(selection, "opacity", [(0, 0.0), (0.6, 0.0), (0.62, 1.0), (5.0, 1.0), (5.4, 0.0)])
        track(selection, "path", [(0, dot), (0.6, dot), (1.6, full)])
        track(sizePill, "opacity", [(0, 0.0), (0.9, 0.0), (1.2, 1.0), (2.0, 1.0), (2.3, 0.0)])
        track(flash, "opacity", [(0, 0.0), (1.8, 0.0), (1.82, 0.8), (2.3, 0.0)])
        // 2.2 s the arrow draws itself, 2.9 s the badge pops, 3.3 s the label slides in; 5 s all fade for the next loop.
        track(arrow, "opacity", [(0, 0.0), (2.2, 0.0), (2.22, 1.0), (5.0, 1.0), (5.4, 0.0)])
        track(arrow, "strokeEnd", [(0, 0.0), (2.2, 0.0), (2.8, 1.0)])
        track(badge, "opacity", [(0, 0.0), (2.9, 0.0), (3.0, 1.0), (5.0, 1.0), (5.4, 0.0)])
        track(badge, "transform.scale", [(0, 0.0), (2.9, 0.0), (3.15, 1.25), (3.35, 0.92), (3.5, 1.0)])
        track(note, "opacity", [(0, 0.0), (3.3, 0.0), (3.65, 1.0), (5.0, 1.0), (5.4, 0.0)])
        track(note, "transform.translation.y", [(0, -12.0), (3.3, -12.0), (3.75, 0.0)])
        let ants = CABasicAnimation(keyPath: "lineDashPhase")
        ants.fromValue = 0
        ants.toValue = -24
        ants.duration = 0.6
        ants.repeatCount = .infinity
        selection.add(ants, forKey: "ants")
    }

    func stop() {
        layer?.sublayers?.forEach { $0.removeAllAnimations() }
        reset(final: true)
    }
}
