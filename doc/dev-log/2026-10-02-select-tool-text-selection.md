# Text selection under the Select tool and in Hand mode (#995)

Issue #995: on desktop the toolbar always has Hand or Select armed, so a
mouse drag over text never selected it (only `V` then `Esc` reached the
tool-free reader state). Rather than add a no-tool state to the toolbar,
the two modes now offer text selection themselves.

## Select tool

- A plain mouse drag that starts **over page text** (and over no
  annotation, selection handle or selected box) selects the text, like a
  reader. The overlay still decides first: handles, rotate, move of a
  selected box, and grab-and-move of an unselected annotation all win
  before text is considered.
- **⌘/Ctrl+drag** is the marquee now (it used to be the other way round:
  ⌘/Ctrl took the page list out of the hit path via `_zoomModifierDown`, so
  the viewer's own drag ran and selected text). The viewer's marquee
  (`_marqueeShouldStart`) now also starts when `_selectToolMarqueeModifier`
  holds - select tool armed (or a default-mode annotation selection) with
  ⌘/Ctrl down. The hover cursor shows `precise` in that state.
- Shift+drag reaches the overlay (Shift doesn't take the list out of the
  hit path) and still rubber-bands additively over text; a plain drag on
  empty paper still marquees.
- Hover shows the I-beam over text (`SystemMouseCursors.text`).
- A select-tool click clears the text selection; the second click of a
  double-click does not (it checks the viewer's `_suppressTap`, which the
  raw pointer-up sets when it selects the word, and which the overlay's tap
  recognizer fires after, since arena sweeps run after raw listeners).
- Starting a text selection clears any annotation selection, so ⌘C copies
  one or the other unambiguously.

### Seam

The overlay's `GestureDetector` is opaque and deeper in the tree, so its
pan recognizer always beats the viewer's. Instead of rewiring the arena,
the overlay **hands the drag off** through five new
`PdfEditingInteractionHost` services: `pageTextAt` (hover probe),
`beginTextSelection` (returns false when there is no text, leaving the drag
to the marquee), `updateTextSelection`, `endTextSelection({cancelled})`
and `clearTextSelection`. The viewer implements them in terms of its own
`_onSelectionUpdate`/`_onSelectionEnd`, converting global positions
through `_listSpaceKey` (same path as `_resolvePagePointGlobal`). The
overlay tracks the handoff with `_textSelecting`; `_bailActiveGesture`
cancels it.

## Hand mode

- Double-click selects a word and double-click-drag extends by words
  (`_onPointerUp` no longer bails in Hand mode; `_onSelectionStart` lets
  `_wordDrag` through before the grab-pan). A plain drag still grabs.
- The closed hand shows on **mouse press**, not once the drag clears the
  slop: `_onPointerDown` swaps `grabCursor` → `grabbingCursor` for a
  primary-button press in Hand mode, and `_onPointerUp` reopens it if the
  press never became a grab-pan.

Tests: `editing_multiselect_test.dart` (select-tool text drag, ⌘+drag
marquee over text, click clears, double-click word; the old "empty area"
marquee test started on the 'Page 1' line and now starts below the shapes)
and `pdf_viewer_test.dart` (Hand double-click, Hand press cursor).
