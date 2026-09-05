# Host entries in the text-selection context menu

`annotationMenuBuilder` has always let a host append its own rows to the
annotation right-click menu. The text menu had no counterpart, so an app
that wanted one extra action over a text selection - Trax's "Link to a
record", which turns the selected glyphs into a `/Link` carrying a
deep-link URI - had only `contextMenuEnabled: false` +
`onContextMenuRequested`. That switch is all-or-nothing: it suppresses the
stock menu for **all five** `PdfContextMenuTarget`s, not just text, so the
host has to rebuild the annotation / locked / empty-page / form branches
too (doable - `showPdfAnnotationMenu` and `showPdfFormFieldMenu` are
public) and then rebuild the text branch by hand.

Rebuilding the text branch mostly worked on public API already
(`PdfEditingController.addMarkup`, `addLinkToSelection` +
`showPdfAddLinkDialog`, `PdfViewerController.copySelection` /
`selectionRectsOn` / `selectionPages`, `textElementForSelection` +
`replaceTextInElement`) - **except Select all**, whose only entry point was
the private `_selectAllTextOn`. So the price of *adding* one row was
*losing* one.

## What landed

`PdfTextMenuBuilder` on `PdfViewer`, forwarded by `PdfEditorView` and
`PdfReader`, deliberately shaped like the annotation hook
(`editing_menu.dart`, beside `PdfAnnotationMenuBuilder`):

- `PdfTextMenuItem` - key / label / icon / enabled / `onSelected`, the
  same five fields as `PdfAnnotationMenuItem`.
- `PdfTextMenuRequest` - `controller` (**nullable**: the text menu opens
  in a plain reader too, which is the one real shape difference from the
  annotation request), `pageIndex`, `selectedText`, `selectionPages`,
  `quadsByPage` as `selectionRectsOn` gives them, and `pagePoint`.
- The entries land in their own group under a divider, after the stock
  markup / Copy / Select all - the contract `annotationMenuBuilder`
  already documents.

Three decisions worth keeping:

- **The request is a snapshot.** It is built before `showMenu` awaits and
  handed back to the picked entry, so an action acts on what the user
  right-clicked even if the live selection moved on while the menu was
  open. The annotation hook reads the controller's selection at build
  time for the same reason.
- **The builder runs even with nothing selected.** A right-click that
  finds no word still opens the menu (Select all is live, Copy is not);
  entries that need text key off `request.hasSelection` rather than being
  hidden. And custom entries *alone* are enough to open the menu, so an
  action that doesn't need text still reaches a page that has none -
  otherwise the `!hasSelection && !hasText` early return would swallow it.
- **The chip is not in scope.** `_showTextMenu` is reached only by
  right-click; the touch selection chip is a fixed icon row (Copy /
  markup / link / Select all) and the long-press path opens the
  *annotation* menu, not this one. Adding host rows there is a separate
  design question.

`_showTextMenu` now shows a `showMenu<Object>` - stock rows keep their
`_TextMenuAction` values, custom rows carry the `PdfTextMenuItem` itself,
and the picked value is type-tested before falling into the existing
exhaustive `_TextMenuAction` switch. `_textMenuRow` takes a nullable
`IconData` so an icon-less host row doesn't leave a hole where the glyph
would be.

`PdfViewerController.selectAllTextOn(page)` is the other half: a public
wrapper over `_selectAllTextOn`, bounds-checked, so the full-takeover
route can rebuild the one row it couldn't. It is also what the "the host
entry keeps the selection the menu opened on" test uses to move the
selection out from under an open menu.

Tests are in `test/editing_menu_test.dart`'s `text context menu (mouse)`
group: divider placement and request contents in a reader, a disabled row
that neither fires nor closes the menu, the no-selection case, the editor
case (controller identity, markup rows still above), the snapshot
guarantee, and `selectAllTextOn` including an out-of-range index.
