import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// R10: the side bar holds each shape's own options. Counter shapes and sizes (S M L XL, pinch or scroll), what
    /// several selected objects share, right-click defaults, and the Font group setting the next text before typing.
    func sideBarFlow() async {
        let d = UserDefaults.standard
        let savedDefaults = d.dictionary(forKey: ToolStyle.defaultsKey)
        defer {
            if let savedDefaults { d.set(savedDefaults, forKey: ToolStyle.defaultsKey) } else { d.removeObject(forKey: ToolStyle.defaultsKey) }
        }
        Settings.returnToSelect = true
        guard let ed = await openEditor(Self.sampleImage(1000, 700)) else { check(false, "the editor opens"); return }
        let v = ed.shotView, o = ed.shapeOptions, bar = ed.debugOptionsBar
        func ids() -> [String] { bar.sections.map(\.id) }
        func lit(_ items: [RibbonItem]) -> [String] { items.filter(\.isOn).map(\.title) }

        // Counter: shape and size.
        type("c")
        check(ids() == ["counterShape", "counterSize"] && !bar.isHidden, "the Counter tool shows shapes and sizes (\(ids()))")
        check(lit(o.counterSizes) == ["Size: Medium"], "Medium is lit for the default width (\(lit(o.counterSizes)))")
        click(ed, CGPoint(x: 300, y: 350))
        guard let counter = v.doc.objects.last, counter.kind == .counter else { check(false, "a counter was placed"); return }
        type("v"); click(ed, CGPoint(x: 300, y: 350))
        check(v.selection == [counter.id], "clicking the counter selects it")
        let small = counter.counterRadius
        o.counterSizes[3].action?()
        check(v.doc.objects.last?.width == 9 && lit(o.counterSizes) == ["Size: Extra Large"], "Extra Large makes the selected counter bigger")
        check((v.doc.objects.last?.counterRadius ?? 0) > small, "its radius grows (\(small) → \(v.doc.objects.last?.counterRadius ?? 0))")
        type("z", mods: .command)
        check(v.doc.objects.last?.width == counter.width, "⌘Z puts the size back")
        check(v.debugResizeCounter(by: 1.5) && v.doc.objects.last?.width == 6 && lit(o.counterSizes) == ["Size: Large"],
              "a pinch or scroll over it resizes it (\(v.doc.objects.last?.width ?? 0))")
        o.counterShapes[CounterShape.square.rawValue].action?()
        check(v.doc.objects.last?.shape == .square, "Square restyles the selected counter")

        // Right-click a choice: Set as Default, and it is picked too.
        let menu = o.counterSizes[2].contextMenu?()
        check(menu?.items.first?.title == "Set “Size: Large” as Default", "right-click offers Set as Default (\(menu?.items.first?.title ?? "-"))")
        menu?.performActionForItem(at: 0)
        check(ToolStyle.loadDefaults().width == 6, "the default width is now Large's")
        key("esc")

        // Several objects: only what they share.
        await closeAllEditors()
        guard let ed2 = await openEditor(Self.sampleImage(1000, 700)) else { return }
        let v2 = ed2.shotView, o2 = ed2.shapeOptions, bar2 = ed2.debugOptionsBar
        type("a"); drag(ed2, CGPoint(x: 100, y: 500), CGPoint(x: 300, y: 450))
        type("l"); drag(ed2, CGPoint(x: 100, y: 300), CGPoint(x: 400, y: 300))
        type("v"); type("a", mods: .command)
        check(v2.selection.count == 2 && bar2.sections.map(\.id) == ["dash", "weight"],
              "an arrow and a line together show Line Style and Weight (\(bar2.sections.map(\.id)))")
        check(bar2.sections.first?.items.contains { $0 === o2.dashes[.dashed] } == false, "with only the line styles both take (no Dashed for arrows)")
        o2.dashes[.handDrawn]?.action?()
        check(v2.doc.objects.allSatisfy(\.sketch), "Hand-Drawn applies to both")
        key("esc")
        type("h")
        check(bar2.isHidden, "the Highlighter has no side bar")
        await closeAllEditors()

        // The Font group sets the next text before typing.
        guard let ed3 = await openEditor(Self.sampleImage(1000, 700)), let f3 = ed3.debugEditorRibbon?.formatting else { return }
        let v3 = ed3.shotView
        type("t")
        check(ed3.formatting.target is NextTextTarget && f3.family.isEnabled && f3.bold.isEnabled, "with the Text tool in hand the Font group is on")
        chooseRibbon(f3.family, "Georgia")
        f3.bold.action?()
        check(f3.family.text == "Georgia" && f3.bold.isOn, "it shows the picked font and Bold")
        click(ed3, CGPoint(x: 200, y: 500)); await sleep(0.15)
        type("Hello"); key("esc")
        let run = v3.doc.objects.last?.runs?.first
        check(v3.doc.objects.last?.kind == .text && run?.family == "Georgia" && run?.bold == true,
              "the new text is typed in Georgia Bold (\(run?.family ?? "-"), bold \(run?.bold ?? false))")
        key("esc")
        type("t")
        chooseRibbon(f3.family, "Set “Georgia” as Default Font")
        check(ToolStyle.loadDefaults().family == "Georgia", "Font › Set as Default Font saves it")
        await closeAllEditors()
        guard let ed4 = await openEditor(Self.sampleImage(600, 400)) else { return }
        type("t")
        check(ed4.shotView.style.family == "Georgia" && ed4.debugEditorRibbon?.formatting.family.text == "Georgia",
              "a new editor's next text starts in the default font")
        type("v")
    }
}
#endif
