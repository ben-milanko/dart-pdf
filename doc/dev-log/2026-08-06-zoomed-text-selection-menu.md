# 2026-08-06 — the paste menu that wasn't: text selection toolbars under the zoom transform

Reported from an iPhone: *"if the page is zoomed in more than 100%, holding
in a text box doesn't bring up the paste menu."* The long press was fine.
The menu came up — hundreds of pixels away from the field, off the side of
the screen.

## Why 100% is the threshold

The viewer splits zoom in two (`_zoomTo` in `pdf_viewer.dart`): at or below
fit-width the *pages lay out* smaller and the `InteractiveViewer` matrix
stays identity; above it the layout is pinned and the zoom lives in the
transform. So >100% is exactly "the page, and every editor over it, is now
inside a scaled `Transform`". Anything that assumed the field's transform to
the screen was a pure translation breaks at that line and only at that line.

Flutter's selection toolbar assumes exactly that. `SelectionOverlay
.showToolbar` wraps the menu in

```dart
CompositedTransformFollower(
  link: toolbarLayerLink,                       // leader: the field
  offset: -renderBox.localToGlobal(Offset.zero),// the field's global origin
  child: contextMenuBuilder(context),
)
```

(`_SelectionToolbarWrapper`, framework `widgets/text_selection.dart`). The
menu itself lays out in **screen** coordinates — `AdaptiveTextSelectionToolbar`
positions itself around `editableTextState.contextMenuAnchors`, which are
global — so the follower's transform and that negated origin are meant to
cancel out. Write the follower's map for a leader at global origin `G` under
scale `s`:

```
p ↦ G + s·(offset + p) = G + s·(-G + p) = (1 - s)·G + s·p
```

At `s = 1` that's the identity, as intended. At `s = 2` the menu is drawn
twice as large **and translated by `-G`** — i.e. displaced by the whole
distance from the screen origin to the field. Measured in a widget test
(800×600, 2× zoom, a free-text box mid-viewport): the menu's buttons landed
269px to the right of where the framework had anchored them. On a 390pt-wide
phone that is entirely off-screen, which is what "holding does nothing"
looks like from the outside.

The scale half of this was already known and half-treated: the editing
overlay counter-scaled the menu with `Transform.scale(_chromeScale, alignment:
topCenter)` and still counter-scales the handles (`_ScaledTextSelectionControls`).
Scaling about the menu's own top-centre fixes its size and leaves the
displacement untouched, so the menu stayed lost.

## The fix

`editing_text_menu.dart` — `pdfPlacedTextSelectionMenu(editableTextState, menu)`
wraps the menu in the inverse of the field's own transform, taken about the
field's origin:

```dart
correction = translate(origin) · inverse(fieldToGlobal)
```

Composed with the follower (`fieldToGlobal ∘ translate(-origin)`) that is
exactly the identity, so the menu lands on the anchors the framework
measured — at any scale, and rotation too (the free-text editor spins its
box with `Transform.rotate`). When the field is unscaled the correction *is*
the identity and the framework's own placement is returned untouched, so
nothing changes below 100%.

Both in-page text inputs use it: the editing overlay's free-text / form
editor (replacing the counter-scale hack — the inverse carries the `1/s`
itself) and the reader's inline form-field editor in `editing_form_layer.dart`,
which had no treatment at all and so was both oversized and displaced.

Residual, noted in the source: the follower links to the field's inner
scroll viewport while the correction is measured on the box the framework
negates (the `EditableText`), so a field scrolled inside itself is off by
its own scroll offset — times the zoom now, rather than once. Our in-page
editors are sized to their content and don't scroll internally.

## Tests

- `editing_text_edit_test.dart` — *the long-press selection menu holds its
  place while zoomed*: long-presses the free-text editor unzoomed and at 2×
  and requires the menu's button bounds to sit in the same place relative to
  `contextMenuAnchors.primaryAnchor`, at the same size, and on screen.
  Measuring against the anchor rather than the press point is what makes the
  two comparable: the caret line is twice as tall at 2×, so the press-relative
  offset legitimately differs. Fails on the parent commit by 269px.
- `editing_form_interactive_test.dart` — *the long-press selection menu lands
  on a zoomed field*: the same property for the reader's form-field editor at
  1.5×. Fails on the parent commit by 117px. It types into the field first —
  an empty field parks its caret at the left edge, which this zoom has pushed
  off-screen, and a menu clamped by the screen edge says nothing about where
  it was anchored.

Both run with `debugDefaultTargetPlatformOverride = TargetPlatform.iOS` and a
mocked clipboard, since long-press-shows-the-menu on a collapsed selection is
iOS behaviour.

`dart analyze` clean; all 2116 `dart_pdf_editor` tests pass.
