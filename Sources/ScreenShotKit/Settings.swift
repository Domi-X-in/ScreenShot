import AppKit

enum Keys {
    static let afterCopy = "afterGrabCopy"
    static let afterSave = "afterGrabSave"
    static let afterShow = "afterGrabShow"
    static let escCopy = "escCopy"
    static let escSave = "escSave"
    static let saveFolder = "saveFolder"
    static let saveFormat = "saveFormat"
    static let windowShadow = "windowShadow"
    static let ocrRemoveBreaks = "ocrRemoveBreaks"
    static let ocrLanguage = "ocrLanguage"
    static let scrollSpeed = "scrollingSpeed"
    static let reverseAutoscroll = "scrollingReverseAutoscroll"
    static let toolColor = "toolColor"
    static let toolWidth = "toolWidth"
    static let counterShape = "counterShape"
    static let toolCustomColor = "toolCustomColor"
    static let afterAreaShow = "afterAreaShow"
    static let hideMenuBarIcon = "hideMenuBarIcon"
    static let captureCursor = "captureCursor"
    static let saveRetinaAt1x = "saveRetinaAt1x"
    static let scrollMaxHeight = "scrollMaxHeight"
    static let windowBackground = "windowBackground"
    static let windowBackgroundColor = "windowBackgroundColor"
    static let urlScheme = "urlSchemeEnabled"
    static let onboardingDone = "onboardingDone"
    static let onboardingPage = "onboardingPage"
}

enum Settings {
    static let d = UserDefaults.standard

    static var defaultFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    static func registerDefaults() {
        d.register(defaults: [
            Keys.afterCopy: false,
            Keys.afterSave: false,
            Keys.afterShow: true,
            Keys.escCopy: true,
            Keys.escSave: false,
            Keys.saveFolder: defaultFolder.path,
            Keys.saveFormat: "png",
            Keys.windowShadow: true,
            Keys.ocrRemoveBreaks: false,
            Keys.ocrLanguage: "auto",
            Keys.scrollSpeed: 0.5,
            Keys.reverseAutoscroll: false,
            Keys.toolColor: 0,
            Keys.toolWidth: 4.0,
            Keys.afterAreaShow: "editor",
            Keys.hideMenuBarIcon: false,
            Keys.captureCursor: "auto",
            Keys.saveRetinaAt1x: false,
            Keys.scrollMaxHeight: 30000,
            Keys.windowBackground: "none",
            Keys.windowBackgroundColor: "#3B82F6",
            Keys.urlScheme: true,
            "appearance": "system",
        ])
    }

    static var afterCopy: Bool { d.bool(forKey: Keys.afterCopy) }
    static var afterSave: Bool { d.bool(forKey: Keys.afterSave) }
    static var afterShow: Bool { d.bool(forKey: Keys.afterShow) }
    static var escCopy: Bool { d.bool(forKey: Keys.escCopy) }
    static var escSave: Bool { d.bool(forKey: Keys.escSave) }
    static var saveFolder: URL { URL(fileURLWithPath: d.string(forKey: Keys.saveFolder) ?? defaultFolder.path) }
    static var saveFormat: String { d.string(forKey: Keys.saveFormat) ?? "png" }
    static var windowShadow: Bool { d.bool(forKey: Keys.windowShadow) }
    static var ocrRemoveBreaks: Bool { d.bool(forKey: Keys.ocrRemoveBreaks) }
    /// Shottr's "OCR main language": a Vision language code, or "auto".
    static var ocrLanguage: String { d.string(forKey: Keys.ocrLanguage) ?? "auto" }
    static var scrollSpeed: Double { d.double(forKey: Keys.scrollSpeed) }
    static var reverseAutoscroll: Bool { d.bool(forKey: Keys.reverseAutoscroll) }
    /// Shottr's "Show Size in Logical Points" (shortcut P): sizes in points instead of pixels.
    static var showPoints: Bool {
        get { d.bool(forKey: "showPoints") }
        set { d.set(newValue, forKey: "showPoints") }
    }
    /// Shottr's "Zoom with mouse wheel": a plain scroll zooms the editor.
    static var wheelZooms: Bool { d.bool(forKey: "wheelZooms") }
    /// Shottr's "Default zoom level: Prefer 100%".
    static var prefer100: Bool { d.bool(forKey: "prefer100") }
    /// Shottr's "After Area Crop, show: Thumbnail / Editor".
    static var showThumbnail: Bool { d.string(forKey: Keys.afterAreaShow) == "thumbnail" }

    static var hideMenuBarIcon: Bool { d.bool(forKey: Keys.hideMenuBarIcon) }
    /// "auto" shows the pointer in fullscreen and delayed screenshots only; "include" / "exclude" always / never.
    static func showsCursor(fullscreen: Bool) -> Bool {
        switch d.string(forKey: Keys.captureCursor) {
        case "include": true
        case "exclude": false
        default: fullscreen
        }
    }
    static var saveRetinaAt1x: Bool { d.bool(forKey: Keys.saveRetinaAt1x) }
    /// Longest scrolling capture, in pixels.
    static var scrollMaxHeight: Int { max(1000, d.integer(forKey: Keys.scrollMaxHeight)) }
    /// "none" (transparent), "wallpaper" or "color".
    static var windowBackground: String { d.string(forKey: Keys.windowBackground) ?? "none" }
    static var windowBackgroundColor: NSColor {
        get { NSColor(rgbaHex: d.string(forKey: Keys.windowBackgroundColor) ?? "") ?? NSColor(hex: 0x3B82F6) }
        set { d.set(newValue.rgbaHex, forKey: Keys.windowBackgroundColor) }
    }
    static var urlSchemeEnabled: Bool { d.bool(forKey: Keys.urlScheme) }

    /// App-only appearance: "system" follows macOS, "light" / "dark" override it for ScreenShot's windows.
    static var appearance: String { d.string(forKey: "appearance") ?? "system" }

    /// Applies the appearance setting to every window of the app (nil = follow macOS).
    @MainActor static func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
