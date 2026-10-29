# Multi-select tabs to share several at once

The open-tabs overview (phone bottom sheet and desktop "View all tabs" dialog,
`_TabsOverview` in `app/lib/editor_screen.dart`) now has a selection mode.

- **Entering:** the header's checklist button (`<prefix>-tabs-select`), or a
  long-press on a tile. Long-press used to open the tab context menu on touch;
  right-click still does, and the selection header's select-all + close covers
  what Close others / Close all did on a phone.
- **While selecting:** a tap checks a tile instead of switching to it, a
  checkbox replaces the tile's close button, and Enter in the search field
  checks the first match. The header shows the count
  (`MaterialLocalizations.selectedRowCountTitle`), select all (toggles the
  tabs the search currently shows), share, and close-selected.
  The selection is a `Set<DocumentTab>` held by identity, pruned on every build
  so closed tabs drop out.
- **Sharing:** `_shareTabs` gathers each tab's current revision exactly as
  Save As would (`_withBakedPageColor`, unsaved edits included). Deferred tabs
  use their held bytes; restored path-only tabs that were never opened are read
  from their origin (`_readOriginFully`). Loading/error/comparison tabs and
  unreadable files are skipped with one `editorTabsNotShared` toast.
  `shareDocumentsAs` (`file_io.dart`) is the multi-file `saveBytesAs`: one
  share sheet with every file on Android/iOS, a download each on the web, and
  on desktop a folder picker (`getDirectoryPath`) that gets a copy of each.
  Names are de-duplicated within the batch and against files already in the
  folder (` (2)`, ` (3)`, ...; probed with `XFile(path).length()` so no
  `dart:io`), so a batch copy never overwrites anything. The button reads
  "Share" on phones and "Save copies" elsewhere.
- **Test seam:** `EditorScreen.shareDocuments`. Covered in
  `app/test/tabs_menu_test.dart` (desktop dialog flow + phone long-press).
