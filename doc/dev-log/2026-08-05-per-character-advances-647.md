# Per-character advances for selection geometry (#647)

Selection and search highlights sat beside the glyphs instead of on them.
`PdfPageText.quadsFor` had carried a placeholder since the beginning:

```dart
// approximate within-run positions by character fraction; per-glyph
// geometry arrives with the font engine
final logicalStart = (overlapStart - run.startIndex) / run.text.length;
```

Slicing a run's width by *character count* assumes every character is the
same width. In a proportional font they are not. On the `buildClassicPdf`
fixture - `Hello, world!` in 24pt Helvetica, the issue's own repro -
double-clicking `world` produced a band 3pt to the right of the word and
6.5pt too narrow. The error scales with how uneven the run is: `I` is
0.278em and `W` is 0.944em, so on `IIIIII WWWWWW` the highlight misses by
more than a quarter of the run, which is the "roughly 1/3" the reporter saw.

Both halves of selection were wrong and compounded: `positionNear` mapped a
click to a character by the same linear fraction, then `quadsFor` mapped it
back.

## The fix

The interpreter already accumulates the exact pen position per glyph - it
just threw it away for anything but embedded outlines. Now it can keep it:

- `PdfTextRun.charOffsets` - em-space offset of every character boundary,
  length `text.length + 1`, last entry `== width`.
- `PdfInterpreter(collectCharOffsets:)` - **off by default**. Painting walks
  get the same positions from `PdfTextRun.glyphs` when the font is embedded
  and would otherwise pay a list per run for nothing;
  `PdfTextExtractor._interpret` turns it on.

The flag is what makes this work for the reported case at all. `glyphs` is
only built for `font.hasOutlines || font.isType3`, so a **non-embedded**
standard-14 Helvetica - exactly the issue's PDF - has no glyph list.
`charOffsets` needs only the metrics, so it covers substituted fonts too.

`PdfExtractedRun.charOffsets` carries the table through to
`quadsFor`/`positionNear` (which now binary-searches for the nearest
boundary instead of scaling a fraction).

## Gotchas

- **The BiDi pass invalidates the table.** `_bidiLine` reverses runs and
  re-splits them per glyph, so the offsets no longer line up with the
  piece's characters. `_sliceCharOffsets` returns null unless the piece is
  the source's own characters in their own order (`sourceEnd - sourceStart
  == text.length`, and not RTL). RTL keeps the old interpolation exactly -
  it already had per-glyph geometry from its own path.
- **Vertical writing mode gets null**: the pen advances along y there, so a
  per-character *x* offset is meaningless.
- **One code can map to several characters** through a /ToUnicode ligature.
  The PDF positions the code, not its pieces, so the advance splits evenly
  across them - the invariant that matters is that the table stays
  `text.length + 1` long (asserted at the emit site).
- **Offsets are clamped non-decreasing.** A negative `Tc` tighter than a
  glyph's own width walks the pen backwards; consumers binary-search these.
  `_bidiLine` already did the same `math.max` for glyph offsets.
- **Two codecs, not one.** `serializePageText` in `render_command_codec.dart`
  is the render-worker hop - the app extracts text off-thread, so *that* is
  the path the fix actually travels in production; missing it would have
  left the bug live everywhere but tests. `pdfEncodePageText` in
  `text_cache.dart` is the on-disk tier (magic bumped `PTX2` → `PTX3` so
  stale blobs miss rather than mis-parse).

## Measurements

`tool/perf.sh gate`: 12 inputs, 13 counters within 3%.
`tool/perf.sh diff d84479b type3-text-sweep` (~7400 glyphs/page, the densest
text scenario): `interpretMs` 0.953x, `extractMs` 1.037x, `peakRssBytes`
1.033x - VERDICT OK. The ~4% on extract is the offset table itself; the
render path is untouched because the flag leaves `charOffsets` null.
