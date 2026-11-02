import AppKit

/// The ribbon editor's visual language (ROADMAP, Fase 6): neutral surfaces carry the interface, and the #FF5500 accent
/// appears only where something is on (the selected tool, a toggled format, the focus ring, a checked menu row).
/// Every color has a dark value (the primary design) and a light one; `color(_:)` returns a dynamic color that follows
/// the appearance of whatever draws it. Values match the "Editor Ribbon Redesign" canvas.
enum DesignTokens {
    enum Role: String, CaseIterable {
        /// Window background behind the image (with the dot grid).
        case canvas
        /// Title bar, ribbon and bottom bars.
        case chrome
        /// Raised surfaces: menus, flyouts, popovers, cards.
        case panel
        /// Text fields and dropdown fields.
        case field
        /// Hairlines and dividers; `lineSoft` where two chrome bars meet.
        case line, lineSoft
        /// Text and icons: primary, secondary (icons at rest), tertiary (group labels, captions).
        case ink, ink2, ink3
        /// Neutral hover and pressed fills.
        case hover, pressed
        /// The accent and its derived tints.
        case accent, accentHover, accentPressed, accentSoft, accentText
        /// The canvas's dot grid.
        case dot
        /// Notification states: the color of the icon and action, and the chip's tinted background.
        case info, infoBackground, success, successBackground, warning, warningBackground, error, errorBackground
    }

    /// (dark, light), as 0xRRGGBBAA.
    static let values: [Role: (dark: UInt32, light: UInt32)] = [
        .canvas: (0x141518FF, 0xE8E8ECFF),
        .chrome: (0x1C1D21FF, 0xF7F7F8FF),
        .panel: (0x25262BFF, 0xFFFFFFFF),
        .field: (0x16171AFF, 0xFFFFFFFF),
        .line: (0x303137FF, 0xD8D8DDFF),
        .lineSoft: (0x26272CFF, 0xE5E5E8FF),
        .ink: (0xECECEFFF, 0x1A1B1EFF),
        .ink2: (0xB6B7BEFF, 0x44454CFF),
        .ink3: (0x8E8F97FF, 0x686971FF),
        .hover: (0x2B2C31FF, 0xEAEAEDFF),
        .pressed: (0x35363CFF, 0xDDDDE2FF),
        .accent: (0xFF5500FF, 0xFF5500FF),
        .accentHover: (0xFF6E26FF, 0xFF6E26FF),
        .accentPressed: (0xD94800FF, 0xD94800FF),
        .accentSoft: (0xFF550029, 0xFF55001C),
        .accentText: (0xFF7A33FF, 0xB33C00FF),
        .dot: (0x2A2B31FF, 0xD0D0D6FF),
        .info: (0x6EA4FFFF, 0x1F63D6FF),
        .infoBackground: (0x6EA4FF1F, 0x1F63D617),
        .success: (0x3FCB82FF, 0x17824AFF),
        .successBackground: (0x3FCB821F, 0x17824A1A),
        .warning: (0xF3BA45FF, 0x8F6200FF),
        .warningBackground: (0xF3BA451F, 0xD6960021),
        .error: (0xFF6166FF, 0xC4252BFF),
        .errorBackground: (0xFF616621, 0xC4252B17),
    ]

    /// The accent ramp, 50 (lightest) to 800; 500 is the brand color.
    static let accentRamp: [(step: Int, hex: UInt32)] = [
        (50, 0xFFF1EA), (100, 0xFFDCC8), (200, 0xFFB48C), (300, 0xFF8A4D), (400, 0xFF6E26),
        (500, 0xFF5500), (600, 0xD94800), (700, 0xC24100), (800, 0x7A2800),
    ]

    /// Text on a filled accent button: white on #FF5500 is under 4.5:1, so the label is near-black.
    static let onAccent = NSColor(srgb: 0x1A0A00FF)

    /// Behind `lock`.
    nonisolated(unsafe) private static var cache: [Role: NSColor] = [:]
    private static let lock = NSLock()

    /// A color that resolves to the dark or light value for the appearance it is drawn in.
    static func color(_ role: Role) -> NSColor {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[role] { return c }
        let v = values[role]!
        let dark = NSColor(srgb: v.dark), light = NSColor(srgb: v.light)
        let c = NSColor(name: NSColor.Name("ScreenShot.\(role.rawValue)")) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        cache[role] = c
        return c
    }

    /// The fixed value of a role in one appearance (for tests, CALayers and other places that can't take a dynamic color).
    static func color(_ role: Role, dark: Bool) -> NSColor {
        let v = values[role]!
        return NSColor(srgb: dark ? v.dark : v.light)
    }

    // MARK: Shape and type

    enum Radius {
        /// Buttons, fields, menu rows.
        static let control: CGFloat = 6
        /// Large ribbon buttons, notification chips, thumbnails.
        static let large: CGFloat = 8
        /// Menus, flyouts, popovers.
        static let menu: CGFloat = 10
        /// The window.
        static let window: CGFloat = 12
        /// The editor's floating cards (title bar, ribbon, canvas, bars): one curvature for every card.
        static let card: CGFloat = 12
    }

    enum Metrics {
        /// The ribbon: two 28 pt rows (or three 20 pt rows) and the group label under them.
        static let ribbonHeight: CGFloat = 94
        static let smallButton: CGFloat = 28
        static let largeButton = CGSize(width: 52, height: 62)
        static let compactGroupButton = CGSize(width: 64, height: 80)
        static let titleBarHeight: CGFloat = 40
        static let statusBarHeight: CGFloat = 44
        static let iconGrid: CGFloat = 24
        /// Icon stroke in points, the same at every icon size.
        static let iconStroke: CGFloat = 1.5
        /// The editor's cards: margin to the window's edges and the gap between cards.
        static let cardInset: CGFloat = 10
        static let cardGap: CGFloat = 10
        /// The title card's top: it centers on the window's buttons in the unified title bar (52 pt).
        static let titleCardTop: CGFloat = 6
        /// The callout style bar beside the canvas.
        static let sideBarWidth: CGFloat = 44
    }

    /// The cards' soft shadow (0 6 18 in the design): stronger in dark, lighter in light.
    enum CardShadow {
        static let offset = CGSize(width: 0, height: -6)
        static let radius: CGFloat = 9
        static func opacity(dark: Bool) -> Float { dark ? 0.25 : 0.10 }
    }

    enum Font {
        nonisolated(unsafe) static let ribbonLabel = NSFont.systemFont(ofSize: 12)
        nonisolated(unsafe) static let largeCaption = NSFont.systemFont(ofSize: 11.5)
        nonisolated(unsafe) static let groupLabel = NSFont.systemFont(ofSize: 11)
        nonisolated(unsafe) static let readout = NSFont.systemFont(ofSize: 12, weight: .medium)
        nonisolated(unsafe) static let caption = NSFont.systemFont(ofSize: 10.5)
        nonisolated(unsafe) static let menuItem = NSFont.systemFont(ofSize: 12.5)
    }

    // MARK: Contrast

    /// WCAG 2.1 contrast ratio of two opaque colors (1…21).
    static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ c: NSColor) -> CGFloat {
        let s = c.usingColorSpace(.sRGB) ?? c
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
    }
}

extension NSColor {
    /// 0xRRGGBBAA in sRGB.
    convenience init(srgb rgba: UInt32) {
        self.init(srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255, green: CGFloat((rgba >> 16) & 0xFF) / 255,
                  blue: CGFloat((rgba >> 8) & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }
}
