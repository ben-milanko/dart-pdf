# Character spacing is a gap, not a shape (over-wide table digits)

A bridging-details table from a CAD-exported form (ArialMT/Arial-BoldMT,
none of them embedded) drew its row numbers - `3`, `4`, `5`, `6` - roughly
four times too wide, fat enough to read as a different, bolder typeface than
the rest of the sheet. Everything else on the page was fine.

The content stream says it plainly:

```
15.137 Tc 54.96 396.24 Td
( 3)Tj
```

At `/F1 9 Tf` that Tc is 1.68 em of character spacing per glyph - the export's
way of reaching the next column - so the pen steps 2.24 em across a digit the
font gives 0.556 em, after a leading space that steps 1.96 em.

## The defect

Exact substituted-glyph placement (#649) gives a substituted run one uniform
horizontal glyph scale and puts every origin on the PDF's own pen offset. The
scale was `Σ substitute advance ÷ Σ PDF pen step`. A pen step is a glyph's
width *plus the spacing that follows it*, so a run carrying a Tc taught the
device that the document's glyphs were that much wider than they are, and the
shapes were stretched to fill the gap: 2.24 ÷ 0.556 = 4.02x on this table.

The rule the code was missing is that **spacing is a gap to open, never a
shape to stretch**. The uniform scale must weigh the substitute's glyphs
against the widths the PDF gives *the same glyphs*, and the spacing must be
left to the offsets, which already carry it.

`PdfTextRun.glyphWidthAt(index, length)` (pdf_graphics `device.dart`) is that
width: the pen step less the run's `letterSpacing`, plus the `wordSpacing`
after a single-byte space. It is now the scale input at all three sites that
copy-fit substituted glyphs:

- `CanvasPdfDevice._buildPlacedLayout` (dart_pdf_editor `canvas_device.dart`)
- `pdfCanvas2dTextLayout` (`web_surface_profile.dart`, the worker Canvas2D
  surface)
- `FlutterGpuTrueTypeTextOutliner.outline` (flutter_gpu `text_outliner.dart`)

The whole-run path (no offset table, or a gradient/stroke run) was never
affected: it reproduces Tc/Tw as real tracking through `TextStyle`, so its
layout width already includes the spacing it is scaled against.

## Words became pieces

Correcting the scale alone breaks the other half of #649. A word was shaped
whole when its interior agreed with the PDF's offsets within 0.02 em, and
placed character by character otherwise. With the spacing out of the scale, an
unspaced shaped word drifts from the offsets by one Tc per character, so every
word of a document that sets *any* appreciable Tc failed that test and blew up
into per-character `drawParagraph` calls.

So the word/character binary is now a greedy cut: a word is broken into the
longest **pieces** that can be shaped tight with no character landing more than
`_placementToleranceEm` from its own offset, each piece drawn at the offset of
its first character. A word the substitute agrees with is still one piece;
disagreement - the substitute's own drift, or a Tc the shaped text does not
carry - is spent at a cut instead of accumulating across the word. This is
strictly better than the old binary, which exploded a whole word when only its
tail drifted.

Rejected on the way: giving a shaped word its Tc back through
`TextStyle.letterSpacing` (Flutter) / `context.letterSpacing` (Canvas2D). It
is faster, but both engines distribute letter spacing *around* each glyph -
Skia paints a lone 'A' with `letterSpacing: 100` at x=50, not x=0 - so every
part would need a half-spacing compensation for a rule neither engine
documents, and being wrong about it puts a pathologically spaced glyph (this
table's, at 0.84 em) visibly off its column.

## Measurements

45 lines of substituted prose, DPR 2, best of 15 (the raster figures are net
of a 6.0 ms empty-page raster; `record` is the cold pass with the layout cache
cleared, `raster` the warm pass):

| Tc (em) | parts | record | raster (net) |
| --- | --- | --- | --- |
| 0 (before, and after) | 506 | 17.8 ms | 7.5 ms |
| 0.005, per-character | 3042 | 10.3 ms | 10.1 ms |
| 0.005, pieces | 944 | 21.6 ms | 8.4 ms |
| 0.02, pieces | 2861 | 15.8 ms | 9.9 ms |

A document that sets no Tc - most of them - is untouched: same parts, same
cost. One that does pays ~15% more text raster than shaping its words whole
would, and avoids the ~35% the per-character fallback would have cost. Steady
paint recurs on every scroll and zoom; the cold shaping pass runs once per
unique run.

## Tests

- `substituted_glyph_placement_test.dart` - `( 3)Tj` under `15.137 Tc` paints
  a digit exactly as wide as an unspaced one, starting on the pen position the
  PDF gives it; a 0.5 em Tc leaves four separate glyph blocks rather than one
  solid stretched word.
- `web_surface_profile_test.dart` - the Canvas2D plan's `unitsPerEm` ignores
  the spacing, and a spaced word is cut so no part drifts.
- `text_outliner_test.dart` - the GPU outliner copy-fits against the glyph
  widths, not the spaced steps.
- `interpreter_test.dart` - `glyphWidthAt` against the interpreter's own
  offsets for a run carrying both Tc and Tw.
