# Tool shortcut keys for every editing tool (Shift extensions)

`pdfEditToolShortcuts` (`packages/dart_pdf_editor/lib/src/editing/
tool_shortcuts.dart`) previously bound only the ~18 common tools to bare
letters and deliberately left the multi-segment / rare-variant tools
unbound. This change gives **every** `PdfEditTool` a shortcut by
introducing a Shift "extension" for the less-common members of a tool
group, so the mnemonics stay grouped once the plain letters run out.

## The value type

The map value changed from `LogicalKeyboardKey` to a small immutable
`PdfToolShortcut` (trigger key + optional `shift`). It exposes:

- `activator` → `SingleActivator(trigger, shift: shift)`, bound by the
  viewer. Because a plain shortcut has `shift: false`, `SingleActivator`
  only fires it when Shift is *up*, so a primary tool (`L` line) and its
  Shift-extended sibling (`⇧L` polyline) never fire together.
- `label` → `'R'` or `'⇧R'`, used in toolbar tooltips and the shortcut
  sheet.

This is the public API type behind `PdfViewer.toolShortcuts`,
`PdfEditingToolbar.toolShortcuts`, `PdfEditorView.toolShortcuts` and
`pdfEditToolShortcutLabel`, so all four were retyped. Only Shift is used
as a modifier, keeping tool keys clear of the ⌘/Ctrl clipboard, undo/redo,
delete and Escape bindings.

## Assignments (the new Shift extensions)

- Draw: `⇧H` freehand highlighter (beside `P` pen).
- Shapes: `⇧L` polyline, `⇧Y` polygon, `⇧D` cloud polygon (beside `R`/`O`/
  `L`/`A`).
- Measure: `⇧P` perimeter, `⇧A` area, `⇧S` slope, `⇧N` angle, `⇧C` arc,
  `⇧V` volume, `⇧M` calibrate (beside `M` distance — `⇧M` "sets the
  measure scale").
- Insert: `⇧T` count (beside `T` free text / `S` stamp).
- Sign: `⇧B` signature box (beside `H` signature).

`editing_tool_shortcuts_test.dart` now asserts every enum member is bound
to a distinct combo and that Shift-extended keys arm their variant while
the bare key still arms the primary.

## Rebinding UI

The shortcut sheet's key-capture dialog (`showPdfShellShortcutsSheet` in
`shell_chrome.dart`) now records the Shift state at capture time, so users
can rebind to Shift combos too; the "unbind" path still uses a
`LogicalKeyboardKey(0)` sentinel and combo-stealing still works via
`PdfToolShortcut` value equality. The capture hint copy mentions the Shift
extension.
