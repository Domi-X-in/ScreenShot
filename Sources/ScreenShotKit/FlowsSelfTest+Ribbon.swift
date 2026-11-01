import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// The editor: the trimmed title bar, and the ribbon's Clipboard, Shapes and Tools groups
    /// driving the editor with real clicks on their buttons.
    func ribbonEditorFlow() async {
        guard let ed = await openEditor(Self.sampleImage(1000, 700)), let win = ed.window else { check(false, "editor opens"); return }
        let v = ed.shotView
        guard let r = ed.debugEditorRibbon else { check(false, "the new editor has a ribbon"); return }

        // Title bar: a card with the window's buttons and the window's own commands; the system toolbar is empty.
        let ids = win.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
        check(ids.isEmpty, "the system toolbar holds nothing (\(ids))")
        guard let cards = ed.debugCards else { check(false, "the new editor is laid out in cards"); return }
        func frame(_ view: NSView) -> CGRect { view.convert(view.bounds, to: nil) }
        let titleFrame = frame(cards.title)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let b = win.standardWindowButton(kind) {
                check(titleFrame.contains(b.convert(b.bounds, to: nil)), "window button \(kind.rawValue) sits inside the title card (\(b.convert(b.bounds, to: nil)) in \(titleFrame))")
            }
        }
        check(allViews(RibbonButton.self, in: cards.title).map(\.item.id) == ["capture", "copyImage", "save", "pin", "undo", "redo"],
              "the title card has New Capture, Copy image, Save, Pin, Undo and Redo")
        check(cards.title.mouseDownCanMoveWindow, "dragging the title card moves the window")
        check(r.view.window === win && r.view.frame.height == DesignTokens.Metrics.ribbonHeight, "the ribbon sits in the window, 94 pt tall")
        // Cards: 10 pt from the window's edges and from each other, 12 pt corners.
        let content = win.contentView!.bounds
        let all: [NSView] = [cards.title, cards.ribbon, cards.canvas, cards.status, cards.recent]
        check(all.allSatisfy { $0.layer?.cornerRadius == DesignTokens.Radius.card }, "every card has the same 12 pt corners")
        check(abs(cards.ribbon.frame.minX - 10) < 0.5 && abs(content.maxX - cards.ribbon.frame.maxX - 10) < 0.5, "cards keep 10 pt from the sides")
        check(abs(cards.title.frame.minY - cards.ribbon.frame.maxY - 10) < 0.5, "10 pt between the title card and the ribbon")
        check(abs(cards.ribbon.frame.minY - cards.canvas.frame.maxY - 10) < 0.5, "10 pt between the ribbon and the canvas")
        check(abs(cards.canvas.frame.minY - cards.status.frame.maxY - 10) < 0.5 && abs(cards.status.frame.minY - cards.recent.frame.maxY - 10) < 0.5,
              "10 pt between canvas, status bar and recent strip")
        check(abs(cards.recent.frame.minY - 10) < 0.5, "10 pt under the recent strip")
        check(v.isDescendant(of: cards.canvas), "the canvas is inside its card")
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
        check(r.areaSelect.isEnabled && !r.format.isEnabled, "Image Area Selection is on; Format waits for a selected object")

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
    }
}
#endif

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// The side bar beside the canvas with callouts: the five designs, the current one lit, a click restyling the
    /// selected callout and the next one; the canvas takes the room back when it hides.
    func calloutBarFlow() async {
        Settings.returnToSelect = true
        guard let ed = await openEditor(Self.sampleImage(1000, 700)), let cards = ed.debugCards else {
            check(false, "the editor opens with its cards"); return
        }
        let bar = ed.debugOptionsBar, o = ed.shapeOptions
        let v = ed.shotView
        func design(_ c: CalloutStyle) -> RibbonItem { o.callouts[c.rawValue] }
        var current: CalloutStyle? { CalloutStyle.allCases.first { design($0).isOn } }
        type("v")
        ed.window?.layoutIfNeeded()
        check(bar.isHidden && abs(cards.canvas.frame.minX - 10) < 0.5, "with Select and nothing selected the bar hides and the canvas uses the room")
        let zoomBefore = v.zoomPercent
        let spot = v.convert(v.viewPoint(forImage: CGPoint(x: 500, y: 350)), to: nil)
        type("e")
        ed.window?.layoutIfNeeded()
        check(!bar.isHidden && abs(cards.canvas.frame.minX - bar.frame.maxX - 10) < 0.5 && abs(bar.frame.width - 44) < 0.5,
              "the Callout tool shows the 44 pt bar beside the canvas")
        let spotAfter = v.convert(v.viewPoint(forImage: CGPoint(x: 500, y: 350)), to: nil)
        check(v.zoomPercent == zoomBefore && abs(spot.x - spotAfter.x) < 1 && abs(spot.y - spotAfter.y) < 1,
              "the picture stays still as the bar comes in (zoom \(zoomBefore)% → \(v.zoomPercent)%, \(spot) → \(spotAfter))")
        check(bar.sections.map(\.id) == ["callout"] && bar.buttons.count == CalloutStyle.allCases.count, "all five callout designs (\(bar.buttons.count))")
        check(current == v.displayedStyle.callout, "the current design is lit")
        design(.thought).action?()
        check(v.style.callout == .thought && current == .thought, "picking Thought sets it for the next callout and lights it")
        drag(ed, CGPoint(x: 500, y: 300), CGPoint(x: 650, y: 180)); await sleep(0.15)
        type("Hi"); key("esc")
        guard let callout = v.doc.objects.last, callout.kind == .callout else { check(false, "a callout was drawn"); return }
        check(callout.calloutStyle == .thought, "the new callout is a thought bubble")
        check(!bar.isHidden && v.selection == [callout.id], "with the callout selected the bar stays")
        design(.shout).action?()
        check(v.doc.objects.last?.calloutStyle == .shout && current == .shout, "picking Shout restyles the selected callout")
        type("z", mods: .command)
        check(v.doc.objects.last?.calloutStyle == .thought, "⌘Z undoes it")
        key("esc"); type("h")
        ed.window?.layoutIfNeeded()
        check(bar.isHidden, "a tool without options (Highlighter) hides the bar again")
        check(v.fitsWindow && v.zoomPercent == zoomBefore, "and the picture fits the canvas again (\(v.zoomPercent)%)")
        type("e")
        check(bar.buttons.first?.toolTip == "Callout Design: \(CalloutStyle.box.title)", "each design has its name as a tooltip (\(bar.buttons.first?.toolTip ?? "-"))")
        type("v")
    }
}
#endif
