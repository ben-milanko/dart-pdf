# Blended transparency groups need their own compositing layer

## Symptom

A real-world quickstart PDF (Time Without Tide) drew its decorative flourishes
- horizontal ornament dividers around section headers - with an opaque **white
box** behind them instead of blending into the cream page. In macOS Preview the
white background is invisible.

## Root cause

The flourishes are **transparency-group form XObjects** whose content is an
opaque CMYK JPEG (the artwork on a white/paper background, no /SMask). The page
draws each group through an ExtGState that sets **`/BM /Multiply`**. Under
Multiply the JPEG's white background multiplies against the cream page and
disappears; only the dark ink survives. That is the intended mechanism.

Per §11.6.6 a transparency group composites **as one object**: the alpha *and
blend mode* in effect at the `Do` apply to the group's composite result, and
reset to their defaults inside the group. Our interpreter
(`PdfInterpreter._doXObject`) only opened a dedicated compositing layer
(`device.beginGroup`) when `groupAlpha < 1 || knockout`. A non-Normal **blend
mode** was not a trigger, so no layer was created and the outer Multiply stayed
as loose device state - which the group's own first `gs` (`/GS0`, `/BM Normal`)
immediately overwrote before the image drew. The image then painted with Normal
blend: an opaque white box straight over the page.

## Fix

`_doXObject` now also opens a group layer when a non-Normal blend mode is active
(`blended = groupBlend != PdfBlendMode.normal`). The canvas device's
`beginGroup` already snapshots the current blend mode into the layer's
compositing paint, so the group as a whole blends onto the backdrop correctly.
Inside the layer the blend mode is reset to Normal (mirroring the existing alpha
reset) so an inner element's own blend isn't applied twice, and the device blend
mode is re-synced to the restored graphics state on the way out (it is not part
of canvas save/restore state).

## Verification

- Page 9 of the report renders the flourishes on cream, no white box; the blue
  score-table banners (also `/BM /Multiply` groups) still render correctly.
- Ghent PDF Output Suite: the GWG16.0/16.1 "Transparency Basic Blend Modes"
  pages went from an "X" in every cell (their own "rendering is incorrect"
  marker) to correct for almost every blend mode, and the vector/text softmask
  pages that were hiding their labels and objects under a mis-composited white
  box now render in full. These are genuine improvements over the pinned
  baselines; re-accept them with `GHENT_UPDATE=1` on the reference render
  environment (not committed here - a bulk `GHENT_UPDATE` in this container also
  rewrote ~24 unrelated overprint/16-bit/ICC baselines with sub-threshold
  rasterization noise, so the safe move is to re-baseline the transparency and
  softmask pages deliberately where the baselines were authored).
- `interpreter_test`, `render_command_test`, `render_command_codec_test`,
  `streaming_interpreter_test`, the pure-Dart PDF.js corpus and the Flutter
  PDF.js render smoke all pass; the Ghent pure-Dart interpret pass is green.

## Not reproduced: "black bar on the RHS of page 9"

The same report was reported to show a black bar down the right edge of page 9
that macOS Preview does not. It did not reproduce in any headless render path
here - direct-canvas, strip/tiled device, or recorded scene replay, at 2x and
3x - where the right edge stays clean cream. Leading hypothesis: the right-edge
border ornament is a black-filled (`0 g`) transparency group clipped to a ~6pt
slice at the page edge and cut out by a **Luminosity** soft mask; if that mask
is dropped in a path we can't exercise here (web/CanvasKit, or the live
worker/atlas deep-zoom region render) the black fill would show as a thin bar
exactly on the RHS. Needs the platform and zoom level to pin down.
