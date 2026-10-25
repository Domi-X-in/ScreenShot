import AppKit
import QuartzCore

/// First-run welcome guide in three steps (ROADMAP, Fase 6 · R8): Welcome (what the app does), Set up (Screen Recording,
/// where screenshots go and what happens after each, light or dark) and Ready (the shortcuts and the first capture).
/// Shown once (Keys.onboardingDone); the menu bar menu reopens it. If macOS quits the app to apply the permission, the
/// guide resumes on the step it was on. The pages are in OnboardingSteps.swift.
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

    static let size = CGSize(width: 860, height: 580)
    private let pages: [OnboardingPage.Type] = [WelcomeStep.self, SetupStep.self, ReadyStep.self]
    /// The footer: Back, the three step names, Skip and Continue.
    private lazy var steps = StepTabs(titles: ["Welcome", "Set up", "Ready"]) { [weak self] i in self?.go(to: i) }
    private lazy var back = PlainButton(title: "Back") { [weak self] in self?.go(to: (self?.index ?? 1) - 1) }
    private lazy var skip = PlainButton(title: "Skip") { [weak self] in self?.go(to: (self?.pages.count ?? 1) - 1) }
    private lazy var next = AccentButton(title: "Continue") { [weak self] in self?.advance() }
    private(set) var index = -1
    private let stage = NSView()
    private var current: OnboardingPage?

    init() {
        let win = NSWindow(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.title = "Welcome to ScreenShot"
        win.center()
        super.init(window: win)
        win.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

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
        if animated && !OnboardingPage.reduceMotion {
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

        steps.selected = i
        back.isHidden = i == 0
        skip.isHidden = i == pages.count - 1
        next.title = page.continueTitle
    }

    /// A dotted background, the page, and a footer with Back, the step names, Skip and Continue.
    private func build() {
        guard let win = window else { return }
        let size = Self.size
        let content = DottedBackground(frame: CGRect(origin: .zero, size: size))
        win.contentView = content
        stage.frame = CGRect(x: 0, y: 64, width: size.width, height: size.height - 64)
        stage.wantsLayer = true
        content.addSubview(stage)
        let footer = FooterBar(frame: CGRect(x: 0, y: 0, width: size.width, height: 64))
        content.addSubview(footer)
        back.frame.origin = CGPoint(x: 20, y: 16)
        steps.frame = CGRect(x: (size.width - steps.frame.width) / 2, y: 20, width: steps.frame.width, height: 24)
        next.frame = CGRect(x: size.width - 20 - next.frame.width, y: 16, width: next.frame.width, height: 32)
        skip.frame.origin = CGPoint(x: next.frame.minX - 6 - skip.frame.width, y: 16)
        for v in [back, steps, skip, next] as [NSView] { footer.addSubview(v) }
        next.onResize = { [weak self] in
            guard let self else { return }
            self.next.frame.origin.x = size.width - 20 - self.next.frame.width
            self.skip.frame.origin.x = self.next.frame.minX - 6 - self.skip.frame.width
        }
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
    var debugStepTitles: [String] { steps.titles }
    var debugContinueTitle: String { next.title }
    var debugBackShown: Bool { !back.isHidden }
    var debugSkipShown: Bool { !skip.isHidden }
    func pressSkip() { skip.onClick() }
    func pressStep(_ i: Int) { steps.onPick(i) }
    var pageCount: Int { pages.count }
    var currentPage: OnboardingPage? { current }
    func pressContinue() { advance() }
    #endif
}

// MARK: - Pages

/// One page of the guide: a flipped canvas laid out top-down; `play` runs its entrance animation.
class OnboardingPage: NSView {
    weak var owner: OnboardingWindowController?
    /// macOS's Reduce Motion (or a test forcing it): no page transitions, entrance animations or looping demos.
    nonisolated(unsafe) static var forceReduceMotion = false
    static var reduceMotion: Bool { forceReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var continueTitle: String { "Continue" }

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
    func text(_ s: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = DesignTokens.color(.ink),
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

    /// Fades a view in while it rises a little, after `delay`.
    func rise(_ v: NSView, delay: CFTimeInterval, distance: CGFloat = 16) {
        guard !Self.reduceMotion else { return }
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
        guard !Self.reduceMotion else { return }
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
}
