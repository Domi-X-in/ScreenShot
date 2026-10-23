import AppKit
import ImageIO

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// Every kind of annotation, made with the keyboard shortcuts and the mouse; ⌘S; ⌘W; reopened from the file.
    func annotateSaveReopen() async {
        guard let ed = await openEditor() else { check(false, "editor opens"); return }
        let v = ed.shotView
        func tool(_ letter: String, _ expected: Tool) {
            type(letter)
            check(v.tool == expected, "key \(letter.uppercased()) picks \(expected.title) (got \(v.tool.title))")
        }
        tool("a", .arrow); drag(ed, CGPoint(x: 100, y: 600), CGPoint(x: 260, y: 460))
        tool("l", .line); var st = v.style; st.dashed = true; v.setStyle(st); drag(ed, CGPoint(x: 100, y: 700), CGPoint(x: 400, y: 700))
        st.dashed = false; v.setStyle(st)
        tool("d", .freehand); drag(ed, CGPoint(x: 500, y: 600), CGPoint(x: 620, y: 680), steps: 10)
        tool("r", .rect); drag(ed, CGPoint(x: 80, y: 130), CGPoint(x: 400, y: 360))
        let rectID = v.doc.objects.last?.id
        key("return")
        await sleep(0.15)
        type("Sales")
        v.commitText()
        check(v.doc.objects.first { $0.id == rectID }?.text == "Sales", "Return then typing puts text in the new rectangle")
        let salesColor = v.doc.objects.first { $0.id == rectID }?.attributedText().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        check(salesColor?.hexString == v.doc.objects.first { $0.id == rectID }?.color.hexString,
              "the text in an unfilled shape is the shape's color (\(salesColor?.hexString ?? "nil"))")
        tool("o", .oval); st = v.style; st.sketch = true; v.setStyle(st); drag(ed, CGPoint(x: 800, y: 130), CGPoint(x: 1100, y: 340))
        st.sketch = false; v.setStyle(st)
        tool("h", .highlighter); drag(ed, CGPoint(x: 85, y: 420), CGPoint(x: 300, y: 480))
        tool("b", .blur); drag(ed, CGPoint(x: 460, y: 150), CGPoint(x: 640, y: 330))
        st = v.style; st.blur = .blurText; v.setStyle(st); drag(ed, CGPoint(x: 80, y: 410), CGPoint(x: 700, y: 500))
        st.blur = .blur; v.setStyle(st)
        tool("s", .spotlight); drag(ed, CGPoint(x: 780, y: 120), CGPoint(x: 1120, y: 360))
        tool("m", .magnifier); drag(ed, CGPoint(x: 900, y: 600), CGPoint(x: 960, y: 650))
        tool("c", .counter); click(ed, CGPoint(x: 1000, y: 500))
        type("7")
        check(v.doc.objects.last?.number == 7, "typing 7 renumbers the new counter (got \(v.doc.objects.last?.number ?? -1))")
        click(ed, CGPoint(x: 1060, y: 500))
        check(v.doc.objects.last?.number == 8, "the next counter continues at 8")
        type("u"); check(v.tool == .ruler, "U picks the Ruler"); drag(ed, CGPoint(x: 700, y: 760), CGPoint(x: 1000, y: 760))
        tool("t", .text); click(ed, CGPoint(x: 700, y: 560))
        await sleep(0.15)
        type("Hello")
        check(typed(ed) == "Hello", "text field takes typing (got \(typed(ed) ?? "nil"))")
        type(" e") // tool letters are just letters while typing
        check(typed(ed) == "Hello e", "letters that are tool shortcuts type into the text box")
        v.tool = .callout // a click on the toolbar's Callout button
        check(v.doc.objects.contains { $0.kind == .text && $0.text == "Hello e" }, "switching tools from the toolbar commits the text")
        drag(ed, CGPoint(x: 300, y: 250), CGPoint(x: 360, y: 560))
        await sleep(0.15)
        type("Look")
        v.commitText()
        await sleep(1.0) // Blur Text scans in the background
        let kinds = v.doc.objects.map(\.kind)
        let expectedKinds: [Tool] = [.arrow, .line, .freehand, .rect, .oval, .highlighter, .blur, .blur, .spotlight, .magnifier, .counter, .counter,
                                     .ruler, .text, .callout]
        check(kinds == expectedKinds, "all \(expectedKinds.count) objects were made in order (got \(kinds.map(\.title)))")
        check(v.doc.objects.first { $0.blurMode == .blurText }?.textRects?.isEmpty == false, "Blur Text found the text line")
        let before = v.doc.render()

        type("s", mods: .command)
        await sleep(0.4)
        guard let url = v.doc.fileURL else { check(false, "⌘S saves to a file"); return }
        check(url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL, "⌘S saves into the Screenshots folder")
        type("w", mods: .command)
        await sleep(0.4)
        check(!editors.contains { $0 === ed }, "⌘W closes the editor")
        AppLogic.shared.openFile(url)
        await sleep(0.5)
        guard let re = editors.first(where: { $0.doc.fileURL?.standardizedFileURL == url.standardizedFileURL }) else {
            check(false, "the saved file reopens in an editor"); return
        }
        check(re.doc.objects.map(\.kind) == expectedKinds, "reopened: every object is back and editable")
        check(re.doc.objects.first { $0.kind == .rect }?.text == "Sales" && re.doc.objects.first { $0.kind == .callout }?.text == "Look"
              && re.doc.objects.filter { $0.kind == .counter }.map(\.number) == [7, 8], "reopened: texts and counter numbers kept")
        await sleep(1.0)
        check(samePicture(before, re.doc.render()), "reopened: it renders exactly as before saving")
    }

    /// ⌘C / ⌘X / ⌘V of objects and images, inside one editor and between two; an image pasted past the edge is kept.
    func copyPaste() async {
        guard let a = await openEditor() else { return }
        let va = a.shotView
        type("r"); drag(a, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        key("return"); await sleep(0.1); type("Card"); va.commitText()
        guard let original = va.doc.objects.first else { check(false, "R then a drag draws a rectangle (tool \(va.tool.title), key window \(NSApp.keyWindow?.title ?? "none"))"); return }
        type("v") // Select tool
        click(a, CGPoint(x: 200, y: 150))
        check(va.selection == [original.id], "clicking inside a shape with text selects it")
        type("c", mods: .command)
        type("v", mods: .command)
        let copy = va.doc.objects.count == 2 ? va.doc.objects[1] : nil
        check(copy?.text == "Card" && copy?.rect.minX == original.rect.minX + 20, "⌘C ⌘V duplicates the shape with its text, offset")
        check(copy.map { va.selection == [$0.id] } == true, "the pasted copy is selected")
        type("x", mods: .command)
        check(va.doc.objects.count == 1, "⌘X removes it")
        type("v", mods: .command)
        check(va.doc.objects.count == 2, "⌘V brings it back")
        key("esc")
        check(va.selection.isEmpty, "Esc clears the selection")
        type("c", mods: .command)
        let copied = NSImage(pasteboard: .general)
        check(copied.map { Int($0.size.width) } == 1200, "⌘C with nothing selected copies the image (\(copied?.size.width ?? 0))")

        guard let b = await openEditor(Self.sampleImage(600, 400, text: "Second")) else { return }
        let vb = b.shotView
        type("v", mods: .command)
        guard let overlay = vb.doc.objects.last, overlay.kind == .image else { check(false, "⌘V pastes the image as an overlay"); return }
        check(vb.selection == [overlay.id], "the pasted image is selected")
        // Drag it so it hangs off the right edge.
        let r = overlay.rect
        drag(b, CGPoint(x: r.midX, y: r.midY), CGPoint(x: r.midX + 420, y: r.midY))
        check(Renderer.canvasSize(vb.doc).width > 600, "the picture grows to keep the image past the edge (\(Renderer.canvasSize(vb.doc).width))")
        key("esc")
        type("c", mods: .command)
        let wide = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        check(wide.map { CGFloat($0.width) } == Renderer.canvasSize(vb.doc).width, "⌘C copies the whole picture, outside part included")

        // An object copied in A pastes into B.
        a.window?.makeKeyAndOrderFront(nil)
        click(a, CGPoint(x: 200, y: 150))
        type("c", mods: .command)
        b.window?.makeKeyAndOrderFront(nil)
        type("v", mods: .command)
        check(vb.doc.objects.last?.kind == .rect && vb.doc.objects.last?.text == "Card", "a shape copied in one editor pastes into another")
    }

    /// Crop and Cut Out when there are objects inside, crossing and fully outside the image.
    func cropAndCutWithOutsideContent() async {
        guard let ed = await openEditor(Self.sampleImage(800, 600)) else { return }
        let v = ed.shotView
        let s = ToolStyle()
        let inside = Annotation(kind: .rect, p1: CGPoint(x: 150, y: 150), p2: CGPoint(x: 250, y: 250), style: s)
        let outside = Annotation(kind: .rect, p1: CGPoint(x: -300, y: 100), p2: CGPoint(x: -100, y: 200), style: s)
        let crossing = Annotation(kind: .arrow, p1: CGPoint(x: 300, y: 300), p2: CGPoint(x: 900, y: 300), style: s)
        v.doc.objects = [inside, outside, crossing]
        ed.documentChanged(resized: true)
        check(Renderer.canvasSize(v.doc).width > 1100, "objects past both edges grow the picture")
        type("x")
        check(v.tool == .crop, "X picks Crop")
        drag(ed, CGPoint(x: 100, y: 100), CGPoint(x: 500, y: 400))
        key("return")
        check(abs(v.doc.image.width - 400) <= 1 && abs(v.doc.image.height - 300) <= 1, "Return crops the image to 400×300 (got \(v.doc.image.width)×\(v.doc.image.height))")
        check(v.doc.objects.contains { $0.id == inside.id && abs($0.rect.minX - 50) <= 1 }, "an object inside moves with the crop")
        check(!v.doc.objects.contains { $0.id == outside.id }, "an object entirely outside the crop is dropped")
        let size = Renderer.canvasSize(v.doc)
        // The arrow crossing the crop's edge is kept whole, so the picture reaches to its tip (nothing is cut off).
        check(size.height <= 302 && size.width < 900, "the cropped picture is the crop plus the arrow crossing its edge (\(size))")
        type("z", mods: .command)
        check(v.doc.image.width == 800 && v.doc.objects.count == 3, "⌘Z restores the image and all objects")

        // Cut Out rows 250…350: objects below move up, the one outside on the left too.
        let below = Annotation(kind: .rect, p1: CGPoint(x: 100, y: 400), p2: CGPoint(x: 200, y: 500), style: s)
        let leftBelow = Annotation(kind: .rect, p1: CGPoint(x: -200, y: 420), p2: CGPoint(x: -100, y: 480), style: s)
        v.doc.objects = [below, leftBelow]
        ed.documentChanged(resized: true)
        type("X", mods: [.shift])
        check(v.tool == .crop && v.cutOutMode, "⇧X opens Cut Out")
        drag(ed, CGPoint(x: 400, y: 250), CGPoint(x: 402, y: 350))
        key("return")
        check(v.doc.image.height == 500, "the 100 px strip is removed (height \(v.doc.image.height))")
        check(v.doc.objects.first { $0.id == below.id }?.rect.minY == 300 && v.doc.objects.first { $0.id == leftBelow.id }?.rect.minY == 320,
              "objects below the strip move up, inside and outside the image")
    }

    /// Backdrop with content past the edge, Resize 50%, blinking GIF.
    func backdropResizeGIF() async {
        guard let ed = await openEditor(Self.sampleImage(800, 600)) else { return }
        let v = ed.shotView
        type("r"); drag(ed, CGPoint(x: 600, y: 200), CGPoint(x: 1000, y: 300)) // past the right edge
        key("return"); await sleep(0.1); type("Note"); v.commitText()
        type("e"); drag(ed, CGPoint(x: 200, y: 200), CGPoint(x: 260, y: 400)); await sleep(0.1); type("Hi"); v.commitText()
        let content = Renderer.canvasSize(v.doc)
        check(content.width > 800, "content past the edge grows the picture")
        type("k")
        check(v.doc.backdrop.isOn, "K turns the backdrop on")
        let withBackdrop = Renderer.canvasSize(v.doc)
        check(withBackdrop.width > content.width && withBackdrop.height > content.height, "the backdrop surrounds everything, including the part past the edge")
        let img = v.doc.render()
        check(img.map { PixelReader($0).color(4, 4)!.alphaComponent > 0.99 } == true, "the backdrop fills the corner")
        let rect = v.doc.objects.first { $0.kind == .rect }!
        let font = rect.shapeFontSize, width = rect.width
        v.resizeImage(by: 0.5)
        let r2 = v.doc.objects.first { $0.id == rect.id }!
        check(v.doc.image.width == 400 && abs(r2.rect.minX - rect.rect.minX / 2) < 1, "Resize 50% halves the image and moves objects")
        check(abs(r2.shapeFontSize - font / 2) < 0.6 && abs(r2.width - width / 2) < 0.01, "and scales the shape's text and outline")
        type("z", mods: .command)
        check(v.doc.image.width == 800, "⌘Z undoes the resize")
        type("g", mods: [.command, .shift])
        await sleep(0.6)
        let gifs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "gif" } ?? []
        let src = gifs.last.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        check(src.map(CGImageSourceGetCount) == 2, "⇧⌘G saves a two-frame GIF")
        if let src, let f = CGImageSourceCreateImageAtIndex(src, 0, nil), let rendered = v.doc.render() {
            check(abs(Double(f.width) / Double(f.height) - Double(rendered.width) / Double(rendered.height)) < 0.01,
                  "the GIF shows the whole picture (backdrop and content past the edge)")
        }
    }

    /// A long editing session, then undo all the way back and redo all the way forward.
    func undoRedoChain() async {
        let base = Self.sampleImage(800, 600)
        guard let ed = await openEditor(base) else { return }
        let v = ed.shotView
        type("r"); drag(ed, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 250))
        type("o"); drag(ed, CGPoint(x: 400, y: 100), CGPoint(x: 600, y: 250))
        type("a"); drag(ed, CGPoint(x: 100, y: 500), CGPoint(x: 400, y: 400))
        type("v")
        click(ed, CGPoint(x: 100, y: 175)) // rect edge
        drag(ed, CGPoint(x: 100, y: 175), CGPoint(x: 160, y: 205)) // move
        key("right"); key("right", mods: .shift) // nudge 1 + 10
        key("return"); await sleep(0.1); type("Move"); v.commitText()
        var st = v.style; st.color = NSColor(hex: 0x34C759); v.setStyle(st) // recolor the selection
        type("d", mods: .command) // duplicate
        type("a", mods: .command) // select all
        v.arrange(.alignTop)
        key("delete")
        type("z", mods: .command) // bring them back
        type("k") // backdrop
        type("x"); drag(ed, CGPoint(x: 50, y: 50), CGPoint(x: 700, y: 550)); key("return") // crop
        let finalPicture = v.doc.render()
        let finalCount = v.doc.objects.count
        var undos = 0
        while !v.doc.undoStack.isEmpty, undos < 60 { type("z", mods: .command); undos += 1 }
        check(v.doc.objects.isEmpty && v.doc.image.width == 800 && !v.doc.backdrop.isOn, "undo all the way back gives the untouched screenshot (\(undos) steps)")
        check(samePicture(v.doc.render(), base), "and it looks exactly like the capture")
        for _ in 0..<undos { type("z", mods: [.command, .shift]) }
        check(v.doc.objects.count == finalCount && samePicture(v.doc.render(), finalPicture), "redo all the way forward gives the final result again")
    }

    /// Selection and keyboard: ⌘A, arrows, Delete, ⌘D, ⌥-drag, Esc, Tab, tool letters while a text field is open.
    func keyboardFlow() async {
        guard let ed = await openEditor() else { return }
        let v = ed.shotView
        type("r"); drag(ed, CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200))
        type("o"); drag(ed, CGPoint(x: 300, y: 100), CGPoint(x: 400, y: 200))
        type("v")
        type("a", mods: .command)
        check(v.selection.count == 2, "⌘A selects everything")
        let x0 = v.doc.objects.map(\.rect.minX)
        key("left")
        key("down", mods: .shift)
        check(zip(v.doc.objects.map(\.rect.minX), x0).allSatisfy { abs($0 - ($1 - 1)) < 0.01 } && v.doc.objects.allSatisfy { abs($0.rect.minY - 110) < 0.01 },
              "arrows nudge the whole selection (1 px, Shift 10 px): x \(x0) → \(v.doc.objects.map(\.rect.minX)), y \(v.doc.objects.map(\.rect.minY))")
        type("d", mods: .command)
        check(v.doc.objects.count == 4 && v.selection.count == 2, "⌘D duplicates the selection and selects the copies")
        key("delete")
        check(v.doc.objects.count == 2, "Delete removes the selection")
        click(ed, CGPoint(x: 99, y: 130)) // the left edge, away from its resize handle
        let count = v.doc.objects.count
        drag(ed, CGPoint(x: 99, y: 130), CGPoint(x: 99, y: 400), mods: .option)
        check(v.doc.objects.count == count + 1, "⌥-drag drops a copy and leaves the original (\(count) → \(v.doc.objects.count), selection \(v.selection.count))")
        key("esc")
        check(v.selection.isEmpty, "Esc clears the selection, the editor stays open")
        check(editors.contains { $0 === ed }, "the editor is still open")
        // Letters that are tool shortcuts type normally inside a text box.
        type("t"); click(ed, CGPoint(x: 600, y: 600)); await sleep(0.15)
        type("abc rotate")
        check(typed(ed) == "abc rotate" && v.tool == .text, "tool letters type normally in a text box (got \(typed(ed) ?? "nil"))")
        v.commitText()
    }

    /// Per-letter styles in text and in a shape survive save and reopen.
    func textStylesFlow() async {
        guard let ed = await openEditor() else { return }
        let v = ed.shotView
        type("t"); click(ed, CGPoint(x: 100, y: 600)); await sleep(0.15)
        type("Hello world")
        for _ in 0..<5 { key("left", mods: .shift) }
        var st = v.style
        st.color = NSColor(hex: 0x007AFF)
        v.setStyle(st)
        v.commitText()
        let t = v.doc.objects.last
        check(t?.runs?.contains { $0.color.hasPrefix("#007AFF") && $0.length == 5 } == true, "selecting “world” and picking blue colors just those letters")
        type("r"); drag(ed, CGPoint(x: 600, y: 500), CGPoint(x: 1000, y: 700))
        key("return"); await sleep(0.1)
        type("Big")
        st = v.style; st.width = 10; v.setStyle(st) // bigger text, while typing
        v.commitText()
        let shape = v.doc.objects.last
        check(shape?.shapeFontSize == 60 && shape?.width == 4, "a size change while typing in a shape sizes the text, not the outline (font \(shape?.shapeFontSize ?? 0), width \(shape?.width ?? 0))")
        type("s", mods: .command)
        await sleep(0.3)
        guard let url = v.doc.fileURL else { check(false, "saved"); return }
        type("w", mods: .command)
        await sleep(0.3)
        AppLogic.shared.openFile(url)
        await sleep(0.4)
        let re = editors.last?.shotView.doc
        check(re?.objects.first { $0.kind == .text }?.runs == t?.runs, "reopened: the blue letters are still blue")
        check(re?.objects.first { $0.kind == .rect }?.shapeFontSize == 60, "reopened: the shape's text size is kept")
    }
}
#endif
