# Resize pages from the thumbnail strip

Right-click a strip/grid tile → **Resize page…** (or **Resize N pages…** over
a multi-selection) opens `showPdfPageResizeDialog`: a paper-size preset
(A3/A4/A5/Letter/Legal/Tabloid, or Custom), portrait/landscape, width ×
height in mm/in/pt, and how the content fits - **Scale content to fit**
(default) or **Keep content size**. Confirm runs
`PdfEditingController.resizePages`, one edit, one undo.

## Library: `PdfEditor.resizePages` (`pdf_document/lib/src/page_resize.dart`)

- The size is **as displayed**: a /Rotate 90/270 page gets the sides swapped
  in its own space, so "A4 landscape" means the same thing on every page.
- The content streams stay byte-identical. A prologue stream
  `q s 0 0 s dx dy cm <old crop box> re W n` and an epilogue `Q` wrap them;
  the clip keeps anything that was cropped out hidden after a fit reveals
  margins. Uniform scale only (`min(w/cw, h/ch)`), centred.
- The new MediaBox and CropBox are `[0 0 w h]`; Bleed/Trim/ArtBox are mapped
  and clipped to the paper (dropped if nothing is left).
- Annotations follow the content: /Rect plus QuadPoints/L/Vertices/CL/
  callout region/InkList/callout leaders mapped, /RD scaled. Uniform scale
  means existing appearances render exactly scaled through the §12.5.5
  BBox→Rect fit, so nothing is regenerated.
- The cm numbers are written with 6 decimals - `ContentWriter.fmt`'s 3 put
  Letter→A4 ~0.3pt out across the page.
- A page already at the size (crop = media = `[0 0 w h]`) is skipped, so a
  no-op resize commits no revision.
- Not handled: explicit destinations into the page keep their old
  coordinates; /VP measure viewports are left alone.

## Editor

- `resizePages` keeps the page selection (no index shifts) but clears the
  slot-based annotation selection, whose geometry moved.
- The dialog is a new Material importer, allowlisted by hand in
  `tool/design_imports_baseline.json` next to `page_range_dialog.dart`; it
  uses `PdfDropdown` (not `DropdownButton`) so the raw-component counter
  stays at zero.
- Tests: `pdf_document/test/page_resize_test.dart`, and the menu/dialog flow
  in `dart_pdf_editor/test/editing_page_ops_test.dart` (remember to `pump()`
  after `enterText` before reading the orientation toggle).
