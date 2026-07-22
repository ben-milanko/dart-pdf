# Grouped, searchable keyboard-shortcuts editor

The keyboard-shortcuts editor (Settings → Keyboard shortcuts…) listed every
tool in one flat, insertion-ordered `ListView`. With ~18 bindings that reads
as an undifferentiated wall. This groups the list by tool category and adds a
search box to filter it.

## What

- **Grouping.** The sheet now renders a section header per tool category and
  the tools under it, in the same order the toolbar dock reads
  (Select → Draw → Shapes → Insert → Measure → Edit). Headers are keyed
  `pdf-shell-shortcut-group-<group>`.
- **Search.** A `TextField` (`pdf-shell-shortcuts-search`,
  `shellShortcutsSearchHint`) filters tools by display name *or* by their
  bound key label (so typing `r` finds the rectangle tool as well as
  anything named with an "r"). An empty result shows a centred
  `shellShortcutsNoMatches` message (`pdf-shell-shortcuts-no-matches`);
  headers for groups with no surviving tool are dropped.

## Where / why

- `PdfEditToolGroup` **moved** from `editing_toolbar.dart` to
  `editing/tool_shortcuts.dart`, joined by a new
  `pdfEditToolGroupOf(PdfEditTool)`. `tool_shortcuts.dart` is the low-level
  file both `editing_toolbar.dart` and `shell_chrome.dart` already import, so
  this keeps the mapping in one place without an import cycle (the toolbar
  imports the shortcuts lib, not vice-versa). Both files are exported from
  `dart_pdf_editor.dart`, so `PdfEditToolGroup`'s public identity is
  unchanged. `pdfEditToolGroupOf` is an **exhaustive** switch over
  `PdfEditTool` — a new tool won't compile until it's assigned a group, so it
  can't silently drop out of the sheet.
- `shell_chrome.dart` — `showPdfShellShortcutsSheet` gained the search field,
  the `byGroup` bucketing, and `_shortcutGroupLabel(context, group)` mapping
  each group to its localized header. The uncontrolled search `TextField`
  keeps its text across `setSheetState` rebuilds (its own `EditableText`
  state), so no `TextEditingController` to dispose in a transient sheet.
- The lazy `ListView` only builds on-screen children, so the grouping test
  scrolls the lower `insert` header into view rather than asserting it built
  eagerly.

## l10n

New keys in `dart_pdf_editor_en.arb` (regenerated with `flutter gen-l10n`):
`shellShortcutsSearchHint`, `shellShortcutsNoMatches` (one `{query}`
placeholder), and `shellShortcutGroup{Select,Markup,Draw,Shapes,Insert,
Measure,Edit}`.
