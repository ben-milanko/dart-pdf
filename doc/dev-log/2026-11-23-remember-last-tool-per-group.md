# Toolbar groups reopen on the tool last used in them

Switching dock groups used to reset each group to its fixed
`PdfToolGroup.defaultTool`: draw a line in Shapes, hop to Insert for a stamp,
come back to Shapes and the rectangle was armed again. Each group now
remembers the tool last armed in it, and opening the group re-arms that tool.

## Where it lives

- `PdfEditingPreferences.lastToolInGroup` / `setLastToolInGroup`: group id ->
  `PdfEditTool`, persisted as one JSON blob under
  `dart_pdf_editor.editing.groupTools`. It is written like the viewports, not
  through `_write`: silent (no `notifyListeners`, it is written on every tool
  change), never sets `_modified` (that would make a pick before the disk read
  discard *every* stored preference), and merged by key at load, so a tool
  armed before the read lands wins over the stored one. Unknown tool names
  (a renamed enum value) are dropped.
- `PdfEditorCommands._rememberGroupTool`: called from `_trackRecentTool`, the
  same controller listener that feeds the recent-tools list, so a tool counts
  however it was armed: strip, keyboard shortcut, palette, recent chip.
  Select is never recorded.
- `PdfEditorCommands.toolOnOpen(group)`: what `openGroup` arms. The
  remembered tool when it is still in the group, allowed by `tools`, and
  arms without a prompt; else `defaultTool`.

## What is not re-armed

- Measure tools without a scale and the signature tool without a drawn
  signature: arming them directly would skip the prompt `toggleTool` runs.
  The group falls back to its default (Measure: nothing).
- Measure *is* re-armed once a scale exists: its null default only exists to
  avoid the prompt.
- Edit still arms nothing on open. Its tools change the document
  (content delete, redact), so opening the strip to look must stay inert.
- Markup still arms no kind on open; it keeps its text-selection hint.
- The mobile tool sheet's group tabs only navigate, as before.

Tests: `editor_commands_test.dart` (reopen, prompts, hidden tools, Edit) and
`preferences_store_test.dart` (persistence, pre-load pick, corrupt entry).
