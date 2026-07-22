# Delete/Backspace shortcut on the thumbnail strip and grid

The page thumbnail strip (`PdfThumbnailSidebar`) and the full-area grid
(`PdfThumbnailView`) already bound copy/cut/paste to ⌘/Ctrl+C/X/V via
their focus-scoped `CallbackShortcuts`. Delete had no keyboard binding -
you had to reach for the selection bar's trash button or a per-tile
delete.

Added `Delete`/`Backspace` to both shortcut maps (guarded by
`allowPageEditing`, alongside the clipboard shortcuts). Each calls a new
`_deletePages()` that mirrors the clipboard-target logic:

- if there is a page selection, `controller.removeSelectedPages()`;
- otherwise delete the keyboard/current page via
  `controller.removePage(_keyboardBase())`.

Both controller paths already refuse to empty the document (the last
remaining page is kept) and clear the selection, so no extra guarding was
needed here.

No conflict with the viewer's own Delete binding (annotation delete,
`pdf_viewer.dart`) or the shell keybinding-capture dialog: the strip/grid
handle the key inside their own `Focus` subtree, exactly the way the
existing C/X/V bindings coexist with the viewer's.

Tests: `editing_page_ops_test.dart` (strip - Delete on a multi-selection,
Backspace on the bare navigation cursor) and `editing_page_clipboard_test.dart`
(grid - Delete on a multi-selection).
