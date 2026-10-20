# Touch long-press marquee in select mode

On touch, the select tool had no way to rubber-band annotations: a mouse
gets the marquee from a plain drag on empty page area (or Shift/⌘/Ctrl over
text), but a touch drag on empty area pans the viewport, and a long-press
there did nothing (or opened the paste menu with a clipboard).

Now, with the select tool armed, **long-press then drag on empty page area
draws a selection box**. Releasing selects the annotations it covers on the
page the press started on.

## Where it lives

The viewer's `_SelectionLongPressRecognizer` already owns select-mode
long-presses that miss annotations (`_selectionLongPressEnabledAt`), so the
marquee rides that recognizer instead of adding another long-press to the
arena:

- `_onLongPressStart` → `_beginTouchMarquee` when `_wordRangeAt` found no
  word and the select tool is armed. It reuses the viewer's Shift+drag
  marquee state (`_marqueeStart`/`_marqueeCurrent`/`_marqueePage`, painted
  by `_MarqueePainter`, committed by `_commitMarquee`).
- `_touchMarqueeGlobal` marks the marquee as a touch one, so
  `_onLongPressMove`/`_onLongPressEnd` route to it.
- A release that never dragged (< 4px box) is the plain long-press it was
  before: the paste menu when `hasAnnotationClipboard` (or
  `requestContextMenu(emptyPage)` with the stock menu off). The menu now
  opens on lift rather than when the hold fires.
- The overlay's `_menuLongPressClaims` stops claiming empty area while
  `PdfEditTool.select` is armed. If both recognizers claimed it, the
  overlay's would win the race and the paste menu would always pre-empt
  the marquee.

## On top of text

A long-press **on a word still selects text** (the word, extended by
dragging), not a box. That matches every phone and the mouse select tool,
where a plain drag over text selects the text. To sweep a box over text,
start it in a margin or between lines. `_wordRangeAt` uses a 14px
along-line tolerance, so the gap past the end of a line counts as empty.
Annotations keep their own long-press (select + menu, or a held drag
moves them).

Tests: `test/editing_longpress_menu_test.dart` (select mode group).
