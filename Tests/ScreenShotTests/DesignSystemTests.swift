import AppKit
import Testing
@testable import ScreenShotKit

@Suite("SVG path data")
struct SVGPathTests {
    func box(_ d: String) throws -> CGRect { try SVGPath.parse(d).boundingBoxOfPath }
    func near(_ a: CGRect, _ b: CGRect, _ tol: CGFloat = 0.01) -> Bool {
        abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
    }

    @Test func linesAndRelativeCommands() throws {
        #expect(near(try box("M4 12h15"), CGRect(x: 4, y: 12, width: 15, height: 0)))
        #expect(near(try box("M14 7l5 5-5 5"), CGRect(x: 14, y: 7, width: 5, height: 10)))
        #expect(near(try box("M2 2H10V8L2 8z"), CGRect(x: 2, y: 2, width: 8, height: 6)))
    }

    @Test("numbers after a moveto are linetos") func implicitLineto() throws {
        #expect(near(try box("M0 0 10 0 10 10"), CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(near(try box("m1 1 4 0 0 4"), CGRect(x: 1, y: 1, width: 4, height: 4)))
    }

    @Test("compact numbers: -.6, 1.5.8, exponents") func compactNumbers() throws {
        #expect(near(try box("M1.5.8l-.6-1e1"), CGRect(x: 0.9, y: -9.2, width: 0.6, height: 10)))
        #expect(near(try box("M0,0L3-4"), CGRect(x: 0, y: -4, width: 3, height: 4)))
    }

    @Test("a circle drawn with two arcs fills its square") func arcs() throws {
        #expect(near(try box("M4 12a8 8 0 1 0 16 0a8 8 0 1 0-16 0"), CGRect(x: 4, y: 4, width: 16, height: 16), 0.05))
        // Flags packed against the next number.
        #expect(near(try box("M0 0a5 5 0 015 5"), CGRect(x: 0, y: 0, width: 5, height: 5), 0.05))
        // An ellipse.
        #expect(near(try box("M3.5 12a8.5 6.5 0 1 0 17 0a8.5 6.5 0 1 0-17 0"), CGRect(x: 3.5, y: 5.5, width: 17, height: 13), 0.05))
    }

    @Test("curves, including reflected controls") func curves() throws {
        _ = try SVGPath.parse("M0 0C1 2 3 4 5 6S9 10 11 12Q13 14 15 16T19 20c1 1 2 2 3 3s1 1 2 2q1 1 2 2t2 2")
        #expect(near(try box("M0 0Q5 10 10 0"), CGRect(x: 0, y: 0, width: 10, height: 5), 0.05))
    }

    @Test("bad data is an error, not a silent blank") func errors() {
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("X0 0") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("12 4") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0 0a5 5 0 2 1 5 5") }
    }
}

@Suite("Icon family")
struct IconTests {
    @Test("every icon's path data parses and draws something", arguments: IconName.allCases)
    func parses(_ name: IconName) throws {
        let p = Icons.parts(name)
        var nonEmpty = false
        for d in [p.stroke, p.fill, p.accent, p.accentFill] where !d.isEmpty {
            let path = try SVGPath.parse(d)
            #expect(!path.isEmpty, "\(name.rawValue)")
            nonEmpty = true
        }
        #expect(nonEmpty, "\(name.rawValue) has no paths")
    }

    @Test("every icon stays on its 24 pt grid", arguments: IconName.allCases)
    func onGrid(_ name: IconName) {
        let p = Icons.paths(name)
        let all = [p.stroke, p.fill, p.accent, p.accentFill].filter { !$0.isEmpty }.map(\.boundingBoxOfPath)
        let bounds = all.dropFirst().reduce(all[0]) { $0.union($1) }
        // The live area is 3…21; a stroke's half-width and the odd overhang (crop marks, the window's title bar) stay
        // well inside the grid.
        #expect(bounds.minX >= 1 && bounds.minY >= 1 && bounds.maxX <= 23 && bounds.maxY <= 23, "\(name.rawValue): \(bounds)")
    }

    @Test("icons render ink at small sizes") func renders() throws {
        for name in [IconName.bold, .arrow, .blur, .gShapes, .highlighter, .statusMark] {
            let img = Icons.image(name, size: 16, color: .black)
            let tiff = try #require(img.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            var inked = 0
            for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 { inked += 1 } }
            #expect(inked > 8, "\(name.rawValue) drew \(inked) pixels")
        }
    }

    @Test("template images take their button's tint; accent parts keep their color") func templates() {
        #expect(Icons.image(.bold).isTemplate)
        #expect(!Icons.image(.bold, color: .red).isTemplate)
        #expect(!Icons.image(.highlighter).isTemplate, "the Highlighter's yellow bar keeps its color")
    }

    @Test("the ribbon has an icon for every tool") func everyTool() {
        let mapped: [Tool: IconName] = [.select: .select, .arrow: .arrow, .rect: .rect, .oval: .oval, .line: .line, .freehand: .freehand,
                                        .text: .textbox, .highlighter: .highlighter, .blur: .blur, .counter: .counter, .spotlight: .spotlight,
                                        .magnifier: .magnifier, .ruler: .ruler, .crop: .crop, .callout: .callout, .image: .openImage]
        #expect(Set(mapped.keys) == Set(Tool.allCases))
    }
}

@Suite("Design tokens")
struct DesignTokenTests {
    typealias Role = DesignTokens.Role
    func c(_ r: Role, _ dark: Bool) -> NSColor { DesignTokens.color(r, dark: dark) }

    @Test func everyRoleHasBothValues() {
        for r in Role.allCases { #expect(DesignTokens.values[r] != nil, "\(r.rawValue)") }
        #expect(DesignTokens.accentRamp.first { $0.step == 500 }?.hex == 0xFF5500)
    }

    @Test("text is at least 4.5:1 on the surfaces it sits on", arguments: [true, false])
    func textContrast(dark: Bool) {
        let mode = dark ? "dark" : "light"
        for text in [Role.ink, .ink2] {
            for surface in [Role.canvas, .chrome, .panel, .field, .hover, .pressed] {
                let ratio = DesignTokens.contrast(c(text, dark), c(surface, dark))
                #expect(ratio >= 4.5, "\(mode) \(text.rawValue) on \(surface.rawValue): \(ratio)")
            }
        }
        // Group labels and captions only sit on the bars and panels.
        for surface in [Role.chrome, .panel, .field] {
            let ratio = DesignTokens.contrast(c(.ink3, dark), c(surface, dark))
            #expect(ratio >= 4.5, "\(mode) ink3 on \(surface.rawValue): \(ratio)")
            let accent = DesignTokens.contrast(c(.accentText, dark), c(surface, dark))
            #expect(accent >= 4.5, "\(mode) accentText on \(surface.rawValue): \(accent)")
        }
    }

    @Test("labels and icons on the accent are readable") func onAccent() {
        #expect(DesignTokens.contrast(DesignTokens.onAccent, c(.accent, true)) >= 4.5)
        #expect(DesignTokens.contrast(.white, c(.accent, true)) >= 3, "white tool icon on the selected tool")
    }

    @Test("status icons are at least 3:1 on the bars", arguments: [true, false])
    func statusContrast(dark: Bool) {
        for s in [Role.info, .success, .warning, .error] {
            let ratio = DesignTokens.contrast(c(s, dark), c(.chrome, dark))
            #expect(ratio >= 3, "\(dark ? "dark" : "light") \(s.rawValue): \(ratio)")
        }
    }

    @Test("dynamic colors follow the appearance") @MainActor func dynamic() {
        let chrome = DesignTokens.color(.chrome)
        var dark: NSColor?, light: NSColor?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { dark = chrome.usingColorSpace(.sRGB) }
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { light = chrome.usingColorSpace(.sRGB) }
        #expect(dark?.hexString == "#1C1D21")
        #expect(light?.hexString == "#F7F7F8")
    }
}
