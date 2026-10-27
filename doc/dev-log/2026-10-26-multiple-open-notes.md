# Several note cards open at once

Follow-up to the note popup card (#1172, #1173). The viewer showed one card
at a time - the single selected note, else the hovered one - so comparing two
notes meant hovering back and forth.

- Each card's author line ends in a button (`PdfNotePopupCard.trailing`,
  supplied by the viewer so `note_popup.dart` stays widgets-only): a pin
  ("Keep open", `notePopupKeepOpen`, `pdf-note-popup-pin`) on a hovered or
  selected card, a close × (`pdf-note-popup-close`) on a pinned one.
- `PdfViewerState._openNotes` holds the pinned cards, oldest first. The layer
  (`_NotePopupLayer`) now resolves a list of placements - pinned, then the
  single selected note, then the hovered one, each note once - and stacks a
  card per placement, keyed so a card keeps its text selection while the
  others come and go.
- A pin survives revisions: `_OpenNote` records the page's indirect
  reference and the note's /NM (falling back to its /Annots slot for notes
  without one), resolved again on every rebuild. A deleted, hidden or
  uncommented note just stops resolving, so undo brings its card back. An
  unrelated document swap clears the pins.
- The card is `IntrinsicWidth` now, so the button sits at the card's right
  edge rather than after a short author line.
- Pinning or closing rebuilds the card under the pointer with a new key; the
  old MouseRegion never reports the exit, so `_noteCardsChanged` resets
  `_overNoteCard` / `_noteCardPressed`.
- Touch: a tap on the pin waits out the viewer's double-tap recognizer
  (~300 ms), like any other tap inside the viewport.

Tests: `test/note_popup_test.dart` - two pinned cards surviving leaving,
an unrelated edit, and closing one; a pinned note deleted then undone.
