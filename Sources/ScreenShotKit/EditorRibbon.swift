import AppKit

/// The editor's ribbon (ROADMAP, Fase 6): Clipboard, Font, Paragraph, Color, Shapes,
/// Tools and Arrange, all wired to the editor's commands (each tool's own options are in the side bar); plus the title
/// bar's commands (Copy image, Save, Pin, Undo, Redo).
@MainActor final class EditorRibbon {
    let view: RibbonView
    let groups: [RibbonGroup]
    /// Font, Paragraph, Color, Arrange and the contextual groups.
    let formatting: RibbonFormatting
    private weak var editor: EditorWindowController?
    private var toolItems: [Tool: RibbonItem] = [:]

    // Clipboard
    let paste: RibbonItem, cut: RibbonItem, copy: RibbonItem, format: RibbonItem
    // Tools without a Tool of their own
    let ocr: RibbonItem, areaSelect: RibbonItem
    // Title bar
    let copyImage: RibbonItem, save: RibbonItem, pin: RibbonItem, undo: RibbonItem, redo: RibbonItem

    /// The ribbon's tools, in the design's order, with their icons.
    static let shapeTools: [(Tool, IconName)] = [(.select, .select), (.freehand, .freehand), (.line, .line), (.arrow, .arrow), (.rect, .rect),
                                                  (.oval, .oval), (.callout, .callout), (.counter, .counter), (.text, .textbox)]
    static let effectTools: [(Tool, IconName)] = [(.highlighter, .highlighter), (.blur, .blur), (.spotlight, .spotlight), (.magnifier, .magnifier),
                                                   (.ruler, .ruler), (.crop, .crop)]

    init(editor: EditorWindowController) {
        self.editor = editor
        let send: (Selector) -> () -> Void = { [weak editor] sel in
            { guard let v = editor?.shotView else { return }; v.window?.makeFirstResponder(v); NSApp.sendAction(sel, to: v, from: nil) }
        }
        paste = RibbonItem("paste", kind: .large, title: "Paste", icon: .paste, action: send(#selector(ShotView.paste(_:))))
        paste.shortcut = "⌘V"
        cut = RibbonItem("cut", kind: .label, title: "Cut", icon: .cut, action: send(#selector(ShotView.cut(_:))))
        cut.shortcut = "⌘X"
        copy = RibbonItem("copy", kind: .label, title: "Copy", icon: .copy, action: send(#selector(ShotView.copy(_:))))
        copy.shortcut = "⌘C"
        format = RibbonItem("format", kind: .label, title: "Format", icon: .formatPainter)
        format.action = { [weak editor] in editor?.shotView.startFormatPainter() }
        ocr = RibbonItem("ocr", kind: .small, title: "Recognize Text or QR", icon: .ocr, action: { [weak editor] in editor?.ocrImage() })
        ocr.shortcut = "⌘O"
        areaSelect = RibbonItem("areaSelect", kind: .small, title: "Image Area Selection", icon: .areaSelect)
        areaSelect.action = { [weak editor] in
            guard let v = editor?.shotView else { return }
            v.beginAreaSelection()
            v.window?.makeFirstResponder(v)
        }
        copyImage = RibbonItem("copyImage", kind: .small, title: Settings.closeAfterCopySave ? "Copy and Close" : "Copy Full Image", icon: .copyImage,
                               action: { [weak editor] in editor?.copyFromTitleCard() })
        if !Settings.closeAfterCopySave { copyImage.shortcut = "⌘C" } // ⌘C copies without closing
        save = RibbonItem("save", kind: .small, title: Settings.closeAfterCopySave ? "Save and Close" : "Save Image", icon: .save,
                          action: { [weak editor] in editor?.saveFromTitleCard() })
        if !Settings.closeAfterCopySave { save.shortcut = "⌘S" }
        pin = RibbonItem("pin", kind: .small, title: "Pin to Screen", icon: .pin, action: { [weak editor] in editor?.pinImage() })
        pin.shortcut = "⌘P"
        undo = RibbonItem("undo", kind: .small, title: "Undo", icon: .undo, action: send(#selector(ShotView.undo(_:))))
        undo.shortcut = "⌘Z"
        redo = RibbonItem("redo", kind: .small, title: "Redo", icon: .redo, action: send(#selector(ShotView.redo(_:))))
        redo.shortcut = "⇧⌘Z"

        var tools: [Tool: RibbonItem] = [:]
        func tool(_ t: Tool, _ icon: IconName) -> RibbonElement {
            let item = RibbonItem(t.rawValue, kind: .small, title: t == .text ? "Text Box" : t.title, icon: icon,
                                  action: { [weak editor] in editor?.pickTool(t) })
            item.shortcut = t.key.uppercased()
            tools[t] = item
            return .item(item)
        }
        let s = Self.shapeTools.map { tool($0.0, $0.1) }
        let e = Self.effectTools.map { tool($0.0, $0.1) }
        toolItems = tools

        formatting = RibbonFormatting(editor: editor, controller: editor.formatting)
        groups = [
            RibbonGroup("clipboard", title: "Clipboard", compactTitle: "Paste", compactIcon: .gPaste, columns: [
                .large(paste),
                .rows([[.item(cut)], [.item(copy)], [.item(format)]]),
            ]),
            formatting.fontGroup, formatting.paragraphGroup, formatting.colorGroup,
            RibbonGroup("shapes", title: "Shapes", compactTitle: "Shapes", compactIcon: .gShapes, columns: [
                .rows([Array(s.prefix(5)), Array(s.suffix(4))]),
            ]),
            RibbonGroup("tools", title: "Tools", compactTitle: "Tools", compactIcon: .gTools, columns: [
                .rows([Array(e.prefix(4)), Array(e.suffix(2)) + [.item(ocr), .item(areaSelect)]]),
            ]),
            formatting.arrangeGroup,
        ]
        view = RibbonView(groups: groups)
    }

    typealias RibbonElement = RibbonRowElement

    func item(for tool: Tool) -> RibbonItem? { toolItems[tool] }

    /// Follows the tool in hand, the selection and what the clipboard holds.
    func update(tool: Tool, hasSelection: Bool, canUndo: Bool, canRedo: Bool) {
        let area = formatting.selectingArea
        for (t, item) in toolItems { item.isActiveTool = t == tool && !(t == .crop && area) }
        areaSelect.isActiveTool = tool == .crop && area
        cut.isEnabled = hasSelection
        format.isEnabled = formatting.canCopyFormat
        format.isOn = formatting.paintingFormat
        let types = NSPasteboard.general.types ?? []
        paste.isEnabled = types.contains(ShotView.objectPasteboardType) || types.contains(.png) || types.contains(.tiff)
        updateHistory(canUndo: canUndo, canRedo: canRedo)
        formatting.update()
    }

    func updateHistory(canUndo: Bool, canRedo: Bool) {
        undo.isEnabled = canUndo
        redo.isEnabled = canRedo
    }

    /// A row of title-bar buttons, drawn like the ribbon's small buttons.
    static func titleBarGroup(_ items: [RibbonItem]) -> NSView {
        let width = items.map(RibbonButton.width(for:)).reduce(0, +) + CGFloat(max(0, items.count - 1)) * 2
        let row = TitleBarRow(frame: CGRect(x: 0, y: 0, width: width, height: DesignTokens.Metrics.smallButton))
        var x: CGFloat = 0
        for item in items {
            let b = RibbonButton(item)
            let w = RibbonButton.width(for: item)
            b.frame = CGRect(x: x, y: 0, width: w, height: DesignTokens.Metrics.smallButton)
            row.addSubview(b)
            x += w + 2
        }
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        return row
    }

    private final class TitleBarRow: NSView {
        override var isFlipped: Bool { true }
        override var intrinsicContentSize: NSSize { frame.size }
    }
}
