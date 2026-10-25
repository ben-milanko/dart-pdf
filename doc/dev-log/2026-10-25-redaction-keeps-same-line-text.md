# Redaction no longer removes un-redacted text on the same line (#1162)

Burning a redaction that covered one word could erase or hide other text on
the same line. Two bugs in `_RedactionBurn._showText`
(`packages/pdf_document/lib/src/redaction.dart`):

1. **Composite fonts dropped the whole operator.** Any `/Type0` run that
   touched a rect was removed in full. Most real-world PDFs (Word, browsers,
   LibreOffice) write each line as one Identity-H `Tj`/`TJ`, so redacting
   one word took the whole line with it. Identity-H runs now split per glyph
   like simple fonts do: two-byte codes, advances from the descendant `/W`
   (`parseCidWidths`/`cidDefaultWidth`, shared with `Type0Font`), and no word
   spacing (§9.3.3 applies `Tw` to single-byte code 32 only). Other CMaps
   still drop the whole operator, because splitting them would mean parsing
   the CMap's code lengths, and removing too much is safer than leaking.
2. **TJ kerns were re-emitted with the wrong sign.** When a run was rebuilt,
   every original TJ number was folded into the gap with its sign flipped,
   so a forward kern (e.g. `-250` used as a word space) turned into a
   backward one. That pulled the rest of the line back over earlier text or
   under the black fill, so it looked deleted.

Rebuilt strings keep their hex/literal form. Tests: the composite and kern
cases in `test/redaction_test.dart`.

## Follow-up: the line below, and redacting a text selection

Testing the preview turned up a third way to lose text: a box over one line
took words from the line below. `_glyphCovered` tested each glyph's em box
(0.2 em below the baseline to a full em above), which overhangs the visible
glyph by a good part of a line, so on ordinary leading the next line's boxes
reached up into the redaction rect. A glyph now counts as covered when a
line through its body (`_glyphBodyHeight` = 0.3 em above the baseline) lies
inside a region for more than `_minCoveredFraction` (10%) of its advance.
That fraction also keeps a neighbour that only grazes the box edge. The
whole-op fallback for non-Identity composite fonts uses the same body line.
The trade-off: a box over only the top or bottom sliver of a line no longer
removes that line's glyphs. They were never hidden by such a box anyway.

Text selections can now be redacted. The right-click text menu and the touch
selection chip have a Redact entry (`pdf-text-menu-redact`,
`pdf-text-selection-chip-redact`, `_redactTextSelection` in pdf_viewer.dart),
which marks the selection's quads (`addRedactionQuads`) and arms the Redact
tool so its Apply button is at hand. Arming Redact while text is selected
marks the selection first (`PdfEditorCommands.toggleToolNow` /
`redactSelection`), as the markup tools do. Dragging across text with the
Redact tool armed still draws a rectangle; it does not select text.
