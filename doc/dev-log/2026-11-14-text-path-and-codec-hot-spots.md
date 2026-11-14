# 2026-11-14 - Text-path and worker-codec hot spots

A profile-led pass over the VM half of the pipeline: record a page
(`RecordingPdfDevice`), encode it (`serializeCommands`), decode it
(`deserializeCommands`), extract its text. Five changes, all found by sampling
the corpus rather than by reading code.

## What changed

- **`PdfFontInfo.widthOf` memoizes simple-font advances** (`_widthCache`, the
  `_charCache` sibling). It runs once per glyph and was a hash lookup in the
  /Widths map - ~11% of a text page. NaN marks "not computed", so a zero or
  default width caches like any other.
- **`_showText` builds the run's text from a reused code-unit list**
  (`_textUnits`) instead of a `StringBuffer` part per glyph (~14% of a text
  page), hoists its per-glyph invariants (Tc, Tw, Th, the Type3 draw test)
  and reuses `sawVisible` instead of `text.trim()` per run.
- **Render command codec format 14: float64 values are little-endian.**
  `ByteData` byte-swaps every big-endian value on a little-endian host, and a
  text run's per-character offsets made that swap a third of a text page's
  encode and half of its decode - the decode being UI-isolate work. Integers
  stay big-endian. The codec only crosses the worker seam and is never
  persisted, so the version bump is the whole migration.
- **`PdfPage.contentBytes()` stops copying.** A single content stream returns
  `decodeStreamData`'s bytes themselves; a /Contents array joins into one
  exact-size buffer. It used to go through a growing `BytesBuilder` - two
  copies of a multi-megabyte CAD stream per interpretation. The result is
  read-only by contract now (no in-repo caller mutated it).
- **`CosLexer._literalString` fast path**: a string with no escape, nested
  parenthesis or CR - nearly every show-text operand - is one `sublist`.

## The dart2js trap

The first cut of the text buffer was a `Uint16List`. On the VM it was the
fastest variant; compiled with dart2js it made text recording ~50% *slower*
than the StringBuffer it replaced. `String.fromCharCodes` only has dart2js
fast paths for a JS array and a `Uint8List`; a `Uint16List` goes through
`_stringFromIterable`. A plain `List<int>` hits a fast path on both (VM:
`cidArray`; dart2js: `JSArray` -> `fromCharCode.apply`) and is at parity with
the StringBuffer on the web while keeping the VM win. Don't "tidy" it back to
a typed list.

The check was a throwaway dart2js build of a record/encode/decode loop run
under node - not the real-Chrome harness. `tool/perf.sh webdiff` on
`wheel-text`/`read-text` is still worth running before a release.

## Measured

`tool/perf.sh diff HEAD~1 dartpdf-corpus --iterations 3` (interleaved,
ratios < 1 are faster):

| metric | ratio |
|---|---|
| openMs | 0.982x |
| firstPageMs | 0.833x |
| interpretMs | 0.865x |
| extractMs | 0.804x |
| saveMs | 0.985x |
| peakRssBytes | 1.002x |

Outliers it flagged are sub-millisecond or image-only rows (scan-book
interpret 1.25x on ~3 ms; two saveMs rows on ~0.3 ms) - cold-JIT noise, not a
path these changes touch. The counter gate is unchanged.

Steady-state (warm JIT, min of many runs) on the text files, which the sweep's
best-of-3 cold runs understate:

| stage (text-report-40p) | before | after |
|---|---|---|
| record | ~10 ms | ~6.6 ms |
| extract | ~8.5 ms | ~5.6 ms |
| encode | ~2.6 ms | ~1.7 ms |
| decode | ~1.2 ms | ~0.5 ms |

CAD/vector pages moved within noise: they are the number lexer and inflate.

## Follow-up: the Type3 cell cache key

`_drawType3Glyph` looked its recorded cell up in a map keyed by an 11-field
record (font, code, the CTM's linear part, both colours, both alphas, stroke
width). Hashing that per glyph - `_Record.hashCode`, `Object.hash` for each
`PdfColor` - plus the record's allocation was about a quarter of recording a
Type3 page. The cells now hang off the font (identity map, with a one-entry
last-font memo) in one chain per character code (`_Type3Cell`), and a lookup
walks the chain comparing fields. A page shows a glyph in a handful of states,
so the chain is short; `_maxType3Cells` still bounds the total.

Same cells, same sharing, byte-identical record (`buf` unchanged). Warm
steady-state on `type3-text-6p`, against the commit before it:

| stage | before | after |
|---|---|---|
| record | ~20 ms | ~8.8 ms |
| extract | ~18.4 ms | ~8.3 ms |

Encode/decode moved only within noise - they don't touch the key.

## Leads left on the table

- **Type3, the rest**: the cell cache key is done (below); what remains per
  glyph is two closures through `PdfFontInfo.renderGlyph`, four matrix
  concats, and a `PdfDrawTiledCellCommand` with two one-element
  `Float64List`s - and on the wire, one tiled-cell reference per glyph
  (`type3-text-6p` still encodes in ~9 ms against ~9 ms to record).
- **VM inflate**: archive's native `ZLibDecoder.decodeBytes` copies its output
  through a doubling `OutputMemoryStream` (~5% on CAD pages). Going around it
  needs `dart:io`, which `lib/` may not import.
- **`_Writer.takeBytes`** copies the whole record once to drop the doubling
  slack (~2-3% of a CAD encode); a size hint from the command count would
  avoid it.
- The NullDevice sweep overstates `hatch-sections`: NullDevice is not a
  `PdfTiledCellSink`, so it pays the per-tile `TranslatingPdfDevice` replay
  that no real device does.
