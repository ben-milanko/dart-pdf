# Overprint — the RGB approximation ceiling (issue #502)

Follow-up to `2026-07-23-overprint-compositing.md`, which made
`CanvasPdfDevice` composite `/op` `/OP` fills and strokes with
`BlendMode.darken` instead of knocking the backdrop out. That flattened the
GWG030 "over spot" fail-markers but left the "over CMYK" ones visible, and the
page stayed a tolerated Ghent deviation. This session asked the natural next
question — can the remaining markers be flattened without a colorant buffer? —
measured it, and concluded no. The takeaway is documentation + tighter guard
coverage, not a behaviour change.

## The fixture, precisely

`GWG030_Gray_K_black_OP_X1.pdf` is a 6×2 grid of self-grading patches (labels
a–l). Each overprints a 50% neutral ink over a coloured backdrop and draws an
"X" marker in that same ink; the marker vanishes **iff** overprint is simulated
correctly, so a visible X is a per-patch fail flag. Probed resources:

- Backdrops: `CS1 = /DeviceN [/Black /GWG Green]` (the "spot" green) and
  `.5 0 1 .5 k` DeviceCMYK (the "CMYK" green — the same RGB colour).
- Inks: `.5 g` (DeviceGray), `0 0 0 .5 k` (DeviceCMYK K), `CS2 = /Separation
  /Black` at `.5` (separation black).
- Overprint drivers: eleven ExtGStates spanning `OP`/`op`/`OPM` combinations,
  OPM 0 (left block, a–f) and OPM 1 (right block, g–l).

## Measured behaviour

Rendered at pixelRatio 2 (511×284) and measured the non-green neutral fraction
(the knocked-out grey X) inside each patch, overprint on vs off (‰):

| patch | ink / backdrop / OPM        | off | on  | result       |
|-------|-----------------------------|----:|----:|--------------|
| a     | K / spot / 0                | 534 |   0 | flattened    |
| g     | K / spot / 1                | 456 |   0 | flattened    |
| h     | gray / spot / 1             | 380 |   0 | flattened    |
| i     | sep-black / spot / 1        | 261 |   0 | flattened    |
| j     | K / CMYK / 1                | 508 |   0 | flattened    |
| f     | sep-black / CMYK / 0        | 465 | 209 | darkened ok  |
| l     | sep-black / CMYK / 1        | 519 | 225 | darkened ok  |
| **d** | **K / CMYK / 0**            |1000 | 556 | **X remains**|
| **e** | **gray / CMYK / 0**         |1000 | 555 | **X remains**|
| **k** | **gray / CMYK / 1**         |1000 | 484 | **X remains**|

So darken flattens 7 of 10 measured patches. The residual gap is a neutral ink
(gray, or K under OPM 0) over a **DeviceCMYK** backdrop, where the correct
result knocks the process colorants out to grey. Note `j` vs `d`: the same 50% K
ink over the same CMYK green is faithful under OPM 1 (zero C/M/Y aren't written,
so the backdrop survives and K just darkens — which is what darken does) but not
under OPM 0 (all four components are written, C/M/Y = 0 knock the backdrop out
to grey — which darken cannot do). The distinction is purely a colorant-space
one; in RGB the CMYK green and the spot green are the same pixels.

## Why no fixed RGB blend closes it

Threaded `OPM` into `CanvasPdfDevice` behind a `debugOverprintStrategy` switch
and rendered the fixture under five composite strategies:

0. darken always (shipped)
1. OPM 1 → darken, OPM 0 → multiply
2. multiply always
3. OPM 1 → darken, OPM 0 → srcOver (knockout)
4. OPM 1 → multiply, OPM 0 → darken

Every alternative regresses at least one group. Strategy 3 is the instructive
one: gating OPM 0 to a knockout *fixes* d/e (over CMYK → uniform grey) but
*reintroduces* the marker on a/b/c (over spot → the separation colorant must
survive the knockout). The two only diverge in colorant space, so no blend that
sees just the RGB backdrop can satisfy both. Strategy 0 (darken always) is the
RGB optimum; the switch and the extra state were reverted.

## What landed

- No renderer behaviour change — the darken approximation stays the ceiling.
  `setOverprint`'s comment now records the empirical finding (and that OPM is
  deliberately not stored because no RGB blend can act on it).
- `overprint_render_test.dart` rewritten from the single patch-A check into the
  full a–l matrix: it pins that overprint flattens the markers it can reach
  ({a,g,h,i,j} → uniform) and that {d,e,k} remain the colorant-buffer gap
  (marker present), both platform-independently. When a colorant buffer lands,
  those three assertions flip and GWG030 leaves `_knownBaselineDeviations`.
- `ghent_render_test.dart`'s deviation comment corrected: the residual failures
  are the CMYK-backdrop neutral-ink knockouts (d/e/k), not "all over-CMYK
  patches / OPM 0" as previously written.

## Remaining work (unchanged from the issue)

Faithful d/e/k needs the scope-3 colorant buffer: composite overprint-affected
draws in a CMYK/spot colorant space with OPM 0/1 semantics and Separation/
DeviceN tint transforms, then convert to RGB. That is a substantial subsystem
on top of the RGBA `ui.Canvas` and interacts with transparency groups; it stays
future work, and pixel-enforcing GWG030 additionally needs its macOS baseline
reseeded once the render is faithful.
