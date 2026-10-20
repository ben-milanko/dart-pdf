# Pressure-sensitive ink turned into a hairline on commit (#660)

Low-pressure ink looked right while the pen was down and then snapped to a
one-device-pixel hairline the moment the committed annotation appearance
replaced the live overlay - and stayed one pixel at 333% zoom. Reported on
Flutter iOS at 333%, but it is not platform-specific.

## The defect

`PdfPageRenderer.renderAnnotationPicture` records a **scale-independent**
`ui.Picture`: the viewer's `_AnnotationAppearanceLayer` paints it through
`canvas.scale(size.width / pageSize.width, ...)`, so one picture serves every
zoom (and the drag/resize previews map it onto a target rect). It built its
device with the default pixel ratio:

```dart
PdfInterpreter(cos: cos, device: CanvasPdfDevice(canvas, images: images))
    .drawAnnotation(page, annotation);
```

`CanvasPdfDevice.strokeWidthFor` then applied #426's one-device-pixel floor at
record time:

```dart
return width * pixelRatio < 1 ? 0 : width;   // pixelRatio == 1 here
```

0 is Skia's hairline - exactly one device pixel at *any* canvas transform - so
every positive width below 1 pt was baked into the picture as "one pixel,
forever", immune to the page-to-view scale it is later replayed at.

Pressure is what made it look intermittent. Ink strokes vary width per segment
at `pdfInkStrokeWidth(base, p)` = `base × (0.4 + 1.2p)`, so a 1.5 pt pen spans
0.6 pt at pressure 0 through 2.4 pt at full pressure: the light end of a stroke
went hairline while the rest of the same stroke kept its width. The live
overlay has no floor at all (`_paintInkStrokes` gets
`preferences.strokeWidth * geometry.scale`, i.e. view pixels), which is why the
transition was visible as a snap.

## The fix

One argument - `pixelRatio: 0` disables the floor for this recording only:

```dart
CanvasPdfDevice(canvas, images: images, pixelRatio: 0)
```

Positive page-space widths survive verbatim and scale with the replay
transform. A genuine `0 w` stroke arrives at the device as 0 and still paints
as Skia's hairline, which is what §8.4.3.2 asks for. Every raster path that
*knows* its output scale keeps its positive ratio, so #426's CAD-linework floor
(0.06 pt / 0.12 pt lines that meant "hairline" and used to paint at ~6% alpha)
is untouched - including the scale-independent **page** picture, whose widths
are the producer's linework rather than an editor-authored measurement.

The asymmetry that leaves: an ink annotation viewed *without* an editing or
form controller renders through the page picture (`showAnnotations`), where the
floor still applies, so a saved 0.6 pt stroke reads as a hairline in the plain
reader path. Fixing that needs the interpreter to tell the device it is inside
the annotation slice - across the record/replay command buffer and the worker
isolates too - which is a bigger change than this bug warrants.

## Coverage

`test/annotation_stroke_width_test.dart`. The measurements are **coverage
sums**, not pixel hits: one pixel column through the stroke, summing 0-1 per
pixel (alpha for the transparent annotation picture, ink darkness for the page
picture). That totals the stroke's device width whatever the antialiasing does
with it, which is what separates a 2 px stroke from a 1 px hairline reliably -
a `patchHas`-style probe cannot.

- `strokeWidthFor` at ratio 1 and 2 still floors (the #426 guard), at 0 keeps
  every positive width and still passes 0 through.
- The recorded annotation picture measures 0.6 / 1.0 / 1.5 pt widths at both
  1:1 and 333%: below, at and above the 1 pt threshold, all scaling with the
  replay scale. Pre-fix the 0.6 pt case reads 1.0 px at *both*.
- An exact `0 w` appearance stroke stays ~1 px at both scales.
- A 0.06 pt **page content** line stays a solid device pixel at both scales -
  #426's floor, pinned.
- The transition end to end: a stroke drawn through the viewer with raw stylus
  events at pressure 0 (TestGesture cannot carry pressure) measures 2.0 px live
  at 333%, and its committed appearance measures 2.0 px too. Pre-fix the
  committed side came out at 1.36.

The 333% scale is reached without a zoom transform by fitting a 240 pt wide
page to the 800 px test viewport: 800/240 = 3.33 px/pt, so page coordinates map
to view coordinates by one multiply.
