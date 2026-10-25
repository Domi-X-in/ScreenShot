# Text formatting

The ribbon's **Font** and **Paragraph** groups (Word's Home › Font and Paragraph), at the top of the editor. It works on every text the user can
edit in a screenshot: text boxes, callouts, and the text inside rectangles and ovals.

## Architecture

```
RibbonFormatting (view)  ──applyFormat / state──▶  FormattingController (store)  ──▶  TextFormattingTarget (adapter)
                                                          ▲                              │
            Word shortcuts (AnnotationFieldEditor) ───────┘                              ▼
                                                                         TextFormatting (pure logic) + Annotation (model)
```

- **`TextFormatting`** (`TextFormatting.swift`) — no views. Reads the format at a selection (`state(of:selection:typing:…)`,
  with Word's mixed rules: a mixed font or size is `nil`, a toggle is on only if the whole selection has it) and applies a
  `FormatChange` to an attributed string (`apply(_:to:selection:typing:…)`): to the selected letters, to the paragraphs
  the selection touches (alignment), or to the pending format (`typing`) at a collapsed caret. Also Word's size stepping
  (`grow`, `shrink`), the Stacked layout, and the commands that rewrite the text itself (`rewrite(_:in:selection:)`:
  Change Case, bullets, numbering).
- **`FormattingController`** (`FormattingController.swift`) — the store, one per editor window. Holds the active target
  and its `TextFormatState`, exposes `applyFormat(_:)` and `getFormatAtSelection()`, and calls `onChange` after every
  focus, selection or caret change and every command. Also maps Word's shortcuts to commands (`change(for:)`).
- **`TextFormattingTarget`** — the one interface a text implements to use the ribbon: `formatState` and
  `applyFormat(_:)` (one undoable step). The adapters:
  - `EditingTextTarget`: the text being typed (field editor). Character changes go to the selection or the caret's
    pending format; alignment to the paragraphs; container changes to the object. Undo is the text's own history, so
    ⌘Z steps back one format at a time while typing.
  - `SelectedTextTarget`: a selected text, callout or shape with text. Changes apply to all of its text; undo is the
    document's.
  - `NextTextTarget`: the text about to be typed, with the Text or Callout tool in hand and nothing typed or selected.
    Changes go to a pending format (`ShotView.nextTextTyping`) that the next new text starts with, like Word's format at
    an empty caret; Font › **Set “…” as Default Font** stores the family in the default style (`ToolStyle.family`).
- **`RibbonFormatting`** (`RibbonFormatting.swift`) — the ribbon's Font, Paragraph, Color and Arrange groups. It only
  shows the store's state and sends it commands. Buttons and menus never take keyboard focus, so the text keeps its
  selection; the size field does take it while you type a size, and the editor keeps the text open and gives the focus
  (and selection) back when the size is applied.
- **Model** — `TextRun` gained `family`, `bold`, `italic`, `underline`, `strike` and `outline`; `Annotation` gained `paragraphAligns`,
  `verticalAlign` and `orientation`. All optional: files saved before open unchanged, and text that only uses the original
  Sans / Goofy faces is saved exactly as before.

`ShotView.formattingTarget()` picks the adapter; `EditorWindowController.syncToolbar()` attaches it whenever focus,
selection or the caret moves.

## Making another text work with the ribbon

1. Write an adapter that conforms to `TextFormattingTarget`:
   - `formatState`: call `TextFormatting.state(of:selection:typing:scale:defaultAlign:)` on its text, and set the
     container fields (`supportsVerticalAlign`, `supportsOrientation`, …) it supports.
   - `applyFormat(_:)`: for character and paragraph changes call `TextFormatting.apply(...)` on its text inside one
     undo step; handle `.verticalAlign` / `.orientation` itself if it has a container.
2. Return it from wherever focus is tracked (here `ShotView.formattingTarget()`) and call
   `FormattingController.attach(_:)` on focus, selection and caret changes (or `refresh()` if the target is the same).
3. To get the shortcuts while typing, route the text's key equivalents through `FormattingController.change(for:)`
   (as `AnnotationFieldEditor.performKeyEquivalent` does).
4. Persist what `TextFormatting.apply` leaves in the attributed string (fonts, underline, paragraph styles).

## Differences from Word

- **Icons:** the app's own icon family (`Icons.swift`), drawn after Office's conventions, not Office's artwork.
- **Sizes** are in the screenshot's pixels (the unit the editor already used), with Word's preset list.
- **Vertical alignment** only applies to rectangles and ovals: a text box and a callout always fit their text, so there
  is no space to align within. The buttons are greyed out for them.
- **Text direction** applies to text boxes and shapes; callouts stay horizontal (the bubble is laid out around a
  horizontal text). While typing, rotated or stacked text is edited horizontally and shown turned once typing ends.
- **Bullets and numbering** are real characters ("• ", "1. ") at the start of each paragraph, so they look the same
  in the editor and in the saved image; Word keeps them as paragraph formatting.
- **Bold** on the System font means the Bold weight; the original default text (System Semibold) shows Bold off.
- With a **selected object** (not typing), the ribbon formats all of its text; Word needs the text to be selected.
  Word's shortcuts only work while typing, so ⌘L keeps opening the home window otherwise.
