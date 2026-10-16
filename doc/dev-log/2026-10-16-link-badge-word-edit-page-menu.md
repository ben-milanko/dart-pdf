# Store-review fixes: link badge, word-level text edit, long-press page menu

A store review listed three complaints: a new link is a blank rectangle,
text editing works letter by letter, and a long-press sometimes opens
nothing. This session fixes all three.

## Link badge

`_addLink` (annotation_editor.dart) takes `iconColor` (on `addLinkToUri` /
`addLinkToDestination` / `addLinkToPage`), which draws `_linkBadge` into the
/AP: a white rounded tile in the top-right corner holding two interlocking
rounded links at 45 degrees. The tile is up to 18pt and is left out when the
region is too small (under 7pt of room). The badge sits inside /Rect, so the
clickable area doesn't change. Links aren't selectable or resizable, so the
badge never gets stretched.

`PdfEditingController.addLink` gained `iconColor`. A bare box link (no
decoration asked for) now gets border + badge in `defaultLinkColor`. Text
selection links keep the underline only, and a negative `iconColor`
suppresses the badge, like the other decorations.

## Word-level text edit

Many generators draw a page one glyph per show operator, placed by `Td`, with
no space glyphs. A `PdfContentElement` is one run, so the content tool
selected letters, and the selection chip's Edit refused any word spanning
more than one run (`textElementForSelection` is single-run only).

- `_textWordAround` / `_textJoins` (editing_controller.dart, top level)
  extend an element to the neighbouring text runs on the same line that
  butt up against it. A neighbour joins when the gap is under 0.15x the
  bounds height (a kerned overlap down to -0.3x is allowed), it overlaps at
  least 60% vertically, and there is no whitespace at the seam.
  `selectedElementWord` / `selectedElementEditText` /
  `selectedElementWordBounds` expose the result. The toolbar's Replace text
  and styled-edit dialogs start from the word, and the overlay paints a
  fainter `elementWordRect` box around it so the user can see what an edit
  covers.
- `textPartsForSelection(page, rects, text)` returns the
  `textElementForSelection` run when there is one. Otherwise it joins the
  text runs the selection rects touch, in content order, and looks for a
  unique alignment of the selection in them. A space in the selection may
  be missing from the runs (`_alignSelection`). The result is one
  `PdfContentTextPart` `(element, find)` per run, and a slice that occurs
  twice in its run refuses the whole selection.
- `replaceTextInParts` runs inside one `apply`. The first part takes the
  whole replacement, with any style. The other slices are then replaced
  with `''`, last-first, so each removal leaves the earlier ranges alone.
  Following text holds position through the usual kern compensation.
  **Gotcha:** rewriting a run splices the snapshot's own
  `operations` list in place, so read `snapshot.operations.length` *before*
  the first edit when computing the shift for the later parts. The styled
  path adds `rg` ops, and before this fix the deletions silently missed.
- The selection chip's Edit, Bold/Italic toggles, search Replace
  (`replaceMatchText`) and the content tool's `replaceSelectedElementText`
  all go through these parts.
- Fixture: `buildGlyphRunsPdf(line)` in pdf_test_fixtures (one Tj per glyph,
  flat 500 widths). Tests: `test/editing_word_edit_test.dart`.

## Long-press always answers

In Select mode (the default), a hold on empty page area is the touch marquee.
A still release opened a menu **only when the annotation clipboard had
content**, and the drag test was 4px, so any natural finger drift turned
into an empty marquee. Either way the user saw nothing.

- `_endTouchMarquee` now treats a drift under `kTouchSlop` as a press. It
  doesn't commit the marquee in that case, and it always opens the menu
  (or hands `emptyPage` to the host when `contextMenuEnabled` is false).
- `_maybeAnnotationMenu` (no tool armed) no longer needs something to
  paste either.
- `showPdfAnnotationMenu` with nothing selected and a `pagePoint` adds a page
  group after Paste: **Add note here** (`pdf-annot-menu-add-note`, new l10n
  key `menuAddNoteHere` in all 23 editor locales) and **Select all**
  (`pdf-annot-menu-select-all-text`, via the new `onSelectAllText`). The
  right-click path now shares `_showSelectionMenu`, so desktop gets the same
  rows and `textPrompt`.
- The early-return condition must keep `unlockTarget` (the Unlock-only menu
  has no selection or clipboard).

The old test "long-press on empty area without a clipboard does nothing"
pressed off-screen (y > 600 in an 800x600 viewport), so it never exercised
the path. The new tests press at `viewPoint(150, 600)`.
