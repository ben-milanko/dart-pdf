# Simple-font encoding in content editing, and search-panel replace

Two things landed: the content editor now reads and writes **simple
(byte-coded) fonts through their own encoding**, and the search panel grew
find *and replace*.

## The bug

A user editing a form's date field saw the content tool report the text as
`-=>-/>?-?@` where the page reads `05/08/2026`, and reported that changing a
character "does weird things … might change a lot of content on the page",
with a mapping like "B = 8, 9 = I, 0 = Space".

Both halves were real, and independent.

### 1. A simple font's byte is not its character

`PdfPageElements.of` decoded a non-/Type0 show string with
`latin1.decode(bytes)`, and `_SimpleRunCodec` did the mirror image:
`glyphText(g) => String.fromCharCode(g)` for matching, and wrote a
replacement as `replace.codeUnits`. That is only right when the font's codes
happen to be Latin-1.

§9.6.6 lets a document remap every code through `/Encoding` `/Differences`,
and a subsetted font routinely renumbers its codes from scratch. The
reporter's font drew `05/08/2026` from the bytes
`2D 3D 3E 2D 2F 3E 3F 2D 3F 40` - which *is* `-=>-/>?-?@` in Latin-1. The
"B = 8" observation is the same table read the other way: typing `B` wrote
byte `0x42`, and `0x42` is whatever glyph the subset put there.

Note the renderer never had this problem - `PdfFontInfo.charFor` resolves
`/ToUnicode` → `/Differences` → built-in Symbol/ZapfDingbats → base encoding
→ Latin-1. Text selection and search read correctly the whole time; only the
content editor had its own shortcut.

The fix is `SimpleFont` (`pdf_document/src/simple_font.dart`), the simple-font
sibling of `Type0Font`: one place that resolves a code to text the way the
renderer does, plus the reverse table for re-encoding replacements, plus the
`/Widths` lookup (which absorbed `content_editor`'s `_widthsFor`). It is used
by `PdfPageElements` (so `element.text` is real text), by `_SimpleRunCodec`
and `_StyledRunCodec` (match *and* write), by the `'`/`"` operator path, and
by `_SimpleReflowFont` in `content_reflow.dart`.

**Encodability is deliberately narrower than decodability.** Decoding keeps
the lenient Latin-1 fallback for any code nothing else explains. Encoding
only uses codes the font *declares* - a base-encoding or `/Differences` glyph
name, or a `/ToUnicode` entry - because a subset that dropped `9` has no
glyph at `0x39`, and writing that byte anyway draws notdef. When a font
declares no encoding at all (the bare base-14 case, and everything this
library writes itself) the identity is used in both directions, so nothing
about the existing round-trip changed. A replacement the font cannot draw
leaves the run untouched, which is the contract `Type0Font` already had for a
glyph its embedded program lacks.

This makes `replaceText`'s `find`/`replace` *text* rather than raw bytes for
simple fonts. For every font whose codes are Latin-1 that is the same string,
which is why all 826 `pdf_document` tests passed unchanged.

One ordering trap worth knowing: fixing the decode *created* a latent bug in
paragraph reflow. `content_reflow` reads `element.text`, so once that decoded
correctly a remapped font would start matching - and `_SimpleReflowFont.showOp`
would then have written `text.codeUnits` as bytes. Fixed in the same pass;
`measure` returns `infinity` for an unencodable line so the wrapper cannot
build lines `showOp` will refuse.

### 2. "It changes it everywhere"

Separately, the element strip's "Replace text" called
`PdfEditingController.replaceSelectedElementText`, which went to the
**page-wide** `PdfEditor.replaceText`. The targeted
`PdfEditor.replaceElementText` already existed (it backs the selection-menu
edit); the element-strip path just never used it. Both it and
`replaceStyledSelectedElementText` now share one `_replaceSelectedElementText`
that goes through the targeted API, so a page whose header and footer read the
same date keeps the one that was not selected.

## Search-panel replace

`PdfSearchResultsPanel(editing:)` turns the find panel into find-and-replace:
a replacement field under the options bar with **Replace** (the current hit)
and **Replace all** (every hit, one undo step). Null `editing` - the default,
and what a read-only shell passes - leaves it a pure find panel.

Two controller methods back it:

- `replaceMatchText(page, rects, find, replace)` resolves the hit through
  `textElementForSelection` (the same conservative gate the selection menu
  uses: exactly one content element, unambiguous) and then
  `replaceTextInElement`. It returns 0 rather than guessing, and the panel
  says so.
- `replaceTextOnPages(pages, find, replace)` is the page-wide form for
  Replace all, applied inside one `apply()` so it is a single undo step.

Worth noting this only became possible with the encoding fix: search hits
come from the text layer while elements come from `PdfPageElements`, and
before the fix those two disagreed about what a remapped run said, so no
search-driven replace could ever have resolved.

The re-search after an edit has an ordering trap. The viewer calls
`_controller.clearSearch()` when it swaps in the new revision, which happens
on the *next frame* - so a re-search issued straight after the edit is thrown
away moments later and the panel goes blank. `_ReplaceBar._refresh` awaits
`WidgetsBinding.instance.endOfFrame` first.

## Layering note

`SimpleFont` needs the Adobe glyph-name tables, which lived in
`pdf_graphics/src/fonts/encodings.dart` - one layer *above* `pdf_document`.
The tables are pure data with no dependencies, so they moved down to
`pdf_document/src/fonts/encodings.dart` (exported from `pdf_document.dart`),
and the old path is now a `show`-list re-export so the font engine's own
imports (`cff.dart`, `type1.dart`, `font_info.dart`) are untouched.

## Files

- `pdf_document/src/simple_font.dart` (new), `src/fonts/encodings.dart` (moved)
- `pdf_document/src/content_elements.dart`, `content_editor.dart`,
  `content_reflow.dart`
- `pdf_graphics/src/fonts/encodings.dart` (re-export shim)
- `dart_pdf_editor/src/editing/editing_controller.dart`, `search_panel.dart`,
  `pdf_editor_view.dart`, `l10n/dart_pdf_editor_en.arb`
- Tests: `pdf_document/test/content_edit_simple_font_test.dart` (new, builds
  the reporter's exact byte sequence), `dart_pdf_editor/test/
  search_replace_test.dart` (new), a targeting case in `editing_test.dart`,
  and `buildTextLinesPdf` in `pdf_test_fixtures`.
