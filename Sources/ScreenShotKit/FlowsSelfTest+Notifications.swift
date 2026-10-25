import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// The new editor's bottom bar: the tool's hint as info, messages in four states (success fades, warnings and errors
    /// stay), actions and dismissing, toasts routed into the bar, the restyled readouts, Backdrop and recent strip.
    func notificationsFlow() async {
        let d = UserDefaults.standard
        d.set(true, forKey: "newEditorUI")
        defer { d.removeObject(forKey: "newEditorUI") }
        guard let ed = await openEditor(Self.sampleImage(900, 600)), let status = ed.debugEditorStatus, let r = ed.debugEditorRibbon else {
            check(false, "the new editor opens with its status bar"); return
        }
        let bar = status.notices, v = ed.shotView

        check(status.window === ed.window && abs(status.frame.height - DesignTokens.Metrics.statusBarHeight) < 0.5, "a 44 pt status bar across the window")
        check(bar.current == nil && bar.shownKind == .info && bar.shownText == StatusBar.hint(for: v.tool, cutOut: false), "the tool's hint shows as info")
        type("u")
        check(bar.shownText == StatusBar.hint(for: .ruler, cutOut: false), "picking the Ruler changes the hint")
        check(!bar.debugCloseShown, "a hint has no close button")

        // Success: Copy Full Image.
        r.copyImage.action?()
        check(bar.current?.kind == .success && bar.shownText == "Copied to the clipboard" && bar.debugCloseShown,
              "Copy Full Image says “Copied to the clipboard” as success (\(bar.shownKind) “\(bar.shownText)”)")
        type("m")
        check(bar.shownText == "Copied to the clipboard", "a new hint doesn't push a message away")
        await sleep(3.3)
        check(bar.current == nil && bar.shownText == StatusBar.hint(for: .magnifier, cutOut: false), "success fades after 3 s and the hint comes back")

        // Warning and error from Toast, which the new editor routes into the bar.
        Toast.show("No text detected in the selected area")
        check(bar.current?.kind == .warning, "a toast about a problem shows as a warning in the bar")
        check(!NSApp.windows.contains { $0.isVisible && $0.level == .statusBar && $0 is NSPanel }, "no floating HUD over the new editor")
        await sleep(3.3)
        check(bar.current?.kind == .warning, "a warning stays until dealt with")
        bar.debugPressClose()
        check(bar.current == nil, "the close button dismisses it")
        Toast.show("Failed to save the GIF: disk full")
        check(bar.current?.kind == .error, "a failure shows as an error")

        // An action.
        var acted = false
        ed.notify(NotificationBar.Notice(.warning, "Annotations aren’t saved yet", actionTitle: "Save image") { acted = true })
        check(bar.showsAction && bar.current?.actionTitle == "Save image", "a message can offer an action")
        bar.debugPressAction()
        check(acted && bar.current == nil, "the action runs and the message closes")
        check(Toast.noticeKind(for: "Image saved to Desktop") == .success && Toast.noticeKind(for: "Sizes in pixels (px)") == .info,
              "toasts map to success and info")

        // Readouts, Backdrop and the recent strip keep their function with the new look.
        let info = ed.debugInfo
        check(!info.sizeText.isEmpty, "the image size readout still shows (\(info.sizeText))")
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        status.backdropButton.onClick?()
        await sleep(0.4)
        let panel = NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.isVisible }
        check(panel != nil, "Backdrop opens its panel")
        panel?.close()
        check(ed.debugRecent.modern, "the recent strip uses the new look")
        await closeAllEditors()

        // The old editor keeps Toast's HUD.
        d.removeObject(forKey: "newEditorUI")
        guard !Settings.newEditorUI, let old = await openEditor(Self.sampleImage(500, 300)) else { return }
        check(!old.notify(NotificationBar.Notice(.info, "x")) && old.debugEditorStatus == nil, "the old editor has no notification bar")
    }
}
#endif
