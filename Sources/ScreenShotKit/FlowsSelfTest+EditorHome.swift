import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// R14: the editor is the home: its capture button, and its page with no screenshot at all.
    func editorHomeFlow() async {
        // An empty folder: the Dock icon shows the page of capture buttons, and nothing gets saved.
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-empty-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let d = UserDefaults.standard
        let saved = d.string(forKey: Keys.saveFolder)
        d.set(empty.path, forKey: Keys.saveFolder)
        defer { d.set(saved, forKey: Keys.saveFolder) }
        func files() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: empty.path)) ?? [] }
        let delegate = NSApp.delegate as? AppDelegate

        if Settings.saveFolder.standardizedFileURL.path == empty.standardizedFileURL.path {
            _ = delegate?.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            await sleep(0.6)
            guard let ed = AppLogic.shared.editor else { check(false, "the editor opens with an empty folder"); return }
            check(ed.emptyState != nil && ed.window?.isVisible == true, "an empty folder shows the page of capture buttons")
            check(ed.emptyState?.items.map(\.title) == ["Area", "Window", "Fullscreen", "Open Image"], "with Area, Window, Fullscreen and Open Image")
            check(ed.window?.firstResponder === ed.emptyState, "the blank picture can't be edited")
            ed.window?.performClose(nil)
            await sleep(0.3)
            check(files().isEmpty, "closing the page saves nothing")
            _ = delegate?.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            await sleep(0.4)
            check(ed.emptyState != nil && ed.window?.isVisible == true, "the Dock icon shows the page again")
            AppLogic.shared.handleCapture(Self.sampleImage(500, 300, text: "First"), scale: 2, area: true)
            await sleep(0.4)
            check(AppLogic.shared.editor === ed && ed.emptyState == nil && ed.doc.image.width == 500, "the first capture replaces the page")
            check(files().isEmpty, "and the blank picture was never saved")
        } else {
            print("SKIP [editor-home] the save folder is fixed for this run, so the empty page can't be checked")
        }
        await closeAllEditors()

        // The capture button: the window steps aside, and comes back if the capture is cancelled.
        guard let ed = await openEditor(Self.sampleImage(640, 360, text: "Behind")), let r = ed.debugEditorRibbon else { check(false, "the editor opens"); return }
        check(r.capture.split && r.capture.menu?().items.map(\.title).count == 3, "the title card has New Capture, with Area, Window and Fullscreen")
        let doc = ed.doc
        AppLogic.shared.hideEditorForCapture()
        check(ed.window?.isVisible == false, "New Capture hides the editor, so it isn't in the picture")
        AppLogic.shared.handleCapture(Self.sampleImage(300, 200, text: "New"), scale: 2)
        await sleep(0.4)
        check(ed.window?.isVisible == true && ed.doc !== doc && ed.doc.image.width == 300, "the new capture comes back in the editor")
        d.set(false, forKey: Keys.afterShow)
        d.set(true, forKey: Keys.afterCopy)
        let current = ed.doc
        AppLogic.shared.hideEditorForCapture()
        AppLogic.shared.handleCapture(Self.sampleImage(200, 200, text: "Copied only"), scale: 2)
        await sleep(0.4)
        check(ed.window?.isVisible == true && ed.doc === current, "a capture that only copies brings the editor back as it was")
        d.set(true, forKey: Keys.afterShow)
        d.set(false, forKey: Keys.afterCopy)
    }
}
#endif
