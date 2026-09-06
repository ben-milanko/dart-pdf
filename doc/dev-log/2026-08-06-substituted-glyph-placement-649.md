# Exact placement for substituted glyphs (#649)

Second half of #647. That issue reported the selection band sitting beside
the glyphs; #648 fixed the *range → geometry* half (`quadsFor` /
`positionNear` now use exact per-character advances). This is the other
half: where the substituted glyphs actually land.

## The defect

For a run with no embedded font program, `CanvasPdfDevice.drawText` shaped
the whole string with a substituted system font and applied **one uniform
horizontal scale** so the run total matched the PDF's advance:

```dart
final scaleX = targetWidth / layout.width;
canvas.scale(scaleX / renderSize, -1 / renderSize);
layout.paint(canvas, Offset(0, -layout.baseline));
```

That pins the run's two **endpoints** and nothing between them. Interior
characters land at the substitute's own advance distribution. On page 1 of
the demo document - a 77-character line drawn as a single `Tj` in
non-embedded 12pt Helvetica - the drift is zero at both ends and **4.4pt at
its worst, mid-run**: about two thirds of a lowercase glyph.

Selection bands, search highlights, markup placed over a selection and
content-element hit boxes all derive from the PDF's own advances, so every
one of them reads as offset against the drawn glyphs by that amount.

## The fix

`PdfTextRun.charOffsets` (added by #648) is the em-space pen offset of
every character boundary, and it is populated for substituted fonts
precisely because it needs only metrics, not outlines. The device now lays
the run out at those offsets instead of scaling the substitute's
distribution to fit.

Three pieces:

1. **`PdfInterpreter`** collects the table for a run with **no glyph list**
   whether or not `collectCharOffsets` was asked for. That flag stays the
   opt-in for *every* run (text extraction wants embedded runs too); an
   embedded run's `glyphs` already carry the same positions, so a painting
   walk still pays nothing on the common embedded-font page.
2. **`render_command_codec`** carries the table across the worker hop, for
   substituted runs only (format version 4 → 5). An embedded run's
   transcript is unchanged in size. `TranslatingPdfDevice` was dropping the
   spacing fields as well as the new table on its way through a tiled
   pattern cell; it carries all of them now.
3. **`CanvasPdfDevice._buildPlacedLayout`** builds the run from parts, each
   drawn at the offset the PDF gives it.

Behind `CanvasPdfDevice.exactSubstitutedGlyphPlacement` (on by default).

### Words, not characters

The obvious reading of the issue - one part per character, each at
`charOffsets[i]` - is exact, and it was the first implementation. It is
also a `drawParagraph` per character, which measured **3.7x the record pass
and 1.6x the full DPR-2 raster** on a page of 5,500 characters of
non-embedded prose. That is not a price this fix is worth.

So the unit is the **word** - a maximal span of non-whitespace characters -
placed at its own offset and shaped whole. A word is broken down into
characters only when it needs to be: `_wordHolds` walks it and compares the
substitute's own cumulative advance against the PDF's at **every character
boundary**, and any excursion past `_placementToleranceEm` (0.02 em, 0.24pt
at 12pt) sends that one word to per-character placement.

Checking every boundary rather than the word's total is the whole point:
matching a total while the interior wanders is the defect being fixed, and
a two-character word can have an exact total with a badly placed interior
(`substituted_glyph_placement_test` pins exactly that case).

What this buys: **word origins are always exact**, so drift can never
accumulate along a line - the 4.4pt case is structurally impossible.
Within a word the error is bounded by the tolerance, an order of magnitude
under what the issue reports, and where even that would be exceeded the
characters are placed individually. It also keeps intra-word kerning, which
is why most substituted text renders unchanged.

### Dropping the substitute's kerning is the point, not a cost

`_composableRun` - #454's gate for the *natural-advance* composition - is
deliberately narrow (no lowercase, letters may only neighbour digits or
spaces) because composing there drops the substitute's cross-character
kerning and the whole-run rendering was the reference.

Placement inverts that reference. A PDF expresses its kerning as `TJ`
adjustments; those are already inside `charOffsets`. The substitute's own
kerning is not the document's - it is error. So `_placeableRun` does not
care about kerning at all; it only asks whether the script lays one glyph
out per character (Latin, Greek, Cyrillic, the common symbol blocks, CJK,
Hangul syllables). Arabic, Hebrew, Indic, South-East Asian, Hangul jamo,
combining sequences and astral characters keep whole-run shaping, as do
vertical and RTL runs, which get no table in the first place.

### The scale is measured over ink alone

The glyph *shapes* still take one uniform squeeze - scaling each part to
its own advance would squeeze an `i` far harder than an `o` and look ragged
- but the ratio is `Σ natural ÷ Σ PDF advance` over the **non-whitespace**
characters. That keeps two things out of it: the substitute's idea of a
space (Skia's reported width for a lone whitespace layout is not something
to build on) and the run's Tc/Tw, which are already inside the offsets. The
space between two placed words is therefore whatever the PDF says, not
whatever the substitute would have drawn - which is the second half of why
lines stop drifting.

As a consequence per-character layouts are now built with
`applySpacing: false`: baking Tc/Tw into a glyph the caller positions
itself would double-count it, and the `_glyphCache` key never carried
spacing anyway, so the key is now honest rather than saved by a gate.

Note the algebra: with the layout reporting `run.width × k` for a layout
laid out at `k` units per em, the caller's own
`scaleX = width × renderSize ÷ layout.width` recovers `renderSize ÷ k`, so
part `i` lands at exactly `offsets[i]` em regardless of the run's total.
`run.width` cancels out of the positions entirely - it only has to be
positive.

### The endpoint trade

Whole-run shaping pins both endpoints exactly and gets every interior
boundary wrong. Placement makes the reverse trade: every part's origin is
exact, and the **last glyph's shape**, drawn at the run's average squeeze
rather than its own, may overhang the run's end by a few percent of an em.
That is the right way round - the origins are what selection, search and
hit-testing are computed from. `substituted_glyph_placement_test` pins both
sides of the trade so neither can drift silently.

## Gotchas

- **A placed layout owns its parts.** #454's composed layouts borrow from
  `_glyphCache` and are transient for exactly that reason - the cache would
  dispose a painter out from under them. A placed layout is *cached* (keyed
  by text + style + a hash of the offsets, since the same text under
  different advances is a different layout), so it shapes its own parts and
  disposes them: `_TextLayout.composed(ownsParts: true)`.
- **`_trimmedForPaint` had to slice the table.** A leading space carrying a
  large `Tw` is how tabular content reaches its column; the device paints
  the trimmed core and translates by `leadingSpace`. The sliced offsets are
  rebased by **`run.leadingSpace`**, not by `offsets[start]`, so a
  disagreement between this trim and the interpreter's per-glyph visibility
  test shifts nothing - every character keeps its absolute page position.
  `_trimEdges` (a `String.trim()`) became `_isTrimWhitespace`, an
  index-wise predicate over the same code-unit set, because the slice needs
  indices.
- **A gradient or stroke keeps whole-run shaping.** Both paint through
  their own fresh whole-run `TextPainter`, which no part can stand in for,
  and the layout's width feeds the `scaleX` those painters are drawn under.
- **One paragraph with a span per character does not work.** It would be a
  single draw call, with each span's `letterSpacing` stretching that
  character to the PDF's advance. The engine's reported boxes say the
  spacing lands after the cluster; the rendered ink says otherwise, and the
  two disagree differently for positive and negative spacing. Positions
  could not be made exact that way, so it was abandoned - see the git
  history of this branch if it looks tempting again.
- **The transcript declines a table of the wrong length** rather than
  indexing off the end of the run, the same way `deserializePageText`
  already did for extraction.

## Perf

- `tool/perf.sh diff HEAD dartpdf-corpus` (VM sweep, 4 interleaved runs):
  **VERDICT OK**. `interpretMs` 1.014x, `extractMs` 1.007x, `peakRssBytes`
  1.002x - the per-run `charOffsets` list on substituted runs is noise, and
  embedded-font pages allocate nothing new.
- Paint, on a synthetic worst case (55 lines × 100 characters of
  non-embedded Helvetica, and a *fixed-pitch* substitute, so **every** word
  fails the tolerance and every character is placed individually): record
  1.9 → 3.9 ms/page, full DPR-2 raster 15 → 21 ms/page. A substitute whose
  relative widths track the PDF's keeps its words whole and costs one draw
  per word; the flutter_test font cannot, which is what makes this a bound
  rather than an estimate.
- Pages whose fonts are embedded record the same commands as before, byte
  for byte.
- Not measured here: the real-Chrome harness (`tool/perf.sh webdiff`) on a
  text-heavy scenario, which is the number that decides whether the
  tolerance wants loosening. Worth running before assuming this is free on
  a standard-14 document.

## Baselines

`ghent_render_test` only pixel-compares on macOS (baselines are rendered
there; CI/Linux rasterizes text with different fonts and skips the diff),
so this change needs the Ghent baselines re-accepted with `GHENT_UPDATE=1`
on a macOS checkout for any patch whose text is not embedded.
