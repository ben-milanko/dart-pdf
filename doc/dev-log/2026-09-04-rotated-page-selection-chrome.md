# A page's /Rotate is not an annotation's rotation

## Symptom

A free-text box on a real-world drawing sits upright on screen, its
selection chrome hugging it. Grab the **right-middle** handle and the
cursor reads up-down; drag it right and the preview shows the box (text
and all) spun a quarter turn, growing *down* the screen; release and the
committed box is the transpose of the one you dragged — a 200×50 label
becomes 50×200, its text clipped to the first line.

Reproduces on any annotation on a `/Rotate 90` (or 270) page.

## Cause

The overlay's `_selectionChrome` derived the selection's resting rotation
from `appearanceQuad` mapped into **view** space (`_quadAngle`), which is
the corner order of the appearance's /BBox×/Matrix fit onto /Rect — in
page space — pushed through `PdfPageGeometry.toViewOffset`. That mapping
folds in the page's display `/Rotate`, so on a `/Rotate 90` page the
lower-left→lower-right edge of *every* square annotation runs down the
screen and the angle reads ±90°.

Everything downstream then treats the box as a rotated one:

- the chrome box becomes the transposed local rect (spun back by the
  painter, so it still *looks* right — which is why the bug is invisible
  until you grab a handle);
- `_handleAt` unrotates the pointer, so the screen-right-middle handle
  resolves to the local top/bottom-middle one — hence the up-down cursor;
- `_wrappedTextBox(rotation: _resizeAngle)` draws the live free-text
  preview spun 90°;
- double-clicking to edit the text opened the inline editor at that same
  transposed box, spun (`_textEditRotation`);
- the commit takes the local path, `resizeSelectedLocal(toPageRect(...))`,
  handing the editor a transposed page rect. `resizeAnnotationLocal`
  measures the annotation's *page-space* rotation itself, finds 0, and
  falls through to the plain `resizeAnnotation` — which faithfully applies
  the transposed rect.

Our own authoring is a case in point: `addFreeText` &co. counter-rotate
oriented artwork inside the appearance's *content stream*
(`_orientedCounterRotation`), never in its /Matrix, so the quad stays
square to the page while the artwork reads upright on screen.

## Fix

The gate is the rotation the **annotation** carries, in page space —
which is what the editor side (`resizeAnnotationLocal`, `restyleAnnotation`,
`_regenerateResizedAppearance`) has always used:

- `PdfAnnotation.appearanceRotation` (annotation.dart) — the angle of
  `appearanceQuad`'s ll→lr edge, radians CCW, ~0.3° of noise reads as 0.
  `PdfEditingController` drops its private `_appearanceRotationOf` for it.
- `_selectionChrome` returns the plain axis-aligned view rect whenever
  `appearanceRotation == 0`, whatever the page's `/Rotate`. A page's
  rotation turns the whole page, chrome included, so an annotation square
  to its page is square to its chrome.

A rotated *appearance* (`rotateAnnotation`, or a producer that bakes the
turn into the /Matrix) is unaffected: it keeps the local-frame chrome,
preview and resize, on rotated and unrotated pages alike.

Second, `_resizeCursorFor` now takes the resting angle and picks the
cursor from the direction the handle actually points on screen (the eight
compass points folded onto the four resize cursors). A 90°-rotated
annotation's local right-middle handle sits on the screen's top edge and
moves up and down; it used to promise left-right.

## Tests

`editing_rotated_page_resize_test.dart` drives the real viewer over a
`/Rotate 90` page (`buildMultiPagePdf(1, rotation: 90)`, new parameter):
the right-middle handle's cursor, the drag that must widen the box on
screen (page /Rect grows along page +y, page x untouched), the
top-middle handle in the other axis, and a genuinely rotated square on an
unrotated page keeping its spun chrome and its follow-the-handle cursor.
`annotation_test.dart` covers `appearanceRotation` directly.

Gotcha: a *vertical* drag started with the default (touch) gesture goes
to the scroll view, not the overlay — the vertical resize drags in that
file use `kind: PointerDeviceKind.mouse`.

## Still open

An appearance rotated by a non-quarter angle **on a rotated page** takes
the local path, and `_geometry.toPageRect` transposes a sideways page's
local box on the way to `resizeSelectedLocal`. Unchanged by this fix, and
it needs the local rect built from the page-space quad centre + view
lengths rather than a view rect mapping.
