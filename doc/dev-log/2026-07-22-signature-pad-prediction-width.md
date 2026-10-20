# Signature pad: predictive ink + a touch more width

The signature-capture pad (`PdfSignatureDialog`, `editing_signature.dart`)
drew its in-progress stroke with the ink appearance's Catmull-Rom smoothing
and pressure-mapped width, but - unlike the ink tool's live layer
(`_ActiveStrokePainter` in `editing_overlay.dart`) - it never applied the
forward-extrapolated lead from `pdfPredictStrokeLead`
(`stroke_prediction.dart`). So the pad line lagged the pen tip by the input
+ render latency the ink tool already masks.

Fix: the pad now runs the same prediction on the active stroke. New
`_activeDisplay` getter appends the display-only lead (and carries the last
pressure onto it) to the in-progress stroke, recomputed every build so the
next real sample replaces it and the lead never enters the captured
`PdfInkSignature`. Gated by a new `predictStrokes` flag on
`PdfSignatureDialog` / `showPdfSignatureDialog` (default true), mirroring
`PdfViewer.predictStrokes`. It's a standalone dialog, so the flag defaults
on rather than threading the viewer's value through every caller.

Also nudged the pen a touch heavier, per the request:
- pad preview `_baseWidth` 2.5 -> 3.0 (dialog only)
- placed/stamped ink width `w / 75` -> `w / 60` in
  `PdfEditingController.signaturePlacement` (~2.7pt at the default 160pt
  width, was ~2pt) - this is what `placeSignature` commits into the
  `/InkList` annotation.

Tests: `editing_signature_prediction_test.dart` renders the pad, draws a
stylus stroke, and asserts inked pixels reach past the last real sample
with `predictStrokes: true` and stop at it with `false` - the pad analogue
of `editing_prediction_test.dart`. Existing signature tests unchanged
(none pinned the width value).
