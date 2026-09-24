# Tab / Shift+Tab between form fields (#932)

Filling a form no longer needs a click per field. In the interactive form
layer, Tab commits the active field and moves to the next one; Shift+Tab
moves back. The walk crosses pages and wraps at both ends.

## Where the pieces live

- **Order (pure, pdf_document)**: `form_tab_order.dart`.
  `PdfFormTabOrder.of(document, form:)` lists every stop (`PdfFormTabStop`:
  page, field, widget index, widget annotation) page by page.
  `PdfPageTabOrder.tabOrder` reads `/Tabs`: `/R` row, `/C` column, `/S`
  structure, and anything else (none, PDF 2.0 `/A`/`/W`, unknown) keeps
  `/Annots` order. `sortPage` is the generic per-page sort and is unit-tested
  on its own. `step(pageIndex:, fieldName:, widgetIndex:, backward:)` picks the
  next or previous stop. If the starting widget isn't a stop, it starts from
  that page.
- **Stops**: text, check box, radio (one stop per button), combo and list
  fields that aren't read-only. Widgets flagged /F hidden, no-view or
  read-only (annotation flag 64) are skipped, and so are push buttons and
  signature fields (`takesTabStop`).
- **Row/column grouping**: sort by the major axis, then an item joins the
  current band when its centre on that axis falls inside the band's first
  item's span. A check box a couple of points lower than the text field
  beside it still reads as the same row. Page space only: `/Rotate` is
  ignored.
- **`/S`** ranks widgets by their `/OBJR` position in
  `PdfStructTree.elementsInReadingOrder()`, keyed by dictionary identity (the
  same identity matching `formWidgetsOn` uses). Unranked widgets go last, in
  `/Annots` order. The ranking is built at most once per order build, and only
  when a page asks for `/S`.
- **Editor glue**: `editing/form_tab_navigation.dart`. Each page mounts its
  own `FormInteractionLayer`, and the target page may not be built yet, so a
  move is *posted* (`pdfFormTabRequests(controller)`, a per-controller
  `ValueNotifier` held in an `Expando`). The target layer takes it right
  away if it is mounted, or in `initState` (post-frame) when the page scrolls
  in. A request carries the `revisionId` it was computed for and is dropped
  once stale. `pdfFormTabOrderOf` caches the order per revision.
- **Scrolling**: the new `PdfViewerController.revealRect(page, rect)` /
  `_revealRect` scrolls as little as possible without changing zoom. It does
  nothing if the rect (plus a 24px margin) is already visible. Otherwise the
  rect is centred on the scroll axis, and on the cross axis too while zoomed
  in (it writes the transform's cross translation). Far moves snap instead of
  animating, the same way `_jumpToPage` does. `showRect` was the wrong tool
  because it zooms to fill 40% of the view. `_PdfViewerPage.onRevealRect`
  passes it to the layer as `onRevealField`.

## Behaviour in the layer

- Text: the Tab bindings sit in the inline editor's `CallbackShortcuts`,
  next to Escape. The key is handled there, so a multi-line field never
  types `\t` and the app's `NextFocusIntent` never runs. Enter still commits
  single-line fields through `onSubmitted`.
- Check box / radio: a focus ring (`pdf-form-focus-ring`, an `IgnorePointer`
  `Focus` over the widget) takes Space/Enter (toggle or select), Tab and
  Escape. Clicking elsewhere clears it (`_onFieldFocusChange`).
- Choice: focus ring, and the menu opens once the reveal scroll has finished
  (`PdfFormTabRequest.revealed`) so it anchors where the field ended up.
  `_menuOpen` keeps the ring alive while the menu holds focus, and focus
  comes back afterwards so Tab carries on.
- The inline editor's `Positioned` is keyed now. Without the key, a Tab
  between two fields on the same page shifted the unkeyed Stack children,
  which rebuilt the TextField and dropped its focus. That fired
  `_onFocusChange`, which committed and closed the new editor right away.
- Opening an editor used to clear the afterimage unconditionally. Now it
  only clears when the same field reopens, so the field a Tab just committed
  keeps showing its new value until its raster lands.
  `_afterMultiline`/`_afterFieldName` store the afterimage's own layout.
- Password fields (#943) need nothing extra. A Tab move opens the editor
  through the same `_openTextEditor` a tap uses, so it is prefilled from
  `controller.formFieldTextValue` (the secret store, not /V), obscured,
  single-line and capped by /MaxLen. The afterimage stays masked through
  `formPasswordMask`. Covered by the password test in
  `editing_form_tab_order_test.dart`.

## Tests

- `pdf_document/test/form_tab_order_test.dart`: R/C/S/none orders, skips,
  step wrap, and non-stop starts on the new
  `buildTabOrderFormPdf({firstPageTabs})` fixture
  (`pdf_test_fixtures/src/tab_order_form.dart`, two pages, with a structure
  tree that tags page 0 out of order).
- `dart_pdf_editor/test/editing_form_tab_order_test.dart` tabs through the
  whole fixture. It checks row order, Space on the check box and radio, the
  scroll onto page 1, that Tab in a multi-line field moves on, the combo menu,
  wrapping back to page 0, Shift+Tab, and that an unrelated focusable widget
  never gets focus. With `onRevealField` disabled it fails, because page 1
  never mounts.

## Left out

- Tab with no active field (fresh document, viewer focused) still goes to
  Flutter's focus traversal. It could start at the current page's first stop.
- Clicking a check box, radio or choice field doesn't set the tab position.
  Only text fields opened by a tap continue with Tab.
- Radio groups get one stop per button rather than one per group with arrow
  keys.
