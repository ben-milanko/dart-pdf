# Paragraph-level reflow editing (PdfEditor.reflowText)

## Paragraph reflow (Tier 4 — `PdfEditor.reflowText`)

Where `replaceText` corrects text *within* a line (holding the rest of the
line put with a compensating kern), `reflowText(index, find, replace)`
(`content_reflow.dart`, a new `part of editor.dart`) edits a whole
paragraph: the replacement may make the paragraph grow or shrink by lines,
its lines re-break at the column's right margin, and the lines that follow
it cascade up/down so nothing overlaps. It returns `true` when a paragraph
was reflowed, `false` (page untouched) otherwise — the same never-corrupt
philosophy as the Type0 editor.

Layering note: the reading-order/paragraph inference lives in
`pdf_graphics` (`PdfTextReflower`), which `pdf_document` may not import, so
the block heuristics are **ported** to run directly over the content stream.
`reflowText` simulates the text/line matrices over `PdfPageElements`'
operations to build `_ReflowLine`s (origin, baseline, leading, font, and the
break that reached each line — decoded text comes from `PdfPageElements`
elements so Type0 reads as real Unicode), then `_reflowGroups` folds
consecutive lines into a paragraph when they share a text object, font +
size, left margin, and a constant leading reached by a *relative* downward
break.

The cascade is the elegant part: the paragraph is re-wrapped (greedy, by the
font's own advances against the widest original line's width) and emitted as
`(line) Tj` + the paragraph's own relative break (`T*` or `0 -L Td`) between
lines, replacing only the op span `[firstShow..lastShow]`. The break that
connects the paragraph to the following content is left in place, so
changing the number of in-paragraph breaks shifts everything after it by
exactly `(newLines − oldLines) × leading` through the content stream's own
relative positioning — no following content is rewritten. It bails when a
line-count change would have to cascade through *absolutely* positioned
following content (it can't move → would overlap).

Fonts: simple Latin-1 (`_SimpleReflowFont`, measuring via `_widthsFor`) and
Identity-H/CIDFontType2 composite (`_Type0ReflowFont` over `_Type0Editing`,
with new `encodeReflowLine`/`measureReflow` helpers that record new glyphs
into `/W` + `/ToUnicode` on `commit`). Type0 reflow requires the embedded
program to carry every glyph (no fallback-font path here).

Out of scope (documented on the extension): multi-column and justified
layouts, first-line indents, the `'`/`"` show-and-break operators, vertical
text, mid-paragraph font/size/colour changes (the span must hold only shows
and relative breaks, else it bails), and non-text content / other text
objects don't move. Tests: `content_reflow_test.dart` (grow, shrink,
same-line-count no-move, Td-break style, miss, rotated/mixed-font bail,
incremental round-trip, and Type0 grow/typing-a-new-char/miss);
`pdf_graphics/test/reflow_render_test.dart` drives the result back through
the rendering interpreter (`PdfTextExtractor`/`PdfTextReflower`) to confirm
the rewritten stream interprets, the footer clears the grown body with no
overlap, and reading order recovers the edited paragraph then the footer.
