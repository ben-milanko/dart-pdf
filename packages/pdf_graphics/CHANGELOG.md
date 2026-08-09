# Changelog

## 3.4.0

- Add exact per-character pen offsets to `PdfTextRun` and
  `PdfExtractedRun`. Selection, search highlights, and hit testing now follow
  proportional glyph widths instead of interpolating evenly across a run
  (#647, #648).
- Carry those offsets through render-command and text-cache serialization so
  worker rendering and cached extraction preserve identical text geometry.

## 3.3.1

- Lockstep patch release to align the dart-pdf package suite at 3.3.1. No
  public `pdf_graphics` API changes since 3.3.0.

## 3.3.0

- Lockstep minor release to align the dart-pdf package suite at 3.3.0. No
  public `pdf_graphics` API changes since 3.2.0.

## 3.2.0

- Render third-party FreeText annotations without appearance streams more
  faithfully: callout text uses the inset text box, long lines wrap, quadding
  is honored, and semantic fill, border, and leader-line styling is painted
  from the annotation dictionary (#621).

## 3.1.1

- Lockstep patch release to align the dart-pdf package suite at 3.1.1. No
  public `pdf_graphics` API changes since 3.1.0.

## 3.1.0

- Render overprint (`/OP`, `/op`, `/OPM`, §8.6.7) faithfully, as the
  subtractive colorant operation it is. State parses into the graphics state
  and is delivered via `PdfDevice.setOverprint`, and the interpreter composites
  an overprinting draw in a real CMYK/spot **colorant buffer**
  (`PdfOverprintCompositor`) before any device sees it, so a DeviceCMYK
  backdrop and a spot backdrop of the same RGB colour — indistinguishable to
  any RGB compositor — now overprint differently. New public
  `PdfColorants`/`PdfInkColorants` and `PdfColorSpace.inkColorants`; new
  `PdfInterpreter(resolveOverprint:)`. The buffer is built only for pages whose
  ExtGStates declare overprint, and declines over content it cannot read
  (images, shadings, transparency groups, translucent paint, ICC/RGB colour),
  where `CanvasPdfDevice`'s `darken` stand-in still applies. Ghent GWG030 now
  grades all twelve of its patches as passing, and the DeviceN overprint
  patches GWG190/191/192 pass both vector cases (#502).
- Images overprint correctly inside the colorant buffer too: sampled images
  report their per-sample colorant readings instead of a flattened RGB, so an
  image over a tinted backdrop knocks out and survives the same way vector
  paint does (#604).
- Re-synchronise the overprint state before every fill and stroke: it was
  delivered only from `gs` and `Q`, so overprint switched on inside a form
  XObject, a tiling-pattern cell or a soft-mask group leaked out and darkened
  everything drawn afterwards (#502).
- Fill four silently-missing fidelity gaps (#546): print-vs-screen annotation
  visibility (`drawAnnotations` gains a `forPrint` flag; screen behaviour
  unchanged), fallback appearance synthesis for annotations without an /AP
  (Polygon/PolyLine, Link borders, FreeText via /DA, non-text button widgets),
  the Type 3 `d1` colour lock (§9.6.5), and image /SMask /Matte un-preblend
  (§11.6.5.3), which removes soft-mask edge fringing.
- Restore the blend mode on form/appearance exits: a non-Normal blend set
  inside a form XObject or annotation appearance no longer leaks into the
  surrounding content (#462).
- Stop word spacing ballooning substituted table digits (#567).
- Recording/painting performance: a resumable page-content walk lets an
  interrupted incremental record continue instead of restarting (#530);
  tiling-pattern cells and Type 3 glyphs are recorded once and replayed per
  occurrence (#524, #535); parsed colorspaces, shadings, and functions are
  cached per document (#534); sRGB-equivalent ICC profiles bypass the colour
  transform (#531); Coons/tensor mesh patches subdivide adaptively (#536);
  colour conversion during record serialization is memoized and a page's
  image decodes are reused across its records (#451).

## 3.0.0

Lockstep major release (a breaking change in `dart_pdf_editor` moves the whole
suite to 3.0.0). `pdf_graphics`'s own public API is unchanged.

- Parse overprint state (`/OP`, `/op`, `/OPM`) into the graphics state and
  deliver it via `PdfDevice.setOverprint`; `CanvasPdfDevice` approximates
  overprint with a `darken` (per-channel min) composite for the common
  neutral-ink-over-colour case — a no-op over white, so pages that set the flags
  defensively over the page background are unaffected (#502).
- Composite a transparency-group form XObject drawn under a non-Normal blend
  mode into its own layer so the group blends onto the backdrop as a single
  object (§11.6.6); previously the outer blend mode leaked and an opaque group
  could paint as a solid box over the page (#505).
- Approximate the Multiply blend mode as alpha when printing so highlights are
  not printed as opaque blocks (#461).
- Cache parsed content operators for form XObjects, annotation appearances, and
  soft masks instead of re-tokenising them on every paint (#471).

## 2.1.0

- Paint sub-pixel strokes as solid hairlines instead of fading them: a stroke
  narrower than a device pixel now draws at full opacity at hairline width,
  matching Acrobat and pdf.js, so CAD linework stays legible when zoomed out
  (#426).
- Honour the `/Indexed` palette when the base is a JPEG2000 image (#431), and
  decode `/Indexed` images over a `/Separation` or `/DeviceN` base (#430).
- Render non-nested radial shadings as a Gouraud cone mesh
  (`PdfShading.toRadialConeMesh`). A radial whose circles are not nested (an
  `r0=0` focal outside the `r1` circle) cannot be expressed as a Skia two-point
  conical gradient - the far disk maps to the swapped side of the
  parametrisation, so an `/Extend=false` end dropped the disk interior and left
  only a crescent. `toGradient` now returns null for those and the interpreter
  paints the mesh; nested and concentric radials still use the device gradient
  (#387).
- Render ZapfDingbats ornament glyphs (codes 0x80-0x8D) instead of tofu (#386),
  and map Symbol's built-in encoding along with the Greek and math glyph names
  (#390).
- Evaluate every input of a type 0 (sampled) function; multi-input samples
  previously read only the first (#409).
- Cache parsed ICC profiles per document rather than re-parsing per image or
  colour-space use (#399).
- Lead the content-operator switch with the path group, the hottest operators
  in a typical page (#401).
- Keep incremental aggregates in the reflow line-banding loop instead of
  recomputing them per candidate line (#407).

## 2.0.0

- Major version bump for the 2.0.0 package suite (breaking change in
  `dart_pdf_editor`; the graphics API is source-compatible with 1.4.7).
- Invert CMY when decoding YCCK/Adobe-inverted JPEGs so CMYK photos embedded
  as DCTDecode render with correct colour, matching pdf.js (#370).
- Support vector printing on Windows and Linux: the page is streamed to the OS
  print system as vector content rather than a rasterised bitmap (#303).
- Extract a shared `PdfColorSpace` module so colour-space resolution is unified
  across the fill/stroke and image-decode paths (internal refactor, #310).

## 1.4.7

- Resolve the Separation/DeviceN tint transform once per distinct sample
  tuple (memoised, cap-bounded) instead of once per pixel, and stop
  decoding a non-JPEG image base twice under a DCTDecode /SMask —
  cutting a 62-page print export's worst DeviceN image from 23.7 s to
  98 ms with bit-identical output across the corpus (#282).

## 1.4.6

- Keep Arabic tashkil and other zero-advance marks with their base glyph when
  reconstructing page text, so extraction and selection follow logical order
  even when the content stream paints each mark as its own positioned run.
- Ignore Unicode BiDi formatting controls in literal `PdfPageText.findAll`
  queries, so right-to-left text copied out of a page can be pasted back into
  search and still match.
- Decode scaled and region CCITT and 1-bit gray images straight into the
  display raster, skipping the native-size RGBA expansion that large scans
  previously paid for.

## 1.4.5

- Preserve logical word order while reconstructing Arabic and other
  right-to-left text, including multi-word lines and mixed-direction content.

## 1.4.4

- Version bump to keep the dart-pdf package suite aligned at 1.4.4. No
  graphics API changes since 1.4.3.

## 1.4.3

- Add geometry-free sparse-strip replay profiling so renderers can detect
  painter-order fragmentation before path flattening and atlas generation.

## 1.4.2

- Version bump to keep the dart-pdf package suite aligned at 1.4.2. No
  graphics API changes since 1.4.1.

## 1.4.1

- Add retained raster scenes and sparse strip plans for fast deep-zoom replay
  of dense vector, text, and image pages.
- Re-sharpen all image types under deep zoom and stream dense content through
  recording paths to reduce latency and memory pressure.
- Add reusable raster geometry, strip binning, curve flattening, and stroke
  contour primitives used by native-isolate and Web Worker rendering.

## 1.4.0

- Version bump to keep the dart-pdf package suite aligned at 1.4.0. Rendering
  changes in this cycle support the editor's color-processing, cloud polygon,
  and large-document interaction improvements.

## 1.3.2

- Version bump to keep the dart-pdf package suite aligned at 1.3.2. No
  graphics API changes since 1.3.1.

## 1.3.1

- Interpreter color-space handling now uses a shared resolved color-space
  path for fill and stroke colors, keeping calibrated, ICC, Indexed,
  Separation, and single-colorant DeviceN `sc`/`SC` resolution consistent.

## 1.2.3

- Version bump to keep the dart-pdf package suite aligned at 1.2.3. No
  graphics or interpreter changes since 1.2.2.

## 1.2.2

- The interpreter now checks for cancellation while walking a page's content
  so a render can be preempted mid-interpretation - used by the viewer's
  background render worker to drop superseded jobs on fast scrolls.

## 1.2.1

- Add a package example for pub.dev scoring.

## 1.2.0

- Search and text-extraction plumbing used by the standalone app's OCR and
  responsive viewer updates.
- Version bump to keep the dart-pdf package suite aligned at 1.2.0.

## 1.1.0

- Performance: a substantially faster interpreter: font-info caching,
  inlined path building, text-show memoization, a shared content-stream
  parse, and scan-only image collection. dart-pdf now renders faster than
  PDFium across the benchmark corpus.
- Background rendering: a record/replay split (`PdfRenderCommand` +
  `RecordingDevice`) captures a page's draw operations so interpretation
  can run off the UI thread. This is the pure-Dart foundation for the editor's
  background-isolate and Web Worker render backends.
- Reflow: `PdfReflowPage` now exposes `items`: text blocks and images
  interleaved in reading order (`PdfReflowItem`/`PdfReflowImage`, with the
  `blocks`/`images`/`text` getters unchanged). The extractor records placed
  images with their page-space bounds and folds each into the read where it
  sits, drops decorative rules and tiny icons, and de-duplicates repeated
  watermarks. Bullet and numbered list items are split into their own
  blocks (`PdfReflowBlock.isListItem`) instead of folding into the prose.
- Fonts: CJK CMap decoders for EUC-JP, GBK, Big5, and UHC charsets, so more
  non-embedded CJK text renders and stays selectable.
- Patterns: tiling-pattern color approximation when a glyph's font is
  substituted.
- Fix: JPEG 2000 tile-part desynchronization, and indexed Lab color
  palettes now decode correctly.

## 1.0.0

First stable release. Changes since 0.1.0:

- Color: Lab, CalGray, and CalRGB CIE-based color spaces; calibrated
  Separation/DeviceN alternate spaces; Indexed color; and pure-Dart
  DeviceCMYK JPEG decoding for correct print-color rendering.
- Fonts: a Type 1 parser; CFF improvements (seac accented-glyph
  composition, encoding supplements, per-FD font-matrix composition);
  TrueType `post`-table glyph-name lookup when there is no usable cmap;
  custom `/Encoding` and ZapfDingbats glyph resolution; vertical writing
  mode (Identity-V / WMode 1) for Type 0 fonts; and CJK CMap support for
  non-embedded Adobe-Japan1 and legacy GBK fonts.
- Transparency: isolated knockout groups (`/K true`); optional content
  groups (OCG) with visibility expressions for correct layer handling.
- Images: full-resolution `/Mask` stencils, and JBIG2 pattern
  dictionaries with halftone regions.
- Patterns: tiling-pattern and shading-pattern fills rendered through
  glyph outlines for text.
- Text: paragraph-aware reflow extraction for reading view; rotated text
  selection geometry.
- Robustness: pages with invalid bounding boxes fall back to valid
  geometry instead of collapsing.
- Document-AI seam: `PdfDocumentContext.of(document)` gathers a document's
  text, form fields, and annotations into a clean, serializable shape for a
  host-supplied language model, and `PdfDocumentActionSink` describes the
  editing actions an agent can drive. A thin adapter over the existing
  extraction/editing surface. The model and transport are host-provided.

## 0.1.0

Initial release.

- Content-stream interpreter covering the full operator set: paths,
  clipping, transparency groups, soft masks, blend modes, optional
  content, type 0-4 functions.
- Device interface: implement one class to render PDF pages anywhere.
- Font engine: Type 1, TrueType, CFF, Type 0/CID, Type 3; embedded and
  standard-14 metrics.
- Shadings 1-7 including mesh parsing; tiling and shading patterns.
- Color: ICC profiles (gray TRC, matrix/TRC, mft1/mft2/mAB LUTs),
  Separation/DeviceN, Indexed, Lab.
- Text extraction with selection geometry, search, and rotation-aware
  page geometry.
- Annotation appearance rendering and form-field appearance support.
