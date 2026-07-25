# dart-pdf - pure-Dart PDF renderer & editor

Monorepo using **pub workspaces** (root `pubspec.yaml` lists members under
`packages/`). Flutter is managed with **fvm** (see `.fvmrc`); use
`fvm flutter` / `fvm dart`, or the binaries in `~/fvm/versions/3.44.8/bin/`.

## Commands

- `fvm flutter pub get` (at repo root - resolves every workspace package)
- `fvm dart analyze` (at root)
- `cd packages/<pkg> && fvm dart test` (pure-Dart packages)
- `cd packages/dart_pdf_editor && fvm flutter test`

## Performance tooling

`tool/perf.sh` is the front door (sweep/render/web/compare-pdfium/gate/dce/
diff/report). The zero-overhead instrumentation core is `PdfPerf`
(`package:pdf_cos/perf.dart`, NOT exported from pdf_cos.dart): enum-indexed
phases/counters, off by default (one branch when compiled in;
`--dart-define=PDF_PERF=false` tree-shakes it — CI-verified by
`tool/check_perf_dce.sh`). `PdfPerfLog.enabled = true` lights up the whole
stack. Never allocate a Stopwatch in lib/ code - use
`PdfPerf.begin()/end()`. Results use the envelope schema
(`tool/perf/SCHEMA.md`); scenarios in `tool/perf/scenarios.json`; perf
budget targets in `tool/perf/targets.json`. Per-PR CI runs the
deterministic counter gate (`tool/perf.sh gate`, baseline
`tool/perf/baselines/counters.json` — re-baseline deliberately with
`--update-baseline`) and `perf_gate_test.dart`/`render_trace_gate_test.dart`.
Nightly trends + dashboard live on the orphan `perf-data` branch
(perf-nightly.yml). A/B a change: `tool/perf.sh diff <ref> [scenario]`.
NEVER edit sources or run builds while a sweep/loop is measuring. See
doc/dev-log/2026-07-18-perf-tooling-suite.md.

**For any change that could affect performance** (interpreter, render
pipeline, font/text, image decode, worker offload, editing/annotation,
search, memory), measure it — don't eyeball it. Use the real-Chrome
harness: `tool/perf.sh web <scenario>` for a single run and
`tool/perf.sh webdiff <ref> <scenario>` for a one-command A/B vs a git
ref (per-metric median deltas, gated on a threshold). Scenarios (scroll/
open/search/edit) live in `app/tool/perf/scenarios.json`; add one for the
workload your change touches if none fits (harness method + JSON entry —
no driver change, see `app/tool/perf/README.md`). VM-layer changes still
A/B through `tool/perf.sh diff`; the web harness catches dart2js-only and
render/memory effects the NullDevice VM sweep can't. Image-codec changes do
have a VM window: a scenario can opt into the `decodeImages` measure
(`"measures"` in scenarios.json), which times `decodePdfImagePixels` over
every image the pages draw and reports `decodeMs`.

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
One-tap self-signed identities are in: `EcPrivateKey.generate` + RFC 6979
`ecdsaSign` + `buildSelfSignedCertificate` (pdf_cos - P-256 keygen and an
X.509 v3 builder, KAT'd against RFC 6979 vectors) feed
`PdfSigningIdentity.generate` (`signing_identity.dart`, with `toPem`/
`fromPem` persistence) and `PdfEditor.saveSelfSigned` /
`saveSignedEcdsa` / `saveSelfSignedPades` (ECDSA CMS via
`cmsSignDetachedEcdsa`). A self-signed cert reads as "signed, validity
unknown" outside our own `PdfTrustStore`; pair with a default TSA
(`PdfDefaultTimestampAuthority`) B-T for trusted time. Org-CA mode is in:
`buildCaCertificate` + `issueCertificate` (pdf_cos) feed
`PdfSigningIdentity.generateCa` + `ca.issue(...)` - members chain to a
shared CA and validate via `PdfTrustStore.trusting([caDer])`. Flutter key
storage + the "Create signing identity" UI are in dart_pdf_editor
(`PdfIdentityStore`/`InMemoryIdentityStore`/`SecureIdentityStore` on
flutter_secure_storage; `CreateSigningIdentityForm` /
`showCreateSigningIdentityDialog`). Sigstore/Fulcio keyless (Tier 3) is in
`fulcio.dart` (pdf_document): `fulcioSigningIdentity({oidcToken, transport})`
mints an ephemeral P-256 key, proves possession (`fulcioProofOfPossession` =
ECDSA over `sha256(subject)`), POSTs the Fulcio v2 `signingCert` request
(`buildFulcioSigningRequest` + `parseFulcioCertificateChain`, transport
injected like the TSA - `PdfFulcioTransport`/`PdfFulcioAuthority`) and wraps
the short-lived chain in a `PdfSigningIdentity` to sign B-T. `pdf_cos` gained
`ecSubjectPublicKeyInfo` + `pemEncode`; in-process fake Fulcio in
`pdf_test_fixtures` (`test_fulcio.dart`, verifies the proof, issues from a test
CA). The tiers (self-signed, org CA, timestamps, keyless, Actalis import) are
written up in `doc/signing-identities.md`. #322 is complete. Keyless is wired
into the app's Digitally sign dialog and **on by default off-web**:
`app/lib/keyless_signing.dart` (`fulcioHttpTransport`, DigiCert
`defaultTimestampClient`, `keylessSigningIdentity`) +
`PdfEditingController.addKeylessSignature` (B-T). Sign-in uses Sigstore's
**public** OAuth broker (`oidc_signin.dart`/`oidc_pkce.dart` - Dex at
oauth2.sigstore.dev, client `sigstore`, PKCE + loopback, like cosign), so no
OAuth registration is needed; `EditorScreen.oidcTokenProvider` is the injected
seam (`app.dart` wires it off-web; null hides the option, or pass your own for a
custom IdP). Loopback needs `dart:io`, so web gets a stub via conditional
import.
Content editing is in: `PdfEditor.stampPage` (text/shapes/JPEG via
`PdfStamp`), `PdfPageElements.of` + `PdfEditor.deleteElements` (element
enumeration with approximate bounds, stream rewriting), and
`PdfEditor.replaceText` (matches across a line's shown
strings and consecutive Tj/TJ runs, with width-compensated re-measurement
from the font's /Widths so following text holds position; composite
/Type0 runs are handled too for the Identity-H/CIDFontType2/Identity-
CIDToGIDMap shape - the composite font model is `Type0Font`
(`type0_font.dart`): `Type0Font.decode` (lenient, for extraction) and
`Type0Font.forEditing` (strict eligibility gate as its construction
contract) both read text from /ToUnicode + widths from /W in one place;
editing re-encodes replacements through the embedded font's own cmap so
any glyph the program carries can be typed, and merges new glyphs'
advances + Unicode into the descendant /W and /ToUnicode via
`commitFontDict`. `content_editor_type0.dart`'s `_Type0RunEditor` is the
thin editor-side wiring (fallback page-resource allocation, updater
marking). When the document font can't draw a character - a subsetted
font dropped it - `replaceText(fallbackFonts:)` embeds a style-matched
bundled fallback as a new page /Font resource and emits that replacement
between Tf switches (the editor passes the DejaVu trio via
`loadFallbackFonts()`); within-line only - CFF/non-Identity Type0 still
out) - all in `content_editor.dart`/`content_elements.dart`. The
flatten→match→splice→kern→coalesce run-rewrite engine is shared:
`TextRunRewriter` + `RunCodec` (`content_run_rewriter.dart`, a
document-free standalone lib so the kern/coalescing math is unit-testable
against a fake codec), with simple / styled / Type0 / Type0-fallback
codecs. `PdfPageElements` decodes Type0 runs through `Type0Font` so
`element.text` is real Unicode (what the content-edit UI shows and passes
as `find`). The content-stream tokenizer (`ContentStreamParser`) now
lives in pdf_cos.
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
`cmsVerify` and `X509Certificate.isSignedBy`). Overprint (/OP, /op, /OPM;
§8.6.7) is parsed into the graphics state and delivered via
`PdfDevice.setOverprint`; `CanvasPdfDevice` approximates it with a `darken`
(per-channel min) composite for the common neutral-ink-over-colour case (a
no-op over white, so defensive `op` pages are unaffected - see
doc/dev-log/2026-07-23-overprint-compositing.md). Remaining gaps:
faithful subtractive overprint (DeviceCMYK-backdrop knockout, OPM 0/1,
text/image overprint) needs a CMYK/spot colorant buffer, so GWG030's
"over CMYK" patches stay a tolerated Ghent deviation; JPX subsampling +
PCRL/CPRL, rendering intents/BPC in ICC.
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
swaps. `PdfEditingToolbar` is the stock chrome. `PdfViewer(editing:)`
(and `formController:`) reads the current revision from the controller
and subscribes to it itself, so the host neither passes `document` nor
rebuilds the viewer as revisions land - `document` is only the
no-controller reader path (`_revisionController`/`_document`/
`_onRevisionControllerChanged` in pdf_viewer.dart). The example app
shows the wiring.
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
