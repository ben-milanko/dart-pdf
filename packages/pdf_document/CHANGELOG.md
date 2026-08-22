# Changelog

## 3.8.0

- Add the lazily materialized `PdfDocument.pages` view and keep document caches
  coherent through `CosDocument.revision`.
- Add `PdfEditImpact.pageOrderOnly` and reconcile page-order-only incremental
  edits without rebuilding unchanged page objects.
- Reduce repeated page-tree and annotation work during large-document startup,
  structural edits, undo, and redo.

## 3.7.0

- Add `SimpleFont`, the simple-font counterpart to `Type0Font`: one place that
  resolves a character code to text the way the renderer does (`/ToUnicode`,
  `/Encoding` `/Differences`, the built-in Symbol and ZapfDingbats encodings,
  then the base encoding), plus the reverse table for re-encoding replacements
  and the `/Widths` lookup.
- Fix content editing against fonts that remap their codes. `PdfPageElements`
  decoded a simple font's show string as Latin-1, so a subsetted font reported
  text such as `-=>-/>?-?@` for a page reading `05/08/2026`, and replacements
  were written back as raw code units. Element text, both run codecs, the `'`
  and `"` operators, and paragraph reflow now all go through the font's own
  encoding.
- Restrict a replacement to codes the font actually declares - a glyph name
  from the base encoding or `/Differences`, or a `/ToUnicode` entry - so a
  subset that dropped a character declines the edit instead of drawing notdef.
  Decoding keeps its lenient Latin-1 fallback. A named base encoding declares
  printable ASCII (0x20-0x7E) per Annex D.
- Move the Adobe glyph-name tables down from `pdf_graphics` to
  `src/fonts/encodings.dart` and export them, so the content editor and the
  font engine share one copy.

## 3.6.0

- Read Bluebeam FreeText paragraph styling from `/DS` and rich-text `/RC` when
  standard PDF entries are absent, preserving alignment, leading, character
  spacing, horizontal scale, and underline when editing or regenerating an
  appearance.
- Let FreeText annotations participate in opacity restyling, write opacity on
  creation, and rebuild their appearances without losing the selected alpha.

## 3.5.1

- Lockstep patch release for the scanned-page rendering fixes in `pdf_cos`,
  `pdf_graphics`, and `dart_pdf_editor`. No public document API changes.

## 3.5.0

- Let `PdfDocument.openSource` expose its requested first-paint page count as a
  temporary page-count hint when the source deliberately omits the rest of the
  page-tree walk. The full document opened during progressive handoff remains
  authoritative, while sparse page-one previews avoid recovery-scanning every
  intentionally absent leaf reference.

## 3.4.0

- Preserve the unresolved vector template on authored stamp annotations and
  expose it through `PdfAnnotation.stampTemplate`, allowing a placed stamp to
  return to a reusable collection without losing dynamic fields (#651).

## 3.3.1

- Fix annotation property edits duplicating the annotation when a page stores
  its `/Annots` array indirectly (#638).
- Preserve embedded font resources when changing FreeText colour, so restyled
  text continues to use the original embedded typeface (#641).

## 3.3.0

- Add lightweight diagnostics to `PdfDiskCache` for hits, misses, writes,
  oversize rejections, evictions, and byte totals, with `resetStats()` and a
  one-line `debugStats` summary. Manifest writes are coalesced across bursts so
  persistent page-raster caches do not rewrite an O(n) manifest for every
  entry (#615).

## 3.2.0

- Improve FreeText callout interoperability: recognize third-party callouts
  from their `/CL` geometry when `/IT` is missing or private, and clamp
  malformed or negative `/RD` insets to a usable callout text box (#621).

## 3.1.1

- Lockstep patch release to align the dart-pdf package suite at 3.1.1. No
  public `pdf_document` API changes since 3.1.0.

## 3.1.0

- Add `PdfEditor.compress()`/`PdfCompressionResult`: lossless file-size
  compaction on save. A whole-graph reachability pass drops the dead objects
  incremental edits accumulate, non-stream objects pack into object streams,
  and uncompressed streams are re-deflated (kept only when smaller). Never
  returns a larger file, includes pending edits, and refuses encrypted
  documents. Decoded stream content is preserved bit-for-bit (#368).
- Hyperlink authoring: `addLinkToUri` / `addLinkToDestination` /
  `addLinkToPage`, mirroring the text-markup creators' quad shape so a text
  selection turns into a link. /Rect bounds the quads, each quad becomes an
  active /QuadPoints region, /Border is suppressed by default, and an
  underline or border decoration bakes an /AP (#500).
- Crop placed images: the image-stamp appearance bakes a normalized crop
  rect, read back via `PdfAnnotation.imageStampCrop`; opacity restyles and
  resizes preserve the crop (#504).
- Render digital-signature boxes in the signer's local timezone (#570).
- Add `PdfAnnotation.isPrint` (§12.5.3 print-vs-screen visibility) (#546).

## 3.0.0

Lockstep major release (a breaking change in `dart_pdf_editor` moves the whole
suite to 3.0.0). `pdf_document`'s own public API is additive.

- Add `PdfEditor.saveSignedExternal`: delegates the RSA operation to a
  `PdfExternalSigner` callback so the private key can stay in a hardware keystore
  (Android KeyStore, iOS Keychain). `PdfSignatureAppearance` gains overridable
  `signedByLabel`/`dateLabel`/`reasonLabel`/`locationLabel`, and the visible `/M`
  and signature-box date now preserve a non-UTC `signingTime`'s offset (UTC
  input unchanged) (#507).
- Fix signature appearance detail text being clipped at the top of the
  signature box (#468).

## 2.1.0

- Cache `PdfPage` instances instead of rebuilding them per access, resolving
  inherited attributes live: a page holds only ancestor-derived values and
  reads its own `/Rotate`, `/MediaBox`, `/CropBox`, and `/Resources` from the
  dictionary, so the cache cannot serve a stale value after an edit (#418).
- Resolve `pageIndexOf` in O(1) through an identity map rather than walking the
  page tree (#397).
- Resolve a form widget to its page in O(1), cache the widget list, and hoist
  the `/Widths` lookup out of the per-glyph loop (#406).
- Reuse the caller's element snapshot on a targeted edit instead of
  re-enumerating the page's elements (#402).
- Support the incremental append save path (`CosUpdater.saveTail()`), so an
  incremental revision costs the size of the change (#413).

## 2.0.0

- Major version bump for the 2.0.0 package suite (breaking change in
  `dart_pdf_editor`; the document API is source-compatible with 1.4.7).
- Open documents from an asynchronous `PdfByteSource` so a remote or large
  local PDF can be rendered progressively as bytes arrive, rather than after
  the whole file is in memory (#328).
- One-tap self-signed signing identities: `PdfSigningIdentity.generate`
  (P-256 keygen + X.509 v3 self-signed cert) with `toPem`/`fromPem`
  persistence, `PdfEditor.saveSelfSigned` / `saveSignedEcdsa` /
  `saveSelfSignedPades` (ECDSA CMS), a default TSA
  (`PdfDefaultTimestampAuthority`) for trusted B-T time, and org-CA mode
  (`PdfSigningIdentity.generateCa` + `ca.issue(...)`) so members chain to a
  shared CA (#337).
- Sigstore/Fulcio keyless signing (Tier 3): `fulcioSigningIdentity` mints an
  ephemeral P-256 key, proves possession, requests a short-lived certificate
  from a Fulcio v2 authority (transport injected like the TSA), and wraps the
  chain in a `PdfSigningIdentity` to sign B-T (#322, #355).
- Internal refactors with no public API change: consolidate the composite-font
  path into one `Type0Font` module and one shared `TextRunRewriter`, and route
  text-box appearance generation through a single shared builder.

## 1.4.7

- Add a visible signature box for `saveSigned`/`saveSignedPades`:
  `PdfSignatureAppearance` describes the widget's page/rect, optional
  handwritten-signature or logo graphic, detail-line show flags, and
  background/border/text colours, rendered into the /AP /N form
  (name or graphic on the left, "Digitally signed by / Date / Reason /
  Location" auto-sized on the right). Output is byte-identical when no box
  is requested; document timestamps never get an appearance (#298).
- Round the corners of /Square annotations: `ContentWriter.roundedRect`
  bakes the radius into the /AP, persisted in /Border (§12.5.4) so it
  survives resize; `restyleAnnotation(cornerRadius:)` rounds or re-squares
  a placed rectangle in place (#297).
- Separate cloud/dash pattern scale from stroke width: the multiplier
  persists on /BE /I (`PdfAnnotation.cloudBorderScale`) and
  `restyleAnnotation(cloudScale:)` reproduces it across restyle and
  reshape; a cloud's /Rect is re-derived from the padded footprint so
  growing scallops no longer clip (#300).
- Recolour captured vector snapshots: `PdfVectorSnapshotEditing` gains
  `isVectorSnapshotStamp` and `recolorVectorSnapshot`, which forces every
  fill/stroke colour operator in the captured Form XObject to a target ink
  (recursing into nested forms, forking a private /Cap copy so other
  pastes keep their colours) while leaving geometry and images untouched;
  paste marks the stamp (DartPdfVectorSnapshot) (#301).
- Curl revision-cloud scallops inward with a trailing-foot lean for the
  hand-drawn look, keeping the outward apex extent (and BBox) unchanged
  (#295).
- Fill cloudy /Polygon annotations along the scalloped cloud path
  (fill+stroke in one pass) so the interior colour reaches the cloud edges
  (#287).
- Free-text appearances support line spacing, character spacing (Tc),
  horizontal glyph scaling (Tz), and underline (per box and per rich run),
  round-tripping through the annotation dictionary and `/RC`.
- Regenerate embedded-font and rich free-text boxes on resize (re-wrapping
  in the recovered face and preserving per-run styling) instead of falling
  back to the appearance stretch.

## 1.4.6

- Add operation-scoped page-content text replacement and expose the active
  font resource on text element snapshots for selection-driven editing.

## 1.4.5

- Version bump to keep the dart-pdf package suite aligned at 1.4.5. No
  document API changes since 1.4.4.

## 1.4.4

- Version bump to keep the dart-pdf package suite aligned at 1.4.4. No
  document API changes since 1.4.3.

## 1.4.3

- Add `PdfBlankDocument.create` for building standalone PDFs with one or more
  empty pages in a chosen standard or custom page size.
- Keep AcroForm text, button, and image appearances upright when fields are
  authored, filled, resized, or regenerated on rotated pages.

## 1.4.2

- Version bump to keep the dart-pdf package suite aligned at 1.4.2. No
  document API changes since 1.4.1.

## 1.4.1

- Add callout annotation authoring and editing, and correct cloudy polygon
  geometry and appearance generation.
- Add rich-text styling for in-place content text edits while preserving the
  surrounding PDF content structure.
- Centralize annotation capability policy and mutation impact tracking so
  editing operations invalidate only the document surfaces they change.
- Improve annotation, form, outline, page, redaction, reflow, and content
  editing robustness through the shared transaction path.

## 1.4.0

- Add document color-processing APIs that discover paint colors, replace
  multiple source colors in one pass, support page ranges, tolerance, and
  transparent replacements.
- Add cloudy polygon annotation appearance generation and resizing support for
  cloud-style shape markups.
- Improve annotation/page editing support used by the editor UI, including
  page-range extraction and more robust annotation duplication workflows.

## 1.3.2

- Add vector stamp templates (`PdfStampTemplate` and
  `PdfStampTemplateComponent`) with text, shapes, images, and saved-signature
  components. `PdfEditor.addTemplateStamp` writes them as normal stamp
  annotations with generated appearance streams.
- Stamp annotations can carry metadata (`stampType` and `stampTags`) and
  resolve dynamic `{{field}}` placeholders at placement time.
- Note and stamp appearances now account for page rotation when authored, so
  oriented pages receive counter-rotated annotation appearances.

## 1.3.1

- Annotation editing now handles malformed or indirect page `/Annots` entries
  consistently when adding, removing, reordering, flattening, signing, form
  editing, redacting, and pasting annotations. Invalid indirect `/Annots`
  values are left untouched and replaced by a valid page-owned array.
- Content rewriting, redaction, and structure-tagging paths now share the COS
  content-stream serializer, including inline-image round-tripping.

## 1.2.3

- Free-text annotations carry a horizontal alignment (left/center/right)
  through the `/Q` quadding: `addFreeText` and `addFreeTextRich` take an
  `align` argument, `PdfFreeTextStyle.alignment` reads it back, and resizing
  or re-editing a box preserves it. Omitting `align` keeps the previous
  behaviour - left for LTR text, right for RTL.
- Fix a free-text box auto-sized to its contents wrapping the last word onto
  a new line: the wrapper's strict width test now tolerates the sub-point
  floating-point round-off in `(lineWidth + 2*pad) - 2*pad`.

## 1.2.2

- Embeddable fonts: `PdfEmbeddedFont.parse` reads a TrueType (`.ttf`) or
  OpenType (`.otf`) file and `addFreeText` can now author text in it,
  embedding the font as a full-Unicode Type0/CIDFontType2 (Identity-H)
  composite with a `/ToUnicode` CMap - so authored text can use any font,
  not just the base-14 faces, and stays selectable, searchable, and
  portable. `PdfEmbeddedFont.fromFreeText` recovers the font from a box's
  own appearance for lossless re-editing.
- Fix non-Latin characters rendering as `??` in free-text annotation
  appearances.
- Fix free-text annotation appearances rendering sideways on rotated pages.
- Right-to-left text direction support in free-text annotations and
  AcroForm field appearances.
- Faster batch annotation deletion.

## 1.2.1

- Add a package example for pub.dev scoring.

## 1.2.0

- OCR text-layer injection is now used by the standalone app's downloadable
  on-device OCR flow.
- Version bump to keep the dart-pdf package suite aligned at 1.2.0.

## 1.1.0

- Page rotation: `PdfEditor.rotatePages(indices, degrees)` turns the named
  pages clockwise by a multiple of 90° (negative for counterclockwise),
  accumulating onto each page's current `/Rotate`.
- Vector snapshots: `PdfEditor.captureVectorSnapshot` captures a page
  region as detached vector graphics (`PdfVectorSnapshot`) and
  `pasteVectorSnapshot` re-materializes it onto any page as a /Stamp
  annotation whose appearance *draws* the captured content, so a snapshot
  pasted back into the PDF stays vector (crisp at any zoom), Bluebeam-style.
- Count tool: `PdfEditor.addCheckMark` places a Bluebeam-style check-mark
  stamp annotation (with `PdfAnnotation.isCheckMark`/`iconName`). It is the
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
  standalone PDF alongside the existing `appendPagesFrom` (insert pages
  from another document) and `extractPages` (arbitrary subset).
- OCR text-layer injection: `PdfEditor.injectTextLayer` writes recognized
  `PdfOcrSpan`s onto a page as invisible (render mode 3) text, sized and
  horizontally scaled to sit over each word. A scanned, image-only page
  becomes selectable, searchable, and extractable without changing how it
  looks. `applyOcr` (with a pluggable engine) lives in `dart_pdf_editor`.
- `PdfImageDocument`: assemble a brand-new PDF from a list of PNG/JPEG
  images, one page per image. This is the pure-Dart half of image/Office
  ingestion (multi-page TIFF, scans, camera shots).
- `PdfImportSource`: a host-provided seam for converting foreign formats
  (DOCX/XLSX/PPTX, …) to PDF bytes. Interface only; dart-pdf does not
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
