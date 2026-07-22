# ZapfDingbats ornament codes 0x80–0x8D rendered as tofu

`test_corpora/pdfjs/ZapfDingbats.pdf` page 2 shows the 14 ornamental
parenthesis/bracket dingbats (glyph names a89, a90, a93, a94, a91, a92,
a205, a85, a206, a86, a87, a88, a95, a96). PDF.js renders them; we rendered
tofu boxes for exactly those 14 glyphs while every other dingbat on the page
was fine.

## Cause

The document selects the standard-14 `ZapfDingbats` font (no embedded
outlines, no `/Encoding`), so codes decode through the font's built-in
encoding. `PdfFontInfo._computeCharFor` handles that via
`zapfDingbatsUnicode(code)` (`fonts/encodings.dart`), but the `_zapfDingbats`
table had a gap between `0x7E` and `0xA1`. The ornaments live at codes
`0x80`–`0x8D` (confirmed from the content stream: `/F3` = ZapfDingbats draws
byte `\x80` immediately before the `a89 [xF8D7]` label, etc.). With no table
entry and no `/Differences`, `charFor` fell through to
`String.fromCharCode(code)` for `0x20..0xFF`, yielding unassigned C1 control
chars → tofu.

The Adobe Glyph List maps these names to the private-use area
(U+F8D7–U+F8E4, which is what the page's own *label text* prints), but they
were later encoded as real Dingbats at U+2768–U+2775 — the code points
conforming viewers actually render. Codes `0x80`–`0x8D` map consecutively to
U+2768–U+2775.

## Fix

Added the 14 `0x80`–`0x8D → 0x2768`–`0x2775` entries to `_zapfDingbats`.
Regression coverage in `font_info_test.dart` ("ZapfDingbats decodes built-in
symbol codes to Unicode").

Note: this container lacks dingbat-capable system fonts, so the Flutter
`pdfjs_render_test` substitutes tofu for *all* dingbats locally and can't
visually confirm the fix — the checked-in `_renders` PNGs come from an
environment that has the fonts. The `charFor` unit test is the
environment-independent verification.
