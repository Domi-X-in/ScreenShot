import AppKit

/// Anything whose text the formatting toolbar can format. To make a new kind of text work with the toolbar, write an
/// adapter that reports `formatState` (usually `TextFormatting.state(of:selection:typing:scale:defaultAlign:)` over its
/// text) and applies changes in `applyFormat` (usually `TextFormatting.apply(_:to:selection:typing:scale:defaultAlign:)`
/// inside one undo step), then hand it to `FormattingController.attach(_:)` whenever it gets focus or is selected.
@MainActor protocol TextFormattingTarget: AnyObject {
    /// The format to show: the selection's, or the pending format at a collapsed caret.
    var formatState: TextFormatState { get }
    /// Applies one change immediately, as a single undoable step.
    func applyFormat(_ change: FormatChange)
}

/// The shared formatting store: which text is active, what format it has, and the one command API the toolbar and the
/// keyboard shortcuts use. One per editor window.
@MainActor final class FormattingController {
    private(set) var target: TextFormattingTarget?
    private(set) var state = TextFormatState.inactive
    /// The toolbar listens here; it's called after every focus, selection or caret change and every applied command.
    var onChange: ((TextFormatState) -> Void)?

    /// Called when focus or selection changes: the active text, or nil when nothing editable is focused.
    func attach(_ t: TextFormattingTarget?) {
        target = t
        refresh()
    }

    func refresh() {
        state = target?.formatState ?? .inactive
        onChange?(state)
    }

    func getFormatAtSelection() -> TextFormatState {
        refresh()
        return state
    }

    func applyFormat(_ change: FormatChange) {
        guard let target else { NSSound.beep(); return }
        target.applyFormat(change)
        refresh()
    }

    /// Word's shortcuts, while text is being typed. ⌘⇧> / ⌘⇧< also arrive as ⌘⇧. / ⌘⇧, on most layouts.
    nonisolated static func change(for event: NSEvent) -> FormatChange? {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        if mods == [.command] {
            switch key {
            case "b": return .bold
            case "i": return .italic
            case "u": return .underline
            case "l": return .alignment(.left)
            case "e": return .alignment(.center)
            case "r": return .alignment(.right)
            case "]": return .step(1)
            case "[": return .step(-1)
            default: return nil
            }
        }
        if mods == [.command, .shift] {
            switch key {
            case ">", ".": return .grow
            case "<", ",": return .shrink
            default: return nil
            }
        }
        return nil
    }
}

/// The text being typed in the editor: the selected letters, or the pending format at the caret.
@MainActor final class EditingTextTarget: TextFormattingTarget {
    private weak var view: ShotView?
    private let id: UUID

    init(view: ShotView, id: UUID) {
        self.view = view
        self.id = id
    }

    var formatState: TextFormatState { view?.editingFormatState(id) ?? .inactive }
    func applyFormat(_ change: FormatChange) { view?.applyEditingFormat(change, to: id) }
}

/// A selected text, callout or shape with text (not being typed): changes apply to all of its text.
@MainActor final class SelectedTextTarget: TextFormattingTarget {
    private weak var view: ShotView?
    private let id: UUID

    init(view: ShotView, id: UUID) {
        self.view = view
        self.id = id
    }

    var formatState: TextFormatState { view?.selectedFormatState(id) ?? .inactive }
    func applyFormat(_ change: FormatChange) { view?.applySelectedFormat(change, to: id) }
}
