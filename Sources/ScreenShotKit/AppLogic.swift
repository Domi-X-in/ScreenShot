import AppKit
import ScreenCaptureKit

/// Capture flows and what happens after a capture (Shottr's AppLogic / Handlers).
@MainActor final class AppLogic {
    static let shared = AppLogic()

    private var lastArea: (displayID: CGDirectDisplayID, rect: CGRect)?
    /// The one editor window (ROADMAP, Fase 6 · R11): everything opened goes into it.
    private(set) var editor: EditorWindowController?
    private var previousApp: NSRunningApplication?
    private var editorHiddenForCapture = false
    /// An area capture is taking its pictures, before the overlay exists: a second request must not start another.
    /// (An overlay nothing owns stays on top of everything and ignores Esc.)
    private var areaCaptureStarting = false
    private var lastLinkCapture = Date.distantPast

    func run(_ a: HotkeyAction) {
        switch a {
        case .area: captureArea(mode: .area)
        case .fullscreen: captureFullscreen()
        case .anyWindow: captureArea(mode: .window)
        case .activeWindow: captureActiveWindow()
        case .scrolling: captureArea(mode: .scrolling)
        case .scrollingManual: captureArea(mode: .scrolling, manualScroll: true)
        case .repeatArea: repeatArea()
        case .ocr: captureArea(mode: .ocr)
        case .delayed: captureFullscreen(delay: 3)
        }
    }

    /// Shown only when ScreenCaptureKit actually refuses. CGPreflightScreenCaptureAccess() is cached per process and can
    /// keep saying "no" after the user grants access, so it is not used to gate captures.
    private func report(_ error: Error, _ prefix: String) {
        restoreEditorAfterCapture()
        guard Capturer.isPermissionError(error) else {
            Toast.show("\(prefix): \(error.localizedDescription)")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "Allow ScreenShot in System Settings › Privacy & Security › Screen & System Audio Recording. If it is already on, turn it off and on again, then quit and reopen ScreenShot."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit ScreenShot")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }

    func captureFullscreen(delay: Int = 0) {
        Task {
            do {
                for s in stride(from: delay, to: 0, by: -1) {
                    Toast.show("Screenshot in \(s)…", duration: 0.9)
                    try await Task.sleep(for: .seconds(1))
                }
                guard let screen = NSScreen.containingMouse() else { throw CaptureError.noDisplay }
                let content = try await Capturer.content()
                let img = try await Capturer.captureScreen(screen, content: content, cursor: Settings.showsCursor(fullscreen: true))
                handleCapture(img, scale: screen.backingScaleFactor)
            } catch {
                report(error, "Can't take a screenshot")
            }
        }
    }

    func captureArea(mode: CurtainMode, manualScroll: Bool = false) {
        guard CurtainController.current == nil, ScrollCapture.current == nil, !areaCaptureStarting else { return }
        areaCaptureStarting = true
        Task {
            defer { areaCaptureStarting = false }
            do {
                let content = try await Capturer.content()
                let windows = Capturer.windowList()
                var shots: [(NSScreen, CGImage)] = []
                for s in NSScreen.screens {
                    shots.append((s, try await Capturer.captureScreen(s, content: content, cursor: Settings.showsCursor(fullscreen: false))))
                }
                let c = CurtainController(shots: shots, windowList: windows, mode: mode) { result in
                    self.curtainFinished(result, mode: mode, manualScroll: manualScroll, content: content)
                }
                CurtainController.current = c
                c.show()
            } catch {
                report(error, "Area capture failed")
            }
        }
    }

    private func curtainFinished(_ result: CurtainResult, mode: CurtainMode, manualScroll: Bool, content: SCShareableContent) {
        switch result {
        case .cancelled:
            restoreEditorAfterCapture()
            return
        case let .area(screen, image, pointRect):
            lastArea = (screen.displayID, pointRect)
            switch mode {
            case .ocr: OCR.run(image)
            case .scrolling: ScrollCapture.start(screen: screen, rect: pointRect, auto: !manualScroll)
            case .area, .window: handleCapture(image, scale: screen.backingScaleFactor, area: true)
            }
        case let .window(id):
            Task {
                do {
                    let img = try await Capturer.captureWindow(id: id, content: content)
                    let scale = content.windows.first { $0.windowID == id }.map { SCContentFilter(desktopIndependentWindow: $0).pointPixelScale }
                    if mode == .ocr { OCR.run(img) } else { handleCapture(img, scale: CGFloat(scale ?? 2)) }
                } catch {
                    report(error, "Window grab failed")
                }
            }
        }
    }

    func captureActiveWindow() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let win = Capturer.windowList().first(where: { $0.pid == pid }) ?? Capturer.windowList().first else {
            Toast.show(CaptureError.noWindow.localizedDescription)
            return
        }
        Task {
            do {
                let content = try await Capturer.content()
                let img = try await Capturer.captureWindow(id: win.id, content: content)
                guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(Geo.flip(win.frame)) }) ?? NSScreen.containingMouse() else {
                    throw CaptureError.noDisplay
                }
                handleCapture(img, scale: screen.backingScaleFactor)
            } catch {
                report(error, "Window grab failed")
            }
        }
    }

    func repeatArea() {
        guard let last = lastArea, let screen = NSScreen.screens.first(where: { $0.displayID == last.displayID }) else {
            Toast.show("Repeat Area Capture takes a screenshot of the previously captured area. Perform an area capture first.", duration: 3)
            return
        }
        Task {
            do {
                let content = try await Capturer.content()
                let img = try await Capturer.captureScreen(screen, content: content, sourceRect: last.rect,
                                                           cursor: Settings.showsCursor(fullscreen: false))
                handleCapture(img, scale: screen.backingScaleFactor)
            } catch {
                report(error, "Area capture failed")
            }
        }
    }

    /// Applies the "after capture" preferences.
    /// Live capture self-test only: receives each capture instead of the copy/save/editor handling.
    var captureHookForTest: ((CGImage, CGFloat) -> Void)?

    func handleCapture(_ img: CGImage, scale: CGFloat, area: Bool = false) {
        if let hook = captureHookForTest { hook(img, scale); return }
        defer { restoreEditorAfterCapture() }
        let copy = Settings.afterCopy, save = Settings.afterSave
        let show = Settings.afterShow || (!copy && !save)
        if copy {
            Exporter.copy(img, scale: scale)
            if !show { Toast.show("Copied to the clipboard") }
        }
        // With "Save" on, the editor works on that saved file, so auto-save updates it instead of making a second copy.
        let savedURL = save ? Exporter.save(img, scale: scale, quiet: show) : nil
        guard show else { return }
        if area && Settings.showThumbnail {
            Thumbnail.show(img, scale: scale)
        } else {
            openEditor(img, scale: scale, url: savedURL)
        }
    }

    func openEditor(_ img: CGImage, scale: CGFloat, state: EditState? = nil, url: URL? = nil) {
        // The editor is already open: the picture replaces the one it shows (that one is auto-saved first).
        if let ed = editor {
            ed.show(image: img, scale: scale, state: state, url: url)
            NSApp.activate()
            ed.window?.makeKeyAndOrderFront(nil)
            ed.window?.makeFirstResponder(ed.shotView)
            return
        }
        let ed = EditorWindowController(image: img, scale: scale, state: state, url: url)
        ed.doc.savedRevision = ed.doc.revision
        editor = ed
        NSApp.activate()
        ed.showWindow(nil)
        ed.window?.makeKeyAndOrderFront(nil)
        ed.window?.makeFirstResponder(ed.shotView)
        ed.applyDefaultZoom()
    }

    /// The Dock icon: the editor as it was left or, with none yet, the newest screenshot. An empty folder shows the
    /// editor's page of capture buttons.
    func showEditor() {
        NSApp.activate()
        if let editor {
            editor.reveal()
            return
        }
        let folder = Settings.saveFolder
        Task.detached(priority: .userInitiated) {
            let newest = LibraryItem.list(in: folder).first?.url
            await MainActor.run {
                // A capture may have opened the editor in the meantime.
                if let editor = self.editor {
                    editor.reveal()
                } else if let newest {
                    self.openFile(newest)
                } else {
                    self.openEmptyEditor()
                }
            }
        }
    }

    private func openEmptyEditor() {
        let blank = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        guard let blank else { return }
        let ed = EditorWindowController(image: blank, scale: 2)
        ed.doc.savedRevision = ed.doc.revision
        editor = ed
        ed.showWindow(nil)
        ed.showEmptyState()
        ed.window?.makeKeyAndOrderFront(nil)
    }

    /// A capture started from the editor: the window steps aside so it isn't in the picture, and comes back if no new
    /// picture replaces what it shows.
    func captureFromEditor(_ a: HotkeyAction) {
        hideEditorForCapture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.run(a) }
    }

    func hideEditorForCapture() {
        editor?.hideEditor()
        editorHiddenForCapture = editor != nil
    }

    func restoreEditorAfterCapture() {
        guard editorHiddenForCapture else { return }
        editorHiddenForCapture = false
        NSApp.activate()
        editor?.reveal()
    }

    /// macOS says memory is short: gives back everything that can be made again.
    func releaseMemory(in window: EditorWindowController? = nil) {
        Log.memory.notice("Memory pressure: releasing caches")
        (window ?? editor)?.releaseMemory()
        // Last: the editor's pending save fills this cache again.
        BasePNGCache.shared.clear()
    }

    func editorClosed(_ ed: EditorWindowController) {
        DispatchQueue.main.async { if self.editor === ed { self.editor = nil } }
    }

    /// After Copy or Save from the title card (with Preferences › General › "Close all windows after Copy or Save"):
    /// every ScreenShot window closes except pins, and the app that was in front before gets the focus back, so the
    /// picture can be pasted there at once. The app keeps running, and the editor is only hidden.
    func closeAllWindows() {
        Thumbnail.dismissCurrent()
        editor?.hideEditor()
        LibraryWindowController.shared?.close()
        OnboardingWindowController.shared?.window?.close()
        (NSApp.delegate as? AppDelegate)?.closePreferences()
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
        if NSFontPanel.sharedFontPanelExists { NSFontPanel.shared.orderOut(nil) }
        // With a Dock icon (R12) macOS doesn't hand the focus back on deactivate, so it is given to that app by name.
        if let previousApp, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        } else {
            NSApp.deactivate()
        }
    }

    /// Remembers the last other app in front, for `closeAllWindows`.
    func trackPreviousApp() {
        let me = NSRunningApplication.current
        if let front = NSWorkspace.shared.frontmostApplication, front != me { previousApp = front }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app != me else { return }
            MainActor.assumeIsolated { AppLogic.shared.previousApp = app }
        }
    }

    func loadFromClipboard() {
        guard let ns = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            Toast.show("Make sure your clipboard contains an image and try again", duration: 2.5)
            return
        }
        open(ns)
    }

    /// Opens an image file; annotations saved by this app come back as editable objects.
    func openFile(_ url: URL) {
        guard let loaded = EditableFile.load(url) else { Toast.show("Image Reading Error"); return }
        openEditor(loaded.image, scale: loaded.scale, state: loaded.state, url: url)
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.directoryURL = Settings.saveFolder
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { openFile(url) }
    }

    private func open(_ ns: NSImage) {
        guard let rep = ns.representations.first, let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Toast.show("Image Reading Error")
            return
        }
        let scale = rep.size.width > 0 ? max(1, CGFloat(cg.width) / rep.size.width) : 1
        openEditor(cg, scale: scale)
    }

    /// screenshot://grab/area, grab/fullscreen, grab/window, grab/window/active, grab/scrolling, grab/repeat, grab/delayed, ocr, load/clipboard
    func handleDeepLink(_ url: URL) {
        guard Settings.urlSchemeEnabled else {
            Toast.show("screenshot:// links are turned off in Preferences › Advanced")
            return
        }
        let path = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).joined(separator: "/").lowercased()
        // A page or an app can fire these as fast as it likes; captures from links are at most one a second.
        if path.hasPrefix("grab/") || path == "ocr" {
            guard Date().timeIntervalSince(lastLinkCapture) >= 1 else { return }
            lastLinkCapture = Date()
        }
        switch path {
        case "grab/area": run(.area)
        case "grab/fullscreen": run(.fullscreen)
        case "grab/window": run(.anyWindow)
        case "grab/window/active": run(.activeWindow)
        case "grab/scrolling": run(.scrolling)
        case "grab/scrolling/manual": run(.scrollingManual)
        case "grab/repeat": run(.repeatArea)
        case "grab/delayed": run(.delayed)
        case "ocr": run(.ocr)
        case "load/clipboard": loadFromClipboard()
        default: Toast.show("Unknown link: \(url.absoluteString)")
        }
    }
}
