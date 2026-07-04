# Docked sidebar panels get a close (×) button on desktop

On a narrow screen the side panels float up as bottom sheets, and
`PdfPanelBottomSheet` gives each a titled header with a close ×. On a wide
(desktop) screen the same panels dock into the `Row` beside the viewer
(`pdf_editor_view.dart`, `pdf_reader.dart`) and had no in-panel way to
dismiss them — only the header's panel-toggle buttons. This adds the
matching little × to the docked layout.

## Shape

- New shared `PdfSidebarCloseButton` in `editing_panel.dart` — a compact
  `IconButton(Icons.close, size 18)` with a "Close" tooltip. The desktop
  counterpart of the sheet chrome's close button.
- Each of the four panels (`PdfThumbnailSidebar`, `PdfSearchResultsPanel`,
  `PdfAnnotationSidebar`, `PdfAnnotationPropertiesPanel`) gained an
  optional `onClose`. The button renders **only** when `onClose != null &&
  !bottomSheet` — a bottom sheet still supplies its own × via
  `PdfPanelBottomSheet`, so the guard prevents a double close button when
  the breakpoint flips.
- Both shells wire `onClose: bottomSheet ? null : () => prefs.showXPanel =
  false`, flipping the same visibility preference the header toggle drives.

## Where the × sits per panel

The panels don't share a header shape, so the button slots into each
panel's existing top region rather than adding a uniform title bar:

- **Thumbnails**: into the existing "Pages" header row, wrapped so the ×
  stays put even when the row swaps to the multi-select bar (2+ pages
  selected). Left-docked, so the row's right padding already clears the
  scrollbar + resize grip via `_extraRightPadding`.
- **Annotations**: beside the filter `TextField` (a `Row` with the field
  `Expanded`). Right-docked → grip on the left, no extra inset needed.
- **Search results** / **Properties**: neither has a persistent docked
  header (search hides its options bar when docked; properties goes
  straight to content), so each gets a slim header row `[Expanded(title),
  ×]` above the body. Search is left-docked, so its header right padding
  adds `PdfSidebarResizeGrip.width` when the grip rides that edge so the ×
  clears it; properties is right-docked and needs no inset.

Keys for tests: `pdf-thumbnail-panel-close`, `pdf-annotation-panel-close`,
`pdf-search-panel-close`, `pdf-properties-panel-close`. Covered by
`pdf_shell_test.dart` "wide: a docked panel's close button hides it".
