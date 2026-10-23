import AppKit
import Testing
@testable import ScreenShotKit

@Suite("Capture settings", .serialized)
struct SettingsFeatureTests {
    /// Sets a preference for one test and puts the old value back.
    private func with(_ key: String, _ value: Any, _ body: () throws -> Void) rethrows {
        let d = UserDefaults.standard, old = d.object(forKey: key)
        d.set(value, forKey: key)
        defer { d.set(old, forKey: key) }
        try body()
    }

    @Test("mouse pointer: Auto shows it in fullscreen shots only")
    func cursor() {
        with(Keys.captureCursor, "auto") {
            #expect(Settings.showsCursor(fullscreen: true) && !Settings.showsCursor(fullscreen: false))
        }
        with(Keys.captureCursor, "include") { #expect(Settings.showsCursor(fullscreen: false)) }
        with(Keys.captureCursor, "exclude") { #expect(!Settings.showsCursor(fullscreen: true)) }
    }

    @Test("Retina at 1× halves the saved image only when turned on")
    func retina() {
        let img = solid(400, 200, 0x336699)
        with(Keys.saveRetinaAt1x, true) {
            let (out, scale) = Exporter.forSaving(img, scale: 2)
            #expect(out.width == 200 && out.height == 100 && scale == 1)
            #expect(pixel(out, 100, 50).hexString == "#336699")
            #expect(Exporter.forSaving(img, scale: 1).0.width == 400, "1× screenshots stay as they are")
        }
        with(Keys.saveRetinaAt1x, false) { #expect(Exporter.forSaving(img, scale: 2).0.width == 400) }
    }

    @Test("scrolling height setting accepts the popup's text and has a floor")
    func scrollHeight() {
        with(Keys.scrollMaxHeight, "20000") { #expect(Settings.scrollMaxHeight == 20000) }
        with(Keys.scrollMaxHeight, 10) { #expect(Settings.scrollMaxHeight == 1000) }
    }

    @Test("a window on a solid color gets a margin of that color")
    func windowOnColor() throws {
        let win = solid(500, 300, 0xFFFFFF)
        let out = try #require(WindowBackground.compose(win, on: .color(NSColor(hex: 0xFF0000))))
        #expect(out.width == 560 && out.height == 360, "30 px margin (6% of 500)")
        #expect(pixel(out, 5, 5).hexString == "#FF0000")
        #expect(pixel(out, 280, 180).hexString == "#FFFFFF")
    }

    @Test("a window on the wallpaper fills the margin with the picture")
    func windowOnImage() throws {
        let wallpaper = solid(1600, 1000, 0x00AA00)
        let out = try #require(WindowBackground.compose(solid(200, 100, 0x000000), on: .image(wallpaper)))
        #expect(out.width == 248 && out.height == 148, "at least 24 px of margin")
        #expect(pixel(out, 3, 3).hexString == "#00AA00")
    }

    @Test("screenshot:// links can be turned off")
    @MainActor func urlScheme() {
        with(Keys.urlScheme, false) { #expect(!Settings.urlSchemeEnabled) }
        with(Keys.urlScheme, true) { #expect(Settings.urlSchemeEnabled) }
    }
}
