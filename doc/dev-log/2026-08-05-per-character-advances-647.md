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
- **Both codecs' tests passed with the offsets dropped.** The worker test
  compared search *hit counts*, and the disk-cache sample runs carried no
  `charOffsets` at all, so neither would have noticed a field missing from
  the wire. Both now compare geometry (quad corners, hit-test positions);
  the worker one was verified to fail with the field removed. A codec test
  that doesn't assert the new field buys nothing - and on the disk tier the
  failure would only appear on a *reopened* document, long after the suite
  went green.

## Measurements

`tool/perf.sh gate`: 12 inputs, 13 counters within 3%.
`tool/perf.sh diff d84479b type3-text-sweep` (~7400 glyphs/page, the densest
text scenario): `interpretMs` 0.953x, `extractMs` 1.037x, `peakRssBytes`
1.033x - VERDICT OK. The render path is untouched because the flag leaves
`charOffsets` null.

**The corpus sweep caught a real regression the single-scenario run didn't.**
`diff d84479b dartpdf-corpus` first came back `extractMs` **1.114x -
REGRESSED** (over the 1.10 gate), worst on `text-report-40p.pdf` at 1.45x.
Two causes, both obvious in hindsight:

- `_sliceCharOffsets` **copied the whole table per run**. The common case is
  one extracted run per source run, where the slice is the whole thing
  already rebased at 0 - so it now returns the source list directly. Nothing
  mutates it, and it saves an allocation *and* a copy on every run.
- the per-glyph loop read `charOffsets.last` to clamp against the previous
  boundary. That is a bounds-checked call once per glyph; `lastOffset` now
  tracks the tail in a local.

After both: `extractMs` **1.009x**, everything else ≤1.017x, VERDICT OK.

Two process notes worth keeping:

- The first corpus number was measured while sources were being edited
  mid-run. `CLAUDE.md` forbids that ("NEVER edit sources or run builds while
  a sweep is measuring") and it is not pedantry - `diff` interleaves
  checkouts of the ref and the working tree, so an edit lands inside
  somebody's measurement. It was discarded and re-run clean.
- `type3-text-sweep` alone said 1.037x and looked fine. The regression only
  showed on the 16-file corpus. For anything touching extraction, run the
  corpus scenario too - one dense synthetic document is not a substitute.
