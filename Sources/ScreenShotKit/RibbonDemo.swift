import AppKit

#if SCREENSHOT_SELFTESTS
/// R2's ribbon on its own, not yet wired to the editor: the seven groups of the design with stand-in actions.
/// `SCREENSHOT_RIBBON_DEMO=1` opens it in a resizable window; the UI snapshots render it at several widths.
@MainActor enum RibbonDemo {
    /// The last command run, for the demo window's readout and the tests.
    static var log: [String] = []

    static func groups() -> [RibbonGroup] {
        func note(_ s: String) -> () -> Void { { log.append(s); NotificationCenter.default.post(name: .ribbonDemoChanged, object: nil) } }
        func menu(_ titles: [String]) -> () -> NSMenu {
            {
                let m = NSMenu()
                for t in titles {
                    if t == "-" { m.addItem(.separator()); continue }
                    let i = NSMenuItem(title: t, action: #selector(DemoTarget.picked(_:)), keyEquivalent: "")
                    i.target = DemoTarget.shared
                    m.addItem(i)
                }
                return m
            }
        }
        func small(_ id: String, _ title: String, _ icon: IconName, menu items: [String]? = nil) -> RibbonItem {
            RibbonItem(id, kind: .small, title: title, icon: icon, action: note(title), menu: items.map(menu))
        }
        func label(_ id: String, _ title: String, _ icon: IconName, menu items: [String]? = nil) -> RibbonItem {
            RibbonItem(id, kind: .label, title: title, icon: icon, action: note(title), menu: items.map(menu))
        }
        func color(_ id: String, _ title: String, _ icon: IconName, _ bar: NSColor?) -> RibbonItem {
            RibbonItem(id, kind: .color, title: title, icon: icon, barColor: bar, action: note(title), menu: menu(["No Color", "-", "More Colors…"]), split: true)
        }

        var tools: [RibbonItem] = []
        func tool(_ id: String, _ title: String, _ icon: IconName) -> RibbonItem {
            let item = RibbonItem(id, kind: .small, title: title, icon: icon)
            item.action = {
                for t in tools { t.isActiveTool = t === item }
                note(title)()
            }
            tools.append(item)
            return item
        }

        let bold = small("bold", "Bold", .bold)
        bold.isOn = true
        bold.action = { bold.isOn.toggle(); note("Bold")() }
        let redo = label("redo", "Redo", .redo)
        redo.isEnabled = false

        let clipboard = RibbonGroup("clipboard", title: "Clipboard", compactTitle: "Paste", compactIcon: .gPaste, columns: [
            .large(RibbonItem("paste", kind: .large, title: "Paste", icon: .paste, action: note("Paste"), menu: menu(["Paste", "Paste as New Image"]), split: true)),
            .rows([[.item(label("cut", "Cut", .cut))], [.item(label("copy", "Copy", .copy))], [.item(label("format", "Format", .formatPainter))]]),
        ])
        let font = RibbonGroup("font", title: "Font", compactTitle: "Fonts", compactIcon: .gFonts, columns: [
            .rows([
                [.item(RibbonItem("family", kind: .field(width: 124), title: "Font", text: "SF Pro Text", menu: menu(["SF Pro Text", "SF Pro Rounded", "New York", "SF Mono"]))),
                 .item(RibbonItem("size", kind: .field(width: 50), title: "Font size", text: "14", menu: menu(["10", "12", "14", "18", "24", "36"]))),
                 .item(small("grow", "Increase Font Size", .growFont)), .item(small("shrink", "Decrease Font Size", .shrinkFont))],
                [.item(bold), .item(small("italic", "Italic", .italic)), .item(small("underline", "Underline", .underline)),
                 .item(small("strike", "Strikethrough", .strike)), .divider,
                 .item(small("orient", "Text Orientation", .textOrient, menu: ["Horizontal", "Rotate 90°", "Rotate 270°", "Stacked"])),
                 .item(small("case", "Change Case", .changeCase, menu: ["Sentence case.", "lowercase", "UPPERCASE", "Capitalize Each Word", "tOGGLE cASE"]))],
            ]),
        ])
        let paragraph = RibbonGroup("paragraph", title: "Paragraph", compactTitle: "Paragraph", compactIcon: .gParagraph, columns: [
            .rows([
                [.item(small("halign", "Horizontal Alignment", .alignLeft, menu: ["Left", "Center", "Right", "Justify"])),
                 .item(small("valign", "Vertical Alignment", .vMiddle, menu: ["Top", "Middle", "Bottom"]))],
                [.item(small("bullets", "Bullets", .bullets, menu: ["None", "Bullets"])),
                 .item(small("numbering", "Numbering", .numbering, menu: ["None", "1. 2. 3."]))],
            ]),
        ])
        let colors = RibbonGroup("color", title: "Color", compactTitle: "Colors", compactIcon: .gColors, columns: [
            .rows([
                [.item(color("fill", "Shape Fill", .shapeFill, nil)), .item(color("outline", "Shape Outline", .shapeOutline, NSColor(hex: 0xF23D4F)))],
                [.item(color("fontColor", "Font Color", .fontFill, .white)), .item(color("fontOutline", "Font Outline", .fontOutline, nil))],
            ]),
        ])
        let shapes = RibbonGroup("shapes", title: "Shapes", compactTitle: "Shapes", compactIcon: .gShapes, columns: [
            .rows([
                [.item(tool("select", "Select", .select)), .item(tool("freehand", "Freehand", .freehand)), .item(tool("line", "Line", .line)),
                 .item(tool("arrow", "Arrow", .arrow)), .item(tool("rect", "Rectangle", .rect))],
                [.item(tool("oval", "Oval", .oval)), .item(tool("callout", "Callout", .callout)), .item(tool("counter", "Counter", .counter)),
                 .item(tool("text", "Text Box", .textbox))],
            ]),
        ])
        let toolsGroup = RibbonGroup("tools", title: "Tools", compactTitle: "Tools", compactIcon: .gTools, columns: [
            .rows([
                [.item(tool("highlighter", "Highlighter", .highlighter)), .item(tool("blur", "Blur", .blur)),
                 .item(tool("spotlight", "Spotlight", .spotlight)), .item(tool("magnifier", "Magnifier", .magnifier))],
                [.item(tool("ruler", "Ruler", .ruler)), .item(tool("crop", "Crop", .crop)), .item(tool("ocr", "OCR / QR", .ocr)),
                 .item(tool("area", "Image Area Selection", .areaSelect))],
            ]),
        ])
        let arrange = RibbonGroup("arrange", title: "Arrange", compactTitle: "Arrange", compactIcon: .gArrange, columns: [
            .rows([[.item(label("arrange", "Arrange", .arrange, menu: ["Bring to Front", "Bring Forward", "-", "Send Backward", "Send to Back"]))],
                   [.item(label("align", "Align", .align, menu: ["Align Left", "Align Center", "Align Right", "-", "Align Top", "Align Middle", "Align Bottom", "-", "Distribute Horizontally", "Distribute Vertically"]))]]),
            .rows([[.item(label("rotate", "Rotate", .rotate, menu: ["Rotate Right 90°", "Rotate Left 90°"]))],
                   [.item(label("flip", "Flip", .flip, menu: ["Flip Vertical", "Flip Horizontal"]))]]),
            .rows([[.item(small("heads", "Arrow Heads", .arrowEnd, menu: ["None", "Open Arrow, End", "Open Arrow, Start", "Both Ends", "-", "Filled Arrow", "Dot End"]))],
                   [.item(small("lineStyle", "Line Style", .lineSolid, menu: ["Solid", "Dashed", "Dotted"]))]]),
        ])
        tools.first { $0.id == "arrow" }?.isActiveTool = true
        _ = redo
        return [clipboard, font, paragraph, colors, shapes, toolsGroup, arrange]
    }

    /// A window with the ribbon across the top and a readout of the width, folded groups and the last command.
    static func window(width: CGFloat) -> (NSWindow, RibbonView) {
        let ribbon = RibbonView(groups: groups())
        let content = DemoBackground(frame: CGRect(x: 0, y: 0, width: width, height: 220))
        ribbon.frame = CGRect(x: 0, y: 0, width: width, height: DesignTokens.Metrics.ribbonHeight)
        ribbon.autoresizingMask = [.width]
        content.addSubview(ribbon)
        let readout = NSTextField(labelWithString: "")
        readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        readout.textColor = DesignTokens.color(.ink2)
        readout.frame = CGRect(x: 16, y: 120, width: width - 32, height: 60)
        readout.autoresizingMask = [.width]
        readout.maximumNumberOfLines = 3
        content.addSubview(readout)
        let w = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Ribbon demo"
        w.contentView = content
        w.contentMinSize = NSSize(width: 480, height: 220)
        w.isReleasedWhenClosed = false
        func refresh() {
            ribbon.layoutSubtreeIfNeeded()
            readout.stringValue = "Width \(Int(ribbon.bounds.width)) · folded \(ribbon.collapsedCount) of \(ribbon.groups.count)\n"
                + "Breakpoints \(ribbon.breakpoints.map { Int($0.rounded(.up)) })\nLast: \(log.last ?? "—")"
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { _ in MainActor.assumeIsolated { refresh() } }
        NotificationCenter.default.addObserver(forName: .ribbonDemoChanged, object: nil, queue: .main) { _ in MainActor.assumeIsolated { refresh() } }
        refresh()
        return (w, ribbon)
    }

    /// `SCREENSHOT_RIBBON_DEMO=1`: opens the demo instead of the app's usual start.
    static func openIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_RIBBON_DEMO"] == "1" else { return false }
        let (w, _) = window(width: 1280)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        demoWindow = w
        return true
    }
    private static var demoWindow: NSWindow?

    final class DemoTarget: NSObject {
        static let shared = DemoTarget()
        @objc func picked(_ sender: NSMenuItem) {
            MainActor.assumeIsolated {
                RibbonDemo.log.append(sender.title)
                NotificationCenter.default.post(name: .ribbonDemoChanged, object: nil)
            }
        }
    }

    private final class DemoBackground: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) { DesignTokens.color(.canvas).setFill(); bounds.fill() }
    }
}

/// Real clicks on the demo ribbon: hover and press states, the folded Shapes group opening its flyout, picking a tool
/// inside it, Esc and an outside click closing it. Runs only with SCREENSHOT_SELFTEST_RIBBON set.
@MainActor enum RibbonSelfTest {
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_SELFTEST_RIBBON"] != nil else { return false }
        setvbuf(stdout, nil, _IONBF, 0) // lines show up even if the app crashes
        let (win, ribbon) = RibbonDemo.window(width: 620)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
        ribbon.layoutSubtreeIfNeeded()
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func event(_ type: NSEvent.EventType, _ view: NSView, _ p: CGPoint? = nil) -> NSEvent {
            let local = p ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            return NSEvent.mouseEvent(with: type, location: view.convert(local, to: nil), modifierFlags: [], timestamp: 0,
                                      windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func click(_ view: NSView) {
            view.mouseDown(with: event(.leftMouseDown, view))
            view.mouseUp(with: event(.leftMouseUp, view))
        }

        let groups = ribbon.groups
        let shapes = groups.first { $0.id == "shapes" }!
        check(ribbon.collapsedCount >= 5 && ribbon.isCompact(shapes), "at 620 pt the right-hand groups are folded (\(ribbon.collapsedCount) folded)")
        guard let button = ribbon.compactButton(for: shapes) else { check(false, "Shapes has a compact button"); exit(1) }
        check(button.displayIcon == .arrow, "the folded Shapes button shows the active Arrow tool")

        click(button)
        check(ribbon.openFlyoutGroup === shapes && button.isOpen, "a click on Shapes opens its flyout")
        guard let flyout = ribbon.openFlyout else { exit(1) }
        check(flyout.parent === win && flyout.frame.maxY <= win.convertToScreen(button.convert(button.bounds, to: nil)).minY,
              "the flyout hangs under its button")
        let rect = flyout.groupView.buttons.first { $0.item.id == "rect" }!
        rect.mouseDown(with: event(.leftMouseDown, rect))
        check(rect.pressed, "pressing a button shows its pressed state")
        rect.mouseUp(with: event(.leftMouseUp, rect))
        check(rect.item.isActiveTool && !shapes.items.first { $0.id == "arrow" }!.isActiveTool, "Rectangle picked in the flyout becomes the tool")
        check(button.displayIcon == .rect, "the folded button now shows Rectangle")
        rect.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: rect.convert(CGPoint(x: 4, y: 4), to: nil), modifierFlags: [],
                                                       timestamp: 0, windowNumber: flyout.windowNumber, context: nil, eventNumber: 0,
                                                       trackingNumber: 0, userData: nil)!)
        check(rect.hovering, "hover is tracked")

        flyout.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: flyout.windowNumber,
                                          context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!)
        // The local key monitor sees events that come through the app, so post Esc through NSApp too.
        NSApp.postEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                                         context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!, atStart: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            check(ribbon.openFlyoutGroup == nil && !button.isOpen, "Esc closes the flyout")
            click(button)
            check(ribbon.openFlyoutGroup === shapes, "it opens again")
            click(button)
            check(ribbon.openFlyoutGroup == nil, "a second click on its button closes it")

            let colors = groups.first { $0.id == "color" }!
            if let c = ribbon.compactButton(for: colors) { click(c) }
            let paragraph = groups.first { $0.id == "paragraph" }!
            if let p = ribbon.compactButton(for: paragraph) { click(p) }
            check(ribbon.openFlyoutGroup === paragraph, "opening another group's flyout closes the first")
            ribbon.closeFlyout()

            win.setContentSize(NSSize(width: 1400, height: 220))
            ribbon.layoutSubtreeIfNeeded()
            let fits = ribbon.bounds.width >= ribbon.breakpoints[0]
            check(!fits || ribbon.collapsedCount == 0, "a wide window shows every group (width \(Int(ribbon.bounds.width)), needs \(Int(ribbon.breakpoints[0])))")
            print(failures == 0 ? "RIBBON SELFTEST OK" : "RIBBON SELFTEST FAILED")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }
}

extension Notification.Name {
    static let ribbonDemoChanged = Notification.Name("ScreenShot.ribbonDemoChanged")
}
#endif
