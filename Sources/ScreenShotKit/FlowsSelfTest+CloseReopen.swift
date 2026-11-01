import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// Closing the editor after an Area capture keeps the capture: the home window lists it and opening it shows the
    /// picture again, with its edits still editable.
    func closeReopenFlow() async {
        func pngs() -> Set<String> {
            Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".png") })
        }
        func captureAndClose(_ text: String, edit: Bool, close: (EditorWindowController) -> Void) async -> String? {
            let before = pngs()
            AppLogic.shared.handleCapture(Self.sampleImage(640, 400, text: text), scale: 2, area: true)
            await sleep(0.3)
            guard let ed = AppLogic.shared.editor else { check(false, "[\(text)] the Area capture opens the editor"); return nil }
            ed.window?.makeKeyAndOrderFront(nil)
            ed.window?.layoutIfNeeded()
            if edit { type("r"); drag(ed, CGPoint(x: 60, y: 60), CGPoint(x: 200, y: 160)); key("esc") }
            close(ed) // at once, before the auto-save timer fires
            await sleep(0.3)
            check(ed.window?.isVisible == false, "[\(text)] the editor goes away")
            let added = pngs().subtracting(before)
            check(added.count == 1, "[\(text)] the capture is kept in the Screenshots folder (\(added.sorted()))")
            return added.first
        }
        func reopen(_ name: String, _ text: String, edited: Bool) async {
            let url = folder.appendingPathComponent(name)
            check(LibraryItem.list(in: folder).first?.url.lastPathComponent == name, "[\(text)] the home window lists it first")
            AppLogic.shared.openFile(url)
            await sleep(0.3)
            guard let ed = AppLogic.shared.editor else { check(false, "[\(text)] opening it reopens the editor"); return }
            check(ed.doc.image.width == 640 && ed.doc.scale == 2, "[\(text)] the editor shows the capture (\(ed.doc.image.width) px @\(ed.doc.scale)x)")
            check(ed.doc.objects.contains { $0.kind == .rect } == edited,
                  edited ? "[\(text)] its edits are still there, editable" : "[\(text)] with no edits added")
            ed.close()
            await sleep(0.2)
        }

        if let name = await captureAndClose("Unedited", edit: false, close: { $0.window?.performClose(nil) }) { await reopen(name, "Unedited", edited: false) }
        if let name = await captureAndClose("Edited", edit: true, close: { $0.window?.performClose(nil) }) { await reopen(name, "Edited", edited: true) }
        // Copy and Close (title card) closes every window the same way.
        UserDefaults.standard.set(true, forKey: Keys.closeAfterCopySave)
        defer { UserDefaults.standard.set(false, forKey: Keys.closeAfterCopySave) }
        if let name = await captureAndClose("Copy and Close", edit: false, close: { $0.debugEditorRibbon?.copyImage.action?() }) {
            await reopen(name, "Copy and Close", edited: false)
        }

        // R13: the Dock icon brings the hidden editor back as it was, even with a pin on screen.
        let delegate = NSApp.delegate as? AppDelegate
        func clickDock(windows: Bool) async {
            _ = delegate?.applicationShouldHandleReopen(NSApp, hasVisibleWindows: windows)
            await sleep(0.5)
        }
        AppLogic.shared.handleCapture(Self.sampleImage(500, 300, text: "Keep me"), scale: 2, area: true)
        await sleep(0.3)
        guard let ed = AppLogic.shared.editor, let r = ed.debugEditorRibbon else { check(false, "the capture opens the editor"); return }
        ed.window?.makeKeyAndOrderFront(nil)
        type("r"); drag(ed, CGPoint(x: 60, y: 60), CGPoint(x: 200, y: 160)); key("esc")
        let doc = ed.doc
        ed.pinImage()
        await sleep(0.3)
        let pin = NSApp.windows.first { $0 is PinWindow && $0.isVisible }
        check(ed.window?.isVisible == false && AppLogic.shared.editor === ed, "Pin hides the editor")
        await clickDock(windows: true)
        ed.escape()
        await sleep(0.3)
        check(ed.window?.isVisible == false && AppLogic.shared.editor === ed, "Esc hides the editor")
        await clickDock(windows: true)
        r.copyImage.action?()
        await sleep(0.4)
        check(ed.window?.isVisible == false && AppLogic.shared.editor === ed, "Copy and Close hides the editor")
        await clickDock(windows: true)
        check(AppLogic.shared.editor === ed && ed.window?.isVisible == true && ed.doc === doc, "the Dock icon shows the same editor and picture")
        check(!doc.undoStack.isEmpty, "with its undo history")
        // The pin's Edit comes back to the same picture, its objects still editable.
        ed.pinImage()
        await sleep(0.3)
        if let edited = NSApp.windows.last(where: { $0 is PinWindow && $0.isVisible && $0 !== pin }),
           let down = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: edited.windowNumber,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
           let item = edited.contentView?.menu(for: down)?.items.first(where: { $0.title == "Edit" }), let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
            await sleep(0.5)
            check(ed.window?.isVisible == true && ed.doc === doc && !doc.undoStack.isEmpty && doc.objects.contains { $0.kind == .rect },
                  "the pin's Edit shows the same picture, editable, with its undo history")
            check(!edited.isVisible, "and the pin goes away")
        } else { check(false, "the pin has an Edit item") }
        pin?.close()
        ed.window?.miniaturize(nil)
        await sleep(0.6)
        await clickDock(windows: false)
        check(ed.window?.isMiniaturized == false && ed.window?.isVisible == true, "the Dock icon brings it back when minimized")
        ed.window?.performClose(nil)
        await sleep(0.3)
        check(ed.window?.isVisible == false && AppLogic.shared.editor === ed, "the red button only hides it")

        // No editor yet, as after launching: the newest screenshot opens.
        ed.close()
        await sleep(0.3)
        check(AppLogic.shared.editor == nil, "the editor is really closed")
        let newest = LibraryItem.list(in: folder).first?.url
        await clickDock(windows: false)
        check(AppLogic.shared.editor?.window?.isVisible == true && AppLogic.shared.editor?.doc.fileURL?.standardizedFileURL == newest?.standardizedFileURL,
              "with no editor, the Dock icon opens the newest screenshot")
    }
}
#endif
