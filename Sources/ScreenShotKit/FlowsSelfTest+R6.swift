import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// R6's new commands in the new editor, used through the ribbon: Strikethrough, a typed Font Size that keeps the
    /// text open, Change Case, Justify, Bullets, Numbering, Font Outline, Copy Format and Image Area Selection.
    func ribbonR6Flow() async {
        Settings.returnToSelect = true
        guard let ed = await openEditor(Self.sampleImage(1000, 700)), let r = ed.debugEditorRibbon else { check(false, "the new editor opens"); return }
        let v = ed.shotView, f = r.formatting, store = ed.formatting
        func editor() -> NSTextView? { ed.window?.firstResponder as? NSTextView }
        func pause() async { await sleep(0.1) }
        func button(_ item: RibbonItem) -> RibbonButton? {
            allViews(RibbonButton.self, in: ed.window?.contentView).first { $0.item === item && !$0.isHiddenOrHasHiddenAncestor }
        }

        // A text with two lines.
        type("t"); click(ed, CGPoint(x: 120, y: 520)); await sleep(0.15)
        type("first line"); key("return"); type("second line")
        editor()?.selectAll(nil); await pause()
        check(f.strike.isEnabled && f.bullets.isEnabled && f.changeCase.isEnabled && f.fontOutline.isEnabled, "the new commands turn on for a text")

        f.strike.action?(); await pause()
        check(store.state.strikethrough && f.strike.isOn, "Strikethrough applies and lights up")
        f.strike.action?(); await pause()

        // Typed Font Size: the text stays open and gets 13.5.
        r.view.layoutSubtreeIfNeeded()
        if let sizeField = button(f.size) {
            sizeField.beginTextEntry()
            check(sizeField.entry != nil && v.isEditingText, "clicking the size opens an editor and the text stays open")
            check(ed.isFormattingControl(ed.window!.firstResponder!), "the size editor counts as a formatting control")
            sizeField.debugType("13,5"); await pause()
            check(store.state.size == 13.5 && f.size.text == "13.5", "a typed 13,5 applies 13.5 (\(store.state.size ?? 0))")
            check(v.isEditingText && editor() != nil && (editor()?.selectedRange().length ?? 0) > 0, "focus and the selection are back in the text (first responder \(String(describing: ed.window?.firstResponder.map { Swift.type(of: $0) })), editing \(v.isEditingText))")
        } else { check(false, "the Font Size field is on screen (Font may be folded)") }

        chooseRibbon(f.changeCase, TextCase.upper.title); await pause()
        check(editor()?.string == "FIRST LINE\nSECOND LINE", "Change Case › UPPERCASE (\(editor()?.string ?? "-"))")
        chooseRibbon(f.changeCase, TextCase.sentence.title); await pause()
        check(editor()?.string == "First line\nSecond line", "Change Case › Sentence case.")
        chooseRibbon(f.hAlign, "Justify"); await pause()
        check(store.state.alignment == .justified && f.hAlign.icon == .justify, "Align Text › Justify, and the button shows it")
        f.bullets.action?(); await pause()
        check(editor()?.string == "• First line\n• Second line" && f.bullets.isOn, "Bullets put a bullet on both lines")
        f.numbering.action?(); await pause()
        check(editor()?.string == "1. First line\n2. Second line" && f.numbering.isOn && !f.bullets.isOn, "Numbering replaces them with 1. 2.")
        f.numbering.action?(); await pause()
        check(editor()?.string == "First line\nSecond line", "Numbering again takes the numbers off")
        f.fontOutlinePalette.pick(NSColor(hex: 0xFF5500)); await pause()
        check(store.state.outline?.hexString == "#FF5500" && f.fontOutline.barColor?.hexString == "#FF5500", "Font Outline outlines the letters")
        key("esc"); key("esc")
        let text = v.doc.objects.last
        check(text?.runs?.contains { $0.outline != nil } == true && text?.paragraphAligns?.first == .justified,
              "outline and justification are kept with the text")

        // Copy Format: a blue dashed rectangle's look onto a second rectangle.
        var s = v.style
        s.color = NSColor(hex: 0x007AFF); s.width = 8; s.dashed = true; v.setStyle(s)
        type("r"); drag(ed, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200)); key("esc")
        s.color = NSColor(hex: 0xFF3B30); s.width = 3; s.dashed = false; v.setStyle(s)
        type("r"); drag(ed, CGPoint(x: 500, y: 100), CGPoint(x: 700, y: 200)); key("esc")
        let rects = v.doc.objects.filter { $0.kind == .rect }
        guard rects.count == 2 else { check(false, "two rectangles"); return }
        click(ed, CGPoint(x: 200, y: 100))
        check(r.format.isEnabled, "with one object selected Format turns on")
        r.format.action?()
        check(v.formatPainter != nil && r.format.isOn, "Format picks up the look and stays lit")
        click(ed, CGPoint(x: 600, y: 100))
        let target = v.doc.objects.first { $0.id == rects[1].id }
        check(target?.color.hexString == "#007AFF" && target?.width == 8 && target?.dashed == true && v.formatPainter == nil,
              "a click gives the second rectangle the blue dashed 8 px look, then Format turns off")
        type("z", mods: .command)
        check(v.doc.objects.first { $0.id == rects[1].id }?.color.hexString == "#FF3B30", "⌘Z undoes it")
        click(ed, CGPoint(x: 200, y: 100)); r.format.action?(); key("esc")
        check(v.formatPainter == nil, "Esc stops Format")

        // Image Area Selection.
        key("esc")
        r.areaSelect.action?()
        check(v.tool == .crop && v.selectingArea && r.areaSelect.isActiveTool && r.item(for: .crop)?.isActiveTool == false,
              "Image Area Selection lights its own button, not Crop")
        let o = ed.shapeOptions
        check(ed.debugOptionsBar.sections.map(\.id) == ["area"] && !o.copyArea.isEnabled, "the side bar shows the Selection commands, off until an area is drawn")
        drag(ed, CGPoint(x: 80, y: 400), CGPoint(x: 480, y: 480))
        check(o.copyArea.isEnabled && o.blurArea.isEnabled, "an area turns the Selection commands on")
        NSPasteboard.general.clearContents()
        o.copyArea.action?()
        check(NSPasteboard.general.types?.contains(.png) == true || NSPasteboard.general.types?.contains(.tiff) == true, "Copy Area puts the area on the clipboard")
        let size = v.doc.image.width
        key("return")
        check(v.doc.image.width == size, "Enter copies; it doesn't crop")
        let count = v.doc.objects.count
        o.blurArea.action?()
        check(v.doc.objects.count == count + 1 && v.doc.objects.last?.kind == .blur, "Blur Area covers it with a blur")
        drag(ed, CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 600))
        o.cropArea.action?()
        check(abs(v.doc.image.width - 800) <= 1, "Crop to Area crops the screenshot (\(v.doc.image.width))")
        ed.pickTool(.crop)
        check(!v.selectingArea && r.item(for: .crop)?.isActiveTool == true, "picking Crop goes back to cropping")
    }
}
#endif
