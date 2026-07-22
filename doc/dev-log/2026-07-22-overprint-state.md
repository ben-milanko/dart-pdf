# Overprint state parsing (/OP, /op, /OPM) — issue #502

The renderer parsed overprint nowhere: the ExtGState `/OP` (stroke),
`/op` (fill) and `/OPM` (overprint mode) keys (PDF §8.6.7) had no home in
the graphics state and were never delivered to any device. GWG030
(2-SPOT gray/K/separation overprint patch) self-grades and failed the
Ghent render suite because of it.

## What landed

- **Graphics state.** `_GraphicsState` gained `fillOverprint`,
  `strokeOverprint`, `overprintMode`, cloned across `q`/`Q` like every
  other field.
- **Parsing.** `_applyExtGState` → new `_applyOverprint(gs)` reads the
  three keys, each updating its flag only when present (mirroring
  `ca`/`CA`/`LW`). The §8.6.7 backward-compat rule is implemented: `/OP`
  drives the nonstroking flag too **only when `/op` is absent** — probe
  `gs.containsKey('op')` before applying the fallback. `/OPM` is clamped
  to `{0, 1}`.
- **Device delivery.** New `PdfDevice.setOverprint({fill, stroke, mode})`,
  a sibling of `setBlendMode`. The interpreter calls it when the effective
  tuple changes, including on `Q` restore. Recorded as
  `PdfSetOverprintCommand` so the record→replay transcript path
  (RecordingPdfDevice → codec → replay) is faithful, with a new codec tag
  `_tSetOverprint = 14`.

## What deliberately did NOT change: compositing

Painting devices (canvas, strip binning, vector-print, image collector)
accept the state but do **not** change compositing yet. Faithful overprint
is subtractive (CMYK/spot colorant min/multiply with OPM-0/1 zero-component
semantics); we composite in RGB, which can't reproduce it.

An RGB darken/Multiply approximation was considered and rejected for this
pass: **~40 currently-passing Ghent pages set `op`/`OP` true defensively**
(fonts, optional content, soft masks, shadings — probe with the OP scan),
and the render suite's pixel comparison is macOS-only (skipped on
Linux/CI), so a broad approximation would silently regress those baselines
with no local signal. Deferred to a future colorant-buffer path; the state
is now threaded to the device so that path has something to consume.

## Test honesty

`GWG030_Gray_K_black_OP_X1.pdf` joins `_knownBaselineDeviations` in
`ghent_render_test.dart` with a back-reference to #502 — the same
missing-feature class as the allowlisted DeviceN `GWG190/191/192` overprint
patches, so the suite is honest rather than red. Still rendered and
asserted non-blank; only the pixel match is skipped.

Guard: `pdf_graphics/test/overprint_test.dart` (spirit of
`ghent_jpx_indexed_test.dart`) pins the parse directly rather than through
the tolerated raster baseline — the `/OP`→fill fallback, the explicit-`/op`
override, OPM clamping, no-op re-delivery, `q`/`Q` restore, and that
GWG030's real page delivers overprint (including OPM 1) to the device.
Codec round-trip added to `render_command_codec_test.dart`.
