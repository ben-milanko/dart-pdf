# Image stamp opacity restyle

**Symptom.** A pasted/placed image (`PdfEditingController.placeImage` /
`addImageInRect`) could not have its opacity changed after the fact: the
tune-menu opacity slider did nothing, and the properties panel showed no
appearance controls at all.

**Root cause.** A placed image is a `/Stamp` annotation whose appearance is
a single image XObject and which carries **no** `/Contents`
(`PdfEditor.addImageStamp`, `annotation_editor.dart`). The behavior's
restyle gate was:

```dart
'Stamp' => annotation.normalAppearance != null &&
    (annotation.contents?.isNotEmpty ?? false),
```

so image stamps failed `canRestyle`. That gate exists because the Stamp
restyle path (`_regenerateStyledAppearance` → `_stampContent`) redraws a
text check-mark from `/Contents` - running it over an image stamp would
wipe the picture. Both symptoms followed from the one gate: the tune-menu
slider still rendered (`behavior.supportsOpacity` is true for `Stamp`) but
`restyleSelected` bailed on `canRestyleSelected`; the properties panel's
`_styleControls` returns early when `!canRestyleSelected`, so it drew
nothing.

**Fix.** Teach the restyle path to re-bake only the alpha over the same
image instead of excluding image stamps.

- `PdfAnnotationBehavior.isImageStamp` (`annotation_behavior.dart`): a
  `/Stamp` whose normal appearance references an image XObject. `canRestyle`
  for `Stamp` now also accepts image stamps.
- `annotation_editor.dart`: `addImageStamp`'s appearance build is factored
  into `_imageStampContent(rect, imageRef, opacity, pageRotation:)` (shared
  so creation and restyle stay identical). `_stampImageRef(form)` recovers
  the existing indirect image reference from an appearance so a restyle
  re-references the picture rather than re-embedding it. The `Stamp` branch
  of `_regenerateStyledAppearance` now forks: image stamp → rebuild via
  `_imageStampContent` at the new alpha; text stamp → the old
  `_stampContent` path. This rides the existing rotation-aware
  `_restyleRegenerate` (local-rect regen + `rotateAnnotation`), so a rotated
  image stamp keeps its angle.
- `_appearanceOpacity(form)` is the fallback when a restyle passes no
  opacity, so an alpha-preserving restyle keeps the current transparency
  instead of resetting to opaque.

**UI.** An image has no tintable colour, so the properties panel hides the
colour swatch for image stamps: `PdfAnnotationBehavior.supportsColor`
(`canRestyle && !isImageStamp`) gates the `pdf-prop-color` row in
`editing_properties.dart`. Opacity stays. The tune menu already only offered
opacity for the default stamp case, so no change there.

**Tests.** `image_stamp_test.dart` flips the old "not restyleable" assertion
to "restyleable for opacity, reads as image stamp, no colour", plus a
round-trip that the alpha changes while `/Img0 Do` (and the image XObject)
survives, and that a no-opacity restyle preserves a bumped alpha.
`editing_properties_test.dart` adds a widget test: a placed image shows no
colour swatch, and dragging the opacity slider lowers `appearanceOpacity`
while the picture survives.
