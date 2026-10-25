import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// Picks the item titled `title` (or starting with it) from a ribbon item's menu, as a click in the menu would.
    @discardableResult
    func chooseRibbon(_ item: RibbonItem, _ title: String, sub: String? = nil) -> Bool {
        guard let make = item.menu else { check(false, "\(item.title) has a menu"); return false }
        var menu = make()
        if let sub {
            guard let s = menu.items.first(where: { $0.title == sub })?.submenu else { check(false, "\(item.title) › \(sub) found"); return false }
            menu = s
        }
        guard let i = menu.items.firstIndex(where: { $0.title == title || $0.title.hasPrefix(title + " ") }) else {
            check(false, "\(item.title) menu has “\(title)” (\(menu.items.map(\.title)))")
            return false
        }
        menu.performActionForItem(at: i)
        return true
    }

    /// The new editor's Font, Paragraph, Color and Arrange groups and its contextual groups, used through their
    /// commands and menus (the old formatting bar's `formatting` and `toolbar` flows, for the ribbon).
    func ribbonFormattingFlow() async {
        let d = UserDefaults.standard
        d.set(true, forKey: "newEditorUI")
        defer { d.removeObject(forKey: "newEditorUI") }
        Settings.returnToSelect = true
        guard let ed = await openEditor(Self.sampleImage(1000, 700)), let r = ed.debugEditorRibbon else { check(false, "the new editor opens"); return }
        let v = ed.shotView, f = r.formatting, store = ed.formatting
        func editor() -> NSTextView? { ed.window?.firstResponder as? NSTextView }
        func shortcut(_ c: String, _ mods: NSEvent.ModifierFlags) {
            guard let win = ed.window, let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0,
                                                                windowNumber: win.windowNumber, context: nil, characters: c,
                                                                charactersIgnoringModifiers: c, isARepeat: false, keyCode: 0) else { return }
            _ = editor()?.performKeyEquivalent(with: e)
        }
        func pause() async {
            await sleep(0.05)
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: ed.window?.windowNumber ?? 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(e, atStart: false)
            }
            await sleep(0.05)
        }
        func shapes() -> ShotView.ShapeStyleState { v.shapeStyleState }

        check(ed.debugTopBarShown == false, "the new editor has no floating formatting bar")
        check(!f.bold.isEnabled && !f.family.isEnabled && !f.size.isEnabled && !f.hAlign.isEnabled, "with no text, Font and Paragraph are off")
        check(!f.strike.isEnabled && !f.bullets.isEnabled && !f.numbering.isEnabled && !f.changeCase.isEnabled && !f.fontOutline.isEnabled,
              "Strikethrough, Bullets, Numbering, Change Case and Font Outline wait for R6")

        // Font and Paragraph on a text being typed.
        type("t"); click(ed, CGPoint(x: 100, y: 500)); await sleep(0.15)
        type("Hello world")
        check(f.bold.isEnabled && !f.family.text.isEmpty && !f.size.text.isEmpty, "typing turns Font on and shows the font and size (\(f.family.text) \(f.size.text))")
        check(f.textGroup.isHidden == false && f.visibleContextualGroup === f.textGroup, "the Text options group shows for a text box")
        editor()?.selectAll(nil)
        await pause()
        r.view.layoutSubtreeIfNeeded()
        f.bold.action?(); await pause()
        check(store.state.bold && f.bold.isOn, "Bold applies and lights up")
        f.italic.action?(); await pause()
        check(store.state.italic && f.italic.isOn, "Italic too")
        if TextFormatting.families.contains("Georgia") {
            chooseRibbon(f.family, "Georgia"); await pause()
            check(store.state.family == "Georgia" && f.family.text == "Georgia", "the Font menu sets Georgia (\(store.state.family ?? "-"))")
        }
        chooseRibbon(f.size, "18"); await pause()
        check(store.state.size == 18 && f.size.text == "18", "the Size menu sets 18")
        f.grow.action?(); await pause()
        check(store.state.size == 20, "Increase Font Size steps 18 → 20 (\(store.state.size ?? 0))")
        f.shrink.action?(); await pause()
        check(store.state.size == 18, "Decrease Font Size steps back to 18")
        shortcut(">", [.command, .shift]); await pause()
        check(store.state.size == 20, "⌘⇧> still works with the ribbon (\(store.state.size ?? 0))")
        shortcut("[", .command); await pause()
        check(store.state.size == 19, "⌘[ takes one point off")
        chooseRibbon(f.hAlign, "Center"); await pause()
        check(store.state.alignment == .center, "Align Text › Center")
        check(f.orientation.isEnabled && !f.vAlign.isEnabled, "a text box can turn but has no vertical alignment")
        chooseRibbon(f.orientation, TextDirection.rotateUp.title); await pause()
        check(store.state.orientation == .rotate270, "Text Direction › Rotate Text Up")
        chooseRibbon(f.orientation, TextDirection.horizontal.title); await pause()
        f.fontPalette.pick(NSColor(hex: 0xAF52DE)); await pause()
        check(store.state.color?.hexString == "#AF52DE" && f.fontColor.barColor?.hexString == "#AF52DE", "Font Color colors the letters and its bar")
        key("esc"); key("esc")
        let text = v.doc.objects.last
        check(text?.kind == .text && text?.text == "Hello world", "the text is kept")

        // Color on a rectangle.
        type("r"); drag(ed, CGPoint(x: 200, y: 150), CGPoint(x: 400, y: 280))
        check(f.fill.isEnabled && f.outline.isEnabled, "a selected rectangle turns Color on")
        check(f.visibleContextualGroup === f.textGroup && f.editText.isEnabled, "a rectangle can hold text: the Text group offers Edit Text")
        check(ed.debugCalloutBar?.isHidden == true, "no callout style bar for a rectangle")
        f.fillPalette.pick(NSColor(hex: 0x34C759))
        check(shapes().fill?.hexString == "#34C759" && f.fill.barColor?.hexString == "#34C759", "Shape Fill fills it green and shows it in the bar")
        f.outlinePalette.pick(NSColor(hex: 0x007AFF))
        check(shapes().outline?.hexString == "#007AFF" && shapes().fill?.hexString == "#34C759", "Shape Outline recolors the outline and keeps the fill")
        chooseRibbon(f.outline, "8 px", sub: "Weight")
        check(v.doc.objects.last?.width == 8 && shapes().weight == 8, "Shape Outline › Weight › 8 px (the old stroke width)")
        chooseRibbon(f.outline, "Dashed", sub: "Dashes")
        check(shapes().dash == .dashed, "Shape Outline › Dashes › Dashed")
        chooseRibbon(f.fill, "Translucent", sub: "Transparency")
        check(shapes().opacity == .translucent, "Shape Fill › Transparency › Translucent")
        chooseRibbon(f.outline, "No Outline")
        check(shapes().noOutline && f.outline.barColor == nil, "No Outline hides it; the bar shows none")
        type("z", mods: .command)
        check(!shapes().noOutline, "⌘Z brings the outline back")

        // Arrange: a second rectangle, Align, Group, Rotate.
        key("esc")
        type("r"); drag(ed, CGPoint(x: 500, y: 200), CGPoint(x: 640, y: 300))
        type("a", mods: .command)
        check(f.arrange.isEnabled && f.align.isEnabled && f.rotate.isEnabled && f.flip.isEnabled, "with objects selected Arrange, Align, Rotate and Flip are on")
        chooseRibbon(f.align, ArrangeAction.alignTop.title)
        let rects = v.doc.objects.filter { $0.kind == .rect }
        check(rects.count == 2 && abs(rects[0].frame.minY - rects[1].frame.minY) < 0.5, "Align › Align Top lines up the tops")
        chooseRibbon(f.arrange, "Group")
        check(v.canUngroup, "Arrange › Group groups them")
        chooseRibbon(f.arrange, "Ungroup")
        check(!v.canUngroup, "Arrange › Ungroup")
        key("esc")
        if let rect = v.doc.objects.last(where: { $0.kind == .rect }) {
            click(ed, CGPoint(x: rect.frame.midX, y: rect.frame.minY + 1))
            let before = v.doc.objects.last { $0.id == rect.id }?.frame.size
            chooseRibbon(f.rotate, TransformAction.rotateRight.title)
            let after = v.doc.objects.last { $0.id == rect.id }?.frame.size
            check(before != nil && after != nil && abs(before!.width - after!.height) < 1, "Rotate › Rotate Right 90° turns it (\(before ?? .zero) → \(after ?? .zero))")
        }

        // Arrow heads and line style.
        key("esc")
        type("a"); drag(ed, CGPoint(x: 150, y: 600), CGPoint(x: 450, y: 560))
        check(f.arrowHeads.isEnabled, "Arrow Heads turns on for an arrow")
        chooseRibbon(f.arrowHeads, ArrowStyle.double.title)
        check(v.doc.objects.last?.arrowStyle == .double, "Arrow Heads › Double Arrow")
        let lineMenu = f.lineStyle.menu!()
        check(lineMenu.items.first { $0.title == DashStyle.dashed.title }?.isEnabled == false, "arrows can't be dashed: Line Style › Dashed is off")
        chooseRibbon(f.lineStyle, DashStyle.handDrawn.title)
        check(v.doc.objects.last?.sketch == true, "Line Style › Hand-Drawn")

        // Contextual groups follow the tool.
        key("esc")
        type("b")
        check(f.visibleContextualGroup === f.blurGroup, "the Blur tool shows its options")
        chooseRibbon(f.blurMode, BlurMode.blurText.title)
        check(v.style.blur == .blurText, "Blur › Mode › Blur Text is used for the next blur")
        chooseRibbon(f.blurMode, BlurMode.blur.title)
        type("c")
        check(f.visibleContextualGroup === f.counterGroup, "the Counter tool shows its options")
        chooseRibbon(f.counterShape, CounterShape.square.title)
        check(v.style.counterShape == .square, "Counter › Shape › Square")
        chooseRibbon(f.counterShape, CounterShape.circle.title)
        type("u")
        check(f.visibleContextualGroup === f.rulerGroup, "the Ruler shows its units")
        type("m")
        check(f.visibleContextualGroup === f.magnifierGroup, "the Magnifier shows lens and zoom")
        ed.pickTool(.crop)
        check(f.visibleContextualGroup === f.cropGroup, "Crop shows its mode, Autoadjust and Imprint Size")
        chooseRibbon(f.cropMode, "Cut Out")
        check(v.cutOutMode && !f.autoadjust.isEnabled, "Crop › Mode › Cut Out (Autoadjust is for Crop)")
        chooseRibbon(f.cropMode, "Crop")
        key("esc")
        type("v")
        check(f.visibleContextualGroup == nil, "with Select and nothing selected no options group shows")
    }
}
#endif
