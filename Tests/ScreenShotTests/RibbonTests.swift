import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Ribbon layout")
struct RibbonLayoutTests {
    /// The design's group widths: Clipboard, Font, Paragraph, Color, Shapes, Tools, Arrange.
    let full: [CGFloat] = [176, 252, 98, 98, 164, 134, 242]

    @Test("everything fits: nothing folds") func allFit() {
        let need = RibbonLayout.width(full: full, collapsed: 0)
        #expect(need == full.reduce(0, +) + 6) // six dividers
        #expect(RibbonLayout.collapsedCount(available: need, full: full) == 0)
        #expect(RibbonLayout.collapsedCount(available: 5000, full: full) == 0)
    }

    @Test("one point short folds the last group only") func foldsFromTheRight() {
        let need = RibbonLayout.width(full: full, collapsed: 0)
        #expect(RibbonLayout.collapsedCount(available: need - 1, full: full) == 1)
    }

    @Test("groups fold one at a time as the room shrinks") func progressive() {
        let bp = RibbonLayout.breakpoints(full: full)
        #expect(bp.count == full.count + 1)
        #expect(zip(bp, bp.dropFirst()).allSatisfy { $0 > $1 }, "each fold needs less room: \(bp)")
        for c in 0..<bp.count {
            #expect(RibbonLayout.collapsedCount(available: bp[c], full: full) == c)
        }
        #expect(bp.last == CGFloat(full.count) * RibbonLayout.compactWidth)
        #expect(RibbonLayout.collapsedCount(available: 10, full: full) == full.count, "all folded when even that doesn't fit")
    }
}

@Suite("Ribbon views") @MainActor
struct RibbonViewTests {
    func makeGroups(activeTool: Bool = true) -> (groups: [RibbonGroup], tool: RibbonItem, bold: RibbonItem) {
        let bold = RibbonItem("bold", kind: .small, title: "Bold", icon: .bold)
        let tool = RibbonItem("arrow", kind: .small, title: "Arrow", icon: .arrow)
        tool.isActiveTool = activeTool
        let g1 = RibbonGroup("clipboard", title: "Clipboard", compactTitle: "Paste", compactIcon: .gPaste, columns: [
            .large(RibbonItem("paste", kind: .large, title: "Paste", icon: .paste)),
            .rows([[.item(RibbonItem("cut", kind: .label, title: "Cut", icon: .cut))], [.item(RibbonItem("copy", kind: .label, title: "Copy", icon: .copy))]]),
        ])
        let g2 = RibbonGroup("font", title: "Font", compactTitle: "Fonts", compactIcon: .gFonts, columns: [
            .rows([[.item(RibbonItem("family", kind: .field(width: 124), title: "Font", text: "SF Pro Text"))], [.item(bold), .divider]]),
        ])
        let g3 = RibbonGroup("shapes", title: "Shapes", compactTitle: "Shapes", compactIcon: .gShapes, columns: [
            .rows([[.item(RibbonItem("select", kind: .small, title: "Select", icon: .select)), .item(tool)]]),
        ])
        return ([g1, g2, g3], tool, bold)
    }

    @Test("a wide ribbon shows every group; a narrow one folds from the right") func folding() {
        let (groups, _, _) = makeGroups()
        let ribbon = RibbonView(groups: groups)
        ribbon.frame.size.width = 2000
        ribbon.layout()
        #expect(ribbon.collapsedCount == 0)
        #expect(groups.allSatisfy { !ribbon.isCompact($0) })

        ribbon.frame.size.width = ribbon.breakpoints[0] - 1
        ribbon.layout()
        #expect(ribbon.collapsedCount == 1)
        #expect(ribbon.isCompact(groups[2]) && !ribbon.isCompact(groups[1]) && !ribbon.isCompact(groups[0]))

        ribbon.frame.size.width = 100
        ribbon.layout()
        #expect(groups.allSatisfy { ribbon.isCompact($0) })
    }

    @Test("a folded group still shows the tool in hand") func activeToolStaysVisible() {
        let (groups, tool, _) = makeGroups()
        let ribbon = RibbonView(groups: groups)
        let shapes = ribbon.compactButton(for: groups[2])!
        #expect(shapes.showsActiveTool && shapes.displayIcon == .arrow)
        #expect(shapes.accessibilityLabel() == "Shapes, active tool: Arrow")
        tool.isActiveTool = false
        #expect(!shapes.showsActiveTool && shapes.displayIcon == .gShapes)
        #expect(ribbon.compactButton(for: groups[0])?.displayIcon == .gPaste)
    }

    @Test("the group and its flyout show the same item") func sharedItems() {
        let (groups, _, bold) = makeGroups()
        let inGroup = RibbonGroupView(groups[1]).buttons.first { $0.item.id == "bold" }!
        let inFlyout = RibbonFlyout(group: groups[1]).groupView.buttons.first { $0.item.id == "bold" }!
        #expect(inGroup.item === inFlyout.item)
        bold.isOn = true
        #expect(inGroup.accessibilityValue() as? String == "on" && inFlyout.accessibilityValue() as? String == "on")
    }

    @Test("group sizes: two 28 pt rows, a large button, the title fits") func groupLayout() {
        let (groups, _, _) = makeGroups()
        let clipboard = RibbonGroupView(groups[0])
        #expect(clipboard.frame.height == DesignTokens.Metrics.ribbonHeight)
        let paste = clipboard.buttons.first { $0.item.id == "paste" }!
        #expect(paste.frame.height == 62 && paste.frame.width >= 52)
        let cut = clipboard.buttons.first { $0.item.id == "cut" }!
        #expect(cut.frame.height == 28 && cut.frame.minX > paste.frame.maxX)
        let font = RibbonGroupView(groups[1])
        #expect(font.buttons.first { $0.item.id == "family" }?.frame.width == 124)
    }

    @Test func buttonWidths() {
        #expect(RibbonButton.width(for: RibbonItem("a", kind: .small, title: "A", icon: .bold)) == 28)
        #expect(RibbonButton.width(for: RibbonItem("a", kind: .small, title: "A", icon: .bold, menu: { NSMenu() })) == 40)
        #expect(RibbonButton.width(for: RibbonItem("a", kind: .color, title: "A", icon: .shapeFill)) == 40)
        #expect(RibbonButton.width(for: RibbonItem("a", kind: .large, title: "Paste", icon: .paste)) == 52)
        let long = RibbonButton.width(for: RibbonItem("a", kind: .label, title: "Copy Format", icon: .copy))
        let short = RibbonButton.width(for: RibbonItem("a", kind: .label, title: "Cut", icon: .cut))
        #expect(long > short && short > 28)
    }

    @Test("a click runs the action; a split button's chevron opens its menu; disabled does nothing") func clicks() {
        var ran = 0, menus: [String] = []
        let saved = RibbonButton.presentMenu
        RibbonButton.presentMenu = { m, _ in menus.append(m.title) }
        defer { RibbonButton.presentMenu = saved }

        let split = RibbonItem("fill", kind: .color, title: "Shape Fill", icon: .shapeFill, action: { ran += 1 }, menu: { NSMenu(title: "palette") }, split: true)
        let b = RibbonButton(split)
        b.frame = CGRect(x: 0, y: 0, width: 40, height: 28)
        b.activate(at: CGPoint(x: 8, y: 14))
        #expect(ran == 1 && menus.isEmpty)
        b.activate(at: CGPoint(x: 36, y: 14))
        #expect(ran == 1 && menus == ["palette"])

        let menuOnly = RibbonButton(RibbonItem("align", kind: .label, title: "Align", icon: .align, action: { ran += 1 }, menu: { NSMenu(title: "align") }))
        menuOnly.frame = CGRect(x: 0, y: 0, width: 80, height: 28)
        menuOnly.activate(at: CGPoint(x: 10, y: 10))
        #expect(menus == ["palette", "align"] && ran == 1)
        #expect(menuOnly.accessibilityRole() == .popUpButton && b.accessibilityRole() == .button)

        split.isEnabled = false
        b.activate(at: CGPoint(x: 8, y: 14))
        #expect(ran == 1 && !b.isAccessibilityEnabled())
    }

    @Test("VoiceOver hears names, values and the selected tool") func accessibility() {
        let (groups, tool, bold) = makeGroups()
        let v = RibbonGroupView(groups[1])
        #expect(v.accessibilityRole() == .group && v.accessibilityLabel() == "Font")
        #expect(v.buttons.first { $0.item.id == "family" }?.accessibilityValue() as? String == "SF Pro Text")
        bold.isOn = false
        #expect(RibbonButton(bold).accessibilityValue() == nil)
        #expect(RibbonButton(tool).accessibilityValue() as? String == "selected")
    }

    @Test("Tooltips survive tracking-area updates (\"Counter (C)\")")
    func tooltipsSurviveTrackingUpdates() {
        let item = RibbonItem("counter", kind: .small, title: "Counter", icon: .counter)
        item.shortcut = "C"
        let b = RibbonButton(item)
        b.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        host.addSubview(b)
        b.updateTrackingAreas()
        b.updateTrackingAreas()
        #expect(b.toolTip == "Counter (C)")
        #expect(b.trackingAreas.contains { $0.owner.map { NSStringFromClass(type(of: $0)) } == "NSToolTipManager" },
                "the tooltip's tracking area is kept")
        #expect(b.trackingAreas.filter { $0.owner === b }.count == 1, "one hover area, not one more per update")
    }
}
