# GPU outliner: fit substituted glyphs to their PDF slots

Follow-up to doc/dev-log/2026-10-10-unembedded-serif-substitution.md, which
taught `CanvasPdfDevice` and the Canvas2D planner to centre a substituted
piece narrower than the PDF's slot for it and squeeze one wider
(`pdfFitSubstitutedPiece`). `FlutterGpuTrueTypeTextOutliner`
(dart_pdf_editor_flutter_gpu `text_outliner.dart`) still drew every glyph
flush left at the run's uniform scale, so an accelerated tile of an
unembedded-Minion heading kept the gaps Canvas had lost.

The outliner places one glyph per placement, so each glyph is its own piece:
`_place` fits it with its substitute advance x the run's `xScale` against
`glyphWidthAt` (spacing excluded), shifts the origin by the centring gap, and
for a squeeze rewrites the outline with x scaled about the pen origin
(`_scaleX`, through `PdfPath.cursor`). Within the 0.02 em tolerance the
outline object is passed through untouched, so a metric-compatible clone's
retained scene is unchanged.

Canvas fits multi-glyph *pieces* where the substitute holds within the cut
tolerance; per-glyph fitting here agrees with it to that tolerance.
Test: `text_outliner_test.dart` "fits each glyph to its PDF slot".
