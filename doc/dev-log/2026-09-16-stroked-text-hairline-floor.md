# Stroked text ignored the device-pixel stroke floor (#912)

Reported as "the same PDF does not look clear in dart-pdf but clear and
vibrant in Okular", with no reproducer attached. The reproducer that *is*
checked in is pdf.js's own `test_corpora/pdfjs/zerowidthline.pdf`, whose last
line reads **"Stroked text with zero line width."**: pdf.js renders it solid
black, we rendered a ghost. Measured over that line at 1:1 (ink summed 0-1 per
pixel, a 190x25 pt window):

| | ink sum | pixels darker than 50% |
|---|---|---|
| pdf.js baseline | 642.4 | 561 |
| dart-pdf, before | **15.7** | **0** |
| dart-pdf, after | 629.1 | 638 |

## The defect

#426 established the rule for path strokes: Skia paints a stroke narrower than
a device pixel as a one-pixel line with its **alpha scaled down** by the
sub-pixel width, so a 0.06 pt CAD hairline came out at ~6% opacity. Reference
viewers paint it as a solid pixel, and `CanvasPdfDevice.strokeWidthFor` floors
it to Skia's transform-invariant hairline (`0`) to match.

Neither text path applied that floor.

* `_drawGlyphOutlines` (embedded outlines) passed `run.strokeWidth` to
  `canvas.drawPath` verbatim, so a thin positive width painted at the same few
  percent alpha.
* The substituted-font painter did worse than nothing with `0 w`: it rewrote
  the width to **one painter unit** (`ts / renderSize` page units, a hundredth
  of the em). That is 0.4 pt at 40 pt text - 36% alpha - and around a tenth of
  a point at the 12 pt body sizes real documents use, i.e. a few percent. So
  the one width the spec defines as *"the thinnest line that can be rendered"*
  (§8.4.3.2) was the one that vanished.

Text rendering modes 1/2/5/6 are not exotic: `0 w` is the initial line width,
so any producer that outlines display text or fakes bold with `Tr 2` without
setting a width hits this.

## The fix

Both paths now run the page-space width through `strokeWidthFor`, and the
substituted painter maps a floored `0` straight through instead of inventing a
width (`w <= 0 || ts <= 0 ? w : w * renderSize / ts`). A hairline stays one
device pixel at every replay scale, which is what the recorded page picture
needs - it is rasterized at several ratios. `pixelRatio: 0` (the annotation
appearance picture, #660) still disables the floor, so authored annotation
widths are untouched.

## Coverage

`test/text_stroke_floor_test.dart`. Coverage sums, not pixel hits - one row
across a glyph stem totals the stroke's device width whatever the antialiasing
does with it, which is what separates a 1 px hairline from a 0.06 px ghost.

- Embedded outlines are driven through `CanvasPdfDevice.drawText` directly,
  with an em-square glyph whose left stem is a plain vertical line: 0.06 pt and
  `0 w` measure ~1 px at 1:1 **and** at 333%, 2 pt measures 2 px and 6.7 px.
  (The interpreter does not route stroke modes on embedded fonts to the device
  yet - it fills the outline in the stroking colour, see below - so the device
  contract is what there is to pin; a replayed render-command buffer reaches it
  by this same door.)
- Substituted text is driven end to end from a PDF: `0 w` and 0.06 pt stroked
  runs must reach full-strength ink (peak > 0.9), and a 4 pt run must still lay
  down more than twice the ink of a hairline, so the floor cannot be read as
  "flatten every stroke to one pixel". Before the fix the peaks were 0.36 and
  0.05.

## Still open

- `PdfInterpreter` renders stroke modes on **embedded** fonts by filling the
  glyph outline in the stroking colour (`fill: embedded ? true : doFill`) - a
  deliberate, documented approximation that predates this, and one that would
  shift many pinned baselines to undo. `Tr 1` on an embedded font therefore
  paints a solid glyph rather than an outline, whatever this floor does.
- The flutter_gpu tile backend strokes text through its own expansion and has
  no floor either; it retires the accelerated session to the exact Canvas
  fallback once 128 paint units resolve below the MSAA coverage quantum, so
  dense sub-pixel linework already lands on the fixed path.
