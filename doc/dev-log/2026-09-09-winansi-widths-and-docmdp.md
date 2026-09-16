# WinAnsi widths for the base-14 faces, and refusing to sign a P=1 certified file

Two correctness fixes, both surfaced by reading the forks of this repo
(`BenjaminD3E/dart-pdf`, branch `feat/external-signing`). The fork carried
them alongside `saveSignedExternal`, which landed upstream as #507; these two
did not come with it.

## Base-14 /Widths stopped at code 126

`ContentWriter.showText` writes Latin-1 bytes through unchanged (only codes
past 0xFF become spaces, `content_writer.dart`), and every base-14 /Font dict
we write declares `/WinAnsiEncoding`. But the metrics only covered ASCII:
`PdfStandardFont.widthOf` returned `_fallbackWidth` above 126, `widths`
returned 95 entries, and all three emitters wrote `/FirstChar 32 /LastChar
126` - `signature_editor.dart` `_signatureFont`, `annotation_editor.dart`
`_fontResource` (free text), `ocr_editor.dart` (the OCR text layer).

So a signer called "José Muñoz" laid out with the wrong advances on our side,
and in any other viewer the accented codes fell outside `/FirstChar..
/LastChar` and advanced by `/MissingWidth` - **0 by default** - stacking the
glyphs on one another. The two halves were separately wrong and agreed with
each other by accident, so nothing caught it.

The tables now run 32-255. They were **generated**, not typed:
`tool/` has no AFM data, so the generator (kept out of the tree; see the PR
for the script) parsed the genuine Adobe Core 14 AFMs shipped with
matplotlib's `pdfcorefonts`, mapped WinAnsi codes to glyph names through this
repo's own `winAnsiGlyphName` tables (`pdf_document/lib/src/fonts/
encodings.dart`), and asserted that the regenerated 32-126 prefix matched the
committed tables byte for byte before emitting the wider ones.

Two things that fell out of doing it that way:

- **Codes WinAnsi leaves undefined** (0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D) get
  the *bullet* width, not zero and not a fallback. ISO 32000-1 Annex D.2:
  unused WinAnsi codes render as bullet, which is what Acrobat does. A zero
  in a written /Widths array is never right, and `standard_font_widths_test`
  pins that no entry is 0.
- **Two pre-existing ASCII entries disagree with WinAnsi** and were left
  alone: `timesRomanWidths` and `timesItalicWidths` give code 39 the width of
  `quoteright` (333) rather than `quotesingle` (180 / 214). That is
  StandardEncoding's reading of the code. It is self-consistent - a viewer
  takes the advance from the /Widths we write, and we measure with the same
  number - so the only symptom is a slightly loose apostrophe in a Times
  appearance. Fixing it would move existing output, so it is a separate call;
  the generator prints both as NOTEs each run.

`ocr_editor`'s font-reuse check matches on the shape it writes, so its
`/LastChar` comparison moved to 255 with the writer. Miss that and it would
allocate a fresh OcrF*n* on every injection.

## Signing a document certified "no changes"

`saveSigned` would happily append a signature to a file whose catalog carries
`/Perms /DocMDP` at `/P 1` - "no changes shall be permitted" (§12.8.2.2,
Table 254). The incremental update breaks the certification it is appended
to, so the result is a file every viewer reports as tampered with. We *wrote*
DocMDP (`_applyDocMdp`) but never read it back.

`_docMdpPermissionLevel()` now reads the level off the certifying signature's
/Reference array, and `_emitSignatureRevision` throws
`CertifiedNoChangesException` before a byte is written - beside the existing
encrypted-document refusal, which is the same kind of guard. Because that
method is the single choke point, every path is covered at once: `saveSigned`,
`saveSignedEcdsa`, `saveSignedExternal`, and the PAdES entry points.

Deliberate edges:

- `/P 2` (fill and sign) and `/P 3` (plus annotations) both permit signing and
  are not refused.
- `/P` absent defaults to **2**, per Table 257 - and a certification we cannot
  read a level out of is also read as 2. Lenient on input, as everywhere else.
- **Document timestamps are exempt** (`docTimeStamp`). They add no content,
  and PAdES B-LTA renewal depends on being able to timestamp a certified
  file.
- The check runs before our own DocMDP is applied, so certifying *at* `/P 1`
  does not refuse itself.

Not done, and worth doing next: `validate()` reports no certification level,
so a host cannot grey out its Sign button ahead of the throw. The reader is
private for now.

## Tests

- `standard_font_widths_test.dart` - AFM values pinned per face, the
  bullet rule, no zero entries, `widthOf` agreeing with the emitted array
  across the whole range, and an end-to-end check that every byte a
  signature appearance actually shows has a non-zero /Widths entry.
- `docmdp_refusal_test.dart` - a hand-built certification from another
  producer at each level, all four signing entry points refused at `/P 1`,
  the timestamp exemption, and a round trip that certifies at `/P 1` through
  `saveSignedPades` and then re-signs.

`annotation_editor_test` pinned the old 95-entry length in two places; both
now expect 224.
