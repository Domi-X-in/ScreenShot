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
    /// Live capture self-test only: keep this app's own windows (the test pattern) in captures.
    static var includeOwnWindows = false

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
        let filter = SCContentFilter(display: display, excludingWindows: includeOwnWindows ? [] : own)
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
        if Settings.windowShadow, let shadowed = try await captureWindowWithShadow(w, content: content) { return shadowed }
        let filter = SCContentFilter(desktopIndependentWindow: w)
        let cfg = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        cfg.width = Int((filter.contentRect.width * scale).rounded())
        cfg.height = Int((filter.contentRect.height * scale).rounded())
        cfg.ignoreShadowsSingleWindow = true
        cfg.showsCursor = false
        cfg.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// A desktop-independent window capture is sized to the window's frame, which cuts its shadow off. To keep the
    /// shadow, capture just that window from its display, with a margin, on a transparent background, then trim.
    private static func captureWindowWithShadow(_ w: SCWindow, content: SCShareableContent) async throws -> CGImage? {
        let center = CGPoint(x: w.frame.midX, y: w.frame.midY) // CG global, top-left origin
        guard let screen = NSScreen.screens.first(where: { CGRect(origin: $0.cgOrigin, size: $0.frame.size).contains(center) }),
              let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { return nil }
        let margin: CGFloat = 80 // macOS window shadows reach roughly 40-60 pt
        let local = w.frame.offsetBy(dx: -screen.cgOrigin.x, dy: -screen.cgOrigin.y).insetBy(dx: -margin, dy: -margin)
            .intersection(CGRect(origin: .zero, size: screen.frame.size))
        guard !local.isEmpty else { return nil }
        let filter = SCContentFilter(display: display, including: [w])
        let cfg = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        cfg.sourceRect = local
        cfg.width = Int((local.width * scale).rounded())
        cfg.height = Int((local.height * scale).rounded())
        cfg.backgroundColor = .clear
        // Display captures drop window shadows unless told otherwise.
        cfg.ignoreShadowsDisplay = false
        cfg.ignoreShadowsSingleWindow = false
        cfg.showsCursor = false
        cfg.captureResolution = .best
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return trimTransparent(img)
    }

    /// Crops away fully transparent rows and columns around an image.
    static func trimTransparent(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return img }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where px[row + x * 4 + 3] > 2 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Bitmap rows run top to bottom, matching CGImage cropping coordinates.
        return img.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
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
