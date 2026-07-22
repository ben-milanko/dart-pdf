# Annotation move/resize did not repaint until a tab switch

## Symptom

Reported against 2.1.0: dragging a text box or an image stamp around the
page (or scaling it) left it visually pinned at its old position. The edit
had landed - selection chrome and the model were at the new spot - but the
rendered appearance only jumped to the new position after switching tabs and
coming back.

## Root cause

`_AnnotationAppearanceLayer` (`pdf_viewer.dart`) renders each annotation's
`/AP` `/N` appearance to a `ui.Picture` and caches it. The layer was
introduced in `5b93c22` ("perf(document): cache PdfPage instances", #418/#441,
shipped in 2.1.0) to stop re-rendering every appearance on the page on every
commit (#404): a page of 50 highlights was paying 50 interpreter walks per
stroke.

The cache was keyed on the appearance stream instance alone. That is correct
for the case it was built for - adding an annotation leaves every existing
appearance stream identical across the incremental revision, so they all hit
the cache. But a rendered picture also **bakes in the annotation's position**:
`renderAnnotationPicture` maps the appearance BBox onto the annotation's
`/Rect` (§12.5.5) through the page transform.

`PdfEditor.moveAnnotation` rewrites only `/Rect` (and shifts the point
arrays); it does not touch the appearance stream. A stretch-resize of a stamp
(§12.5.5, non-regenerating subtypes) likewise changes `/Rect` while the stream
stays put. So after a move/resize the stream instance was unchanged, the cache
returned the **stale picture positioned at the old `/Rect`**, and the box
looked frozen. A tab switch rebuilt the layer state, clearing the cache and
forcing a fresh render at the new box - which is why the change appeared only
then.

(Shapes and free text *regenerate* their appearance on resize, so a new stream
= a cache miss = correct repaint. That is why the bug showed up on move-any and
on resize of the stretch subtypes - stamps/images - but not on shape/free-text
resize.)

## Fix

Key the cache on `(appearanceStream, /Rect)` instead of the stream alone
(`_appearanceKey`). `PdfRect` has value equality, so a moved/resized box gets a
new key, misses, and re-renders at its new position, while every untouched
appearance on the page still hits - the #404 optimisation is preserved for the
common add-an-annotation path. The old-position picture falls out of the `live`
set and is retired as usual.

## Test

`annotation_appearance_cache_test.dart` gains a widget test that pumps a real
`PdfViewer`, drops a solid-red box, captures the `RepaintBoundary`, and asserts
red pixels are present at the box and absent elsewhere - then moves the box and
asserts the red **follows** it (present at the new `/Rect`, gone from the old).
Reverting the key to stream-only fails the post-move assertion, confirming the
test pins the regression.
