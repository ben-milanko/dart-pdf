# Reusing recorded text and filling high-zoom tiles

Follow-up to [viewport rendering at 3000–10000%](2026-09-08-extreme-zoom-performance.md).

The engineering sheet's render worker already walks roughly 1.1 million
operators to record the page. Preparing selection and search used to walk them
again. Complete native and web recordings now retain a text-only snapshot before
annotation appearances are appended and before the render codec removes exact
character advances and marked-content ids. Extraction applies the existing
separator, bidi and geometry logic to that snapshot.

The snapshot discards paths, images and glyph outlines. Text in repeated cells
stays compact until extraction; nested translations preserve the original
floating-point evaluation order. Source text inside a masked group remains
searchable, while text defining the mask is excluded, matching fresh extraction.
Invisible OCR text and tagged text retain their existing semantics.

Each worker retains at most 32 pages and an estimated 16 MiB of this metadata,
rejecting a single oversize entry. Repeated image-resolution or annotation
visibility recordings reuse it. Edits invalidate affected pages; undo/reopen
clears the cache. Partial and cancelled recordings never supply complete text.
A miss, including a worker-pool reassignment, uses ordinary extraction.

The earlier spatial-grid change also exposed a scheduling coupling. A page
with at least 32,768 commands needs its grid built off the UI thread, but that
does not make every indexed tile expensive. The tile scheduler now reserves
one-tile-per-paint admission for pages above the original 250,000-command
ceiling. The supplied 77,312-command transcript can fill the ordinary eight-tile
batch. The outstanding-work limit, backend limits and strip limits still apply;
larger pages remain limited to two outstanding tiles.

## Paired measurements

Local Flutter test engine, supplied single-page engineering sheet, one warm-up
pair followed by seven alternating measured pairs:

| Phase | Previous path | Reuse path |
| --- | ---: | ---: |
| Page recording, including metadata capture when enabled | 380.87 ms | 393.82 ms |
| Text extraction after recording | 372.39 ms | 9.95 ms |
| Sum of the above phase medians | 753.26 ms | 403.77 ms |

Offset collection and snapshot capture add approximately 13 ms to recording;
capture alone takes 5.95 ms. Later extraction is about 37 times faster. The
snapshot estimates 8,151,548 bytes (7.77 MiB), fitting the worker's 16 MiB bound.
All 13,452 text runs and 14,911 characters match fresh extraction exactly,
including the 1,672,773-byte text buffer. The 18,206,202-byte render buffer is
also unchanged.

The actual native worker returned text in 15.49 ms after a completed record.
Cold extraction on a newly started worker took 399.49 ms; that comparison
includes startup on the cold side and must not be read as a pure extraction
speedup. The phase measurements above isolate the extraction work itself.

## Validation and reproduction

Tests compare serialized extracted text exactly, covering Unicode, selection
advances, MCIDs and geometry. Coverage includes masks, annotations, invisible
text, nested Type3/pattern cells, Arabic marks, proportional spacing, cancellation,
resume and revisions, plus representative PDF.js and Ghent documents. Native
and actual browser workers exercise full, vector-only, progressive, bounded
prefix and region-index record paths. Tile tests hold raster futures unresolved
to verify bounded scheduling across repeated paints on native and Chrome.

From `packages/dart_pdf_editor`, the opt-in private-document benchmark is:

```sh
PDF_PATH=/absolute/path/to/drawing.pdf \
PDF_TEXT_BENCHMARK_OUT=/tmp/recorded-text.json \
  fvm flutter test --no-pub test/benchmark_recorded_text_test.dart
```

It alternates variants, discards one warm-up pair and measures seven pairs.
It separates initial offset collection/capture from later extraction, compares
render-command bytes and extracted-text bytes, and also probes the real worker.
Cold worker extraction includes startup; it is reported separately from local
phase timings. A sum of phase medians is explicitly labelled, not presented as
an end-to-end latency measurement. The private input and outputs remain local.

## Mask diagnostic

The new opt-in `benchmark_mask_layers_test.dart` separates replay, raster-image
readiness and pixel readback. Its baseline manually replays the old unclipped
Canvas path, so a future production clip cannot change both sides of the oracle.
Image/layer removal variants deliberately change semantics and are diagnostic
only. Its software baseline PNGs match the previous benchmark byte for byte.

An explicit output clip made no consistent difference across four masked
regions at 3000%, 6000% and 10000% in software Skia. Impeller reported image
readiness much earlier but incurred substantial work during pixel readback;
neither the readiness time alone nor the readback-inclusive time establishes
on-screen display latency. No mask or image-sampling change ships here.

The upper and lower logo regions visibly contain masked images. The middle
region at 10000% is mostly blank despite intersecting the source group's bounds,
so it measures costly conservative work with little visible content. The masks
are small alpha images with transfer functions, and their transforms differ
slightly from those of the source images. Pre-compositing them at matching
pixel coordinates would therefore be incorrect. A future mask optimization
needs real presentation timings and checks for mask/source alignment, transfer
semantics and sampling at fractional positions.
