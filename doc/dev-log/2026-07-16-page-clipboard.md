# Page copy/cut/paste in the thumbnail view (cross-tab)

Added whole-page copy/cut/paste to the thumbnail strip and grid, with a
clipboard shared across document tabs so pages copied in one open document
paste into another.

## The shared clipboard

`PdfPageClipboard` (`editing_page_clipboard.dart`) is a `ChangeNotifier`
holding the copied pages as a **self-contained PDF byte buffer** plus a page
count. Bytes come from `exportPages` (pdf_cos's from-scratch writer via
`extractPages`), so a paste deep-copies everything each page references and
never depends on the source document - or the tab it came from - still being
open.

`PdfPageClipboard.instance` is a process-wide singleton; every
`PdfEditingController` defaults to it (new `pageClipboard` constructor arg),
so cross-tab paste works with **zero host wiring** - the example app's tabs
each `PdfEditingController(bytes, ...)` and automatically share it. Pass a
private clipboard to isolate a session (the tests do).

The controller registers `notifyListeners` on the clipboard (mirroring how
it listens to `preferences`), so every tab rebuilds its paste affordances
the instant any tab fills or clears the clipboard. Removed in `dispose`
(instance-method tear-offs compare equal, so `removeListener` matches).

## Controller ops (`editing_controller.dart`)

- `copyPages(indices)` / `copySelectedPages()` - fill the clipboard; no
  document edit, no revision.
- `cutPages(indices)` / `cutSelectedPages()` - copy **then** `removePages`
  in one undoable edit. Refused (nothing copied) when it would empty the
  document, matching `removeSelectedPages`. Clears the selection.
- `pastePages({at})` - `insertPagesFromBytes` at `at` (default: append),
  then selects the pasted run so the strip highlights what landed. One undo
  removes the paste.
- `hasPageClipboard` gates the paste affordances.

## UI (`editing_thumbnails.dart`)

Wired into every surface, both the docked strip and the full-area grid:

- **Context menu** (`_showPageTileMenu`): Copy / Cut / Paste rows
  (`pdf-thumbnail-menu-{copy,cut,paste}`). Cut dims when it would empty the
  doc; Paste dims when the clipboard is empty and drops its pages after the
  right-clicked page (jumping there).
- **Bulk selection bar** (`_PageSelectionBar`): copy/cut icon buttons
  (`pdf-thumbnail-{copy,cut}-selected`).
- **Header page-actions menu** (`_PageActionsButton`): a Paste entry
  (`pdf-thumbnail-paste-pages`) - the touch path, since long-press starts a
  reorder drag rather than the context menu. The button now also renders
  when the clipboard has pages even if no insert/export callback is wired,
  gated on `allowPageEditing`.
- **Keyboard**: ⌘/Ctrl+C/X/V in both strip and grid, acting on the page
  selection (or the keyboard/current page when nothing is selected); paste
  reveals the landing page. Gated on `allowPageEditing`.

Tests in `editing_page_clipboard_test.dart` cover the clipboard, all three
controller ops (incl. cut-empty refusal and undo), cross-tab paste through a
shared clipboard, and each UI surface.
