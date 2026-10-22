import AppKit

/// Small HUD notification at the top of the active screen (Shottr's WinNotifier): an icon matched to the message,
/// a frosted capsule, and a short spring-in / fade-out.
@MainActor enum Toast {
    private static var panel: NSPanel?
    private static var generation = 0

    private enum Kind {
        case success, warning, working, info

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .working: "text.viewfinder"
            case .info: "info.circle.fill"
            }
        }

        var tint: NSColor {
            switch self {
            case .success: NSColor(hex: 0x30D158)
            case .warning: NSColor(hex: 0xFF9F0A)
            case .working: Theme.accentTop
            case .info: .secondaryLabelColor
            }
        }
    }

    private static func kind(for text: String) -> Kind {
        let t = text.lowercased()
        if ["fail", "can't", "error", "no text", "unknown", "requires", "make sure", "not "].contains(where: t.contains) { return .warning }
        if t.hasSuffix("…") || t.contains("in ") && t.contains("…") { return .working }
        if ["copied", "saved", "copy", "save"].contains(where: t.contains) { return .success }
        return .info
    }

    static func show(_ text: String, duration: TimeInterval = 1.8) {
        panel?.orderOut(nil)
        generation += 1
        let gen = generation
        let kind = kind(for: text)

        let icon = NSImageView(image: NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))!)
        icon.contentTintColor = kind.tint
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 4
        label.preferredMaxLayoutWidth = 380
        let stack = NSStackView(views: [icon, label])
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 11, left: 16, bottom: 11, right: 20)
        let size = stack.fittingSize

        let fx = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        fx.material = .hudWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = min(22, size.height / 2)
        fx.layer?.borderWidth = 1
        fx.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        stack.frame = fx.bounds
        fx.addSubview(stack)

        let screen = NSScreen.containingMouse().visibleFrame
        let frame = CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 28, width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame.offsetBy(dx: 0, dy: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = fx
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p

        // Drop in from slightly above with a gentle overshoot.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.3, 0.4, 1)
            p.animator().setFrame(frame, display: true)
            p.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard gen == generation else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p.animator().alphaValue = 0
                p.animator().setFrame(frame.offsetBy(dx: 0, dy: 6), display: true)
            }) {
                p.orderOut(nil)
            }
        }
    }
}
