# Changelog

## Unreleased

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
