---
name: corpus-tests
description: Run, review, and accept the PDF test-corpus suites — the local corpus/ parse and render sweeps, the Ghent PDF Output Suite render baselines (GHENT_UPDATE), and the PDF.js comparison renders and galleries. Use when validating parser or rendering changes against real-world PDFs or updating render baselines.
---

# Test corpus suites

`corpus/` (git-ignored) holds ~50 real-world PDFs copied from Ben's local
folders and OneDrive - CAD drawings, scanned docs, reports, forms. Use them
to validate changes:

- Parse check: `cd packages/pdf_document && fvm dart tool/inspect.dart ../../corpus/*.pdf`
- Render check: `cd packages/dart_pdf_editor && PDF_PATH=../../corpus/<file>.pdf PDF_PAGE=0 fvm flutter test test/render_smoke_test.dart` (writes /tmp/dart_pdf_render.png)
- Full render sweep: `cd packages/dart_pdf_editor && CORPUS_DIR=../../corpus RENDER_OUT=../../corpus/renders fvm flutter test test/corpus_render_test.dart`

`test_corpora/ghent/` (checked in) is the Ghent PDF Output Suite V5.0 -
54 print-conformance PDFs (overprint, DeviceN, spot, ICC v2/v4, 16-bit,
transparency blend modes, softmasks, optional content, font formats,
JBIG2/JPX) incl. 3 composite test pages. Two test layers:

- `packages/pdf_graphics/test/ghent_corpus_test.dart` - pure-Dart: every
  page must interpret without throwing and paint > 0 ops.
- `packages/dart_pdf_editor/test/ghent_render_test.dart` - rasterizes every
  page and diffs against checked-in baselines in
  `test_corpora/ghent/_baselines` (fail when >0.05% of pixels differ by
  >8/channel). Missing baselines seed on first run; accept intentional
  rendering changes with `GHENT_UPDATE=1 fvm flutter test
  test/ghent_render_test.dart`. Mismatches dump actual+diff PNGs to
  `test_corpora/ghent/_failures/` (git-ignored). The baselines pin
  current behavior, not GWG conformance - many patches print their own
  pass criterion on the page (overprint simulation isn't implemented;
  GWG173's faint "X" is a known JBIG2 deviation).

Run the checked-in corpora from their package directories so the relative
`../../test_corpora/...` paths line up:

- Ghent pure-Dart pass: `cd packages/pdf_graphics && fvm dart test test/ghent_corpus_test.dart`
- Ghent render/baseline pass: `cd packages/dart_pdf_editor && fvm flutter test test/ghent_render_test.dart`
- Accept intentional Ghent baseline changes: `cd packages/dart_pdf_editor && GHENT_UPDATE=1 fvm flutter test test/ghent_render_test.dart`
- Ghent visual review gallery: `cd packages/dart_pdf_editor && GHENT_RENDER_OUT=../../test_corpora/ghent/_renders fvm flutter test test/ghent_render_test.dart`, then open `test_corpora/ghent/_renders/index.html`
- PDF.js pure-Dart pass: `cd packages/pdf_graphics && fvm dart test test/pdfjs_corpus_test.dart`
- PDF.js render smoke pass: `cd packages/dart_pdf_editor && fvm flutter test test/pdfjs_render_test.dart`
- PDF.js visual review gallery: `cd packages/dart_pdf_editor && PDFJS_RENDER_OUT=../../test_corpora/pdfjs/_renders fvm flutter test test/pdfjs_render_test.dart`, then open `test_corpora/pdfjs/_renders/index.html`
- Generate PDF.js reference baselines: `cd packages/dart_pdf_editor/tool/pdfjs_baseline && npm install && npm run render`
- PDF.js pixel compare + side-by-side results: `cd packages/dart_pdf_editor && PDFJS_BASELINE_DIR=../../test_corpora/pdfjs/_baselines fvm flutter test test/pdfjs_render_test.dart`, then open `test_corpora/pdfjs/_renders/index.html`
- All checked-in corpus tests: run the four non-update test commands above
  (excluding the visual galleries); they are intentionally split because
  `pdf_graphics` is VM-only and `dart_pdf_editor` needs Flutter rasterization.

The Ghent gallery writes the same 2x rasters used for baseline comparison.
The PDF.js gallery writes the same pages as the smoke pass by default (up to
five per file at 1x); override it with `PDFJS_RENDER_MAX_PAGES` and
`PDFJS_RENDER_PIXEL_RATIO` when you need deeper or sharper review. When
`PDFJS_BASELINE_DIR` is set, the Flutter test compares Dart rasters against
the PDF.js baselines using `PDFJS_COMPARE_CHANNEL_TOLERANCE` (default 8) and
`PDFJS_COMPARE_MAX_DIFF_FRACTION` (default 0.0005), and writes
`test_corpora/pdfjs/_renders/index.html` unless `PDFJS_RENDER_OUT` overrides
the output directory. The results page shows each page as one row with the
PDF.js baseline, Dart render, and diff side by side.
