# Document-conversion pipeline: image to PDF export + office seam

## Document-conversion pipeline: image↔PDF export + office seam

Three pieces, layered the same way the rest of the conversion surface is.

**image → PDF (pure Dart, `pdf_document/src/image_pdf.dart`).** `PdfImageDocument`
already turned a stack of PNG/JPEG images into a one-page-per-image PDF (one
pixel = one point at `dpi`); extended it with a fixed-page-size mode. New
`PdfPageSize` (A3/A4/A5/Letter/Legal/Tabloid constants + `portrait`/`landscape`
reorient), `PdfImageFit` (`contain`/`cover`/`fill`/`none`), and `PdfImageAlign`
(nine fractional anchors). With `pageSize: null` (default) the old behaviour is
untouched — page sized to image, image fills it, no clip — so existing callers
and tests are unchanged. With a `pageSize`, the image is laid into the content
box (page minus `margin` on each side): `_fit` computes the `cm` scale + origin,
and `cover`/`none`/non-zero-margin emit a `re … W n` clip so overflow is
trimmed and margins are honoured. JPEGs still pass through verbatim (DCTDecode,
no re-encode — now asserted: the embedded stream's raw bytes equal the input).
The content stream is built with `ContentWriter` instead of the old hand-rolled
string. CLI: `pdf_document/example/image_to_pdf.dart` (`dart run`, uses
`dart:io` — fine in an example).

**PDF → image (Flutter, `dart_pdf_editor/src/page_export.dart`).**
`PdfPageExport.exportPage`/`exportPages` wrap `PdfPageRenderer.renderImage` and
encode the result. `PdfRasterFormat.png` goes through `ui.Image.toByteData(png)`;
`jpeg` has no `dart:ui` encoder, so it pulls `rawRgba`, flattens straight alpha
onto `pageColor` (`_flattenOnto` — JPEG can't store alpha, so transparent
margins must read as paper, not black), and hands it to `package:image`'s
`encodeJpg`. Resolution is `dpi` (default 150) or an explicit `scale`
(pixels/point) override; `pixelRatio = scale ?? dpi/72`. CLI:
`dart_pdf_editor/example/tool/pdf_to_images.dart` — runs under `flutter test`
(rasterization needs the engine), reads `PDF_PATH`/`OUT_DIR`/`DPI`/`FORMAT`/
`PAGES` env. Tests round-trip a solid-colour image image→PDF→image and assert
PNG dimensions/pixels exactly and the JPEG path matches within tolerance.

**office → PDF (seam only, `pdf_document/src/office_conversion.dart`).** Faithful
`.docx`/`.xlsx`/`.pptx`/ODF rendering is a LibreOffice-sized project, not a pure-
Dart function, so — exactly like `PdfOcrEngine` — only the contract ships.
`PdfOfficeConverter` (abstract: `convert(PdfOfficeDocument) → PDF bytes`,
`supportedFormats`), `PdfOfficeFormat` (+`.sniff` by extension / RTF magic),
`PdfOfficeDocument`, `PdfOfficeConversionException`, and the default
`UnsupportedPdfOfficeConverter` that throws with guidance toward the recommended
seam: a host implements the converter against a **headless LibreOffice service**
(`soffice --headless --convert-to pdf` behind HTTP) or a cloud conversion API,
keeping the pure-Dart layers `dart:io`-free and web-safe; the returned PDF bytes
open with `PdfDocument.open` and the rest of dart-pdf applies unchanged. No
`dart:io`/native deps entered `lib/`.

**Apps: "Export page as image…".** Both the `/app` shell and the editor
`example` got a menu action wiring `PdfPageExport` to the platform save flow.
It renders the page the viewer is currently on (`PdfViewerController.currentPage`,
clamped) at the current edit revision, after a small dialog picks format
(PNG/JPEG) and resolution (72/150/300/600 dpi). Saving reuses each app's
existing single-image path — desktop save dialog, web download, mobile share
sheet: `/app` added `saveImageBytesAs` to `file_io.dart` and a reusable dialog +
options in `image_export.dart`; the example carries a compact inline copy
(`_exportImage`/`_saveImageBytes`/`_showImageExportDialog`). Current-page export
keeps the save uniform across every platform (one file). Test:
`app/test/export_image_menu_test.dart` asserts the menu entry shows only with a
document open and opens the format/resolution dialog (the rasterize+save tail
needs platform channels, so it stops at the dialog).
