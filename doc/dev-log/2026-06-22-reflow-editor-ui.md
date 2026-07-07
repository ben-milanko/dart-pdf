# Paragraph reflow - editor UI wiring

Exposes the Tier-4 `PdfEditor.reflowText` paragraph reflow (see
`2026-06-22-paragraph-reflow-editing.md`) through the editing UI, next to
the existing in-line "Replace text" action.

- `PdfEditingController.reflowSelectedElementText(text)`
  (`editing_controller.dart`) mirrors `replaceSelectedElementText`: it runs
  `reflowText(page, selectedElement.text!, text)` inside `apply`, so a
  successful reflow is one incremental revision and a bail
  (`reflowText` → false) is a no-op - `apply` already skips when the editor
  has no changes, so no empty undo step is pushed. Returns whether a
  paragraph reflowed. The `find` is the selected line's own `element.text`,
  so reflow re-wraps the paragraph that line belongs to.

- `PdfEditingToolbar._elementStrip` gains a "Reflow paragraph"
  `IconButton` (`Icons.wrap_text`, key `pdf-reflow-element-text`) beside the
  keyed "Replace text" button (`pdf-replace-element-text`), shown whenever
  `canEditSelectedElementText`. `_reflowElementText` opens the injected
  `textPrompt` multiline (pre-filled with the line), calls the controller,
  and - when reflow declines (not a single-column reflowable paragraph) -
  shows a floating SnackBar pointing the user back to Replace text. The
  post-await SnackBar is guarded by `context.mounted`.

Tests (`editing_reflow_test.dart`): controller-level grow-and-cascade,
no-selection no-op, and unreflowable (rotated) no-op; plus widget tests that
the strip surfaces the keyed button for a selected text element and reflows
on tap (stubbed `textPrompt`), and that a growing edit on the trailing
single-line block (nothing after it to cascade) bails and surfaces the
fallback hint without modifying the document.

Reflow deliberately takes no `fallbackFonts` (the reflow path has no
fallback-font branch - Type0 reflow requires the document font to carry
every glyph), unlike `replaceSelectedElementText`.
