# dart-pdf - pure-Dart PDF renderer & editor

Monorepo using **pub workspaces** (root `pubspec.yaml` lists members under
`packages/`). Flutter is managed with **fvm** (see `.fvmrc`); use
`fvm flutter` / `fvm dart`, or the binaries in `~/fvm/versions/3.44.4/bin/`.

## Commands

- `fvm flutter pub get` (at repo root - resolves every workspace package)
- `fvm dart analyze` (at root)
- `cd packages/<pkg> && fvm dart test` (pure-Dart packages)
- `cd packages/dart_pdf_editor && fvm flutter test`

## Layering rules (strict)

`pdf_cos` ← `pdf_document` ← `pdf_graphics` ← `dart_pdf_editor`

- `dart:ui` and Flutter imports are **only** allowed in `dart_pdf_editor`.
  Everything else must run on the Dart VM (server/CLI/tests) and on the web.
- `dart:io` is not allowed anywhere in `lib/` (web support); use
  `package:archive` for compression.
- `pdf_cos` knows nothing about pages or rendering - only the COS object
  model, syntax, filters, xref, and (de)serialization.

## Design conventions

- Parsers are lenient on input (real-world PDFs are broken: wrong /Length,
  missing endobj, junk before header) and strict on output.
- Streams stay as raw byte views (`Uint8List.sublistView`) until decoded;
  objects load lazily through the xref.
- `CosDictionary` is keyed by `String` (name without the slash).
- Test fixtures are built programmatically in `test/fixtures.dart` so byte
  offsets are always correct - don't hand-edit offsets.

## Test corpus

`corpus/` (git-ignored, ~50 real-world PDFs) plus the checked-in
`test_corpora/ghent/` (Ghent PDF Output Suite, render baselines) and
`test_corpora/pdfjs/` suites validate parser and rendering changes.
For the commands (parse/render sweeps, baseline accept via GHENT_UPDATE,
visual galleries, PDF.js pixel compare), invoke the `corpus-tests` skill
(`.claude/skills/corpus-tests/SKILL.md`).

## Roadmap context

See README.md. The pipeline through the viewer is done: interpreter, font
engine, Flutter rendering, text selection/search, annotation appearance
rendering, and encryption both ways (RC4/AES-128/AES-256 decryption;
encrypt-on-write re-encrypts changed objects on save -
`StandardSecurityHandler.encryptObjectGraph` (the graph walk + exempt
policy live on the handler, shared with the loader's `decryptObjectGraph`);
signing encrypted files stays refused). Annotation authoring is in:
`PdfEditor` creates highlights/ink/shapes/free text/notes/stamps with
generated appearance streams (`annotation_editor.dart`) and can flatten
them into page content. AcroForm support is in: `PdfAcroForm`/`PdfFormField`
model (`form.dart`) plus filling with regenerated appearances
(`form_editor.dart` - text/checkbox/radio/choice, auto-size, quadding).
Page manipulation is in (`page_editor.dart`): reorder/move/remove flatten
the page tree (materializing inherited attributes), `appendPagesFrom`
deep-copies pages across documents, `extractPages` splits into a fresh
file via `CosDocumentBuilder` (pdf_cos's from-scratch writer).
Digital signatures are in: `PdfSignature.of(doc)` + `validate()`
(`signature.dart`; CMS/X.509/RSA/ECDSA primitives live in
`pdf_cos/src/crypto/` - asn1, rsa, ecdsa, cms) and `PdfEditor.saveSigned`
(`signature_editor.dart`, adbe.pkcs7.detached with ByteRange patching).
The enterprise tier - PAdES B-B/B-T/B-LT/B-LTA, RFC 3161 timestamps, the
/DSS+/VRI Document Security Store, and Certify/DocMDP - is in
`PdfEditor.saveSignedPades` (`pades_editor.dart`, async; TSA/OCSP/CRL
transports injected via `pades.dart`'s `PdfTimestampClient`/
`PdfRevocationClient`, no `dart:io`); crypto in `pdf_cos/src/crypto/`
tsp/ocsp/crl + cms ESS/timestamp helpers (KATs vs OpenSSL in
`pkix_test.dart`, fixtures from `tool/gen_pkix_fixtures.sh`). validate()
reports `padesLevel`, `timestamp`, and offline `embeddedRevocation` from the
/DSS. pyHanko 0.35 judges our B-LTA output VALID + LTV-enabled offline
(`pdf_document/tool/emit_pades_ltv.dart`). See doc/dev-log.md. Signing
encrypted files is still refused. Test signer identity in
`pdf_test_fixtures/src/signer_identity.dart`; LTV CA/leaf/TSA + revocation
fixtures in `pkix_ltv.dart`, the in-process TSA in `test_tsa.dart`.
Content editing is in: `PdfEditor.stampPage` (text/shapes/JPEG via
`PdfStamp`), `PdfPageElements.of` + `PdfEditor.deleteElements` (element
enumeration with approximate bounds, stream rewriting), and
`PdfEditor.replaceText` (matches across a line's shown
strings and consecutive Tj/TJ runs, with width-compensated re-measurement
from the font's /Widths so following text holds position; composite
/Type0 runs are handled too for the Identity-H/CIDFontType2/Identity-
CIDToGIDMap shape - `content_editor_type0.dart`'s `_Type0Editing` reads
existing text from /ToUnicode, re-encodes replacements through the
embedded font's own cmap so any glyph the program carries can be typed,
and merges new glyphs' advances + Unicode into the descendant /W and
/ToUnicode; when the document font can't draw a character - a subsetted
font dropped it - `replaceText(fallbackFonts:)` embeds a style-matched
bundled fallback as a new page /Font resource and emits that replacement
between Tf switches (the editor passes the DejaVu trio via
`loadFallbackFonts()`); within-line only - CFF/non-Identity Type0 still
out) - all
in `content_editor.dart`/`content_elements.dart`; shared Type0 metric
parsing (/ToUnicode + /W) is in `type0_metrics.dart`, and
`PdfPageElements` decodes Type0 runs through it so `element.text` is real
Unicode (what the content-edit UI shows and passes as `find`). The
content-stream tokenizer (`ContentStreamParser`) now lives in pdf_cos.
Paragraph-level reflow is in: `PdfEditor.reflowText` (`content_reflow.dart`)
re-wraps a whole detected paragraph when the replacement changes its line
count and cascades the following lines through the content stream's own
relative breaks - single-column, left-aligned, simple + Identity-H Type0
fonts; multi-column/justified/first-line-indent/`'`/`"`/vertical out (see
[doc/dev-log.md](doc/dev-log.md)).
The roadmap is complete. Polish landed since: LZW/RunLength filters, xref recovery
(`CosDocument.open` falls back to scanning for `N G obj` when the xref
chain is broken), type 4 PostScript calculator functions, /Count-based
page lookup with full-walk fallback, gradient /Extend semantics, JPEG
/Decode + color-key masks, and /Rotate folded into `PdfPageGeometry`
(selection, highlights, overlays, and hit-testing are rotation-aware;
the geometry mirrors the renderer's canvas transform).
The big-gap batch landed next, all KAT-validated against reference
codecs: encrypt-on-write (`StandardSecurityHandler.encryptObjectGraph`;
signing encrypted files still refused), trust-store chain validation
(`verifyCertificateChain` in pdf_cos cms.dart, `PdfTrustStore` +
`validate(trustStore:)` in pdf_document), mesh shadings 4-7
(`PdfMeshParser`/`PdfMesh`, device `fillMesh`, drawVertices in
dart_pdf_editor), CCITT G3/G4 (`CcittDecoder`, KAT vs libtiff), JBIG2
embedded profile (`Jbig2Decoder` + shared `MqDecoder` in
filters/mq.dart, KAT vs jbig2enc/jbig2dec), JPEG 2000 (`JpxDecoder`,
lossless bit-perfect vs OpenJPEG, lossy ±1), deep-zoom detail patch
(`PdfPageView` renders the visible slice past the raster caps;
`rasterizeRegion`), and real ICC (`IccProfile` in pdf_graphics -
gray TRC, matrix/TRC, mft1/mft2/mAB LUTs, validated vs littleCMS;
wired into sc/scn and image decoding). RSASSA-PSS verification is in
(`rsaVerifyPss` in pdf_cos rsa.dart - MGF1 + EMSA-PSS with salt-length
recovery, KAT vs OpenSSL; PSS-params parsing and dispatch in cms.dart's
`cmsVerify` and `X509Certificate.isSignedBy`). Remaining gaps:
JPX subsampling + PCRL/CPRL, rendering intents/BPC in ICC.
The decoded-image cache budget (`PdfImageCache.maxBytes`, settable) is
platform-aware: `pdfDefaultImageCacheBytes()` in performance_policy.dart -
desktop 256 MB, mobile/web 128 MB, 64 MB on a <=2 GB browser device
(`navigator.deviceMemory`, web-only and secure-context-only, via the
performance_memory.dart conditional export). The numbers are measured, not
guessed - see doc/dev-log/2026-07-16-image-cache-budget.md and
`test/benchmark_image_cache_budget_test.dart`; re-run it before changing
them. `didHaveMemoryPressure` on the viewer clears the image + preview
caches.
The editing UI is in (dart_pdf_editor `src/editing/`): `PdfEditingController`
owns the edit session - every edit is an incremental save, so revisions
are byte prefixes of one buffer and undo/redo is a stack of lengths;
`PdfViewer(editing:)` injects per-page tool overlays (markup/ink/shapes/
free text/note/stamp; select + move + resize via
`PdfEditor.resizeAnnotation`, which rewrites /Rect and scales the point
arrays - appearances regenerate for shapes/free text, stretch per
§12.5.5 otherwise; see the batch-3 session-1 block), binds undo/redo/delete/escape
shortcuts, and preserves the viewport across same-geometry document
swaps. `PdfEditingToolbar` is the stock chrome. The host must rebuild
the viewer with `editing.document` whenever the controller notifies
(asserted in debug builds); the example app shows the wiring.
On top of that: style controls (controller carries strokeWidth/opacity/
fontSize; the toolbar's tune button opens a slider popup), an
annotation sidebar (`PdfAnnotationSidebar` - lists by page, tap selects
via `selectAnnotation(page, slot)`, trailing delete), and a content
tool (`PdfEditTool.content`: taps hit-test `PdfPageElements` - cached
per revision in the controller - orange selection chrome; delete via
`deleteElements`, in-line text rewrite via `replaceText`
(`replaceSelectedElementText`), and paragraph reflow via `reflowText`
(`reflowSelectedElementText`) - the element strip's "Reflow paragraph"
action (`pdf-reflow-element-text`) re-wraps the selected line's whole
paragraph, toasting a fallback hint when the shape isn't reflowable;
element ids die with every revision, so any edit clears the element
selection).
Page management UI: `PdfThumbnailSidebar` (editing_thumbnails.dart) -
display-list thumbnails (`renderPicture` replayed scaled, no
rasterization), tap to jump, long-press drag to reorder
(ReorderableListView `onReorderItem` - already index-adjusted), footer
delete; `controller.movePage`/`removePage` clear the slot-based
annotation selection first because page indices shift under it, and
`removePage` is a no-op on the last page. Reorder drag: immediate for
mouse pointers, long-press for touch (custom listener picking the
recognizer per pointer kind). The strip shows a viewport indicator fed
by `PdfViewerController.visiblePageRegion(page)` (fractions 0–1) and
repainted via `viewportChanges` (a separate Listenable so scrolling
doesn't spam controller listeners). `PdfViewer.initialFit` defaults to
`PdfViewerFit.page` (whole first page visible, Chrome-style) - widget
tests that do view-coordinate math pin `initialFit: PdfViewerFit.width`.
`PdfThumbnailView` (same file, exported) is the full-area sibling: a
reflowing `Wrap` grid with the strip's whole control set plus a header
size slider (`thumbnailViewTileWidth` pref), custom drag reorder
(`DragTarget`+`Draggable`/`LongPressDraggable`, mouse-immediate via a
`MouseRegion` hover flag), and a "page picker" tap (`_PageTile.
onActivatePage`). `PdfEditorView` overlays it over the live viewer as a
view mode (`showThumbnailView`, toggled from View options alongside
reflow; `altView` = reflow-or-grid suppresses the panels/toolbar).

## Development session log

Detailed per-session notes (gotchas, file pointers, design rationale)
live in [doc/dev-log/](doc/dev-log/) - **one file per session**, named
`YYYY-MM-DD-slug.md`. Consult them (or git history) when you need the
background on a specific subsystem. Record new session notes by **adding
a new file** there (never append to a shared file - that conflicts on
every concurrent PR); see [doc/dev-log/README.md](doc/dev-log/README.md).
Notes written before 2026-06-22 are in the frozen
[doc/dev-log.md](doc/dev-log.md) archive.
