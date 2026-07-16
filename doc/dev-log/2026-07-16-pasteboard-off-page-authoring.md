# Drawable pasteboard: authoring annotations off the page

## Goal

Let a user draw annotations *outside* the page box - in a blank margin
beside the page - and have them save with the page. The earlier
"over-pan past the edge" work (see 2026-07-16-overpan-margin.md and the
fit-zoom pan commits) only let you *look* past the edge; it never gave you
a surface to draw on out there, and the reveal gesture (trackpad/Shift-
wheel) was undiscoverable, especially with a mouse.

## Approach: an inset page with a drawable band (opt-in)

`PdfViewer.pasteboardMargin` (logical px, default 0 = off; also on
`PdfEditorView`). When set, the widest page fit-widths to
`viewport - 2*margin` instead of the full viewport, so a blank band of
`margin` px stays visible on each side of the page. The band is a real,
laid-out part of the page tile, so a pen/mouse lands in it (Flutter only
delivers pointer events inside laid-out bounds - an off-screen overflow
would not have worked).

Key point that made this cheap: `PdfPageGeometry.toPagePoint` never
clamped, so a view position outside the page already maps to a PDF
coordinate outside the crop box. The ink capture path
(`editing_overlay.dart` `_onPointerDown`/`_onPointerMove` ->
`toPagePoint`) has no clamp either, and `PdfAnnotationEditor.addInk` /
`_inkAppearance` derive the `/Rect` from the actual points with no
MediaBox intersection. So off-page ink authors and persists with no
model changes - the whole problem was *layout*: giving the pen a surface
in the margin.

## The pieces

- `page_geometry.dart`: `PdfPageGeometry` gained an optional
  `origin` (default `Offset.zero`) - where the page's top-left sits in the
  coordinate space the view offsets live in. `toViewOffset` adds it,
  `toPagePoint` subtracts it. With the page inset by the band, the editing
  overlay spans the full tile and uses `origin: Offset(margin, 0)`, so a
  gesture in the band maps (unclamped) to a negative / off-page x.
- `pdf_viewer.dart`:
  - `_pasteboardX` = `min(pasteboardMargin, viewWidth*0.3)`;
    `_contentWidth` = `viewWidth - 2*_pasteboardX`; `_fitWidthScale` now
    divides by `_contentWidth`, so pages render inset and `_pageLeft`
    centers them with the band. At `pasteboardMargin == 0` every value is
    identical to before (guarded by the `<= 0` short-circuit), so the
    default view and the whole existing test suite are unchanged.
  - `_PdfViewerPage` gained a `pasteboard` field. Its build wraps the
    page-space layers (raster, annotation appearance, highlight, field
    wash, cross-page ghost) in a `Padding(horizontal: pasteboard)` so they
    inset together, while the editing/overlay `LayoutBuilder` stays
    `Positioned.fill` (the full tile) and builds its shared `geometry` with
    `viewSize: (w - 2*pasteboard, h)` and `origin: (pasteboard, 0)`. The
    other page-space painters keep their own origin-0 geometry from the
    (now inset) padded box, so everything lands on the same on-screen rect.
- `pdf_editor_view.dart`: `pasteboardMargin` passthrough to the inner
  `PdfViewer`. The example app sets it to 96 so the demo shows the band.

## Verified

`test/editing_pasteboard_test.dart`: a stylus stroke started at screen
x=40 (inside a 120px left band) commits an `Ink` annotation whose first
point x is < the crop box left (measured -87.4 in page space), and that
off-page `/Rect` round-trips through `editing.bytes` -> reopen. The
coordinate-sensitive suites (viewer, iPad ink, rotation, drag preview,
shape resize, page geometry) all pass unchanged at `pasteboardMargin: 0`.

## Not done yet (follow-ups)

- Only **ink/pen** is fully off-page. The placement clamps for
  notes/stamps/free-text/shapes still clamp to the crop box
  (`editing_controller.dart` ~2163/2528/2852, `editing_overlay.dart`
  ~1877), so those tools snap back onto the page in the band. Widen those
  clamp boxes by the pasteboard margin to let every tool author off-page.
- Vertical band (top/bottom) - the inset is horizontal only for now;
  vertical needs the itemExtent / scroll-geometry sums to grow (see the
  deferred vertical-bleed task).
- Flatten currently clips off-page appearances at the MediaBox; add an
  option to expand the MediaBox so pasteboard art survives flatten.
