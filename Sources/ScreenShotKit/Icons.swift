import AppKit

/// The app's icon family (ROADMAP, Fase 6): one outline style on a 24 pt grid with an 18 pt live area, a 1.5 pt stroke
/// at every size, round caps and joins, 2 pt corners. The path data is the same as the design canvas's Icon component,
/// so the two never drift apart. Icons are template images (they take the button's tint); parts marked as accent keep
/// their own color, like the ink bar under the Highlighter.
enum IconName: String, CaseIterable {
    // Window chrome and title bar
    case copyImage, save, pin, drag, dragIndicator
    // Clipboard
    case paste, cut, copy, formatPainter, undo, redo
    // Font
    case growFont, shrinkFont, bold, italic, underline, strike, textOrient, changeCase
    // Paragraph
    case alignLeft, alignCenter, alignRight, justify, vTop, vMiddle, vBottom, bullets, numbering
    // Color
    case shapeFill, shapeOutline, fontFill, fontOutline, noFill, eyedropper, weight
    // Shapes
    case select, freehand, line, arrow, rect, oval, callout, counter, textbox
    // Tools
    case highlighter, blur, spotlight, magnifier, ruler, crop, ocr, areaSelect
    // Arrange
    case arrange, bringFront, sendBack, bringForward, sendBackward
    case align, alignL, alignC, alignR, alignT, alignM, alignB, distH, distV
    case rotate, rotR, rotL, flip, flipH, flipV
    // Lines and arrow heads
    case arrowHead, arrowNone, arrowEnd, arrowStart, arrowBoth, arrowFilled, arrowDot
    case lineStyle, lineSolid, lineDash, lineDot
    // Compact ribbon groups
    case gPaste, gFonts, gParagraph, gColors, gShapes, gTools, gArrange
    // Callout styles (the side bar)
    case calloutBox, calloutCard, calloutSpeech, calloutThought, calloutShout
    // Side bar choices
    case counterSquare, counterBubble, blurText, erase, eraseText
    // Status menu and Library
    case statusMark, capFull, capArea, capRepeat, capTimer, capWindow, capActive, capScroll, capScrollManual
    case openImage, guide, updates, prefs, power, search, folder, photo
    // App chrome and notifications
    case backdrop, library, info, success, warning, error, close, chev, chevR, check, more
}

/// One icon's path data: strokes, solid fills, and the strokes and fills that take the accent color.
struct IconParts {
    var stroke = ""
    var fill = ""
    var accent = ""
    var accentFill = ""
}

enum Icons {
    // MARK: Path helpers (the same as the design's)

    private static func n(_ v: CGFloat) -> String {
        let r = (v * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(Double(r))
    }
    /// A circle.
    private static func c(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> String {
        "M\(n(x - r)) \(n(y))a\(n(r)) \(n(r)) 0 1 0 \(n(2 * r)) 0a\(n(r)) \(n(r)) 0 1 0 \(n(-2 * r)) 0"
    }
    /// An ellipse.
    private static func e(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> String {
        "M\(n(x - rx)) \(n(y))a\(n(rx)) \(n(ry)) 0 1 0 \(n(2 * rx)) 0a\(n(rx)) \(n(ry)) 0 1 0 \(n(-2 * rx)) 0"
    }
    /// A rounded rectangle.
    private static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ k: CGFloat = 2) -> String {
        "M\(n(x + k)) \(n(y))h\(n(w - 2 * k))a\(n(k)) \(n(k)) 0 0 1 \(n(k)) \(n(k))v\(n(h - 2 * k))a\(n(k)) \(n(k)) 0 0 1 \(n(-k)) \(n(k))"
            + "h\(n(-(w - 2 * k)))a\(n(k)) \(n(k)) 0 0 1 \(n(-k)) \(n(-k))v\(n(-(h - 2 * k)))a\(n(k)) \(n(k)) 0 0 1 \(n(k)) \(n(-k))z"
    }
    /// A polyline through x, y pairs.
    private static func l(_ p: CGFloat...) -> String { "M" + p.map(n).joined(separator: " ") }

    private static let letterA = "M6 18l6-14 6 14M8.4 13h7.2"
    private static let ocrCorners = "M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"

    // MARK: Catalog

    static func parts(_ name: IconName) -> IconParts {
        switch name {
        // Window chrome
        case .copyImage: IconParts(stroke: r(8, 8, 12, 12, 2) + "M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" + l(10.5, 17.5, 13, 14.5, 15, 16.5, 16.5, 15, 18, 16.5))
        case .save: IconParts(stroke: l(12, 4, 12, 15) + l(7.5, 10.5, 12, 15, 16.5, 10.5) + "M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3")
        case .pin: IconParts(stroke: "M9 3.5h6M10 3.5v5.5l-3 3.5h10l-3-3.5V3.5M12 12.5v8")
        case .drag: IconParts(stroke: r(4, 4, 16, 16, 3) + l(4, 16, 8.5, 11, 12, 14.5, 14.5, 12, 20, 17), fill: "M17 8.5a1.6 1.6 0 1 1-3.2 0a1.6 1.6 0 1 1 3.2 0z")
        // Google's Material Symbols "drag_indicator" (Apache 2.0): two columns of three dots.
        case .dragIndicator: IconParts(fill: "M11 6a2 2 0 1 1-4 0a2 2 0 1 1 4 0zM11 12a2 2 0 1 1-4 0a2 2 0 1 1 4 0zM11 18a2 2 0 1 1-4 0a2 2 0 1 1 4 0zM17 6a2 2 0 1 1-4 0a2 2 0 1 1 4 0zM17 12a2 2 0 1 1-4 0a2 2 0 1 1 4 0zM17 18a2 2 0 1 1-4 0a2 2 0 1 1 4 0z")
        // Clipboard
        case .paste: IconParts(stroke: "M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2" + r(9, 3, 6, 4, 1.5) + l(9, 12, 15, 12) + l(9, 16, 13, 16))
        case .cut: IconParts(stroke: c(6.5, 17, 2.5) + c(17.5, 17, 2.5) + l(8.3, 15.2, 17, 4) + l(15.7, 15.2, 7, 4))
        case .copy: IconParts(stroke: r(8, 8, 12, 12, 2) + "M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2")
        case .formatPainter: IconParts(stroke: r(4, 3, 14, 5, 1.5) + "M18 5.5h2v5h-8v3" + r(10.5, 13.5, 3, 7, 1))
        case .undo: IconParts(stroke: "M9 14L4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11")
        case .redo: IconParts(stroke: "M15 14l5-5-5-5M20 9H9.5a5.5 5.5 0 0 0 0 11H13")
        // Font
        case .growFont: IconParts(stroke: "M3 19L8.5 5 14 19M5.2 14h6.6M16 9l2.5-3 2.5 3")
        case .shrinkFont: IconParts(stroke: "M3 19L8.5 5 14 19M5.2 14h6.6M16 6l2.5 3 2.5-3")
        case .bold: IconParts(stroke: "M7 4h6a4 4 0 0 1 0 8H7zM7 12h7a4 4 0 0 1 0 8H7z")
        case .italic: IconParts(stroke: "M10 4h8M6 20h8M14.5 4l-5 16")
        case .underline: IconParts(stroke: "M7 4v7a5 5 0 0 0 10 0V4M5 20h14")
        case .strike: IconParts(stroke: "M16.5 7.5c-.6-1.8-2.3-3-4.5-3-2.6 0-4.5 1.4-4.5 3.4 0 1.4.8 2.4 2.4 3M4 12h16M7.8 16.4c.6 1.9 2.3 3.1 4.4 3.1 2.6 0 4.6-1.4 4.6-3.5 0-.7-.2-1.3-.6-1.8")
        case .textOrient: IconParts(stroke: "M14 7L3 12l11 5M10.5 8.6v6.8M19 19V5M16.5 7.5L19 5l2.5 2.5")
        case .changeCase: IconParts(stroke: "M3 17.5l3.8-11 3.8 11M4.3 13.5h5" + c(16.5, 14.7, 2.8) + l(19.3, 11.5, 19.3, 17.5))
        // Paragraph
        case .alignLeft: IconParts(stroke: l(4, 6, 20, 6) + l(4, 10, 14, 10) + l(4, 14, 20, 14) + l(4, 18, 14, 18))
        case .alignCenter: IconParts(stroke: l(4, 6, 20, 6) + l(7, 10, 17, 10) + l(4, 14, 20, 14) + l(7, 18, 17, 18))
        case .alignRight: IconParts(stroke: l(4, 6, 20, 6) + l(10, 10, 20, 10) + l(4, 14, 20, 14) + l(10, 18, 20, 18))
        case .justify: IconParts(stroke: l(4, 6, 20, 6) + l(4, 10, 20, 10) + l(4, 14, 20, 14) + l(4, 18, 20, 18))
        case .vTop: IconParts(stroke: r(3.5, 3.5, 17, 17, 2.5) + l(7.5, 7.5, 16.5, 7.5) + l(9, 10.5, 15, 10.5))
        case .vMiddle: IconParts(stroke: r(3.5, 3.5, 17, 17, 2.5) + l(7.5, 10.5, 16.5, 10.5) + l(9, 13.5, 15, 13.5))
        case .vBottom: IconParts(stroke: r(3.5, 3.5, 17, 17, 2.5) + l(7.5, 13.5, 16.5, 13.5) + l(9, 16.5, 15, 16.5))
        case .bullets: IconParts(stroke: l(9, 6, 20, 6) + l(9, 12, 20, 12) + l(9, 18, 20, 18), fill: c(5, 6, 1.4) + c(5, 12, 1.4) + c(5, 18, 1.4))
        case .numbering: IconParts(stroke: l(10, 6, 20, 6) + l(10, 12, 20, 12) + l(10, 18, 20, 18) + "M4.5 4.8L6 4v4M4.3 10.6a1.4 1.4 0 0 1 2.6.6c0 .9-2.6 2.3-2.6 2.8h2.7M4.4 16.4h2.4l-1.4 1.5a1.3 1.3 0 1 1-1.1 2.1")
        // Color
        case .shapeFill: IconParts(stroke: "M5 11l6-6 7 7-6 6a1.4 1.4 0 0 1-2 0l-5-5a1.4 1.4 0 0 1 0-2zM8.5 2.5L11 5M5.5 12.5h12M20 14.5s1.6 2.1 1.6 3.1a1.6 1.6 0 0 1-3.2 0c0-1 1.6-3.1 1.6-3.1z")
        case .shapeOutline: IconParts(stroke: "M14.5 4.5l5 5L10 19H5v-5zM12.5 6.5l5 5")
        case .fontFill: IconParts(stroke: letterA)
        case .fontOutline: IconParts(stroke: "M5 19L10.4 5h3.2L19 19h-3.2l-1.2-3.4H9.4L8.2 19zM10.3 13h3.4L12 8.4z")
        case .noFill: IconParts(stroke: c(12, 12, 8) + l(6.3, 17.7, 17.7, 6.3))
        case .eyedropper: IconParts(stroke: "M14.5 6.5l3 3M19.5 4.5a2.1 2.1 0 0 0-3 0L14 7l3 3 2.5-2.5a2.1 2.1 0 0 0 0-3zM15.5 8.5l-9 9V20H9l9-9")
        case .weight: IconParts(stroke: l(4, 6, 20, 6), fill: r(4, 10.5, 16, 2, 1) + r(4, 16, 16, 3.5, 1.5))
        // Shapes
        case .select: IconParts(stroke: "M5.5 3.5l13 6.2-5.6 1.6-2.5 5.6z")
        case .freehand: IconParts(stroke: "M3 17c2.5-5 4.5-8.5 6.5-8.5 2.8 0-.6 8.5 2.4 8.5 1.9 0 3.6-4.6 4.8-6.6 1.3-2.3 2.8-2.7 4.3-1.9")
        case .line: IconParts(stroke: l(5, 19, 19, 5))
        case .arrow: IconParts(stroke: l(5, 19, 19, 5) + l(10, 5, 19, 5, 19, 14))
        case .rect: IconParts(stroke: r(4, 6, 16, 12, 2))
        case .oval: IconParts(stroke: e(12, 12, 8.5, 6.5))
        case .callout: IconParts(stroke: "M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-8l-4 3.5V17H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z")
        case .counter: IconParts(stroke: c(12, 12, 8.5) + "M10.5 9.5L12.5 8v8M10.5 16h4")
        case .textbox: IconParts(stroke: r(3, 4, 18, 16, 2) + "M8 9h8M12 9v7")
        // Tools
        case .highlighter: IconParts(stroke: c(5.5, 14, 2.2) + l(7.7, 11.8, 7.7, 16.2) + l(9.8, 8.5, 9.8, 16.2) + c(12, 14, 2.2)
                                        + "M15.5 10l4-4 2 2-4 4zM15.5 10l-1.3 3.3 3.3-1.3", accentFill: r(3, 19, 18, 2.5, 1))
        case .blur: IconParts(fill: c(5.5, 5.5, 1.6) + c(12, 5.5, 1.6) + c(18.5, 5.5, 1.2) + c(5.5, 12, 1.6) + c(12, 12, 1.2) + c(18.5, 12, 0.9)
                                + c(5.5, 18.5, 1.2) + c(12, 18.5, 0.9) + c(18.5, 18.5, 0.6))
        case .spotlight: IconParts(stroke: r(3, 4, 18, 16, 3) + c(12, 12, 4.5) + l(4.5, 9.5, 8.5, 5.5) + l(15.5, 18.5, 19.5, 14.5) + l(4.5, 14, 6.5, 12) + l(17.5, 12, 19.5, 10))
        case .magnifier: IconParts(stroke: c(10.5, 10.5, 6.5) + l(15.3, 15.3, 20, 20) + l(10.5, 8, 10.5, 13) + l(8, 10.5, 13, 10.5))
        case .ruler: IconParts(stroke: "M3.5 15.5l12-12 5 5-12 12z" + l(6.5, 12.5, 8.5, 14.5) + l(9, 10, 10.3, 11.3) + l(11.5, 7.5, 13.5, 9.5) + l(14, 5, 15.3, 6.3))
        case .crop: IconParts(stroke: "M6 2.5V16a2 2 0 0 0 2 2h13.5M2.5 6H16a2 2 0 0 1 2 2v13.5")
        case .ocr: IconParts(stroke: ocrCorners + l(8, 9.5, 16, 9.5) + l(8, 12.5, 16, 12.5) + l(8, 15.5, 12.5, 15.5))
        case .areaSelect: IconParts(stroke: "M4 7V5a1 1 0 0 1 1-1h2M11 4h2M17 4h2a1 1 0 0 1 1 1v2M20 11v2M20 17v2a1 1 0 0 1-1 1h-2M13 20h-2M7 20H5a1 1 0 0 1-1-1v-2M4 13v-2"
                                       + l(8, 16, 11, 12.5, 13, 14.5, 14.5, 13, 16, 15), fill: c(15, 9, 1.2))
        // Arrange
        case .arrange: IconParts(stroke: "M12 3l9 4.5-9 4.5-9-4.5zM3 12l9 4.5 9-4.5M3 16.5L12 21l9-4.5")
        case .bringFront: IconParts(stroke: "M15 9V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h3", fill: r(9, 9, 11, 11, 2))
        case .sendBack: IconParts(stroke: r(9, 9, 11, 11, 2), fill: "M4 6a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v3H9v6H6a2 2 0 0 1-2-2z")
        case .bringForward: IconParts(stroke: r(3, 8, 12, 12, 2) + "M18.5 16V4M15.5 7l3-3 3 3")
        case .sendBackward: IconParts(stroke: r(3, 4, 12, 12, 2) + "M18.5 8v12M15.5 17l3 3 3-3")
        case .align, .alignL: IconParts(stroke: l(4, 3, 4, 21) + r(7, 6, 13, 4, 1.5) + r(7, 14, 8, 4, 1.5))
        case .alignC: IconParts(stroke: l(12, 3, 12, 6) + l(12, 10, 12, 14) + l(12, 18, 12, 21) + r(5, 6, 14, 4, 1.5) + r(8, 14, 8, 4, 1.5))
        case .alignR: IconParts(stroke: l(20, 3, 20, 21) + r(4, 6, 13, 4, 1.5) + r(9, 14, 8, 4, 1.5))
        case .alignT: IconParts(stroke: l(3, 4, 21, 4) + r(6, 7, 4, 13, 1.5) + r(14, 7, 4, 8, 1.5))
        case .alignM: IconParts(stroke: l(3, 12, 6, 12) + l(10, 12, 14, 12) + l(18, 12, 21, 12) + r(6, 5, 4, 14, 1.5) + r(14, 8, 4, 8, 1.5))
        case .alignB: IconParts(stroke: l(3, 20, 21, 20) + r(6, 4, 4, 13, 1.5) + r(14, 9, 4, 8, 1.5))
        case .distH: IconParts(stroke: l(4, 3, 4, 21) + l(20, 3, 20, 21) + r(9.5, 7, 5, 10, 1.5))
        case .distV: IconParts(stroke: l(3, 4, 21, 4) + l(3, 20, 21, 20) + r(7, 9.5, 10, 5, 1.5))
        case .rotate: IconParts(stroke: "M20 12a8 8 0 1 1-2.3-5.7M20 4v4.5h-4.5")
        case .rotR: IconParts(stroke: r(4, 11, 9, 9, 1.5) + "M8.5 7.5A7 7 0 0 1 19 11M16.6 10.2l2.4 1.3 1.3-2.6")
        case .rotL: IconParts(stroke: r(11, 11, 9, 9, 1.5) + "M15.5 7.5A7 7 0 0 0 5 11M7.4 10.2L5 11.5 3.7 8.9")
        case .flip, .flipH: IconParts(stroke: "M12 3v2M12 8v2M12 13v2M12 18v3M9 6.5L3 18h6zM15 6.5L21 18h-6z")
        case .flipV: IconParts(stroke: "M3 12h2M8 12h2M13 12h2M18 12h3M6.5 9L18 3v6zM6.5 15L18 21v-6z")
        // Lines and arrow heads
        case .arrowHead, .arrowEnd: IconParts(stroke: "M4 12h15M14 7l5 5-5 5")
        case .arrowNone: IconParts(stroke: l(4, 12, 20, 12))
        case .arrowStart: IconParts(stroke: "M5 12h15M10 7l-5 5 5 5")
        case .arrowBoth: IconParts(stroke: "M5 12h14M9 7l-5 5 5 5M15 7l5 5-5 5")
        case .arrowFilled: IconParts(stroke: "M4 12h11", fill: "M13.5 6.8L21 12l-7.5 5.2z")
        case .arrowDot: IconParts(stroke: "M4 12h12", fill: c(18, 12, 2.6))
        case .lineStyle: IconParts(stroke: l(3, 6, 21, 6) + "M3 12h4M10 12h4M17 12h4M3 18h.01M7.5 18h.01M12 18h.01M16.5 18h.01M21 18h.01")
        case .lineSolid: IconParts(stroke: l(3, 12, 21, 12))
        case .lineDash: IconParts(stroke: "M3 12h4M10 12h4M17 12h4")
        case .lineDot: IconParts(stroke: "M3 12h.01M7.5 12h.01M12 12h.01M16.5 12h.01M21 12h.01")
        // Compact ribbon groups
        case .gPaste: IconParts(stroke: "M8.5 4.5h-2a2 2 0 0 0-2 2V19a2 2 0 0 0 2 2H10M15.5 4.5h2a2 2 0 0 1 2 2V9" + r(8.5, 3, 7, 3.5, 1.25) + r(12.5, 12, 9, 9, 2) + l(14.5, 18.5, 16.5, 16, 19.5, 18.5))
        case .gFonts: IconParts(stroke: "M3 18l5-13 5 13M4.9 13.5h6.2" + c(17.5, 15.5, 2.5) + l(20, 12, 20, 18))
        case .gParagraph: IconParts(stroke: "M17 4h-7a4 4 0 0 0 0 8h3M13 4v16M17 4v16")
        case .gColors: IconParts(stroke: c(9, 9, 5) + c(15, 9, 5) + c(12, 14.5, 5))
        case .gShapes: IconParts(stroke: r(3, 3, 8, 8, 1.5) + c(17, 7, 4) + "M12 13.5l5 7.5H7z")
        case .gTools: IconParts(stroke: l(4, 20, 13.5, 10.5) + l(11.5, 9.5, 14.5, 12.5) + "M17 3v4M15 5h4M20 10v3M18.5 11.5h3M10 3.5v2M9 4.5h2")
        case .gArrange: IconParts(stroke: r(3, 3, 11, 11, 2) + "M10 14v4a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-4")
        // Callout styles
        case .calloutBox: IconParts(stroke: r(3, 4, 18, 12, 1.5) + l(8, 16, 5, 20.5))
        case .calloutCard: IconParts(stroke: r(3, 4, 18, 12, 3.5) + "M9 16l-1.5 4.5 5-4.5")
        case .calloutSpeech: IconParts(stroke: "M7 4h10a4 4 0 0 1 4 4v4a4 4 0 0 1-4 4h-6l-4 4v-4a4 4 0 0 1-4-4V8a4 4 0 0 1 4-4z")
        case .calloutThought: IconParts(stroke: e(12, 10, 9, 6) + c(7, 18.5, 1.5) + c(4.5, 21, 1))
        case .calloutShout: IconParts(stroke: "M12 2.5l2 4.2 4.5-2.2-1.2 4.8 4.7 1.2-4.2 2.6 2.5 4.2-4.8-.6L14.5 21 12 17.2 9.5 21l-1-4.3-4.8.6 2.5-4.2L2 10.5l4.7-1.2-1.2-4.8 4.5 2.2z")
        // Side bar choices
        case .counterSquare: IconParts(stroke: r(3.5, 3.5, 17, 17, 3) + "M10.5 9.5L12.5 8v8M10.5 16h4")
        case .counterBubble: IconParts(stroke: "M12.5 3.5a7.5 7.5 0 1 1-3.6 14.1L4 19.5l1.9-4.6A7.5 7.5 0 0 1 12.5 3.5z" + "M11 8.5L13 7v8M11 15h4")
        case .blurText: IconParts(stroke: l(4, 18.5, 20, 18.5), fill: r(4, 5, 3.5, 3.5, 0.6) + r(8.5, 5, 3.5, 3.5, 0.6) + r(13, 5, 3.5, 3.5, 0.6) + r(17.5, 5, 2.5, 3.5, 0.6)
                                    + r(4, 10.5, 3.5, 3.5, 0.6) + r(8.5, 10.5, 3.5, 3.5, 0.6) + r(13, 10.5, 2.5, 3.5, 0.6))
        case .erase: IconParts(stroke: "M14 4.5l5.5 5.5-9.5 9.5H6.5l-3-3a1.5 1.5 0 0 1 0-2.1zM8.5 10l5.5 5.5" + l(10.5, 19.5, 20.5, 19.5))
        case .eraseText: IconParts(stroke: l(4, 6, 20, 6) + l(4, 11, 12, 11) + l(4, 16, 9, 16), fill: r(13.5, 9, 7, 11, 1.5))
        // Status menu and Library
        case .statusMark: IconParts(stroke: ocrCorners + c(12, 12, 3.5))
        case .capFull: IconParts(stroke: r(2.5, 4, 19, 13, 2) + l(9, 20.5, 15, 20.5) + "M7 9.5V8h2M17 9.5V8h-2M7 11.5V13h2M17 11.5V13h-2")
        case .capArea: IconParts(stroke: "M4 7V4h3M10 4h4M17 4h3v3M20 10v4M20 17v3h-3M14 20h-4M7 20H4v-3M4 14v-4" + l(12, 9.5, 12, 14.5) + l(9.5, 12, 14.5, 12))
        case .capRepeat: IconParts(stroke: "M18.5 12a6.5 6.5 0 1 1-1.9-4.6M17 3.5V7.4h-3.9" + r(9.5, 9.5, 5, 5, 1))
        case .capTimer: IconParts(stroke: c(12, 13, 7.5) + l(12, 9, 12, 13, 14.5, 15.5) + l(10, 3, 14, 3) + l(18.5, 6, 19.8, 4.7))
        case .capWindow: IconParts(stroke: r(3, 4.5, 18, 15, 2.5) + l(3, 8.5, 21, 8.5), fill: c(5.8, 6.5, 0.7) + c(8, 6.5, 0.7))
        case .capActive: IconParts(stroke: r(3, 4.5, 14, 12, 2) + l(3, 8, 17, 8), fill: "M14 13l7 2.6-3.1 1.3-1.3 3.1z")
        case .capScroll: IconParts(stroke: r(6, 3, 12, 18, 2.5) + l(12, 8, 12, 16) + l(9.5, 13.5, 12, 16, 14.5, 13.5) + l(9.5, 10.5, 12, 8, 14.5, 10.5))
        case .capScrollManual: IconParts(stroke: r(3, 3, 11, 16, 2) + l(6, 7, 11, 7) + l(6, 10, 11, 10) + r(15, 11, 6, 10, 3) + l(18, 13.5, 18, 15.5))
        case .openImage: IconParts(stroke: r(3, 4, 18, 16, 2) + l(3, 16, 8, 11, 12, 15, 15, 12, 21, 18) + c(16, 8.5, 1.5))
        case .guide: IconParts(stroke: c(12, 12, 9) + "M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.6v.6", fill: c(12, 17, 1))
        case .updates: IconParts(stroke: "M20 12a8 8 0 0 1-14.5 4.6M4 12a8 8 0 0 1 14.5-4.6M18.5 3.5v4h-4M5.5 20.5v-4h4")
        case .prefs: IconParts(stroke: l(4, 7, 6.8, 7) + l(11.2, 7, 20, 7) + c(9, 7, 2.2) + l(4, 17, 12.8, 17) + l(17.2, 17, 20, 17) + c(15, 17, 2.2))
        case .power: IconParts(stroke: "M12 3v8M7 6a7.5 7.5 0 1 0 10 0")
        case .search: IconParts(stroke: c(10.5, 10.5, 6) + l(15, 15, 20, 20))
        case .folder: IconParts(stroke: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z")
        case .photo: IconParts(stroke: r(3.5, 5, 17, 14, 2) + l(3.5, 15, 8, 11, 12, 14.5, 15, 12, 20.5, 17) + c(15.5, 9, 1.3))
        // App chrome and notifications
        case .backdrop: IconParts(stroke: r(2.5, 4.5, 19, 15, 3) + r(6.5, 8.5, 11, 7, 1.5))
        case .library: IconParts(stroke: r(3.5, 3.5, 7, 7, 1.5) + r(13.5, 3.5, 7, 7, 1.5) + r(3.5, 13.5, 7, 7, 1.5) + r(13.5, 13.5, 7, 7, 1.5))
        case .info: IconParts(stroke: c(12, 12, 9) + l(12, 11, 12, 16.5), fill: c(12, 7.9, 1.1))
        case .success: IconParts(stroke: c(12, 12, 9) + "M8 12.5l2.7 2.7L16 9.5")
        case .warning: IconParts(stroke: "M10.3 4.2L2.8 17.5a2 2 0 0 0 1.7 3h15a2 2 0 0 0 1.7-3L13.7 4.2a2 2 0 0 0-3.4 0z" + l(12, 9.5, 12, 13.5), fill: c(12, 16.8, 1.1))
        case .error: IconParts(stroke: c(12, 12, 9) + l(9, 9, 15, 15) + l(15, 9, 9, 15))
        case .close: IconParts(stroke: l(6, 6, 18, 18) + l(18, 6, 6, 18))
        case .chev: IconParts(stroke: "M6 9.5l6 6 6-6")
        case .chevR: IconParts(stroke: "M9.5 6l6 6-6 6")
        case .check: IconParts(stroke: "M5 12.5l4.5 4.5L19 7.5")
        case .more: IconParts(stroke: "M5 12h.01M12 12h.01M19 12h.01")
        }
    }

    /// The accent parts' default color (the Highlighter's ink bar).
    static let defaultAccent: [IconName: NSColor] = [.highlighter: NSColor(srgb: 0xFFD60AFF)]

    // MARK: Paths and images

    /// The icon's paths on its 24 pt grid (y down). Cached; path data is checked by the tests, so a bad path is a bug.
    static func paths(_ name: IconName) -> (stroke: CGPath, fill: CGPath, accent: CGPath, accentFill: CGPath) {
        lock.lock(); defer { lock.unlock() }
        if let p = pathCache[name] { return p }
        let p = parts(name)
        func parse(_ d: String) -> CGPath { (try? SVGPath.parse(d)) ?? CGMutablePath() }
        let result = (parse(p.stroke), parse(p.fill), parse(p.accent), parse(p.accentFill))
        pathCache[name] = result
        return result
    }

    /// The icon at `size` points. With no `color` it is a template image that takes its button's tint; accent parts
    /// (if any) are drawn in `accent`, or the icon's default accent, and then the image is not a template.
    static func image(_ name: IconName, size: CGFloat = 16, color: NSColor? = nil, accent: NSColor? = nil,
                      stroke: CGFloat? = nil) -> NSImage {
        let p = paths(name)
        let hasAccent = !p.accent.isEmpty || !p.accentFill.isEmpty
        let accentColor = accent ?? defaultAccent[name]
        let lineWidth = stroke ?? (name == .chev || name == .chevR ? 1.75 : DesignTokens.Metrics.iconStroke)
        let template = color == nil && !(hasAccent && accentColor != nil)
        // A colored accent rules out a template image, so the rest takes the icon ink (resolved when drawn).
        let baseInk = color ?? (template ? .black : DesignTokens.color(.ink2))
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let k = size / DesignTokens.Metrics.iconGrid
            var t = CGAffineTransform(scaleX: k, y: k)
            let ink = baseInk.cgColor
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(lineWidth)
            if let s = p.stroke.copy(using: &t), !s.isEmpty {
                ctx.addPath(s); ctx.setStrokeColor(ink); ctx.strokePath()
            }
            if let f = p.fill.copy(using: &t), !f.isEmpty {
                ctx.addPath(f); ctx.setFillColor(ink); ctx.fillPath()
            }
            let acc = (accentColor ?? color ?? .black).cgColor
            if let a = p.accent.copy(using: &t), !a.isEmpty {
                ctx.addPath(a); ctx.setStrokeColor(acc); ctx.strokePath()
            }
            if let a = p.accentFill.copy(using: &t), !a.isEmpty {
                ctx.addPath(a); ctx.setFillColor(acc); ctx.fillPath()
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = name.rawValue
        return image
    }

    /// Behind `lock`.
    nonisolated(unsafe) private static var pathCache: [IconName: (stroke: CGPath, fill: CGPath, accent: CGPath, accentFill: CGPath)] = [:]
    private static let lock = NSLock()
}
