import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// All views of a type under `root`.
    func views<T: NSView>(_ t: T.Type, in root: NSView?) -> [T] {
        guard let root else { return [] }
        return (root as? T).map { [$0] } ?? [] + root.subviews.flatMap { views(t, in: $0) }
    }

    func allViews<T: NSView>(_ t: T.Type, in root: NSView?) -> [T] {
        guard let root else { return [] }
        var out: [T] = []
        if let x = root as? T { out.append(x) }
        for s in root.subviews { out += allViews(t, in: s) }
        return out
    }

    /// The popover window that `open` brings up.
    func popover(_ open: () -> Void) async -> NSWindow? {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        open()
        await sleep(0.4)
        return NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.isVisible }
    }

    /// Backdrop, Resize, Arrange and options-bar controls, used with real clicks on their controls.
    func panelsFlow() async {
        guard let ed = await openEditor(Self.sampleImage(800, 600)) else { return }
        let v = ed.shotView
        let content = ed.window?.contentView

        // Backdrop panel: a preset swatch, the fill popup, a slider.
        guard let pill = allViews(PillButton.self, in: content).first(where: { $0.accessibilityLabel() == "Backdrop" }) else {
            check(false, "the options bar has a Backdrop button"); return
        }
        let panel = await popover { _ = pill.accessibilityPerformPress() }
        check(panel != nil, "the Backdrop button opens its panel")
        let swatches = allViews(NSButton.self, in: panel?.contentView).filter { $0.toolTip == "Sunset" }
        swatches.first?.performClick(nil)
        await sleep(1) // a person pauses between controls; changes within 0.8 s count as one undo step
        check(v.doc.backdrop.isOn && v.doc.backdrop.colors == ["#FA709A", "#FEE140"], "clicking the Sunset swatch turns the backdrop on with its colors")
        if let fill = allViews(NSPopUpButton.self, in: panel?.contentView).first(where: { $0.itemTitles.contains("Mesh Gradient") }) {
            fill.selectItem(withTitle: "Mesh Gradient")
            _ = fill.target?.perform(fill.action, with: fill)
            check(v.doc.backdrop.fill == .mesh, "the Fill menu switches to Mesh Gradient")
            await sleep(1)
        } else { check(false, "the panel has a Fill menu") }
        if let aspect = allViews(NSPopUpButton.self, in: panel?.contentView).first(where: { $0.itemTitles.contains("1:1") }) {
            aspect.selectItem(withTitle: "1:1")
            _ = aspect.target?.perform(aspect.action, with: aspect)
            let c = Renderer.canvasSize(v.doc)
            check(abs(c.width - c.height) < 1, "Aspect 1:1 makes the picture square (\(c))")
            await sleep(1)
        } else { check(false, "the panel has an Aspect menu") }
        if let padding = allViews(NSSlider.self, in: panel?.contentView).first(where: { $0.accessibilityLabel() == "Padding" }) {
            let before = Renderer.canvasSize(v.doc)
            padding.doubleValue = 0.2
            _ = padding.target?.perform(padding.action, with: padding)
            check(Renderer.canvasSize(v.doc).width > before.width, "dragging Padding up grows the margin")
        } else { check(false, "the panel has a Padding slider") }
        let undoSteps = v.doc.undoStack.count
        let padded = Renderer.canvasSize(v.doc)
        type("z", mods: .command)
        check(v.doc.undoStack.count == undoSteps - 1 && Renderer.canvasSize(v.doc).width < padded.width && v.doc.backdrop.fill == .mesh,
              "one ⌘Z undoes just the last panel change (the padding)")
        panel?.close()
        type("k")
        check(!v.doc.backdrop.isOn, "K turns the backdrop off")

        // Resize panel: 50% preset.
        let resize = await popover { ed.showResizePanel() }
        if let presets = allViews(NSSegmentedControl.self, in: resize?.contentView).first(where: { $0.segmentCount == 6 }) {
            presets.trackingMode = .selectOne // a click selects the segment while the action runs
            presets.selectedSegment = 2 // 50%
            _ = presets.target?.perform(presets.action, with: presets)
            await sleep(0.2)
            check(v.doc.image.width == 400, "Resize › 50% halves the screenshot (\(v.doc.image.width))")
            type("z", mods: .command)
        } else { check(false, "the Resize panel has the size presets") }
        resize?.close()

        // Options bar on a selection: the arrow style control restyles the selected arrow.
        type("a"); drag(ed, CGPoint(x: 100, y: 500), CGPoint(x: 300, y: 400))
        type("v"); click(ed, CGPoint(x: 200, y: 450))
        if let arrows = allViews(DefaultableSegmentedControl.self, in: content).first(where: { !$0.isHidden && $0.segmentCount == ArrowStyle.allCases.count }) {
            arrows.selectedSegment = 1
            _ = arrows.target?.perform(arrows.action, with: arrows)
            check(v.doc.objects.last?.arrowStyle == ArrowStyle(rawValue: 1), "choosing another arrow style restyles the selected arrow")
        } else { check(false, "the options bar shows arrow styles for a selected arrow") }

        // Arrange panel from the options bar.
        type("r"); drag(ed, CGPoint(x: 500, y: 100), CGPoint(x: 600, y: 160))
        type("v")
        type("a", mods: .command)
        let arrange = await popover {
            if let b = allViews(NSButton.self, in: content).first(where: { $0.title == "Arrange" && !$0.isHidden }) { b.performClick(nil) }
        }
        check(arrange != nil, "the Arrange button shows for a selection and opens its panel")
        allViews(NSButton.self, in: arrange?.contentView).first { $0.identifier?.rawValue == ArrangeAction.alignTop.rawValue }?.performClick(nil)
        let tops = v.doc.objects.map(\.frame.minY)
        check(tops.allSatisfy { abs($0 - tops[0]) < 0.5 }, "Align Top from the panel lines up the tops (\(tops))")
        arrange?.close()
    }

    /// Pin, Esc (copy and close), the floating thumbnail's buttons, the menu bar menu.
    func windowsFlow() async {
        // ⌘P pins the picture and closes the editor.
        guard let ed = await openEditor(Self.sampleImage(600, 400)) else { return }
        type("p", mods: .command)
        await sleep(0.4)
        let pin = NSApp.windows.first { $0 is PinWindow && $0.isVisible }
        check(pin != nil && !editors.contains { $0 === ed }, "⌘P pins the screenshot on screen and closes the editor")
        pin?.close()
        await sleep(0.2)
        check(!NSApp.windows.contains { $0 is PinWindow && $0.isVisible }, "the pin closes")

        // Esc copies and closes (default setting).
        UserDefaults.standard.set(true, forKey: Keys.escCopy)
        UserDefaults.standard.set(false, forKey: Keys.escSave)
        guard let ed2 = await openEditor(Self.sampleImage(500, 300)) else { return }
        NSPasteboard.general.clearContents()
        key("esc")
        await sleep(0.3)
        check(!editors.contains { $0 === ed2 } && NSImage(pasteboard: .general).map { Int($0.size.width) } == 500,
              "Esc copies the picture and closes the editor")

        // The floating thumbnail after an area capture: Edit opens the editor.
        UserDefaults.standard.set("thumbnail", forKey: Keys.afterAreaShow)
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        AppLogic.shared.handleCapture(Self.sampleImage(700, 450), scale: 1, area: true)
        await sleep(0.5)
        let thumb = NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.isVisible }
        if let palette = allViews(IconPalette.self, in: thumb?.contentView).first {
            palette.onSelect?(0) // Edit
            await sleep(0.4)
            check(editors.contains { $0.doc.image.width == 700 } && thumb?.isVisible == false, "the thumbnail's Edit opens the capture in the editor")
        } else { check(false, "the thumbnail has its button row") }
        UserDefaults.standard.set("editor", forKey: Keys.afterAreaShow)
        await closeAllEditors()

        // The menu bar menu.
        let menu = NSMenu()
        (NSApp.delegate as? AppDelegate)?.menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        for t in ["Open ScreenShot", "Area Capture", "Fullscreen Screenshot", "Welcome Guide…", "Check for Updates…", "Preferences…", "Quit ScreenShot"] {
            check(titles.contains(t), "the menu bar menu has “\(t)”")
        }
        if let open = menu.items.first(where: { $0.title == "Open ScreenShot" }), let action = open.action {
            NSApp.sendAction(action, to: open.target, from: open)
            await sleep(0.4)
            check(LibraryWindowController.shared?.window?.isVisible == true, "Open ScreenShot shows the home window")
        }
    }

    /// The home window: its capture buttons, search by name, date and text, opening a screenshot.
    func libraryFlow() async {
        // Three screenshots in the folder, one with recognizable text.
        for (i, text) in ["Quarterly report", "Grocery list", "Flight AB123"].enumerated() {
            let doc = EditorDocument(image: Self.sampleImage(900, 500, text: text), scale: 1)
            _ = Exporter.saveEditable(doc, rendered: doc.render()!, to: folder.appendingPathComponent("lib-\(i).png"), quiet: true)
        }
        (NSApp.delegate as? AppDelegate)?.showLibrary()
        await sleep(0.6)
        guard let lib = LibraryWindowController.shared, let content = lib.window?.contentView else { check(false, "the home window opens"); return }
        lib.reload()
        let segments = allViews(NSSegmentedControl.self, in: content).first { $0.segmentCount == 3 }
        check((0..<3).compactMap { segments?.label(forSegment: $0) } == ["Area", "Window", "Fullscreen"], "it has Area / Window / Fullscreen buttons")
        guard let collection = allViews(NSCollectionView.self, in: content).first,
              let search = allViews(NSSearchField.self, in: content).first else { check(false, "it lists screenshots and has a search field"); return }
        // Wait for the text index (it reads each file in the background).
        // Slow machines (CI runners) take a while to recognize text; wait up to 90 s.
        var waited = 0.0
        while TextIndex.shared.text(for: folder.appendingPathComponent("lib-2.png"))?.contains("AB123") != true, waited < 90 {
            await sleep(0.5)
            waited += 0.5
        }
        check(waited < 90, "the text in new screenshots is recognized in the background (\(waited) s)")
        func searchFor(_ q: String) -> Int {
            search.stringValue = q
            lib.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
            return collection.numberOfItems(inSection: 0)
        }
        check(searchFor("") >= 3, "all screenshots are listed (\(collection.numberOfItems(inSection: 0)))")
        check(searchFor("lib-1") == 1, "searching a file name finds it")
        check(searchFor("AB123") == 1, "searching text inside a screenshot finds it")
        check(searchFor("flight ab123") == 1, "search ignores case and matches every word")
        check(searchFor("nothing like this") == 0, "a search with no match shows nothing")
        _ = searchFor("lib-1")
        collection.selectItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: [])
        lib.collectionView(collection, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        await sleep(0.4)
        check(editors.contains { $0.doc.fileURL?.lastPathComponent == "lib-1.png" }, "clicking a result opens it in the editor")
        lib.window?.close()
    }

    /// Preferences: every pane opens; checkboxes, radios and menus write their settings and take effect.
    func preferencesFlow() async {
        (NSApp.delegate as? AppDelegate)?.showPreferences()
        await sleep(0.4)
        guard let win = NSApp.windows.first(where: { $0.windowController is PreferencesWindowController }), let tb = win.toolbar else {
            check(false, "Preferences opens"); return
        }
        func pane(_ i: Int) async {
            let item = tb.items[i]
            if let a = item.action { NSApp.sendAction(a, to: item.target, from: item) }
            await sleep(0.3)
        }
        func checkbox(_ title: String) -> NSButton? { allViews(NSButton.self, in: win.contentView).first { $0.title == title } }
        let d = UserDefaults.standard

        await pane(0)
        let save = checkbox("Save")
        let was = d.bool(forKey: Keys.afterSave)
        save?.performClick(nil)
        check(save != nil && d.bool(forKey: Keys.afterSave) == !was, "General › After screenshot › Save toggles the setting")
        save?.performClick(nil)
        checkbox("Light")?.performClick(nil)
        await sleep(0.2)
        check(Settings.appearance == "light" && NSApp.appearance?.name == .aqua, "Appearance › Light applies at once")
        checkbox("System")?.performClick(nil)
        await sleep(0.2)
        check(Settings.appearance == "system" && NSApp.appearance == nil, "Appearance › System follows macOS again")
        checkbox("Hide the menu bar icon")?.performClick(nil)
        check(Settings.hideMenuBarIcon, "Hide the menu bar icon is saved")
        checkbox("Hide the menu bar icon")?.performClick(nil)
        checkbox("Include")?.performClick(nil)
        check(Settings.showsCursor(fullscreen: false), "Mouse pointer › Include")
        checkbox("Auto")?.performClick(nil)
        checkbox("Color")?.performClick(nil)
        check(Settings.windowBackground == "color", "Window background › Color")
        checkbox("None")?.performClick(nil)

        await pane(1)
        let recorders = allViews(RecorderButton.self, in: win.contentView)
        check(recorders.count == 9, "Hotkeys lists the 9 shortcuts")
        if let area = recorders.first {
            area.performClick(nil)
            check(area.title == "Type shortcut…", "clicking a shortcut starts recording")
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: win.windowNumber,
                                     context: nil, characters: "4", charactersIgnoringModifiers: "4", isARepeat: false, keyCode: 21)!
            NSApp.postEvent(e, atStart: true)
            await sleep(0.3)
            check(HotKeyCenter.shared.shortcut(for: .fullscreen)?.display == "⇧⌘4" || recorders.contains { $0.title.contains("⇧⌘4") },
                  "typing ⇧⌘4 records it (\(area.title))")
        }
        allViews(NSButton.self, in: win.contentView).first { $0.title == "Reset to Defaults" }?.performClick(nil)
        check(HotKeyCenter.shared.shortcut(for: .area)?.display == "⇧⌘2", "Reset to Defaults brings back ⇧⌘2")

        await pane(2)
        if let ocr = allViews(DefaultsPopup.self, in: win.contentView).first(where: { $0.itemTitles.contains("Automatic") }) {
            if let i = ocr.itemTitles.firstIndex(where: { $0.lowercased().contains("spanish") || $0.lowercased().contains("español") }) {
                ocr.selectItem(at: i)
                _ = ocr.target?.perform(ocr.action, with: ocr)
                check(Settings.ocrLanguage.hasPrefix("es"), "OCR main language › Spanish (\(Settings.ocrLanguage))")
            } else { check(false, "the OCR language list has Spanish") }
        } else { check(false, "Advanced has the OCR language menu") }
        if let height = allViews(DefaultsPopup.self, in: win.contentView).first(where: { $0.itemTitles.contains { $0.contains("10,000") || $0.contains("10.000") } }) {
            height.selectItem(at: 1)
            _ = height.target?.perform(height.action, with: height)
            check(Settings.scrollMaxHeight == 10000, "Scrolling capture height › 10,000 px (\(Settings.scrollMaxHeight))")
        } else { check(false, "Advanced has the scrolling height menu") }
        checkbox("Allow screenshot://grab/area, …")?.performClick(nil)
        check(!Settings.urlSchemeEnabled, "the screenshot:// checkbox turns links off")
        checkbox("Allow screenshot://grab/area, …")?.performClick(nil)
        win.close()
    }
}
#endif
