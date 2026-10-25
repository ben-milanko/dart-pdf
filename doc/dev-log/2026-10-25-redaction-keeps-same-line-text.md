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
