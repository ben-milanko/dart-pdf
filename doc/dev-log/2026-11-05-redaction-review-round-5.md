# Redaction: review round 5

A fifth adversarial review, this time of the code merged in #1259 (cleanup
pass, whole-word removal, image mode). It found eleven confirmed problems.
Each has a regression test in the `round 5` group of
`test/redaction_traces_test.dart` (or `redaction_raster_test.dart`), and
each test fails on the code before this change.

## Leaks

- **One fill per letter.** Whole-word removal added a fill box per letter
  it took beyond the box, so the boxes recorded each letter's width. Now
  each grown word gets one box over the whole word.
- **Glyphs without Unicode.** A glyph whose font has no `/ToUnicode` entry
  has empty text, which counted as a space, so every glyph was its own word
  and was cut letter by letter. Only real whitespace splits words now.
- **The gap after the last kept letter.** `[(Name: ) -8000] TJ` kept the
  removed width when nothing used the pen after it. The tidy pass now drops
  the kerns at the end of a `TJ` when the next thing is a new position or
  the end of the object (a lone string becomes a `Tj`).
- **Tagged lines.** `EMC` counted as drawing, so a dead kern inside marked
  content survived, and a positioning run before `EMC` or before a state
  operator (`Tf`) was written out unfolded, keeping the stops of removed
  lines. State and marked content no longer interrupt a run or the
  lookahead.
- **Leftover colour.** Groups were tidied before text objects, so
  `q 0.9 0.2 0.1 rg BT ... ET Q` kept its colour once its text went, and a
  group holding only balanced marked content (`/Artifact BMC ... EMC`)
  counted as drawing. Text objects are tidied first now, groups after, and
  marked content left empty goes (the passes repeat until nothing changes).

## Changed what kept text looked like

- **Graphics state in an emptied text object.** Only text state survived,
  so `rg`, `gs`, `w` and the like set inside a removed text object were
  lost, and later text changed colour or opacity. Everything except
  positioning, shows and balanced marked content now survives.
- **Leading and `q`/`Q`.** The fold tracked `TL` without `q`/`Q`, or a
  top-level `TL`, so a later `T*` folded with the wrong leading and kept
  text moved. The leading is now saved and restored with the graphics state.
- **Precision.** The serializer rounded reals to six decimals, which moved
  text drawn under a tiny `cm`. A burn now writes every digit
  (`ContentStreamSerializer.serialize(preserveRealPrecision:)`). Inline
  image keys are also name-escaped now, so a key can't break out into the
  content stream.

## Elsewhere

- **Fills from kept appearances.** Burning a kept annotation's appearance
  ran after the page's fill was painted, so its whole-word fills landed on
  the next page. The annotation step runs first now.
- **Image mode and structure text.** Only elements whose own `/Pg` was the
  page lost `/Alt`/`/ActualText`/`/E`. An element whose page came from a
  parent, or only from a marked-content or object reference, kept them.
  Now those elements and every element above them are stripped.
- **Image mode memory.** `applyRedactionsAsImages` lowers the resolution
  past 50 MP a page (about 200 MB of RGBA) instead of running out of memory
  on a huge page.

Letter-mechanics tests on composite fonts (`redaction_test.dart`) now pin
`wholeWords: false`, since their codes have no Unicode and are one word.
