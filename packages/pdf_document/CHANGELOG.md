# Changelog

## 1.1.0

- Vector snapshots: `PdfEditor.captureVectorSnapshot` captures a page
  region as detached vector graphics (`PdfVectorSnapshot`) and
  `pasteVectorSnapshot` re-materializes it onto any page as a /Stamp
  annotation whose appearance *draws* the captured content — so a snapshot
  pasted back into the PDF stays vector (crisp at any zoom), Bluebeam-style.
- Count tool: `PdfEditor.addCheckMark` places a Bluebeam-style check-mark
  stamp annotation (with `PdfAnnotation.isCheckMark`/`iconName`) — the
  building block for a running on-page tally.
- Fix: JPEG 2000 tile-part desynchronization, and indexed Lab color
  palettes now decode correctly.

## 1.0.0

First stable release. Changes since 0.1.0:

- Line/PolyLine/Polygon annotations: reading and authoring with the full
  PDF Table 176 line-ending vocabulary, plus reshaping.
- Measurement annotations (§12.9): `PdfMeasure`/`PdfNumberFormat`, scale
  calibration (`setMeasurementScale`), and `addMeasurement` for
  distance/perimeter/area with a `/Measure` dictionary and a baked-in
  formatted caption.
- True redaction: mark `/Redact` regions and burn the underlying content
  irreversibly.
- Image stamps: `PdfEditor.addImageStamp` places a PNG/JPEG as a stamp
  annotation; dashed (`/D`) stroke patterns for all shape subtypes; and
  annotation flip when a resize handle is dragged past the zero point.
- Form widgets: `resizeFormWidget` rewrites a field's `/Rect` and
  regenerates its appearance at the new size.
- Page assembly: `PdfEditor.insertBlankPage` adds a new empty page at any
  position (sized to request, default US Letter), and
  `PdfDocument.extractPageRange` exports a contiguous span of pages as a
  standalone PDF — alongside the existing `appendPagesFrom` (insert pages
  from another document) and `extractPages` (arbitrary subset).
- OCR text-layer injection: `PdfEditor.injectTextLayer` writes recognized
  `PdfOcrSpan`s onto a page as invisible (render mode 3) text — sized and
  horizontally scaled to sit over each word — so a scanned, image-only page
  becomes selectable, searchable, and extractable without changing how it
  looks. `applyOcr` (with a pluggable engine) lives in `dart_pdf_editor`.
- `PdfImageDocument`: assemble a brand-new PDF from a list of PNG/JPEG
  images, one page per image — the pure-Dart half of image/Office
  ingestion (multi-page TIFF, scans, camera shots).
- `PdfImportSource`: a host-provided seam for converting foreign formats
  (DOCX/XLSX/PPTX, …) to PDF bytes. Interface only — dart-pdf does not
  implement OOXML→PDF layout.

## 0.1.0

Initial release.

- `PdfDocument`: page tree with inherited attributes, metadata, outlines,
  text-page lookup.
- `PdfEditor`: incremental-save editing. Annotation authoring (highlight,
  ink with pressure, shapes, free text, notes, stamps), flattening,
  page manipulation (reorder, remove, append across documents, extract),
  content stamping/deletion/text replacement.
- Annotations: appearance generation, resize/rotate/restyle, slicing
  eraser, clipboard snapshots, /NM-keyed diff + replay for sync.
- Measurements (§12.9): `PdfMeasure`/`PdfNumberFormat` (parse/emit/format),
  scale calibration (`setMeasurementScale`), and `addMeasurement` for
  distance/perimeter/area annotations with a /Measure dictionary, a
  formatted /Contents, and a caption baked into the appearance
  (`PdfAnnotation.measure`/`measurementText`).
- AcroForm: field model, filling with regenerated appearances, field
  administration (add/rename/remove/retype/flatten), button images.
- Digital signatures: `PdfSignature.validate()` with optional trust-store
  chain validation, and signing via `saveSigned`.
- Image embedding: JPEG passthrough and full baseline PNG (all bit
  depths/color types, tRNS, Adam7) with alpha soft masks.
