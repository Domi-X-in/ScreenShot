import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// The top toolbar's Office-style controls on empty, single, multiple and mixed selections, the shared card, and the
    /// slimmed bottom bar.
    func toolbarFlow() async {
        guard let ed = await openEditor(Self.sampleImage(1000, 700)) else { return }
        let v = ed.shotView
        let bar = ed.debugTopBar
        let ui = bar.debugControls
        Settings.returnToSelect = true
        Settings.alignToCanvas = false
        func obj(_ id: UUID) -> Annotation? { v.doc.objects.first { $0.id == id } }
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        /// Picks an item as a click in the menu would (the menu is kept alive: an item only holds it weakly).
        func choose(_ menu: NSMenu?, _ title: String) {
            guard let menu, let i = menu.items.firstIndex(where: { $0.title == title }) else { check(false, "menu item “\(title)” found"); return }
            menu.performActionForItem(at: i)
        }
        func sub(_ items: [NSMenuItem], _ title: String) -> NSMenu? { items.first { $0.title == title }?.submenu }

        // Both bars are the same card; the bottom one keeps only the hint, info cells and Backdrop.
        check(Swift.type(of: ed.debugStatusBar).isSubclass(of: ToolbarShell.self) && Swift.type(of: bar).isSubclass(of: ToolbarShell.self),
              "the top toolbar and the status bar share ToolbarShell")
        let bottom = descendants(ed.debugStatusBar)
        check(!bottom.contains { $0 is NSSlider || $0 is NSSegmentedControl || $0 is ColorSplitButton || $0 is NSPopUpButton },
              "no shape-editing controls remain in the bottom bar")
        check(ed.debugStatusBar.layer?.cornerRadius == bar.layer?.cornerRadius && ed.debugStatusBar.layer?.borderWidth == bar.layer?.borderWidth,
              "same corners and hairline on both bars")
        check(Array(bar.debugSectionTitles.prefix(6)) == ["Text Workflows", "Font", "Paragraph", "Shape Styles", "Arrange", "Align"],
              "sections in order (\(bar.debugSectionTitles))")
        check(ui.toolSection.isHidden, "no tool section with the Select tool")

        // Empty selection: everything that needs a selection is off.
        type("v")
        check(!bar.fill.isEnabled && !bar.outline.isEnabled && !ed.debugRibbon.fontColor.isEnabled, "nothing selected: colors are greyed out (fill \(bar.fill.isEnabled), outline \(bar.outline.isEnabled), font \(ed.debugRibbon.fontColor.isEnabled), tool \(v.tool.title))")
        check(!ui.forward.isEnabled && !ui.backward.isEnabled && !ui.group.isEnabled && !ui.ungroup.isEnabled && !ui.rotate.isEnabled
              && !ui.align.isEnabled, "nothing selected: Arrange and Align are greyed out")

        // The Rectangle tool with nothing selected: Shape Fill sets the fill for the next rectangle (no undo step).
        type("r")
        check(bar.fill.isEnabled && bar.outline.isEnabled, "with the Rectangle tool, Fill and Outline set the next shape's style")
        let undoDepth = v.doc.undoStack.count
        bar.fill.pick(NSColor(hex: 0x34C759))
        check(v.style.fillColor?.hexString == "#34C759" && v.style.fill == .opaque && v.doc.undoStack.count == undoDepth,
              "Fill with nothing selected changes the new-shape style only")
        drag(ed, CGPoint(x: 100, y: 450), CGPoint(x: 300, y: 550))
        guard let a = v.doc.objects.last, a.kind == .rect else { check(false, "rectangle drawn"); return }
        check(a.fillColor?.hexString == "#34C759" && a.fill == .opaque && a.color.hexString != "#34C759",
              "the new rectangle is filled green with its own outline color (\(a.color.hexString))")
        check(v.selection == [a.id] && ui.forward.isEnabled && ui.rotate.isEnabled && ui.align.isEnabled && !ui.group.isEnabled,
              "one shape selected: Arrange and Align on, Group off (\(v.selection.count) selected)")

        // Single selection: Fill, Outline, No Outline, Weight, Dashes; each one undo step.
        bar.fill.pick(NSColor(hex: 0xFFCC00))
        check(obj(a.id)?.fillColor?.hexString == "#FFCC00", "Shape Fill recolors the fill")
        type("z", mods: .command)
        check(obj(a.id)?.fillColor?.hexString == "#34C759", "⌘Z undoes the fill")
        type("z", mods: [.command, .shift])
        let outlineBefore = obj(a.id)?.color
        bar.outline.pick(NSColor(hex: 0x007AFF))
        check(obj(a.id)?.color.hexString == "#007AFF" && obj(a.id)?.fillColor?.hexString == "#FFCC00",
              "Shape Outline recolors the outline and keeps the fill (\(outlineBefore?.hexString ?? "-") → \(obj(a.id)?.color.hexString ?? "-"))")
        bar.outline.onColor?(nil)
        check(obj(a.id)?.noOutline == true, "No Outline hides the outline")
        choose(sub(bar.debugOutlineItems, "Weight"), "8 px")
        check(obj(a.id)?.width == 8 && obj(a.id)?.noOutline == false, "Weight 8 sets the outline width and shows it again")
        choose(sub(bar.debugOutlineItems, "Dashes"), "Dashed")
        check(obj(a.id)?.dashed == true && obj(a.id)?.sketch == false, "Dashes › Dashed")
        let outlineNow = bar.debugOutlineItems
        let weightMenu = sub(outlineNow, "Weight")
        check(weightMenu?.items.first { $0.state == .on }?.title == "8 px", "the Weight menu checks the current weight")
        bar.fill.onColor?(nil)
        check(obj(a.id)?.fill == FillStyle.none, "No Fill removes the fill")
        choose(sub(bar.debugFillItems, "Transparency"), "Translucent")
        check(obj(a.id)?.fill == .translucent, "Transparency › Translucent fills it again, see-through")

        // The palette: theme grid with tints and shades, standard colors, No Fill, More Colors….
        let palette = bar.fill.paletteMenu()
        let grids = palette.items.compactMap { $0.view as? ColorGridView }
        check(grids.first?.debugColors.count == 6 && grids.first?.debugColors.allSatisfy { $0.count == 10 } == true,
              "theme colors: 10 colors, each with 5 tints and shades")
        check(grids.count >= 2 && grids[1].debugColors == [OfficeColors.standard], "a row of standard colors")
        check(palette.items.contains { $0.title == "No Fill" } && palette.items.contains { $0.title == "More Colors…" },
              "No Fill and More Colors… are in the Fill menu")
        let outlineMenuTitles = bar.outline.paletteMenu().items.map(\.title)
        check(outlineMenuTitles.contains("No Outline") && outlineMenuTitles.contains("Weight") && outlineMenuTitles.contains("Dashes"),
              "the Outline menu has No Outline, Weight and Dashes")
        check(!ed.debugRibbon.fontColor.paletteMenu().items.contains { $0.title == "No Fill" || $0.title == "No Outline" },
              "Font Color has no “No …” item")
        check(bar.fill.lastColor.hexString == "#FFCC00" && bar.outline.lastColor.hexString == "#007AFF",
              "each control remembers its own last color (fill \(bar.fill.lastColor.hexString), outline \(bar.outline.lastColor.hexString))")
        bar.fill.split.onPrimary?()
        check(obj(a.id)?.fillColor?.hexString == "#FFCC00", "clicking the Fill icon applies its last color")
        bar.fill.debugPickCustomColor(NSColor(hex: 0x123456))
        check(OfficeColors.recent.first?.hexString == "#123456" && obj(a.id)?.fillColor?.hexString == "#123456",
              "More Colors… applies the color and adds it to Recent Colors")
        check(bar.fill.paletteMenu().items.contains { $0.title == "Recent Colors" }, "the palette shows Recent Colors")

        // A second object: an arrow. Multi-selection with mixed values.
        type("a")
        var s = v.style
        s.color = NSColor(hex: 0xFF3B30)
        v.setStyle(s)
        drag(ed, CGPoint(x: 400, y: 600), CGPoint(x: 600, y: 650))
        guard let b = v.doc.objects.last, b.kind == .arrow else { check(false, "arrow drawn"); return }
        type("a", mods: .command)
        let st = v.shapeStyleState
        check(st.outlineMixed && st.outline == nil, "two different outline colors show as mixed")
        check(st.fillEnabled && st.weightEnabled, "Fill stays on for a selection with a shape in it")
        bar.outline.pick(NSColor(hex: 0xAF52DE))
        check(obj(a.id)?.color.hexString == "#AF52DE" && obj(b.id)?.color.hexString == "#AF52DE", "Outline applies to every selected object")
        check(!v.shapeStyleState.outlineMixed, "then it isn't mixed anymore")
        bar.fill.pick(NSColor(hex: 0xFF9500))
        check(obj(b.id)?.color.hexString == "#AF52DE" && obj(a.id)?.fillColor?.hexString == "#FF9500", "Fill skips the arrow (it has no fill)")
        type("z", mods: .command)
        check(obj(a.id)?.fillColor?.hexString == "#123456", "one ⌘Z undoes the whole multi-selection change")

        // Group, select as one, move, ungroup.
        check(ui.group.isEnabled && !ui.ungroup.isEnabled, "two objects: Group on, Ungroup off")
        ui.group.performClick(nil)
        let gid = obj(a.id)?.groupID
        check(gid != nil && obj(b.id)?.groupID == gid, "Group puts both in one group")
        check(!ui.group.isEnabled && ui.ungroup.isEnabled, "a group selected: Ungroup on")
        click(ed, CGPoint(x: 800, y: 300)) // empty spot
        check(v.selection.isEmpty, "clicking outside deselects")
        let aBox = obj(a.id)!.rect
        click(ed, CGPoint(x: aBox.minX + 2, y: aBox.midY))
        check(v.selection == [a.id, b.id], "clicking one member selects the whole group")
        let bStart = obj(b.id)!.p1
        drag(ed, CGPoint(x: aBox.minX + 2, y: aBox.midY), CGPoint(x: aBox.minX + 42, y: aBox.midY + 10))
        check(abs(obj(b.id)!.p1.x - bStart.x - 40) < 1, "dragging a member moves the group")
        type("d", mods: .command)
        let copies = v.doc.objects.filter { v.selection.contains($0.id) }
        check(copies.count == 2 && copies.allSatisfy { $0.groupID != nil && $0.groupID != gid }, "a duplicated group is a new group of its own")
        type("z", mods: .command)
        click(ed, CGPoint(x: obj(a.id)!.rect.minX + 2, y: obj(a.id)!.rect.midY))
        ui.ungroup.performClick(nil)
        check(obj(a.id)?.groupID == nil && obj(b.id)?.groupID == nil, "Ungroup")

        // Rotate and flip.
        v.setSelection([a.id], primary: a.id)
        let r0 = obj(a.id)!.rect
        choose(bar.debugRotateMenu, "Rotate Right 90°")
        let r1 = obj(a.id)!.rect
        check(abs(r1.width - r0.height) < 0.5 && abs(r1.height - r0.width) < 0.5 && abs(r1.midX - r0.midX) < 0.5 && abs(r1.midY - r0.midY) < 0.5,
              "Rotate Right 90° turns the rectangle in place (\(r0.size) → \(r1.size))")
        v.setSelection([b.id], primary: b.id)
        let arrow0 = obj(b.id)!
        v.transform(.flipHorizontal)
        let arrow1 = obj(b.id)!
        check(abs(arrow1.p1.x - arrow0.p2.x) < 0.5 && abs(arrow1.p2.x - arrow0.p1.x) < 0.5 && arrow1.p1.y == arrow0.p1.y,
              "Flip Horizontal mirrors the arrow")
        check(bar.debugRotateMenu.items.map(\.title).filter { !$0.isEmpty } == TransformAction.allCases.map(\.title),
              "Rotate menu: Rotate Right 90°, Rotate Left 90°, Flip Vertical, Flip Horizontal")

        // Align and distribute, to the selection and to the canvas.
        type("r")
        drag(ed, CGPoint(x: 650, y: 420), CGPoint(x: 700, y: 470))
        let c = v.doc.objects.last!
        type("a", mods: .command)
        let alignTitles = bar.debugAlignMenu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        check(alignTitles == ["Align Left", "Align Center", "Align Right", "-", "Align Top", "Align Middle", "Align Bottom", "-",
                              "Distribute Horizontally", "Distribute Vertically", "-", "Align to Selection", "Align to Canvas"],
              "the Align menu is laid out like Office's (\(alignTitles))")
        let distribute = bar.debugAlignMenu.items.first { $0.title == "Distribute Horizontally" }
        check(distribute.map { v.validateMenuItem($0) } == true, "three objects: Distribute is on")
        let leftmost = [a, b, c].map { obj($0.id)!.frame.minX }.min()!
        v.arrange(.alignLeft)
        check([a, b, c].allSatisfy { abs(obj($0.id)!.frame.minX - leftmost) < 0.5 }, "Align Left to the selection lines them up on the leftmost")
        choose(bar.debugAlignMenu, "Align to Canvas")
        check(Settings.alignToCanvas && bar.debugAlignMenu.items.first { $0.title == "Align to Canvas" }?.state == .on, "Align to Canvas is checked")
        v.arrange(.alignRight)
        check([a, b, c].allSatisfy { abs(obj($0.id)!.frame.maxX - v.doc.imageRect.maxX) < 0.5 }, "Align Right to the canvas")
        Settings.alignToCanvas = false
        v.setSelection([a.id, b.id], primary: a.id)
        check(distribute.map { v.validateMenuItem($0) } == false, "two objects: Distribute is off")

        // Order: Bring Forward / Send Backward split buttons.
        v.setSelection([a.id], primary: a.id)
        let before = v.doc.objects.firstIndex { $0.id == a.id }!
        ui.forward.onPrimary?()
        check(v.doc.objects.firstIndex { $0.id == a.id } == before + 1, "Bring Forward moves it up one step")
        let front = ui.forward.menuProvider?().items.first
        check(front?.title == "Bring to Front", "Bring Forward's menu holds Bring to Front")
        ui.backward.onPrimary?()
        check(v.doc.objects.firstIndex { $0.id == a.id } == before, "Send Backward moves it back")
        check(ui.backward.menuProvider?().items.first?.title == "Send to Back", "Send Backward's menu holds Send to Back")

        // Text in a mixed selection: Font Color and Bold apply to every text; shapes without text are left alone.
        type("t"); click(ed, CGPoint(x: 120, y: 120)); await sleep(0.1); type("Title"); key("esc"); key("esc")
        let text = v.doc.objects.last!
        type("o"); drag(ed, CGPoint(x: 700, y: 100), CGPoint(x: 900, y: 200))
        key("return"); await sleep(0.1); type("Note"); key("esc")
        let oval = v.doc.objects.last!
        v.setSelection([text.id, oval.id, b.id], primary: text.id)
        ed.syncToolbar()
        check(ed.debugRibbon.fontColor.isEnabled && ed.formatting.target is MultiSelectedTextTarget,
              "texts in a multi-selection: Font Color and the Font section work on all of them")
        ed.debugRibbon.fontColor.pick(NSColor(hex: 0x007AFF))
        func firstColor(_ id: UUID) -> String? { (obj(id)?.attributedText().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.hexString }
        check(firstColor(text.id) == "#007AFF" && firstColor(oval.id) == "#007AFF", "Font Color colors both texts (\(firstColor(text.id) ?? "-"), \(firstColor(oval.id) ?? "-"))")
        check(obj(b.id)?.color.hexString == "#AF52DE", "and leaves the arrow alone")
        check(ed.formatting.state.color?.hexString == "#007AFF", "the store shows the shared color")
        ed.formatting.applyFormat(.bold)
        check(ed.formatting.state.bold, "Bold on a multi-selection bolds every text")
        type("z", mods: .command)
        check(!ed.formatting.state.bold, "one ⌘Z undoes it")

        // Text Direction: Word's menu, icons, the active option checked; the active one again goes back to horizontal.
        v.setSelection([oval.id], primary: oval.id)
        ed.syncToolbar()
        let dir = ed.debugRibbon.debugDirectionMenu
        let dirTitles = dir.items.filter { !$0.isSeparatorItem }.map(\.title)
        check(dirTitles == ["Angle Counterclockwise", "Angle Clockwise", "Vertical Text", "Rotate Text Up", "Rotate Text Down", "Horizontal"],
              "Text Direction lists Word's options (\(dirTitles))")
        check(dir.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil }, "each option has its icon")
        check(dir.items.first { $0.title == "Horizontal" }?.state == .on, "Horizontal is checked for straight text")
        check(dir.items.first { $0.title == "Angle Clockwise" }?.isEnabled == false, "angled text isn't offered (no angled orientation yet)")
        ed.debugRibbon.debugPickDirection(.rotateUp)
        check(obj(oval.id)?.orientation == .rotate270, "Rotate Text Up turns the text 270°")
        check(ed.debugRibbon.debugDirectionMenu.items.first { $0.title == "Rotate Text Up" }?.state == .on, "and is checked next time")
        ed.debugRibbon.debugPickDirection(.rotateUp)
        check(obj(oval.id)?.orientation == .horizontal, "picking it again goes back to horizontal")
        ed.debugRibbon.debugPickDirection(.vertical)
        check(obj(oval.id)?.orientation == .stacked, "Vertical Text stacks the letters")
        await snapshot(ed, "toolbar-shape")
        if let doc = bar.debugScroll.documentView {
            let clip = bar.debugScroll.contentView
            clip.scroll(to: CGPoint(x: max(0, doc.frame.width - clip.bounds.width), y: 0))
            bar.debugScroll.reflectScrolledClipView(clip)
            await snapshot(ed, "toolbar-end")
            clip.scroll(to: .zero)
            bar.debugScroll.reflectScrolledClipView(clip)
        }

        // Narrow window: the toolbar stays one line and scrolls.
        ed.window?.setContentSize(NSSize(width: 800, height: 600))
        ed.window?.layoutIfNeeded()
        let scroll = bar.debugScroll
        check((scroll.documentView?.frame.width ?? 0) > scroll.contentView.bounds.width && bar.frame.maxX <= (ed.window?.contentView?.bounds.width ?? 0) - 11,
              "a narrow window: the toolbar scrolls sideways inside its card (\(Int(scroll.documentView?.frame.width ?? 0)) in \(Int(scroll.contentView.bounds.width)))")
        check(bar.frame.height == EditorToolbar.height, "and stays one line high")
        await snapshot(ed, "toolbar-narrow")

        // A tool with options of its own shows them in a last section.
        type("x")
        ed.syncToolbar()
        check(!ui.toolSection.isHidden, "the Crop tool adds its own section")
        type("v")
    }
}
#endif
