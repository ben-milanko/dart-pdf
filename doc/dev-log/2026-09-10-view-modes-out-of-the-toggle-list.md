# View modes stop pretending to be display toggles (2026-09-10)

The trigger was one line of feedback: "the Page grid option is in an awkward
spot". It is, and the reason is worth writing down, because the placement was a
symptom.

## What was wrong

`PdfShellViewOptionsButton`'s popup held nine rows of four different kinds:
overlay toggles (annotations, scrollbar chapters, form-field highlight), two
view modes (Reflow text, Page grid), two settings with values (paper colour,
guides), and two dialog openers (author, shortcuts). No dividers, no grouping.

The modes were the real problem. Both REPLACE the page viewer, so only one can
be on, and the old handler expressed that by having each clear the other:

```dart
case _ViewOption.reflow:
  preferences.showThumbnailView = false;
  preferences.showReflowView = !preferences.showReflowView;
```

Drawn as checkmarks, that reads as three unrelated switches where ticking one
silently unticks another. And there was no "Pages" member: plain pages existed
only as the absence of the other two, so leaving a mode meant unticking the one
you ticked rather than choosing where to go.

The invariant was also re-implemented per caller, and one caller had it wrong -
the app's command palette set `showReflowView` / `showThumbnailView`
independently, so it could put the document in both modes at once.

## What landed

**The invariant moved to the state object.** `PdfEditingPreferences.viewMode`
(`PdfViewMode.pages | reflow | pageGrid`) reads and writes the pair coherently
and notifies once. The two bools stay - they are persisted keys and hosts use
them - but nothing in our own code sets them individually any more. The
`_ViewOption` enum lost its `reflow` and `pageGrid` cases entirely.

**Desktop: a `SegmentedButton` above the display toggles.** It is a custom
`PopupMenuEntry`, following `_KeyboardShortcutMenuItem`, which was already the
precedent for a non-item row in this menu. Picking a mode closes the popup,
matching the checked items it replaced.

**Compact: the modes went UP, not down.** They are tiles in the Controls
sheet's existing View section (`pdfShellViewModeControls`), not in the Settings
sheet - on a phone Controls is the parent surface and Settings a child of it.
This closed a real gap: `pdf_editor_view.dart` had already given Reflow a
one-tap tile there, on the reasoning that phone readers reach for it often, and
the page grid had never got one - it was Controls -> Settings -> scroll -> tick.
`showPdfShellViewOptionsSheet` dropped its `reflow` / `pageGrid` parameters, and
the Settings tile moved to the sheet's action row with the other dialog openers.

## Two traps

**Flutter caps a popup menu at 280pt.** `_kMenuMaxWidth` is `5 * 56`, which is
why the menu has always been ~275 wide. Three labelled segments do not fit, and
nothing warns you - the labels just squeeze. `PopupMenuButton.constraints` now
raises the cap to `6 * 56` when the modes are present, and only then.

**A `SegmentedButton` fills the width it is offered**, so that constant is not
a ceiling the content stops short of - it IS the menu's width whenever the
modes show. Confirmed by measuring: every locale reported the same width,
because the cap, not the labels, was setting it. 336 was chosen from real
Roboto metrics ("Reflow text" is the widest English label at ~79pt of 14pt
type, plus segment padding, times three) - NOT from a widget test, whose test
font makes any text measurement meaningless.

Segment labels ellipsize with the full text in a tooltip. They have to:
segments are all as wide as the widest, and Ukrainian's "Переформатувати
текст" alone runs 21 characters - a set that fits no sane menu.
`pdf_shell_test.dart` pins both the width and the Ukrainian no-overflow case.

One consequence to remember: the popup and its compact twin
(`showPdfShellViewOptionsSheet`) no longer hold the same things. That is
deliberate - only compact has a parent surface to promote the modes into - but
the two are easy to edit as if they mirrored each other.
