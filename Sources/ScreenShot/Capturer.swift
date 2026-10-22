import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay, noWindow

    var errorDescription: String? {
        switch self {
        case .noDisplay: "Can't find the display to capture"
        case .noWindow: "No windows are present, try taking a fullscreen screenshot instead"
        }
    }
}

struct WindowInfo {
    let id: CGWindowID
    let frame: CGRect // CG global coordinates (top-left origin)
    let pid: pid_t
}

@MainActor enum Capturer {
    /// Asks macOS for Screen Recording access once; later checks happen when a capture fails.
    static func requestPermissionOnFirstLaunch() {
        let key = "askedScreenRecording"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == SCStreamErrorDomain && e.code == SCStreamError.Code.userDeclined.rawValue
    }

    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Captures a display (or a display-local `sourceRect` in points, top-left origin), excluding this app's windows.
    static func captureScreen(_ screen: NSScreen, content: SCShareableContent, sourceRect: CGRect? = nil) async throws -> CGImage {
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.noDisplay
        }
        let own = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingWindows: own)
        let cfg = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        let r = sourceRect ?? CGRect(origin: .zero, size: display.frame.size)
        if sourceRect != nil { cfg.sourceRect = r }
        cfg.width = Int((r.width * scale).rounded())
        cfg.height = Int((r.height * scale).rounded())
        cfg.showsCursor = false
        cfg.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// Captures a single window with transparency (and optionally its shadow), like Shottr's window capture.
    static func captureWindow(id: CGWindowID, content: SCShareableContent) async throws -> CGImage {
        guard let w = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: w)
        let cfg = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        cfg.width = Int((filter.contentRect.width * scale).rounded())
        cfg.height = Int((filter.contentRect.height * scale).rounded())
        cfg.ignoreShadowsSingleWindow = !Settings.windowShadow
        cfg.showsCursor = false
        cfg.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// Normal-layer on-screen windows of other apps, front to back.
    static func windowList() -> [WindowInfo] {
        let own = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { d in
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: b),
                  frame.width > 40, frame.height > 40,
                  (d[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { return nil }
            return WindowInfo(id: id, frame: frame, pid: pid)
        }
    }
}
