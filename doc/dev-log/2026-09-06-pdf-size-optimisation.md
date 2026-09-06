# PDF size optimisation (#368)

`PdfCompressor.optimize` and `PdfEditor.compress(options:)` now provide a
rewritten copy and exact sequential size accounting. Defaults are lossless:
dead-object removal, object/xref streams, unfiltered/Flate recompression,
unused-resource cleanup, identical image/font/ICC deduplication, and supported
TrueType/CFF font subsetting. Independent options control each pass. Screen,
eBook and Print presets opt into image processing at 72/150/300 DPI with JPEG
qualities 60/75/90. Output is never larger than the source.

The app menu's **Reduce file size…** opens settings, runs an isolated worker on
native platforms, reports savings by category, and saves a separate copy with
the existing save/download/share flow. Pending ink and inline text are included;
the current tab, dirty state and undo history are preserved. All 20 app locales
include the new strings. Web builds run the same pure-Dart API, but Flutter's
web `compute` still executes on the browser event loop; a dedicated worker is
a future responsiveness improvement for large files.

Preservation rules:

- Resource liveness unions names across pages, inherited resources, forms,
  appearances, Type 3 glyphs and patterns. AcroForm default resources remain
  available for later filling. Ambiguous content prevents pruning.
- Re-Flate preserves the predictor-encoded bytes and original DecodeParms.
- Dedup fingerprints retain all dictionary semantics; optional-content and
  structure identity links prevent merging even when their targets look equal.
- Images use their largest placement across pages and nested forms, including
  UserUnit. Masks, one-bit/JBIG2, ICC/CMYK, uncertain placements, EXIF rotation,
  and images above 16 million pixels remain unchanged. Gray stays DeviceGray.
- Font subsetting retains glyph IDs, used outlines, composite dependencies,
  metrics and CFF subroutines. Editable form fonts, ambiguous mappings,
  unsupported formats and no-subsetting fonts are retained with a report.
- Encrypted and incomplete sources are refused. Signed copies require an
  explicit signature-invalidation choice. Linearization is not implemented.

The first before/after pixel test caught an existing compactor defect: the COS
serializer rounded all reals to six decimal places, changing a Type 3 font
matrix in GWG090. Compaction now opts into exact double serialization through
both builder modes. Other authored output keeps its previous formatting.
The compactor also reserves cyclic indirect arrays before traversing them and
preserves PDF 2.0 headers.

Validation:

- All 16 sampled Ghent/PDF.js documents render with identical before/after
  pixels, including Type 3 fonts, embedded fonts, patterns, optional content,
  16-bit ICC images, JPEG 2000, CCITT, JBIG2 and soft masks. Sample size:
  10,536,739 → 9,349,260 bytes.
- Full eligible pure-Dart corpus sweep: 206 files / 274 pages reopened and
  interpreted with unchanged paint-operation counts and no failures. PDF.js:
  3,002,877 → 1,945,942 bytes (35.2%); Ghent: 88,136,349 → 79,941,394 (9.3%).
  Encrypted/signed sources and the known unopenable fuzz inputs were excluded.
- Independent fontTools validation of a 20,339-glyph OpenType CFF font
  confirmed identical retained outlines/widths after subsetting.
- Focused COS, optimiser, app and save-flow regressions pass. The app's web
  release build succeeds; the existing scanner plugin still emits the
  unrelated Wasm dry-run warning for dart:html.

Repeat the pixel gate from `packages/dart_pdf_editor` with
`fvm flutter test test/compression_render_test.dart`. Optimiser unit tests are
`compress_test.dart` and `compressor*_test.dart` in `pdf_document`; app tests are
`reduce_file_size_test.dart`.
