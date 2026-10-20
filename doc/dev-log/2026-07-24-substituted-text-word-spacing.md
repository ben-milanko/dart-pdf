# Substituted-font word spacing & edge whitespace (over-wide table digits)

## Symptom

A real-world PDF (ARTC ESC-21-03, the "Busbar Voltage Leak to Earth
Measurements" tables in §3.5.1/§3.6.1) rendered its numeric table cells as
enormous, distorted digits - the leakage-volts columns ballooned to several
times their size and overlapped, while the resistance column and body text
were fine. Every font on the page is a **non-embedded** standard TrueType
(Arial/Verdana/Tahoma, WinAnsiEncoding, no FontFile), so the renderer
substitutes a system/bundled font (DejaVu via `dart_pdf_editor_assets`).

Reproduce with real fonts (not the flutter_test **Ahem** font, which draws
every substituted glyph as a solid box and hides this): register DejaVu as
`Helvetica`/`DejaVu Sans`/`Times New Roman` via `FontLoader`, then
`PdfPageExport.exportPages` the page.

## Root cause

The affected cells set a large word spacing, e.g.

    /TT2 1 Tf  0.0034 Tc 8.0586 Tw  7.98 0 0 7.98 110.1 664.5203 Tm
    [(-)6( 0.)6(05 )2459(0.)6(1 )-7496(140000 )]TJ

`Tw 8.0586` (~8 em at this font size) is a **positioning** device - it pushes
the pen to the next column - applied to the single space in each little
segment (`( 0.)`, `(05 )`, ...).

The substitute paint path (`CanvasPdfDevice.drawText`) lays the whole run out
as one string and stretches it horizontally so its total advance matches
`PdfTextRun.width`. `width` (`advance / emScale` in the interpreter) folds Tw
in, so a segment like `"05 "` reported `width ≈ 9.7 em` while its visible
glyphs are ~1.1 em - the stretch blew the digits up ~8x. The device also
`letterSpacing: 0`'d the layout, so none of the spacing lived in the layout
either; it was all recovered by stretching glyph shapes.

Two distinct failure modes, both from the same conflation of *pen advance*
with *glyph extent*:

- **Trailing** space with large Tw: stretch target `width` includes it, but
  Flutter's `TextPainter.width` **drops trailing whitespace**, so `scaleX`
  explodes.
- **Leading** space with large Tw (`( 0.)`): must shift "0." right into the
  next column, but the whole-run model draws from the run origin and Flutter
  also drops leading whitespace - the glyphs can't move right, and `width`
  still over-stretches them.

## Fix

Reproduce the PDF's Tc/Tw as *real* spacing in the substitute layout, and hand
the device the visible-glyph geometry separately so trailing/leading
whitespace opens a genuine gap instead of stretching glyphs. `PdfTextRun`
gained four fields (all em units, all default to the previous behaviour):

- `letterSpacing` / `wordSpacing` (Tc/Tw normalised by font size; Tw is 0 for
  composite/CID fonts, which Tw never touches). The device applies them via
  `TextStyle.letterSpacing`/`wordSpacing`, so the layout's own advances match
  `width` (no shape stretching) and justified paragraphs spread correctly.
- `visibleWidth` - advance to the **end of the last non-whitespace glyph**
  (null when there's no trailing whitespace). The device stretches to this,
  matching Flutter's trailing-trimmed `layout.width`.
- `leadingSpace` - advance to the **start of the first non-whitespace glyph**.
  The device paints a whitespace-trimmed copy of the run, translated right by
  `leadingSpace`, stretched to `visibleWidth - leadingSpace`.

Crucially `width`, `transform`, and `text` stay whitespace-inclusive, so
**text extraction** (which reads inter-run gaps for word-break/selection
geometry off `width`/`transform`) is untouched - only painting trims.

`interpreter.dart` computes the two advances in the existing glyph loop; the
per-glyph visibility test is a non-allocating `_isBlankText` (matches Dart's
`String.trim()` whitespace set) rather than `text.trim().isNotEmpty`, since it
runs once per glyph on the hot text path. `canvas_device.dart` builds the
trimmed `paintRun` only when there is edge whitespace (`_trimmedForPaint`),
applies the `leadingSpace` canvas translation, and keys the layout cache on the
spacing so differently-spaced identical text doesn't collide. The per-glyph
compose path (#454) is disabled when spacing is present (it can't represent
the gaps).

## Files

- `packages/pdf_graphics/lib/src/device.dart` - four new `PdfTextRun` fields.
- `packages/pdf_graphics/lib/src/interpreter.dart` - `leadingAdv` /
  `visibleAdvance` accumulation, `_isBlankText`, emit the new fields.
- `packages/dart_pdf_editor/lib/src/canvas_device.dart` - apply
  letter/word spacing, trim + translate + stretch to visible width.
- `packages/pdf_graphics/test/interpreter_test.dart` - geometry contract test
  (trailing-space, leading-space, and plain-run cases with exact Helvetica-AFM
  advances).

## Notes / gotchas

- The flutter_test **Ahem** font masks this class of bug - always verify
  substituted-font rendering with real fonts registered.
- Ghent has 20 pre-existing colour/overprint baseline failures unrelated to
  this change (identical count on `main`); pdfjs pixel-compare (164) stays
  green.
