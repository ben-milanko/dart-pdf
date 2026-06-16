# Changelog

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
