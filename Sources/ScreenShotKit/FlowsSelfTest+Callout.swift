import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// The callout and text editing cases reported from real use: new lines, custom color, deleting all the text,
    /// and finishing with a click outside.
    func calloutEditingFlow() async {
        guard let ed = await openEditor(Self.sampleImage(1000, 700)) else { return }
        let v = ed.shotView
        Settings.returnToSelect = true
        var cs = v.style
        cs.callout = .box
        cs.color = NSColor(hex: 0x007AFF)
        v.setStyle(cs)

        // 1 · Return adds a second line.
        type("e")
        drag(ed, CGPoint(x: 200, y: 300), CGPoint(x: 400, y: 150))
        await sleep(0.15)
        type("Line one")
        key("return")
        type("Line two")
        check(typed(ed) == "Line one\nLine two", "Return starts a second line in a callout (got \(typed(ed)?.debugDescription ?? "nil"))")
        let oneLine = Annotation(kind: .callout, p1: .zero, p2: .zero, style: cs).fontSize
        click(ed, CGPoint(x: 800, y: 600)) // outside
        guard let c1 = v.doc.objects.last, c1.kind == .callout else { check(false, "the callout was kept"); return }
        check(c1.text == "Line one\nLine two", "both lines are kept (\(c1.text.debugDescription))")
        check(c1.calloutShape().body.boundingBox.height > oneLine * 2.2, "the bubble grows to fit two lines")

        // 4 · Clicking outside finished it, made no new callout, and switched to Select.
        check(v.doc.objects.filter { $0.kind == .callout }.count == 1, "clicking outside doesn't start another callout")
        check(v.tool == .select, "clicking outside switches to Select (tool is \(v.tool.title))")

        // 2 · Custom color while typing in a callout (the color panel sends changeColor: to the text too).
        type("e")
        drag(ed, CGPoint(x: 600, y: 300), CGPoint(x: 750, y: 150))
        await sleep(0.15)
        type("Purple")
        let panel = NSColorPanel.shared
        ed.debugOptions.debugOpenCustomColor()
        check(panel.isVisible && panel.screen == ed.window?.screen && ed.window.map { panel.frame.intersects($0.frame.insetBy(dx: -400, dy: -400)) } == true,
              "Custom color opens the color panel next to the editor, on its screen")
        ed.debugOptions.debugPickCustomColor(NSColor(hex: 0x8E44AD))
        // AppKit also sends changeColor: to the text being edited.
        _ = ed.window?.firstResponder?.tryToPerform(#selector(NSTextView.changeColor(_:)), with: panel)
        key("esc") // Esc finishes typing
        let c2 = v.doc.objects.last
        check(c2?.color.hexString == "#8E44AD", "a custom color colors the bubble (\(c2?.color.hexString ?? "nil"))")
        let textColor = c2?.attributedText().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        check(textColor?.hexString == NSColor(hex: 0x8E44AD).contrasting.hexString, "and the text stays readable on it (\(textColor?.hexString ?? "nil"))")
        check(v.tool == .select, "Esc also finishes and switches to Select")

        // Custom color on a selected callout (not typing).
        if let c2 { click(ed, CGPoint(x: c2.calloutShape().body.boundingBox.midX, y: c2.calloutShape().body.boundingBox.midY)) }
        ed.debugOptions.debugOpenCustomColor()
        ed.debugOptions.debugPickCustomColor(NSColor(hex: 0x16A085))
        check(v.doc.objects.last?.color.hexString == "#16A085", "a custom color recolors a selected callout")
        panel.orderOut(nil)

        // 3 · A white callout: edit it, ⌘A, Delete, type again; the bubble stays white.
        var white = v.style
        white.color = NSColor.white
        white.callout = .box
        type("e")
        v.setStyle(white)
        drag(ed, CGPoint(x: 200, y: 600), CGPoint(x: 400, y: 500))
        await sleep(0.15)
        type("Old text")
        click(ed, CGPoint(x: 900, y: 100))
        guard let w = v.doc.objects.last, w.kind == .callout else { check(false, "white callout made"); return }
        let body = w.calloutShape().body.boundingBox
        type("v")
        click(ed, CGPoint(x: body.midX, y: body.midY), clicks: 2) // double-click edits it
        await sleep(0.15)
        check(typed(ed) == "Old text", "double-clicking the callout edits its text")
        type("a", mods: .command)
        key("delete")
        check(typed(ed) == "", "⌘A then Delete empties it")
        type("New")
        click(ed, CGPoint(x: 900, y: 100))
        let w2 = v.doc.objects.first { $0.id == w.id }
        check(w2?.text == "New" && w2?.color.hexString == "#FFFFFF", "after retyping, the bubble is still white (\(w2?.color.hexString ?? "gone"))")
        let t2 = w2?.attributedText().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        check(t2?.hexString == NSColor.white.contrasting.hexString, "and its text is still dark (\(t2?.hexString ?? "nil"))")
        // Deleting everything and clicking away removes it instead of leaving an empty or recolored bubble.
        click(ed, CGPoint(x: body.midX, y: body.midY), clicks: 2)
        await sleep(0.1)
        type("a", mods: .command)
        key("delete")
        click(ed, CGPoint(x: 900, y: 100))
        check(!v.doc.objects.contains { $0.id == w.id }, "a callout left empty is removed")

        // 4 · Every drawing tool hands back to Select after one shape; Counter stays on for numbering in a row.
        for (letter, kind) in [("a", Tool.arrow), ("r", .rect), ("o", .oval), ("l", .line), ("h", .highlighter), ("b", .blur)] {
            type(letter)
            drag(ed, CGPoint(x: 100, y: 100), CGPoint(x: 220, y: 180))
            check(v.tool == .select && v.doc.objects.last?.kind == kind, "after drawing with \(kind.title) the tool is Select")
            type("z", mods: .command)
        }
        type("t"); click(ed, CGPoint(x: 500, y: 500)); await sleep(0.1); type("Hi")
        click(ed, CGPoint(x: 900, y: 650))
        check(v.tool == .select && v.doc.objects.filter { $0.kind == .text }.count == 1, "Text: clicking outside finishes it and switches to Select")
        type("c"); click(ed, CGPoint(x: 300, y: 300)); click(ed, CGPoint(x: 360, y: 300))
        check(v.tool == .counter && v.doc.objects.filter { $0.kind == .counter }.count == 2, "Counter stays on so you can number several in a row")
        // Two-line text in a text box and in a shape, for a look at the saved picture.
        type("t"); click(ed, CGPoint(x: 560, y: 420)); await sleep(0.1)
        type("First line"); key("return"); type("Second line"); key("esc")
        type("r"); drag(ed, CGPoint(x: 560, y: 520), CGPoint(x: 900, y: 660))
        key("return"); await sleep(0.1); type("Top"); key("return"); type("Bottom"); key("esc")
        check(v.doc.objects.last?.text == "Top\nBottom", "Return adds lines inside a shape too")
        type("s", mods: .command)
        await sleep(0.4)
        Settings.returnToSelect = false
        type("a"); drag(ed, CGPoint(x: 100, y: 400), CGPoint(x: 200, y: 450))
        check(v.tool == .arrow, "with the preference off, tools stay on after drawing")
        Settings.returnToSelect = true
    }
}
#endif
