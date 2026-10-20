# Speculative deepenings from the 2026-07-16 architecture review (#320)

Collector issue #320 gathered five Speculative-rated candidates from the
architecture review. This session promoted all five. Four were code
changes; one was already done. All behavior-preserving, each with tests.

## #2 - Shared `PdfMatrix` value type + `fitFormToRect`

`PdfMatrix` already existed but in `pdf_graphics`, which is *downstream* of
`pdf_document`, so the three ad-hoc affine representations in `pdf_document`
(`content_elements.dart`'s record tuple, `content_reflow.dart`'s six
mutable `a..f` locals, `annotation_editor.dart`'s `List<double>`) could not
use it. Fix: **lower `PdfMatrix` into `pdf_cos`** (the lowest layer) and
re-export it from `pdf_graphics/src/matrix.dart` so its public API and every
internal import stay unchanged. Added `PdfMatrix.row`/`toList`/`apply` and
`==`.

The §12.5.5 BBox→Rect fit is now one helper, `matrix_geometry.dart`'s
`fitFormToRect(bbox, matrix, rect)` (+ `boundsUnderMatrix`, `boundsOfPoints`),
in `pdf_document` (it returns/takes `PdfRect`, which lives there). Shared by
extraction, reflow, annotation flatten/resize/rotate/flip. Key identities
verified in tests: the old six-locals `translate` == `translation(tx,ty)
.concat(current)`, and the old `_mulAffine(a,b)` == `a.concat(b)` (both
row-vector, `this`-first).

Gotcha: `_bakedFormMatrix` must still reject a degenerate BBox (returns null
so callers skip), while the inline flatten path keeps its unit-scale
fallback and draws anyway - so `fitFormToRect` uses the unit-scale fallback
and `_bakedFormMatrix` checks `boundsUnderMatrix` separately before calling.

## #4 - Type3 glyph re-entry behind `PdfFontInfo.renderGlyph`

`isType3`/`type3Matrix`/`type3ProcFor`/`type3Resources` used to be public on
`PdfFontInfo` only so `interpreter.dart`'s `_drawType3Glyph` could re-enter
`_run`. Now `PdfFontInfo.renderGlyph(code, decode:, execute:)` owns "a Type3
glyph *is* a content stream" (the CharProc lookup and the glyph-space
/FontMatrix); the interpreter passes `decode` (so it keeps its own parse
cache + COS access) and `execute` (the ctm setup, state save/restore, and
`_run`). `type3Matrix`/`type3ProcFor`/`type3Resources` are now private;
`isType3` stays (glyph-placement decisions still need it).

## #3 - `decodePdfImage` façade

`image_pixels.dart` now exposes `decodePdfImage(stream, {region,
targetWidth, targetHeight})`: callers state which pixels they want, and the
façade picks the region-scaled / whole-image scaled / full fast path, then
falls back to a full decode cropped+downsampled when the fast path can't
handle the stream (stacked filter, Indexed-8/ICC/Lab, 16-bit, /SMask). The
region-fallback policy used to be copied into `render_command_codec.dart`
(deep-zoom detail) - both its region path and whole-image scaled path now
call the façade; the private `_cropDownsampleDecodedPixels` moved into
`image_pixels.dart` as public `cropDownsamplePdfDecodedPixels`.

Equivalence relied on: `_capImageResolution(full, transform, ratio)` and
`_targetDecodedSize` both derive their size from the same
`cappedImagePixelSize`, so "full decode then cap" == "full decode
downsampled to target". `decodePdfImageBase` stays public - the caveat in
the issue - because the editor's `dart:ui` layer pairs a purely-decoded base
with the platform JPEG codec (a non-CMYK DCT base or a DCT /SMask). Test
pins the fast region path and the full-decode fallback to pixel-identical
output.

## #1 - `HandleLayout` selection-chrome geometry

Extracted the annotation overlay's resize/rotate **hit-test** geometry
(handle centers, the rotate knob's position + hit test, `rotatePoint`, all
scaled by `_chromeScale`, spun by the resting angle) into a pure value type,
`editing/handle_layout.dart`. `_handleAt`/`_hitsRotateHandle`/`_rotatePoint`
delegate to it; the controller can-resize/can-rotate gates stay in the
State. Hit-testing is now a plain unit test over `Rect`/`Offset`.

Scope note: the two `pdf_viewer.dart` classes the issue named
(`_SelectionHandle`/`_TextSelectionChrome`) are the *text-selection carets*,
structurally different (start/end handles, no 8-corner + rotate layout), so
they were left alone. The chrome **painter** (`editing_overlay.dart`, canvas
`rotate`/`translate` with its own +2·scale inflation and knob-distance −2
inset) is also left as-is - unifying it with the hit-test frame would move
pixels. The issue's stated goal was pure-function hit-testing, which is what
landed.

## #5 - ObjStm header parsing dedup: already done

`_ObjectStream` parses the "/N pairs, /First offset" wire format once and
exposes it via `index`; `CosDocument._recover` already reuses that
(`stream.index[index].$1`) instead of re-parsing - with a comment saying so.
Already covered by `document_test.dart`'s "recovery reuses the object-stream
decoder for the header index" and "a truncated object-stream header still
salvages leading objects" (the latter proves a lenience fix in the decoder
now reaches recovery). No code change; verified only.
