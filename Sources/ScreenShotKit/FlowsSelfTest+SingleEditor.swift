import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// R11: the app has one editor window, and the title card's Copy and Save close every window but pins (Preferences ›
    /// General, on by default) so the picture can be pasted at once in the app that was in front.
    func singleEditorFlow() async {
        let d = UserDefaults.standard
        defer { d.set(false, forKey: Keys.closeAfterCopySave) }
        Settings.returnToSelect = true
        func pngs() -> Set<String> {
            Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".png") })
        }
        func visible(_ w: NSWindow?) -> Bool { w?.isVisible == true }

        // One window for everything.
        guard let ed = await openEditor(Self.sampleImage(800, 500, text: "First")) else { check(false, "the editor opens"); return }
        type("r"); drag(ed, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 250)); key("esc")
        let before = pngs()
        guard let again = await openEditor(Self.sampleImage(600, 400, text: "Second")) else { return }
        check(again === ed && editors.count == 1 && ed.doc.image.width == 600, "a new capture opens in the same editor window")
        let saved = pngs().subtracting(before)
        check(saved.count == 1, "the edited capture it replaced was auto-saved to the folder (\(saved))")
        if let name = saved.first {
            AppLogic.shared.openFile(folder.appendingPathComponent(name))
            await sleep(0.3)
            check(editors.count == 1 && ed.doc.fileURL?.lastPathComponent == name && ed.doc.objects.contains { $0.kind == .rect },
                  "opening that file shows it in the same window, still editable")
        }
        let beforeUnedited = pngs()
        _ = await openEditor(Self.sampleImage(500, 300, text: "Third"))
        _ = await openEditor(Self.sampleImage(400, 300, text: "Fourth"))
        check(editors.count == 1 && pngs() == beforeUnedited, "an unedited capture is replaced without leaving a file")

        // Copy closes every window but pins.
        d.set(true, forKey: Keys.closeAfterCopySave)
        ed.pinImage() // a pin on screen, then the editor again
        await sleep(0.3)
        guard let pin = NSApp.windows.first(where: { $0 is PinWindow && $0.isVisible }) else { check(false, "a pin is on screen"); return }
        guard let ed2 = await openEditor(Self.sampleImage(700, 450, text: "Copy me")), let r = ed2.debugEditorRibbon else { return }
        LibraryWindowController.show()
        (NSApp.delegate as? AppDelegate)?.showPreferences()
        await sleep(0.3)
        check(r.copyImage.title == "Copy and Close" && r.save.title == "Save and Close", "the title card says Copy and Close, Save and Close")
        NSPasteboard.general.clearContents()
        r.copyImage.action?()
        await sleep(0.3)
        let copied = NSImage(pasteboard: .general).map { Int($0.size.width) }
        check(copied == 700, "Copy puts the picture on the clipboard (\(copied ?? 0))")
        check(!visible(ed2.window) && !visible(LibraryWindowController.shared?.window) && editors.isEmpty,
              "and closes the editor and the home window")
        check(!NSApp.windows.contains { $0.isVisible && $0.windowController is PreferencesWindowController }, "and Preferences")
        check(pin.isVisible, "pins stay on screen")
        check(AppLogic.shared.editor == nil, "the app keeps running with no editor open")
        pin.close()

        // Save does the same once the file is written.
        guard let ed3 = await openEditor(Self.sampleImage(640, 360, text: "Save me")), let r3 = ed3.debugEditorRibbon else { return }
        type("o"); drag(ed3, CGPoint(x: 100, y: 100), CGPoint(x: 250, y: 200)); key("esc")
        let beforeSave = pngs()
        r3.save.action?()
        await sleep(0.3)
        check(pngs().count == beforeSave.count + 1 || ed3.doc.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true,
              "Save writes the file")
        check(!visible(ed3.window) && editors.isEmpty, "and closes the editor")

        // A failed save leaves everything open.
        let unwritable = URL(fileURLWithPath: "/System/screenshot-r11-test.png")
        guard let ed4 = await openEditor(Self.sampleImage(500, 300), url: unwritable), let r4 = ed4.debugEditorRibbon else { return }
        type("r"); drag(ed4, CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150)); key("esc")
        r4.save.action?()
        await sleep(0.3)
        check(visible(ed4.window) && ed4.debugEditorStatus?.notices.current?.kind == .error,
              "a failed save keeps the editor open and shows the error (\(ed4.debugEditorStatus?.notices.shownText ?? "-"))")

        // With the setting off, Copy keeps the editor open.
        d.set(false, forKey: Keys.closeAfterCopySave)
        r4.copyImage.action?()
        await sleep(0.2)
        check(visible(ed4.window), "with the setting off, Copy keeps the editor open")
        await closeAllEditors()
    }
}
#endif
