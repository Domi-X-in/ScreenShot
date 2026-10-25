import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// The new editor (Settings.newEditorUI): the trimmed title bar, and the ribbon's Clipboard, Shapes and Tools groups
    /// driving the editor with real clicks on their buttons.
    func ribbonEditorFlow() async {
        let d = UserDefaults.standard
        d.set(true, forKey: "newEditorUI")
        defer { d.removeObject(forKey: "newEditorUI") }
        guard let ed = await openEditor(Self.sampleImage(1000, 700)), let win = ed.window else { check(false, "editor opens"); return }
        let v = ed.shotView
        guard let r = ed.debugEditorRibbon else { check(false, "the new editor has a ribbon"); return }

        // Title bar: the window's own commands only.
        let ids = win.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
        check(ids.contains("titleActions") && ids.contains("dragOut") && ids.contains("history"), "the title bar has the actions, drag and undo/redo (\(ids))")
        check(!ids.contains("tools") && !ids.contains("crop") && !ids.contains("adjust"), "the tools left the title bar")
        check(r.view.window === win && r.view.frame.height == DesignTokens.Metrics.ribbonHeight, "the ribbon sits in the window, 94 pt tall")
        check(abs(r.view.frame.minY - v.frame.maxY) < 1, "the canvas starts under the ribbon (ribbon \(r.view.frame), canvas \(v.frame))")
        let shown = r.groups.filter { !$0.isHidden }.map(\.id)
        check(Array(shown.prefix(7)) == ["clipboard", "font", "paragraph", "color", "shapes", "tools", "arrange"],
              "the design's seven groups in order, then at most one contextual group (\(shown))")
        check(shown.count <= 8, "only the tool in hand's options group shows")

        func button(_ item: RibbonItem) -> RibbonButton? {
            let roots: [NSView?] = [win.contentView, win.contentView?.superview] + (win.toolbar?.items.map(\.view) ?? [])
            return roots.flatMap { allViews(RibbonButton.self, in: $0) }.first { $0.item === item && !$0.isHiddenOrHasHiddenAncestor }
        }
        func press(_ item: RibbonItem) {
            guard let b = button(item) else { check(false, "\(item.title) has a button on screen"); return }
            let p = CGPoint(x: 6, y: b.bounds.midY)
            func e(_ t: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: b.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            b.mouseDown(with: e(.leftMouseDown))
            b.mouseUp(with: e(.leftMouseUp))
        }
        func active() -> [Tool] { Tool.allCases.filter { r.item(for: $0)?.isActiveTool == true } }

        check(active() == [v.tool], "the tool in hand is lit in the ribbon (\(active().map(\.title)), tool \(v.tool.title))")
        press(r.item(for: .rect)!)
        check(v.tool == .rect && active() == [.rect], "clicking Rectangle picks it and lights only it")
        type("o")
        check(v.tool == .oval && active() == [.oval], "the O key lights Oval in the ribbon")
        press(r.item(for: .highlighter)!)
        check(v.tool == .highlighter, "Tools › Highlighter picks the highlighter")
        press(r.item(for: .crop)!)
        check(v.tool == .crop && active() == [.crop], "Tools › Crop starts cropping")
        key("esc")
        check(!r.areaSelect.isEnabled && !r.format.isEnabled, "Image Area Selection and Format are off until R6")

        // Clipboard on a drawn rectangle.
        press(r.item(for: .rect)!)
        drag(ed, CGPoint(x: 200, y: 200), CGPoint(x: 400, y: 320))
        check(v.doc.objects.count == 1 && v.selection.count == 1 && r.cut.isEnabled, "a new rectangle is selected and Cut turns on")
        check(r.undo.isEnabled && !r.redo.isEnabled, "after drawing, Undo is on and Redo off")
        press(r.copy)
        check(NSPasteboard.general.types?.contains(ShotView.objectPasteboardType) == true, "Copy puts the rectangle on the clipboard")
        ed.syncToolbar()
        check(r.paste.isEnabled, "Paste turns on with an object on the clipboard")
        press(r.paste)
        check(v.doc.objects.count == 2, "Paste adds a copy (\(v.doc.objects.count) objects)")
        press(r.cut)
        check(v.doc.objects.count == 1 && v.selection.isEmpty && !r.cut.isEnabled, "Cut removes the pasted copy and turns itself off")

        // Undo and Redo from the title bar.
        press(r.undo)
        check(v.doc.objects.count == 2 && r.redo.isEnabled, "Undo in the title bar brings the copy back; Redo turns on")
        press(r.redo)
        check(v.doc.objects.count == 1, "Redo cuts it again")
        press(r.copyImage)
        check(NSPasteboard.general.types?.contains(.png) == true || NSPasteboard.general.types?.contains(.tiff) == true,
              "Copy Full Image puts the picture on the clipboard")

        // A folded Shapes group keeps the tool in hand visible.
        press(r.item(for: .callout)!)
        r.view.frame.size.width = 300
        r.view.layout()
        if let shapes = r.groups.first(where: { $0.id == "shapes" }), let c = r.view.compactButton(for: shapes) {
            check(r.view.isCompact(shapes) && c.displayIcon == .callout, "with the ribbon narrow, folded Shapes shows Callout (\(c.displayIcon))")
        }
        win.layoutIfNeeded()
        await closeAllEditors()

        // Without the setting the editor is unchanged (unless SCREENSHOT_NEW_UI forces the new one for the whole run).
        d.removeObject(forKey: "newEditorUI")
        guard !Settings.newEditorUI else { return }
        guard let old = await openEditor(Self.sampleImage(600, 400)) else { return }
        let oldIds = old.window?.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
        check(old.debugEditorRibbon == nil && oldIds.contains("tools"), "with newEditorUI off the editor keeps its tool strip")
    }
}
#endif
