# dart-pdf — pure-Dart PDF renderer & editor

Monorepo using **pub workspaces** (root `pubspec.yaml` lists members under
`packages/`). Flutter is managed with **fvm** (see `.fvmrc`); use
`fvm flutter` / `fvm dart`, or the binaries in `~/fvm/versions/3.44.2/bin/`.

## Commands

- `fvm flutter pub get` (at repo root — resolves every workspace package)
- `fvm dart analyze` (at root)
- `cd packages/<pkg> && fvm dart test` (pure-Dart packages)
- `cd packages/dart_pdf_editor && fvm flutter test`

## Layering rules (strict)

`pdf_cos` ← `pdf_document` ← `pdf_graphics` ← `dart_pdf_editor`

- `dart:ui` and Flutter imports are **only** allowed in `dart_pdf_editor`.
  Everything else must run on the Dart VM (server/CLI/tests) and on the web.
- `dart:io` is not allowed anywhere in `lib/` (web support); use
  `package:archive` for compression.
- `pdf_cos` knows nothing about pages or rendering — only the COS object
  model, syntax, filters, xref, and (de)serialization.

## Design conventions

- Parsers are lenient on input (real-world PDFs are broken: wrong /Length,
  missing endobj, junk before header) and strict on output.
- Streams stay as raw byte views (`Uint8List.sublistView`) until decoded;
  objects load lazily through the xref.
- `CosDictionary` is keyed by `String` (name without the slash).
- Test fixtures are built programmatically in `test/fixtures.dart` so byte
  offsets are always correct — don't hand-edit offsets.

## Test corpus

`corpus/` (git-ignored) holds ~50 real-world PDFs copied from Ben's local
folders and OneDrive — CAD drawings, scanned docs, reports, forms. Use them
to validate changes:

- Parse check: `cd packages/pdf_document && fvm dart tool/inspect.dart ../../corpus/*.pdf`
- Render check: `cd packages/dart_pdf_editor && PDF_PATH=../../corpus/<file>.pdf PDF_PAGE=0 fvm flutter test test/render_smoke_test.dart` (writes /tmp/dart_pdf_render.png)
- Full render sweep: `cd packages/dart_pdf_editor && CORPUS_DIR=../../corpus RENDER_OUT=../../corpus/renders fvm flutter test test/corpus_render_test.dart`

`test_corpora/ghent/` (checked in) is the Ghent PDF Output Suite V5.0 —
54 print-conformance PDFs (overprint, DeviceN, spot, ICC v2/v4, 16-bit,
transparency blend modes, softmasks, optional content, font formats,
JBIG2/JPX) incl. 3 composite test pages. Two test layers:

- `packages/pdf_graphics/test/ghent_corpus_test.dart` — pure-Dart: every
  page must interpret without throwing and paint > 0 ops.
- `packages/dart_pdf_editor/test/ghent_render_test.dart` — rasterizes every
  page and diffs against checked-in baselines in
  `test_corpora/ghent/_baselines` (fail when >0.05% of pixels differ by
  >8/channel). Missing baselines seed on first run; accept intentional
  rendering changes with `GHENT_UPDATE=1 fvm flutter test
  test/ghent_render_test.dart`. Mismatches dump actual+diff PNGs to
  `test_corpora/ghent/_failures/` (git-ignored). The baselines pin
  current behavior, not GWG conformance — many patches print their own
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

## Roadmap context

See README.md. The pipeline through the viewer is done: interpreter, font
engine, Flutter rendering, text selection/search, annotation appearance
rendering, and encryption both ways (RC4/AES-128/AES-256 decryption;
encrypt-on-write re-encrypts changed objects on save — `_encryptedCopy`
in updater.dart; signing encrypted files stays refused). Annotation authoring is in:
`PdfEditor` creates highlights/ink/shapes/free text/notes/stamps with
generated appearance streams (`annotation_editor.dart`) and can flatten
them into page content. AcroForm support is in: `PdfAcroForm`/`PdfFormField`
model (`form.dart`) plus filling with regenerated appearances
(`form_editor.dart` — text/checkbox/radio/choice, auto-size, quadding).
Page manipulation is in (`page_editor.dart`): reorder/move/remove flatten
the page tree (materializing inherited attributes), `appendPagesFrom`
deep-copies pages across documents, `extractPages` splits into a fresh
file via `CosDocumentBuilder` (pdf_cos's from-scratch writer).
Digital signatures are in: `PdfSignature.of(doc)` + `validate()`
(`signature.dart`; CMS/X.509/RSA/ECDSA primitives live in
`pdf_cos/src/crypto/` — asn1, rsa, ecdsa, cms) and `PdfEditor.saveSigned`
(`signature_editor.dart`, adbe.pkcs7.detached with ByteRange patching).
Test signer identity in
`pdf_test_fixtures/src/signer_identity.dart`.
Content editing is in: `PdfEditor.stampPage` (text/shapes/JPEG via
`PdfStamp`), `PdfPageElements.of` + `PdfEditor.deleteElements` (element
enumeration with approximate bounds, stream rewriting), and
`PdfEditor.replaceText` (simple fonts only) — all in
`content_editor.dart`/`content_elements.dart`; the content-stream
tokenizer (`ContentStreamParser`) now lives in pdf_cos.
The roadmap is complete. Polish landed since: LZW/RunLength filters, xref recovery
(`CosDocument.open` falls back to scanning for `N G obj` when the xref
chain is broken), type 4 PostScript calculator functions, /Count-based
page lookup with full-walk fallback, gradient /Extend semantics, JPEG
/Decode + color-key masks, and /Rotate folded into `PdfPageGeometry`
(selection, highlights, overlays, and hit-testing are rotation-aware;
the geometry mirrors the renderer's canvas transform).
The big-gap batch landed next, all KAT-validated against reference
codecs: encrypt-on-write (updater `_encryptedCopy`; signing encrypted
files still refused), trust-store chain validation
(`verifyCertificateChain` in pdf_cos cms.dart, `PdfTrustStore` +
`validate(trustStore:)` in pdf_document), mesh shadings 4-7
(`PdfMeshParser`/`PdfMesh`, device `fillMesh`, drawVertices in
dart_pdf_editor), CCITT G3/G4 (`CcittDecoder`, KAT vs libtiff), JBIG2
embedded profile (`Jbig2Decoder` + shared `MqDecoder` in
filters/mq.dart, KAT vs jbig2enc/jbig2dec), JPEG 2000 (`JpxDecoder`,
lossless bit-perfect vs OpenJPEG, lossy ±1), deep-zoom detail patch
(`PdfPageView` renders the visible slice past the raster caps;
`rasterizeRegion`), and real ICC (`IccProfile` in pdf_graphics —
gray TRC, matrix/TRC, mft1/mft2/mAB LUTs, validated vs littleCMS;
wired into sc/scn and image decoding). Remaining gaps:
RSASSA-PSS, JPX subsampling + PCRL/CPRL, rendering intents/BPC in ICC.
The editing UI is in (dart_pdf_editor `src/editing/`): `PdfEditingController`
owns the edit session — every edit is an incremental save, so revisions
are byte prefixes of one buffer and undo/redo is a stack of lengths;
`PdfViewer(editing:)` injects per-page tool overlays (markup/ink/shapes/
free text/note/stamp; select + move + resize via
`PdfEditor.resizeAnnotation`, which rewrites /Rect and scales the point
arrays — appearances regenerate for shapes/free text, stretch per
§12.5.5 otherwise; see the batch-3 session-1 block), binds undo/redo/delete/escape
shortcuts, and preserves the viewport across same-geometry document
swaps. `PdfEditingToolbar` is the stock chrome. The host must rebuild
the viewer with `editing.document` whenever the controller notifies
(asserted in debug builds); the example app shows the wiring.
On top of that: style controls (controller carries strokeWidth/opacity/
fontSize; the toolbar's tune button opens a slider popup), an
annotation sidebar (`PdfAnnotationSidebar` — lists by page, tap selects
via `selectAnnotation(page, slot)`, trailing delete), and a content
tool (`PdfEditTool.content`: taps hit-test `PdfPageElements` — cached
per revision in the controller — orange selection chrome; delete via
`deleteElements`, text rewrite via `replaceText`; element ids die with
every revision, so any edit clears the element selection).
Page management UI: `PdfThumbnailSidebar` (editing_thumbnails.dart) —
display-list thumbnails (`renderPicture` replayed scaled, no
rasterization), tap to jump, long-press drag to reorder
(ReorderableListView `onReorderItem` — already index-adjusted), footer
delete; `controller.movePage`/`removePage` clear the slot-based
annotation selection first because page indices shift under it, and
`removePage` is a no-op on the last page. Reorder drag: immediate for
mouse pointers, long-press for touch (custom listener picking the
recognizer per pointer kind). The strip shows a viewport indicator fed
by `PdfViewerController.visiblePageRegion(page)` (fractions 0–1) and
repainted via `viewportChanges` (a separate Listenable so scrolling
doesn't spam controller listeners). `PdfViewer.initialFit` defaults to
`PdfViewerFit.page` (whole first page visible, Chrome-style) — widget
tests that do view-coordinate math pin `initialFit: PdfViewerFit.width`.

## Development session log

Detailed per-session notes (gotchas, file pointers, design rationale)
have been moved to [doc/dev-log.md](doc/dev-log.md) to keep this file
under the context-size limit. Consult it (or git history) when you need
the background on a specific subsystem; append new session notes there.
