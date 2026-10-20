# Sectioning the app menu, and a palette over everything else

The DartPDF menu had grown to fourteen defined rows - twelve visible on
macOS with a document open, five with nothing open - and five scopes shared
one flat list: app (New window, Settings), file (New, Open, Open Recent),
document (Save as, Print, Sign, OCR, Compare), one page-scoped verb (Export
page as image…) and a mode toggle (Switch to read-only). Two unlabelled
dividers carried all of the grouping, and six of the twelve visible rows had
no keyboard route at all.

The design canvas that led to this weighed four directions (sectioning it,
folding specialists into a submenu, splitting document actions out to the
header, and a command palette). Two were picked: **section the menu** and
**add the palette app-wide**.

## The menu

`_appMenuItems` no longer hand-builds `PopupMenuItem`s. It builds
`_MenuAction` descriptors in three lists - `_fileActions`,
`_documentActions`, `_appActions` - and renders them. That indirection is
the point: `_paletteCommands` reads the *same* descriptors, so an action
added to the menu joins the palette without a second registration. The merge
with `main` proved it - upstream's new **Insert document…** row became a
descriptor and turned up in the palette with no palette-side change, which
`command_palette_test.dart` now asserts.

Rules that came out of drawing the states rather than the desktop mock:

- **A section header is earned by two rows or more.** With nothing open the
  App section holds only Settings, and a header over one row says less than
  the divider above it already does; it falls back to today's bare divider.
- **Read-only is a switch, not a verb.** The old row rewrote its own label
  ("Switch to read-only" / "Switch to edit mode"), so the current mode was
  only legible by reading which way the sentence pointed. The switch is
  `IgnorePointer`-wrapped: the row keeps the tap, the switch is the readout.
- **`Export page as image…` cannot carry a shortcut.** At 16px it fills the
  row, and Flutter's `PopupMenu` is capped at 280px (`_kMenuMaxWidth`), so
  label + trailing shortcut collide. It stays mouse-only unless the menu
  moves off `PopupMenu` to something wider.
- The menu is now taller than a phone screen at touch row heights (14 rows
  at 48px plus headers ≈ 830px). It scrolls, which is why
  `doc_scan_menu_test` has to `ensureVisible` before tapping Insert scan.
  The alternative the design named - moving the document section to the
  header's ⋯ on compact widths - is still open.

## The palette

`app/lib/command_palette.dart` is the UI; `EditorScreen._paletteCommands`
is the index. Sources: the menu descriptors, `pdfToolCatalog()` from the
editor package, the six panels, five view-option toggles, and the recent
files - 60-odd commands.

- **The catalogue is new public API.** The dock's group table used to be a
  private `static const _groups` inside `_PdfEditingToolbarState`, with the
  tool names in a private switch beside it. Both moved to
  `editing_tool_catalog.dart` (`pdfToolGroups`, `pdfToolCatalog()`,
  `pdfEditToolLabel` and friends); the toolbar keeps `_GroupTool`/`_ToolGroup`
  as typedefs onto the public classes, so its 5000 lines were untouched.
- **Results name their source** ("Menu", "Shapes tool", "Panel"). The palette
  is meant to teach where a command lives, not become a second place to learn
  it - so it shows the surface and the shortcut rather than hiding them.
- **Unavailable commands stay listed, dimmed, with the reason.** "Where is
  it?" deserves an answer; a gap is not one.
- **⌘K is a global hook, not a `CallbackShortcuts` binding.** The first cut
  registered it beside ⌘P/⌘O in the body's `CallbackShortcuts`, and it
  silently did nothing on the welcome screen, where nothing holds focus. It
  now hangs off `_onGlobalKeyEvent` next to the F12 devtools hook, guarded by
  `_paletteOpen` so the key can't stack copies.
- **Arrow keys had to be taken from the text field.** The handler hangs off
  the field's *own* `FocusNode` (`FocusNode(onKeyEvent:)`), because a node's
  own handler runs before the text-editing shortcuts above it; an ancestor
  `Focus` loses ↑/↓ to caret movement.
- Rows are built lazily (`ListView.builder`), so a widget test cannot expect
  a result 30 rows down to exist - type for it instead.

## Strings

Sixteen new keys across all 20 locale bundles (`tool/check_arb_coverage.dart`
enforces parity), and `editorMenuSwitchToReadOnly`/`editorMenuSwitchToEdit`
retired with the verb row. Panel and view-option labels are *not* new: the
palette reuses `pdfL10n`'s existing `shellPanel*` / `shell*` strings, so a
result reads exactly as the surface it points at.
