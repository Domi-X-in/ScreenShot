import AppKit
import ScreenCaptureKit

/// Capture flows and what happens after a capture (Shottr's AppLogic / Handlers).
@MainActor final class AppLogic {
    static let shared = AppLogic()

    private var lastArea: (displayID: CGDirectDisplayID, rect: CGRect)?
    private var editors: [EditorWindowController] = []

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
                let screen = NSScreen.containingMouse()
                let content = try await Capturer.content()
                let img = try await Capturer.captureScreen(screen, content: content)
                handleCapture(img, scale: screen.backingScaleFactor)
            } catch {
                report(error, "Can't take a screenshot")
            }
        }
    }

    func captureArea(mode: CurtainMode, manualScroll: Bool = false) {
        guard CurtainController.current == nil, ScrollCapture.current == nil else { return }
        Task {
            do {
                let content = try await Capturer.content()
                let windows = Capturer.windowList()
                var shots: [(NSScreen, CGImage)] = []
                for s in NSScreen.screens {
                    shots.append((s, try await Capturer.captureScreen(s, content: content)))
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
                let screen = NSScreen.screens.first { $0.frame.intersects(Geo.flip(win.frame)) } ?? NSScreen.containingMouse()
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
                let img = try await Capturer.captureScreen(screen, content: content, sourceRect: last.rect)
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
        // A file that is already open is brought forward instead of opened twice.
        if let url, let existing = editors.first(where: { $0.doc.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            NSApp.activate()
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let ed = EditorWindowController(image: img, scale: scale, state: state, url: url)
        ed.doc.savedRevision = ed.doc.revision
        editors.append(ed)
        NSApp.activate()
        ed.showWindow(nil)
        ed.window?.makeKeyAndOrderFront(nil)
        ed.window?.makeFirstResponder(ed.shotView)
        ed.applyDefaultZoom()
    }

    func editor(showing url: URL) -> EditorWindowController? {
        editors.first { $0.doc.fileURL?.standardizedFileURL == url.standardizedFileURL }
    }

    func editorClosed(_ ed: EditorWindowController) {
        DispatchQueue.main.async { self.editors.removeAll { $0 === ed } }
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
        let path = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).joined(separator: "/").lowercased()
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
