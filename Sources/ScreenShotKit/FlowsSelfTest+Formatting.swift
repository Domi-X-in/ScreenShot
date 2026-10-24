import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// The Word-style formatting toolbar, used through its controls and Word's shortcuts.
    func formattingFlow() async {
        guard let ed = await openEditor(Self.sampleImage(1000, 700)) else { return }
        let v = ed.shotView
        let ui = ed.debugRibbon.debugControls
        let store = ed.formatting
        Settings.returnToSelect = true
        func editor() -> NSTextView? { ed.window?.firstResponder as? NSTextView }
        func shortcut(_ c: String, _ mods: NSEvent.ModifierFlags) {
            guard let win = ed.window, let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0,
                                                                windowNumber: win.windowNumber, context: nil, characters: c,
                                                                charactersIgnoringModifiers: c, isARepeat: false, keyCode: 0)
            else { return }
            _ = editor()?.performKeyEquivalent(with: e)
        }
        /// A person's actions are separate events; macOS groups undo by event, so give each its own turn.
        func pause() async {
            await sleep(0.05)
            // A real event through the app's event loop: AppKit closes the undo group of each event it handles.
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: ed.window?.windowNumber ?? 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(e, atStart: false)
            }
            await sleep(0.05)
        }
        func fontAt(_ i: Int) -> NSFont? { editor()?.textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont }

        check(!ui.styles.isEnabled && !ui.font.isEnabled && !ui.size.isEnabled && !ui.align.isEnabled, "with no text, the toolbar is greyed out")

        // Typing a text.
        type("t"); click(ed, CGPoint(x: 100, y: 500)); await sleep(0.15)
        type("Hello world")
        check(ui.styles.isEnabled && ui.size.isEnabled && store.state.isActive, "typing a text turns the toolbar on")
        check(!ui.size.stringValue.isEmpty && ui.font.titleOfSelectedItem != nil, "it shows the text's font and size (\(ui.font.titleOfSelectedItem ?? "-") \(ui.size.stringValue))")
        check(!ui.vertical.isEnabled && ui.direction.isEnabled, "vertical alignment is off for a text box (it fits its text); direction is on")

        // Bold from the toolbar on “world”.
        editor()?.setSelectedRange(NSRange(location: 6, length: 5))
        ed.debugRibbon.debugClickStyle(0)
        await pause()
        check(fontAt(6).map(TextFormatting.isBold) == true && fontAt(0).map(TextFormatting.isBold) == false, "Bold applies to the selected word only")
        check(ui.styles.isSelected(forSegment: 0), "Bold shows pressed for the bold word")
        await snapshot(ed, "ribbon-editing")
        check(editor() != nil && editor()?.selectedRange() == NSRange(location: 6, length: 5), "the text keeps the focus and its selection after the click")
        editor()?.setSelectedRange(NSRange(location: 2, length: 0))
        store.refresh()
        check(!ui.styles.isSelected(forSegment: 0), "moving the caret into “Hello” shows Bold off")
        editor()?.setSelectedRange(NSRange(location: 0, length: 11))
        store.refresh()
        check(!ui.styles.isSelected(forSegment: 0), "a half-bold selection shows Bold off (Word)")

        // ⌘I at a collapsed caret: the next letters are italic.
        editor()?.setSelectedRange(NSRange(location: 11, length: 0))
        shortcut("i", .command)
        await pause()
        check(ui.styles.isSelected(forSegment: 1), "⌘I at the caret shows Italic pressed (pending format)")
        await snapshot(ed, "ribbon-italic-pending")
        type("!")
        await pause()
        check(fontAt(11).map(TextFormatting.isItalic) == true && fontAt(5).map(TextFormatting.isItalic) == false, "the next letter typed is italic, the rest isn't")

        // Typing a size in the size box: it takes the focus for a moment, then gives it back.
        editor()?.selectAll(nil)
        ed.window?.makeFirstResponder(ui.size)
        await sleep(0.2)
        check(v.isEditingText, "focusing the size box keeps the text open")
        ui.size.stringValue = "13.5"
        _ = ui.size.target?.perform(ui.size.action, with: ui.size)
        await sleep(0.1)
        check(editor() != nil && editor()?.selectedRange().length == 12, "after the size, the focus and the selection are back in the text")
        check(store.state.size == 13.5 && ui.size.stringValue == "13.5", "a typed size 13.5 applies (\(store.state.size ?? 0))")
        await pause()
        ui.grow.performClick(nil)
        await pause()
        check(store.state.size == 14, "Grow Font steps 13.5 → 14 (\(store.state.size ?? 0))")
        shortcut(">", [.command, .shift])
        await pause()
        check(store.state.size == 16, "⌘⇧> steps 14 → 16")
        shortcut("[", .command)
        await pause()
        check(store.state.size == 15, "⌘[ takes one point off")

        // Font family from the menu.
        if let i = ui.font.itemTitles.firstIndex(of: "Georgia") {
            ui.font.selectItem(at: i)
            _ = ui.font.target?.perform(ui.font.action, with: ui.font)
            await pause()
            check(fontAt(0).map(TextFormatting.family(of:)) == "Georgia" && ui.font.titleOfSelectedItem == "Georgia", "the font menu sets Georgia")
        } else { check(false, "the font menu lists Georgia") }

        // Alignment: ⌘E centers; ⌘Z undoes just that.
        // A second line, typed at the end.
        editor()?.setSelectedRange(NSRange(location: (editor()?.string as NSString?)?.length ?? 0, length: 0))
        key("return"); await pause(); type("Second"); await pause()
        let full = editor()?.string
        editor()?.setSelectedRange(NSRange(location: 0, length: 0))
        shortcut("e", .command)
        await pause()
        check(ui.align.selectedSegment == 1, "⌘E centers the paragraph and the toolbar shows it")
        editor()?.setSelectedRange(NSRange(location: 14, length: 0))
        store.refresh()
        check(ui.align.selectedSegment == 0, "the second paragraph is still left-aligned")
        editor()?.setSelectedRange(NSRange(location: 0, length: 0))
        type("z", mods: .command)
        store.refresh()
        check(ui.align.selectedSegment == 0 && editor()?.string == full, "⌘Z undoes just the alignment (text intact)")

        // Finish: the text stays selected and the toolbar formats all of it.
        key("esc")
        guard let text = v.doc.objects.last, text.kind == .text else { check(false, "the text was kept"); return }
        check(store.state.isActive && store.target is SelectedTextTarget, "a selected text keeps the toolbar on")
        ed.debugRibbon.debugClickStyle(2)
        check(v.doc.objects.last?.runs?.allSatisfy { $0.underline == true } == true, "Underline on a selected text underlines all of it")
        type("z", mods: .command)
        check(v.doc.objects.last?.runs?.contains { $0.underline == true } != true, "⌘Z undoes it")

        // A rectangle with text: vertical alignment and direction.
        type("r"); drag(ed, CGPoint(x: 500, y: 150), CGPoint(x: 900, y: 450))
        key("return"); await sleep(0.1); type("Box")
        key("esc")
        guard let box = v.doc.objects.last, box.kind == .rect else { check(false, "rectangle made"); return }
        check(ui.vertical.isEnabled && ui.direction.isEnabled, "a shape's text can be aligned vertically and turned")
        ui.vertical.selectedSegment = 2
        _ = ui.vertical.target?.perform(ui.vertical.action, with: ui.vertical)
        ui.direction.selectItem(at: 1)
        _ = ui.direction.target?.perform(ui.direction.action, with: ui.direction)
        let b2 = v.doc.objects.first { $0.id == box.id }
        await snapshot(ed, "ribbon-shape")
        check(b2?.verticalAlign == .bottom && b2?.orientation == .rotate90,
              "Align Bottom and Rotate 90° apply to the shape (\(String(describing: b2?.verticalAlign)), \(String(describing: b2?.orientation)), target \(String(describing: store.target.map { Swift.type(of: $0) })), selection \(v.selection.count))")

        // A callout can't be turned.
        type("e"); drag(ed, CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 100)); await sleep(0.1); type("Note")
        check(!ui.direction.isEnabled && !ui.vertical.isEnabled, "callouts don't offer direction or vertical alignment")
        key("esc"); key("esc")
        check(!store.state.isActive && !ui.styles.isEnabled, "with nothing selected the toolbar is greyed out again")

        // Saved and reopened.
        type("s", mods: .command)
        await sleep(0.4)
        guard let url = v.doc.fileURL else { check(false, "saved"); return }
        type("w", mods: .command)
        await sleep(0.3)
        AppLogic.shared.openFile(url)
        await sleep(0.4)
        guard let re = editors.last?.shotView.doc else { check(false, "reopened"); return }
        let t = re.objects.first { $0.kind == .text }
        let runs = t?.runs ?? []
        check(t?.text == full && runs.contains { $0.family == "Georgia" && $0.bold == true } && runs.contains { $0.italic == true },
              "reopened: font, bold, italic and size are kept (\(runs.map { "\($0.family ?? "-") b\($0.bold ?? false) i\($0.italic ?? false) \($0.size)" }))")
        let r = re.objects.first { $0.kind == .rect }
        check(r?.verticalAlign == .bottom && r?.orientation == .rotate90, "reopened: the shape keeps Bottom and 90°")
    }
}
#endif
