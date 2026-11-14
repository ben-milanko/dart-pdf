# 2026-11-14 - Type3: the rest of the per-glyph cost

Follow-up to `2026-11-14-text-path-and-codec-hot-spots.md`, which replaced
the Type3 cell cache's record key. What a Type3 glyph still cost after that,
per occurrence, and what happened to each part:

## Recording (`PdfInterpreter._drawType3Glyph`)

- **The cache is consulted first.** Every glyph went through
  `PdfFontInfo.renderGlyph` - two closures, the CharProc map lookup, and
  `_opsCache.putIfAbsent` for the parsed operations - before it looked for
  its recorded cell. A hit needs none of that, so the lookup now comes first
  and `renderGlyph` is only called for the first sight of a glyph in a state
  (or a state that can't be cached: a soft mask or a pattern fill).
  `PdfFontInfo.type3GlyphMatrix` is the one thing the fast path needs from
  the font.
- **The glyph CTM is computed on scalars.** It was four `PdfMatrix.concat`
  calls - five allocations per glyph. The same arithmetic is now written out
  on locals, **term for term, including the multiplications by 0 and 1**, so
  the result is bit-identical. Don't simplify those terms: `x * 0.0` is not
  always `+0.0`, and a different rounding would re-key every cell and shift
  recorded origins.
- **Blank codes are settled once.** A code with no CharProc, or an empty or
  undecodable one (a space, usually), took the full slow path every time.
  `_Type3FontCells.blank` remembers it per font.

Not done: the stamp itself (`PdfDrawTiledCellCommand` plus two one-element
`Float64List`s). It is ~1% and the command shape is shared with tiling
patterns and the canvas's cell-picture cache.

## The wire (`render_command_codec.dart`)

A Type3 text run still writes its glyph list - one `PdfGlyphPlacement` per
glyph, each with its own text. That string went through `utf8.encode` (two
lists allocated) on the way out and `utf8.decode` over a fresh view on the
way in, per glyph.

- **`_Writer.str` copies ASCII straight in**, falling back to the encoder at
  the first unit >= 0x80. This is every string the codec writes, so run text
  and font names benefit too.
- **`_Reader.glyphText` reads a one-ASCII-byte glyph text without the
  decoder.** Deliberately *not* in `_Reader.str`: a byte-loop ASCII check
  there measured no better than the decoder on whole runs (its own ASCII
  scan is fast), so ordinary run text reads exactly as before.

No format change: the bytes are identical, so `_formatVersion` stays 14.

## Verified

Output is unchanged: the sha256 over every recorded page's bytes (and their
decode -> re-encode) across `test_corpora/{dartpdf,pdfjs,ghent}` - 375 pages,
35,892 tiled/Type3 stamps - is the same before and after. Counter gate
unchanged.

## Measured

`type3-text-6p`, min of many warm runs, against the commit before:

| stage | VM JIT | VM AOT | dart2js (node) |
|---|---|---|---|
| record | ~9.0 -> ~7.2 ms | noisy, no worse | ~90 -> ~41 ms |
| encode | ~9.4 -> ~6.7 ms | ~9.0 -> ~6.4-8.5 ms | ~46 -> ~19 ms |
| decode | ~2.6 -> ~2.1 ms | ~6.2 -> ~2.7-4.4 ms | ~21 -> ~13 ms |
| extract | ~8.2 -> ~5.5 ms | ~9.3 -> ~5.0-7.0 ms | - |

The dart2js column is the one that moved most: its closures, map lookups and
pure-Dart UTF-8 codec cost far more per call than the VM's. Ordinary text
pages: encode a little faster everywhere (dart2js `text-report-40p` ~5 -> ~2
ms), everything else within noise.

Measurement notes for next time: JIT timings on the cloud box swing +-30%
between rounds; alternate A/B runs and compare minima, or build both sides
with `dart compile exe`. The dart2js check is a throwaway record/encode/decode
loop compiled with `dart compile js -O2` and run under node with
`globalThis.self = globalThis` prepended.
