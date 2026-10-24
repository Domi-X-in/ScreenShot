import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// Selecting or editing an object shows its own style in the options bar, and changing one setting changes only that.
    func styleSyncFlow() async {
        guard let ed = await openEditor(Self.sampleImage(1000, 700)) else { return }
        let v = ed.shotView
        Settings.returnToSelect = true
        func shown() -> ToolStyle { ed.debugOptions.debugShownStyle }
        func setOption(_ change: (inout ToolStyle) -> Void) { var s = shown(); change(&s); v.setStyle(s) }

        // A big blue text, then the style for new objects goes back to red 4.
        var s = v.style
        s.color = NSColor(hex: 0x007AFF); s.width = 8; s.font = .goofy
        v.setStyle(s)
        type("t"); click(ed, CGPoint(x: 100, y: 600)); await sleep(0.1); type("Blue text"); key("esc")
        check(v.selection.count == 1 && shown().color.hexString == "#007AFF", "Esc finishes typing and leaves the text selected, its style shown (\(v.selection.count) selected, \(shown().color.hexString))")
        key("esc") // a second Esc lets it go
        let text = v.doc.objects.last!
        s.color = NSColor(hex: 0xFF3B30); s.width = 4; s.font = .sans
        v.setStyle(s)
        check(shown().color.hexString == "#FF3B30", "with nothing selected the bar shows the style for new objects (\(shown().color.hexString), \(v.selection.count) selected)")
        click(ed, CGPoint(x: text.bounds.midX, y: text.bounds.midY))
        check(v.selection == [text.id], "clicking the text selects it")
        check(shown().color.hexString == "#007AFF" && shown().width == 8 && shown().font == .goofy,
              "the bar shows the text's own color, size and font (\(shown().color.hexString), \(shown().width), \(shown().font))")

        // A green Card callout.
        s.color = NSColor(hex: 0x34C759); s.callout = .card; s.width = 5
        type("e"); v.setStyle(s)
        drag(ed, CGPoint(x: 500, y: 300), CGPoint(x: 600, y: 150)); await sleep(0.1); type("Card"); key("esc"); key("esc")
        let callout = v.doc.objects.last!
        s.color = NSColor(hex: 0xFF3B30); s.callout = .box; s.width = 4; v.setStyle(s)
        let body = callout.calloutShape().body.boundingBox
        click(ed, CGPoint(x: body.midX, y: body.midY))
        check(shown().color.hexString == "#34C759" && shown().callout == .card && shown().width == 5, "selecting a callout shows its color, design and size")

        // Editing: the bar follows the letters.
        click(ed, CGPoint(x: text.bounds.midX, y: text.bounds.midY), clicks: 2)
        await sleep(0.15)
        guard let editor = ed.window?.firstResponder as? NSTextView else { check(false, "double-click edits the text"); return }
        check(shown().color.hexString == "#007AFF" && shown().width == 8, "while typing, the bar shows the text's style (\(shown().color.hexString), \(shown().width))")
        editor.setSelectedRange(NSRange(location: 0, length: 4)) // "Blue"
        setOption { $0.color = NSColor(hex: 0xAF52DE) } // purple letters
        editor.setSelectedRange(NSRange(location: 6, length: 0)) // cursor in "text"
        check(shown().color.hexString == "#007AFF", "with the cursor in “text” the bar shows blue (\(shown().color.hexString))")
        editor.setSelectedRange(NSRange(location: 2, length: 0)) // cursor in "Blue"
        check(shown().color.hexString == "#AF52DE", "with the cursor in “Blue” the bar shows purple")
        editor.selectAll(nil)
        setOption { $0.width = 12 } // bigger, all of it
        key("esc")
        let t2 = v.doc.objects.first { $0.id == text.id }!
        let colors = Set((t2.runs ?? []).map(\.color))
        check(colors.count == 2 && (t2.runs ?? []).allSatisfy { $0.size == 72 }, "a size change keeps each letter's color (\(t2.runs?.map { "\($0.color) \($0.size)" } ?? []))")

        // Two selected arrows of different colors: changing the width keeps each color.
        s.width = 4; s.color = NSColor(hex: 0xFF3B30); v.setStyle(s)
        type("a"); drag(ed, CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200))
        s.color = NSColor(hex: 0x007AFF); s.width = 8; v.setStyle(s)
        type("a"); drag(ed, CGPoint(x: 100, y: 300), CGPoint(x: 300, y: 300))
        let arrows = v.doc.objects.filter { $0.kind == .arrow }
        click(ed, CGPoint(x: 200, y: 200)); click(ed, CGPoint(x: 200, y: 300), mods: .shift)
        check(v.selection == Set(arrows.map(\.id)), "both arrows selected")
        setOption { $0.width = 6 }
        let after = v.doc.objects.filter { $0.kind == .arrow }
        check(after.allSatisfy { $0.width == 6 } && after.map(\.color.hexString) == ["#FF3B30", "#007AFF"],
              "changing the width of two arrows keeps their own colors (\(after.map(\.color.hexString)))")
        setOption { $0.sketch = true }
        check(v.doc.objects.filter { $0.kind == .arrow }.allSatisfy(\.sketch), "Hand-drawn applies to arrows already drawn")
    }
}
#endif
