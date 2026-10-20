# Multiply highlights printed opaque on Windows/Linux

## Symptom

A user opened a foreign engineering drawing (Foxit "InkHighlight" annotations)
on Windows 2.1.0: the highlights looked correctly see-through in the viewer,
but printed as solid opaque yellow blocks that hid the linework underneath.
(Clicking a highlight also read "opacity 100%" — see the aside below.)

## Root cause

These highlights — and, it turns out, **our own** highlights too — draw an
*opaque* fill/stroke whose translucency is produced entirely by a `/BM
/Multiply` blend mode in the appearance stream's ExtGState. There is no `/CA`
or `/ca` alpha anywhere; the see-through look is the blend, not any opacity.

- The on-screen renderer and our raster export path both honor `/BM/Multiply`
  (`CanvasPdfDevice` maps it to `BlendMode.multiply` + `saveLayer`), so the
  viewer is correct.
- **Windows/Linux print does not go through the OS** — there is no native
  PDF-print API there, so `native_print_io.dart` reports `vector: true` and
  lowers each page with our own engine through `encodePageForVectorPrinting`
  → the `_EncodingDevice` in `vector_print.dart`. That device's `setBlendMode`
  was a deliberate no-op ("blend modes flatten to normal for print"), so the
  Multiply was dropped and the opaque yellow painted source-over.

macOS/iOS/Android/web hand the raw PDF to the OS (`printPdf`), so this only
bit the Windows/Linux vector path.

## Fix (`vector_print.dart`)

The op set has no blend modes (GDI/Cairo composite source-over), but it *does*
carry per-paint alpha that the replayers honor. So a darkening blend is now
approximated by lowering alpha:

- `setBlendMode` records the active blend (plain field — the interpreter
  re-issues it on every graphics-state change, `Q` restore included).
- `_flattenAlpha` caps fill/stroke paint at `_blendFlattenAlpha = 0.4` while a
  Multiply/Darken blend is active (`min`, not scale — an already-fainter paint
  isn't dimmed further). This is what a highlighter pen and a real print
  flattener both do; no single alpha reproduces Multiply exactly (over white it
  stays saturated, over black it goes dark), so 0.4 is the readable-through
  compromise.

Verified against the user's file: its yellow InkHighlight ops now lower to
alpha 102 (0.4·255) instead of 255. Tests in `vector_print_test.dart` cover a
Multiply fill, a Multiply stroke, and reset-by-a-following-Normal-blend.

## Not addressed (deliberately)

The "opacity slider reads 100%" symptom is left as-is: it is technically
correct (`PdfAnnotation.appearanceOpacity` reads `/ca`, of which there is none
— the translucency is a blend mode). Making the slider *represent* blend-mode
highlights would be a separate change in `annotation.dart`.
