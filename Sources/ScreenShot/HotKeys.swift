import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask
    var key: String

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    var nsModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        return f
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static func keyName(_ e: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let s = special[Int(e.keyCode)] { return s }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

enum HotkeyAction: String, CaseIterable, Identifiable {
    case area, fullscreen, anyWindow, activeWindow, scrolling, scrollingManual, repeatArea, ocr, delayed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: "Area Capture"
        case .fullscreen: "Fullscreen Screenshot"
        case .anyWindow: "Capture Any Window"
        case .activeWindow: "Capture Active Window"
        case .scrolling: "Scrolling Capture"
        case .scrollingManual: "Manual Scrolling Capture"
        case .repeatArea: "Repeat Area Capture"
        case .ocr: "Recognize Text/QR"
        case .delayed: "Delayed Screenshot (3s)"
        }
    }

    var defaultShortcut: Shortcut? {
        let cs = UInt32(cmdKey | shiftKey)
        switch self {
        case .fullscreen: return Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: cs, key: "1")
        case .area: return Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: cs, key: "2")
        case .anyWindow: return Shortcut(keyCode: UInt32(kVK_ANSI_7), modifiers: cs, key: "7")
        case .scrolling: return Shortcut(keyCode: UInt32(kVK_ANSI_8), modifiers: cs, key: "8")
        case .ocr: return Shortcut(keyCode: UInt32(kVK_ANSI_9), modifiers: cs, key: "9")
        case .repeatArea: return Shortcut(keyCode: UInt32(kVK_ANSI_0), modifiers: cs, key: "0")
        case .activeWindow, .scrollingManual, .delayed: return nil
        }
    }
}

/// Global hotkeys through Carbon's RegisterEventHotKey (what Shottr does via sindresorhus/KeyboardShortcuts).
@MainActor final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var handler: ((HotkeyAction) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var installed = false
    private(set) var suspended = false

    private func storageKey(_ a: HotkeyAction) -> String { "hotkey.\(a.rawValue)" }

    func shortcut(for a: HotkeyAction) -> Shortcut? {
        if let data = UserDefaults.standard.data(forKey: storageKey(a)) {
            // Empty data marks a shortcut the user cleared.
            return try? JSONDecoder().decode(Shortcut.self, from: data)
        }
        return a.defaultShortcut
    }

    func set(_ s: Shortcut?, for a: HotkeyAction) {
        let data = s.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        UserDefaults.standard.set(data, forKey: storageKey(a))
        reload()
    }

    func resetAll() {
        HotkeyAction.allCases.forEach { UserDefaults.standard.removeObject(forKey: storageKey($0)) }
        reload()
    }

    func suspend() { suspended = true; unregisterAll() }
    func resume() { suspended = false; reload() }

    func reload() {
        install()
        unregisterAll()
        guard !suspended else { return }
        for (i, a) in HotkeyAction.allCases.enumerated() {
            guard let s = shortcut(for: a) else { continue }
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x5353_4854), id: UInt32(i)) // 'SSHT'
            if RegisterEventHotKey(s.keyCode, s.modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            } else {
                NSLog("Hotkey %@ (%@) could not be registered", a.title, s.display)
            }
        }
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let index = Int(hk.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.fire(index) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func fire(_ index: Int) {
        let all = HotkeyAction.allCases
        guard index < all.count else { return }
        handler?(all[index])
    }
}
