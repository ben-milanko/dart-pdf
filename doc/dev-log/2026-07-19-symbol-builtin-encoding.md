# Symbol's built-in encoding (and Greek/math glyph names)

Follow-on from #386, which filled the ZapfDingbats ornament gap. The question
that prompted this was "are there other symbols we should pre-empt?" - the
answer turned out not to be more dingbats.

## ZapfDingbats is finished

After #386 the table carries 201 entries. The only codes still unmapped in
`0x20`-`0xFF` are `0x20`, `0x7F`, `0x8E`-`0xA0`, `0xF0` and `0xFF`, and those
are genuinely unassigned in ZapfDingbatsEncoding (Annex D.6). `0x20` falls
through to a real space. Nothing left to pre-empt there.

## The actual gap: Symbol

`font_info.dart` special-cased `_isZapfDingbats(baseFont)` but had no
equivalent for `Symbol` - the *other* symbolic member of the standard 14. A
document may select it with no `/Encoding` and no embedded program, and then
every code fell through to the Latin-1 approximation at the bottom of
`_computeCharFor`.

Two separate failures, both reproduced before fixing:

- `/BaseFont /Symbol`, no `/Encoding`: `charFor(0x61)` returned `'a'` instead
  of alpha, `0xA5` returned `'¥'` instead of infinity, `0xD6` `'Ö'` instead of
  radical. On screen these came out as `.notdef` boxes, because the substituted
  macOS Symbol face has no glyph at U+0061.
- `/Encoding /Differences [97 /alpha /beta /summation /infinity]`:
  **also** wrong. `_glyphNameUnicode` had zero entries for Greek or math glyph
  names - all 35 probed names missed - so an explicit, unambiguous instruction
  from the document was silently ignored. This one is not Symbol-specific: any
  font may use those names.

The second is the more serious of the two and is why the fix is two tables, not
one.

## The tables

`_symbol` (189 codes) is derived from Adobe's own Symbol-to-Unicode mapping
rather than hand-written, with three deliberate departures where Adobe's value
is unhelpful on a real system font:

- Greek letters use the Greek block, not a compatibility duplicate: `0x44`
  Delta → U+0394 (not U+2206 INCREMENT), `0x57` Omega → U+03A9 (not U+2126 OHM
  SIGN), `0x6D` mu → U+03BC (not U+00B5 MICRO SIGN). Keeps the Greek run
  internally consistent and lets a reader's typed Greek letter match a search.
- The "sans" legal marks use the real characters (registersans → U+00AE,
  copyrightsans → U+00A9, trademarksans → U+2122) instead of Adobe's
  corporate-use subarea.
- The big-delimiter assembly pieces map to U+239B-U+23AE, the block Unicode
  added for exactly these glyphs. Same reasoning as #386's ornaments: the
  private-use code points are tofu outside Adobe's own fonts.

`0x60` radicalex keeps its private-use value - it is a bare overbar extender
with no single agreed code point.

The 189 glyph names also go into `_glyphNameUnicode` (176 were new), which is
what fixes `/Differences` for every font.

## Precedence, and why `_differenceNames` exists

`_encodingNames` merges the base encoding and `/Differences` into one map, so
it can't express "the document named this glyph explicitly". That matters here
because the built-in table has to sit on *both* sides of a lookup:

- It must **beat a base encoding**. Producers routinely tag a Symbol font
  `/WinAnsiEncoding` while meaning the Greek glyphs; honouring WinAnsi there
  reintroduces the bug. (Lenient on input, per the house rule.)
- It must **lose to `/Differences`**, which is the document naming the glyph
  outright (§9.6.6.1).

Hence a separate `_differenceNames` field carrying just the Differences
entries, consulted before the built-in tables. For non-symbolic fonts this
changes nothing - a Differences entry already overwrote the base name in
`_encodingNames`, so the resolved value is identical.

The same built-in fallback is added to `_encodingUnicode`, which feeds glyph
*selection* (`_gidFor`), so this fixes rendering and not merely extraction.
`charFor`'s output is the string written into the run buffer at
`interpreter.dart:1743` and handed to the device for substituted fonts.

## Validation

- `pdf_graphics`: 864 tests pass, including 9 new Symbol cases.
- Full PDF.js render suite: no page changed. No fixture in the corpus uses
  Symbol, which is also why this went unnoticed - worth keeping in mind when
  reasoning about coverage from the corpora alone.
- Ghent baseline suite: unchanged (the pre-existing `GWG030` spot/overprint
  failure is on `main` too).
- End-to-end: a hand-built one-page PDF selecting `/BaseFont /Symbol` renders
  `αβγδπω` and `∞√∫≅` where it previously drew `.notdef` boxes, with a
  Helvetica control line on the same page still reading `abgdpw`.

## Known gap left open

`devicen.pdf` page 1 in the PDF.js gallery drifted from a 0.000% to a 3.785%
baseline diff at some point after `0b0b62c0`, unrelated to this change and
present on `main`. Bisect in progress separately.
