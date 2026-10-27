# Note popup: selectable text, and cards for commented markups

Follow-up to the note popup card (#1172) and the note-thread fix (#1174).

## Selectable comment text

- `PdfViewerState._buildNotePopupLayer` wraps `PdfNotePopupCard` in a
  `SelectionArea`, so the author line, the comment and the replies can be
  selected: mouse drag, double-click, and long-press on touch.
  - The selection area lives in the viewer, not in `note_popup.dart`, so the
    card stays widgets-only and the design-import baseline is unchanged.
  - Its context menu goes through `pdfHostRoute`, like every other editor
    text field, so a non-Material host still gets localizations for it.
- Copy and select-all: the viewer's default shortcuts bind ⌘/Ctrl+C to
  `PdfCopyIntent` (page text or the annotation clipboard) and ⌘/Ctrl+A to
  `PdfSelectAllIntent`. Those `Shortcuts` sit above the card, so a nearer
  `Shortcuts` (`_noteCardShortcuts`) maps the same keys to
  `CopySelectionTextIntent.copy` and `SelectAllTextIntent` while focus is in
  the card. Without it, ⌘C inside the card copied nothing; the test proves
  that.
- `_noteCardPressed` keeps a hover card open while a selection drag that
  started on it wanders off the card. The hide timer is armed again on
  release.

## Highlights and shapes with a comment

- `pdfIsNotePopupTarget` now accepts any markup carrying a non-empty
  /Contents, not only /Text notes. It still excludes replies and review-state
  annotations, FreeText (its contents are already drawn on the page), and
  Popup, Link and Widget.
- `_noteAt` hit-tests a text markup by its `/QuadPoints`
  (`_textMarkupQuadHit`), falling back to /Rect. Without that, a commented
  highlight would pop up over the blank gaps its bounding box spans.

Tests: `test/note_popup_test.dart` covers drag-selecting and copying with
the keyboard, the card staying open when a drag leaves it, a commented
shape's card versus a bare shape's, and eligibility.
