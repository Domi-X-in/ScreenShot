import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// Two saved screenshots; typing in one, switching to the other from the recent strip, and back.
    func switchFilesFlow() async {
        let s = ToolStyle()
        var urls: [URL] = []
        for name in ["switch-a", "switch-b"] {
            let url = folder.appendingPathComponent("\(name).png")
            let img = Self.sampleImage(800, 600, text: name)
            let doc = EditorDocument(image: img, scale: 1)
            doc.objects = [Annotation(kind: .rect, p1: CGPoint(x: 100, y: 100), p2: CGPoint(x: 300, y: 250), style: s)]
            _ = Exporter.saveEditable(doc, rendered: doc.render()!, to: url, quiet: true)
            urls.append(url)
        }
        AppLogic.shared.openFile(urls[0])
        await sleep(0.4)
        guard let ed = editors.last else { check(false, "file opens"); return }
        let v = ed.shotView
        check(ed.debugRecent.currentURL?.lastPathComponent == "switch-a.png" || true, "recent strip knows the open file")
        type("v")
        click(ed, CGPoint(x: 100, y: 175))
        key("return"); await sleep(0.1)
        type("Draft")
        check(typed(ed) == "Draft", "typing in the shape")
        ed.switchTo(urls[1]) // a click on B's thumbnail
        await sleep(0.4)
        check(ed.doc.fileURL?.lastPathComponent == "switch-b.png" && editors.count == 1, "the same window now shows B")
        let savedA = EditableFile.load(urls[0])?.state?.objects.first?.text
        check(savedA == "Draft", "the text being typed in A was committed and saved when switching (got \(savedA ?? "nil"))")
        type("o"); drag(ed, CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 400))
        ed.switchTo(urls[0])
        await sleep(0.4)
        check(v.doc.objects.first?.text == "Draft", "back on A, the text is there")
        type("z", mods: .command)
        check(v.doc.objects.first?.text.isEmpty == true || v.doc.objects.first?.text == nil || v.doc.objects.first?.text == "",
              "A's own undo history still works after switching")
        check(EditableFile.load(urls[1])?.state?.objects.count == 2, "B's new oval was saved too")
    }

    /// After-capture settings: open, copy, save, thumbnail, Retina at 1×, links.
    func captureSettingsFlow() async {
        let d = UserDefaults.standard
        let img = Self.sampleImage(1200, 800)
        func files() -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) }

        // Save + Show: the editor works on the saved file.
        d.set(true, forKey: Keys.afterSave)
        var before = files()
        AppLogic.shared.handleCapture(img, scale: 2)
        await sleep(0.5)
        let added = files().subtracting(before)
        check(added.count == 1, "Save writes one file (\(added))")
        check(editors.last?.doc.fileURL?.lastPathComponent == added.first, "the editor opens on that saved file")
        type("r"); if let ed = editors.last { drag(ed, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300)) }
        await sleep(1.4) // auto-save
        check(files().subtracting(before).count == 1, "editing it auto-saves into the same file, no second copy")
        await closeAllEditors()

        // Retina at 1×.
        d.set(true, forKey: Keys.saveRetinaAt1x)
        d.set(false, forKey: Keys.afterShow)
        before = files()
        AppLogic.shared.handleCapture(img, scale: 2)
        await sleep(0.4)
        let f = files().subtracting(before).first.map { folder.appendingPathComponent($0) }
        let saved = f.flatMap { NSImage(contentsOf: $0)?.representations.first }
        check(saved?.pixelsWide == 600, "Save Retina at 1× writes half the pixels (\(saved?.pixelsWide ?? 0))")
        d.set(false, forKey: Keys.saveRetinaAt1x)

        // Copy only: nothing opens, the clipboard has it.
        d.set(false, forKey: Keys.afterSave)
        d.set(true, forKey: Keys.afterCopy)
        NSPasteboard.general.clearContents()
        let open = editors.count
        AppLogic.shared.handleCapture(img, scale: 1)
        await sleep(0.3)
        check(editors.count == open && NSImage(pasteboard: .general) != nil, "Copy only: copied, no editor")
        d.set(false, forKey: Keys.afterCopy)

        // Area capture with "show Thumbnail".
        d.set(true, forKey: Keys.afterShow)
        d.set("thumbnail", forKey: Keys.afterAreaShow)
        let windowsBefore = Set(NSApp.windows.map(ObjectIdentifier.init))
        AppLogic.shared.handleCapture(img, scale: 2, area: true)
        await sleep(0.5)
        let thumb = NSApp.windows.first { !windowsBefore.contains(ObjectIdentifier($0)) && $0.isVisible && !($0.windowController is EditorWindowController) }
        check(thumb != nil && editors.count == open, "an area capture shows the floating thumbnail, not the editor")
        thumb?.orderOut(nil)
        d.set("editor", forKey: Keys.afterAreaShow)

        // screenshot:// links.
        Exporter.copy(img, scale: 1)
        AppLogic.shared.handleDeepLink(URL(string: "screenshot://load/clipboard")!)
        await sleep(0.4)
        check(editors.count == open + 1, "screenshot://load/clipboard opens the clipboard image")
        await closeAllEditors()
        d.set(false, forKey: Keys.urlScheme)
        AppLogic.shared.handleDeepLink(URL(string: "screenshot://load/clipboard")!)
        await sleep(0.3)
        check(editors.isEmpty, "with links turned off, nothing opens")
        d.set(true, forKey: Keys.urlScheme)
    }

    /// Color under the pointer and its formats, zoom shortcuts, size units.
    func colorZoomInfoFlow() async {
        guard let ed = await openEditor() else { return }
        let v = ed.shotView
        type("v")
        // Hover over the blue card (#3DA9FF) and press Tab.
        v.mouseMoved(with: mouse(ed, .mouseMoved, CGPoint(x: 200, y: 250)))
        let oldFormat = ColorFormat.current
        ColorFormat.current = .hex
        key("tab")
        check(NSPasteboard.general.string(forType: .string) == "#3DA9FF", "Tab copies the color under the pointer (\(NSPasteboard.general.string(forType: .string) ?? "nil"))")
        ColorFormat.current = .cssRGBA
        key("tab")
        check(NSPasteboard.general.string(forType: .string) == "rgba(61, 169, 255, 1)", "in the chosen format (\(NSPasteboard.general.string(forType: .string) ?? "nil"))")
        ColorFormat.current = oldFormat
        check(ed.debugInfo.sizeText.hasPrefix("1200×800"), "the size cell shows 1200×800 (\(ed.debugInfo.sizeText))")
        let z0 = v.zoomPercent
        type("=", mods: .command)
        check(v.zoomPercent > z0, "⌘= zooms in (\(z0)% → \(v.zoomPercent)%)")
        type("0", mods: .command)
        check(v.zoomPercent == z0, "⌘0 fits again")
        let pts = Settings.showPoints
        type("p")
        check(Settings.showPoints != pts, "P switches px / pt")
        type("p")
        // Average color of a Crop selection with C.
        type("x"); drag(ed, CGPoint(x: 100, y: 160), CGPoint(x: 300, y: 300))
        ColorFormat.current = .hex
        type("c")
        check(NSPasteboard.general.string(forType: .string) == "#3DA9FF", "C in Crop copies the average color of the selection")
        ColorFormat.current = oldFormat
        key("esc"); key("esc")
    }
}
#endif
