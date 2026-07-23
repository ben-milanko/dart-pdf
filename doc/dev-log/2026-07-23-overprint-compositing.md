# Overprint compositing — darken approximation (issue #502)

Follow-up to `2026-07-22-overprint-state.md`, which parsed `/OP` `/op`
`/OPM` into the graphics state and delivered them to the device via
`PdfDevice.setOverprint` but left compositing unchanged. This session makes
the RGB canvas act on that state.

## What landed

`CanvasPdfDevice` now consumes the nonstroking (`/op`) and stroking (`/OP`)
overprint flags: while a flag is set and the blend mode is Normal, the
corresponding paint composites with `BlendMode.darken` (per-channel min)
instead of `srcOver`.

- `setOverprint` stores `_fillOverprint` / `_strokeOverprint`. New
  `_fillElementBlend` / `_strokeElementBlend` getters fold overprint into the
  element blend, sitting under the existing knockout (`BlendMode.src`) and
  explicit-`/BM` precedence. Wired into `fillPath`, `fillPathGradient`,
  `fillMesh` (nonstroking) and `strokePath` (stroking). Text and image
  overprint are deliberately left out for now — see limitations.
- `OPM` (`mode`) is accepted but not stored: OPM 0/1 only changes which
  DeviceCMYK components a *colorant* buffer would write, which the RGB
  approximation cannot represent.
- Kill switch `CanvasPdfDevice.debugOverprintCompositing` (default on), used
  by the A/B harness and the guard test.

## Why `darken` (not `multiply`)

`darken` = per-channel `min(ink, backdrop)`. Two properties make it the right
stand-in for "the ink darkens what it covers instead of knocking it out":

- **No-op over white.** `min(ink, 1) = ink`, i.e. identical to normal
  painting over the page background. Pages that set overprint defensively but
  paint over white are therefore unchanged.
- **Preserves the darker channels.** A neutral 50% ink over a saturated
  backdrop keeps the backdrop's already-dark colorant channels and only clips
  the lighter ones — close to a spot/process colorant surviving the overprint.

`multiply` was tried first and rejected empirically: it darkens *all* channels
multiplicatively, so overprinting 50% K onto a backdrop that already carries
50% K double-darkens it. On GWG030 that turned the fail-marker "X" from a light
knockout into a *darker* mark — still visible. `darken` makes the "over spot"
markers vanish (rendered `/tmp` before/after during development).

## Regression evidence (answers #506's open worry)

The state-parsing PR deferred compositing because ~40 Ghent pages set `op`/`OP`
defensively and the render suite's pixel diff is macOS-only, so a broad
approximation could silently regress baselines with no local signal. This
session got the local signal: an A/B harness rendered every Ghent page with
`debugOverprintCompositing` off then on (same platform, so text AA is
identical) and diffed. **Only 17 pages change, all overprint/transparency test
pages** — GWG030/040/041 (Gray/White overprint), GWG010/011 (CMYK/mode
overprint), GWG020, GWG120, GWG132/133, GWG190/191/192 (DeviceN overprint),
GWG031 (image overprint), GWG161, and the CMYK/SPOT/ICC master pages. No
general-content page moves, because `darken`-over-white is a no-op. CI is
unaffected (the pixel diff is skipped when `CI=true`; every page still renders
and is asserted non-blank).

## Limitations (still deviations)

Faithful overprint is a subtractive CMYK/spot colorant operation. `darken`
handles the common "neutral ink over a coloured backdrop" case but cannot:

- Distinguish a DeviceCMYK backdrop (whose process channels are *knocked out*
  by an overprinting process ink) from a spot backdrop of the same RGB colour
  (whose spot colorant *survives*). GWG030's "over CMYK" patches (d-f, j-l)
  therefore keep their markers; the "over spot" patches (a-c, g-i) are fixed.
- Act on the OPM 0/1 zero-component distinction.
- Overprint text or images (nonstroking `/op` in principle applies; the text
  path reuses cached, blend-less painters and images composite separately).

So GWG030 stays in `ghent_render_test.dart`'s `_knownBaselineDeviations`
(note updated), alongside the DeviceN GWG190/191/192 patches, until a real
colorant-buffer compositor lands. Full fidelity remains issue #502 scope 3.

## Tests

- `dart_pdf_editor/test/overprint_render_test.dart` (new): renders GWG030 with
  overprint compositing on and off and asserts patch 'a' (50% K over spot)
  shows the light knockout "X" without it and is near-uniform green with it —
  a composite guard in the spirit of `ghent_jpx_indexed_test.dart`, runnable
  on Linux (no pixel baseline needed).
- `pdf_graphics/test/overprint_test.dart` header updated; still pins the
  parse/delivery half.
- `ghent_render_test.dart` GWG030 deviation note updated.
