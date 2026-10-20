# 2026-10-16 - image crop chrome fixes

Two visual bugs in the interactive image crop (`PdfImageCropOverlay`,
`editing_image_crop.dart`):

- **Giant confirm/cancel chips.** The crop overlay sits inside the viewer's
  zoom transform, but the chips were laid out at 1:1 logical size, so at 386%
  they rendered ~130px across and sat on top of the image. They now
  counter-scale by `chromeScale` (`FractionalTranslation` + `Transform.scale`,
  the same pattern as `_buildSelectionChip`), ride 12px below the crop, flip
  above it when the page runs out, and tuck inside the bottom edge as a last
  resort.
- **Wrong handles.** The ordinary selection chrome (tinted box, square resize
  knobs, rotate knob) kept painting under the crop frame, because
  `_EditingPreviewPainter` was never told a crop was armed. `selectionRect`,
  `showHandles` and `showRotateHandle` are now off while `cropping`, and the
  crop frame draws proper crop handles: corner L-brackets and edge-midpoint
  bars (accent over a white halo), with a haloed rule-of-thirds grid.

Hit-testing is unchanged (`HandleLayout.handleAt` on the crop rect).
Regression test: "the chips counter-scale with zoom and sit below the crop"
in `test/editing_image_crop_test.dart`.
