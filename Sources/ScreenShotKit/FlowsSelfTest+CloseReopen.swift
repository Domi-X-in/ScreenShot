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
            check(AppLogic.shared.editor == nil, "[\(text)] the editor closes")
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

        if let name = await captureAndClose("Unedited", edit: false, close: { $0.close() }) { await reopen(name, "Unedited", edited: false) }
        if let name = await captureAndClose("Edited", edit: true, close: { $0.close() }) { await reopen(name, "Edited", edited: true) }
        // Copy and Close (title card) closes every window the same way.
        UserDefaults.standard.set(true, forKey: Keys.closeAfterCopySave)
        defer { UserDefaults.standard.set(false, forKey: Keys.closeAfterCopySave) }
        if let name = await captureAndClose("Copy and Close", edit: false, close: { $0.debugEditorRibbon?.copyImage.action?() }) {
            await reopen(name, "Copy and Close", edited: false)
        }
    }
}
#endif
