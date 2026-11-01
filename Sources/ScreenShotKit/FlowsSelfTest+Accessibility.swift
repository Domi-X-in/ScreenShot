import AppKit

#if SCREENSHOT_SELFTESTS
extension FlowsSelfTest {
    /// VoiceOver can name every control: in the editor (title card, ribbon, folded groups, callout bar, bottom bar,
    /// recent strip), the Library and each step of the welcome guide. Custom-drawn controls must be accessibility
    /// elements with a label; standard controls need a title or a label.
    func accessibilityFlow() async {
        func unnamed(in root: NSView?) -> [String] {
            allViews(NSView.self, in: root).filter { v in
                guard !v.isHiddenOrHasHiddenAncestor, isControl(v) else { return false }
                return name(of: v).isEmpty
            }.map { "\(Swift.type(of: $0))" }
        }

        // The editor, with the callout bar showing and the ribbon both wide and folded.
        Settings.returnToSelect = true
        guard let ed = await openEditor(Self.sampleImage(1000, 700)), let win = ed.window else { check(false, "the editor opens"); return }
        type("e")
        await sleep(0.2)
        let wide = unnamed(in: win.contentView)
        let count = allViews(NSView.self, in: win.contentView).filter { !$0.isHiddenOrHasHiddenAncestor && isControl($0) }.count
        check(wide.isEmpty && count > 40, "every editor control (\(count)) has a VoiceOver name (missing: \(Set(wide)))")
        win.setContentSize(NSSize(width: 780, height: win.contentView?.bounds.height ?? 600))
        win.layoutIfNeeded()
        await sleep(0.2)
        let narrow = unnamed(in: win.contentView)
        check(narrow.isEmpty, "the folded ribbon's group buttons have names too (missing: \(Set(narrow)))")
        type("v")
        await closeAllEditors()

        // The Library.
        LibraryWindowController.show()
        await sleep(0.4)
        let library = unnamed(in: LibraryWindowController.shared?.window?.contentView)
        check(library.isEmpty, "every Library control has a VoiceOver name (missing: \(Set(library)))")
        LibraryWindowController.shared?.window?.orderOut(nil)

        // The welcome guide, step by step.
        let d = UserDefaults.standard
        let wasDone = d.object(forKey: Keys.onboardingDone)
        defer {
            if let wasDone { d.set(wasDone, forKey: Keys.onboardingDone) } else { d.removeObject(forKey: Keys.onboardingDone) }
            d.set(0, forKey: Keys.onboardingPage)
        }
        OnboardingWindowController.show(from: 0)
        guard let ob = OnboardingWindowController.shared else { check(false, "the guide opens"); return }
        for i in 0..<ob.pageCount {
            ob.go(to: i, animated: false)
            await sleep(0.1)
            let missing = unnamed(in: ob.window?.contentView)
            check(missing.isEmpty, "every control on guide step \(i + 1) has a VoiceOver name (missing: \(Set(missing)))")
        }
        ob.window?.orderOut(nil)
        OnboardingWindowController.shared = nil
    }

    /// Something a pointer can press or edit.
    private func isControl(_ v: NSView) -> Bool {
        if let f = v as? NSTextField { return f.isEditable }
        if let i = v as? NSImageView { return i.isEditable } // a picture, not a control (thumbnails, badges)
        if v is NSScroller { return false } // VoiceOver names scroll bars itself
        if v is NSControl { return true }
        return [RibbonButton.self, CompactGroupButton.self, BarButton.self, PlainButton.self, AccentButton.self, TogglePill.self,
                LookPreview.self, StepTabs.self, DragOutView.self, ClickableStack.self].contains { Swift.type(of: v) == $0 }
            || v.accessibilityRole() == .button
    }

    /// What VoiceOver reads for it.
    private func name(of v: NSView) -> String {
        if let s = v.accessibilityLabel(), !s.isEmpty { return s }
        if let s = v.accessibilityTitle(), !s.isEmpty { return s }
        if let b = v as? NSButton, !b.title.isEmpty { return b.title }
        if let f = v as? NSSearchField { return f.placeholderString ?? "" }
        if let s = (v as? NSSegmentedControl)?.cell?.accessibilityLabel(), !s.isEmpty { return s }
        return ""
    }
}
#endif
