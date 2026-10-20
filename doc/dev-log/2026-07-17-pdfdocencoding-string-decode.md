# PDFDocEncoding text-string decode (tofu in form dropdowns)

## Symptom

A CAA request form showed "tofu" (missing-glyph boxes) between the code and
the description in every combo-box dropdown option, e.g.
`V6 ASB □ Absolute Signal Blocking`. The same options rendered fine in the
field's own appearance stream - only the editor's dropdown menu (which reads
`PdfFormField.options` -> `CosString.text`) showed the box.

## Cause

The separator byte in the `/Opt` display strings is `0x85`. In PDFDocEncoding
(ISO 32000-1 §7.9.2 / Annex D.3) `0x85` is an EN DASH ("–"), but
`CosString.text` decoded non-BOM strings with `latin1.decode`, and Latin-1
maps `0x85` to U+0085 (NEL, a C1 control character) which has no glyph -> the
Flutter `Text` widget drew a missing-glyph box. The comment already flagged
Latin-1 as "an approximation of PDFDocEncoding"; the approximation breaks
exactly on the `0x80-0x9F` band, where PDF puts printable punctuation
(bullet, dashes, curly quotes, ™, ﬁ/ﬂ, OE/oe, …) and Latin-1 has C1 controls.

## Fix

`CosString.text` (`pdf_cos/src/objects.dart`) now decodes non-BOM strings as
real PDFDocEncoding: a small `_pdfDocToUnicode` table remaps only the bytes
that differ from Latin-1 (`0x18-0x1F` accents, `0x80-0x9E` punctuation/ligatures,
and `0xA0` = Euro); every other byte still decodes as its own value, so
ASCII and the Latin-1 high range (`0xA1-0xFF`) are unchanged. The three
undefined PDFDocEncoding slots (`0x7F`, `0x9F`, `0xAD`) pass through as their
raw byte, matching the previous lenient behaviour.

The UTF-16BE (`FE FF`) and UTF-8 (`EF BB BF`) BOM paths are untouched. The
encoder (`CosString.fromText`) is left as-is: characters outside Latin-1 (an
en dash is U+2013) already serialize as UTF-16BE, so `fromText(...).text`
round-trips correctly.

## Tests

`pdf_cos/test/string_text_test.dart` - ASCII unchanged, Latin-1 high bytes
unchanged, the `0x80-0xA0` punctuation band decodes to real glyphs (incl. the
`V6 ASB – …` dropdown case), undefined slots pass through, BOM paths and a
`fromText` round-trip.
