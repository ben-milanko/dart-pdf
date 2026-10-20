# Revision cloud: curl the scallop necks inward

## What changed

The cloudy `/BE` border ("revision cloud") scallops were plain outward puffs
whose feet met flat on the polygon edge, so the valleys between puffs were
straight-cornered cusps sitting exactly on the baseline. The request was to
make them "curl in a little" so each scallop reads as a rounder, near-closed
puff with a pinched inward cusp between neighbours (the classic
Bluebeam/Acrobat revision-cloud look).

### First attempt (insufficient) — perpendicular inset only

The first cut added just `_cloudNeckInset = 0.2`: pull the shared foot between
two puffs *inward* (toward the interior) by `bulge * _cloudNeckInset`. This
turned out to be visually invisible on screen — the reviewer said the cloud
"still looks the same." The reason: the foot control handle still pointed
purely perpendicular (`+n`), so each puff rose straight up off its foot as a
plain half-circle hump regardless of where the foot sat. Insetting the foot
only lowered the cusp point a couple of points; it did not change the
half-circle *character* of the puff. See the before/after in the harness —
lean 0 (with any inset) is indistinguishable from the shipped cloud.

### Real fix — tangential foot lean

The thing that actually curls a puff is leaning the foot control handle
*tangentially along the edge*, so the arc overshoots past vertical into a
rounder shape with a pinched neck. Added `_cloudNeckCurl` (fraction of the
perpendicular foot handle `cf`).

Leaning *both* feet symmetrically (`-u` at the start foot, `+u` at the end
foot, curl 0.5) rounded the puffs but left them symmetric. The reviewer wanted
only one side leaned per arc, which reads as the hand-drawn revision-cloud
"roll" - each scallop rises upright on its leading foot and curls over on its
trailing foot, and because the lean follows the edge direction `+u`, every
puff rolls the same way around the whole outline. Final: lean the **trailing
(end) foot only** by `+u*(cf*_cloudNeckCurl)`, leading foot upright, with
`_cloudNeckCurl = 0.75` (a single handle needs more lean than two to reach the
same roundness; 0.75 rounds cleanly with no loop - loops start past ~1.0).

Crucially the lean is **purely tangential** (along the edge), so a puff's
outward `n`-extent is still bounded by the apex height `bulge` — the convex
hull of the control points never reaches past `bulge` in the normal direction.
So `_cloudPadding` / the form BBox math is untouched, exactly as with the
inset. `_cloudNeckInset = 0.2` is kept alongside the curl: it deepens the
pinched cusp, while the curl does the rounding. Both `0` reproduce the plain
humps.

## Where

- `pdf_document` `annotation_editor.dart`: `_appendCloudPath` computes the
  apex from the raw edge midpoint (`mx`/`my`), subtracts `nx*inset` /
  `ny*inset` from each foot, and leans only the *trailing* foot handle by
  `+ux*curl` / `+uy*curl` (leading foot handle left at `nx*cf` / `ny*cf`); new
  `_cloudNeckCurl` (and existing `_cloudNeckInset`) constants next to
  `_cloudBulgeFactor`. Flip the roll direction by moving the lean to the
  leading foot (`-ux*curl` on the start handle) instead.
- `dart_pdf_editor` `editing_overlay.dart`: `_cloudPath` mirrors the same
  inset *and* curl (its own `_cloudNeckInset` / `_cloudNeckCurl` constants) so
  the live preview and afterimage curl identically to the committed
  appearance. Three constants now stay in lock-step across the two files.

## Tuning

Replicated the Dart path math in a JS/canvas harness (same approach as the
2026-07-09 cloud-shape session) and rendered with Chromium. First a
both-feet sweep (0.4→1.6) to find the rounding range; then a one-sided
(trailing-foot-only) sweep (0.6/0.75/0.9). Picked `_cloudNeckCurl = 0.75`,
trailing foot only — a clear asymmetric roll (obviously different from the
shipped half-circle humps and from the symmetric both-feet version), clean and
loop-free whether filled or stroked. `_cloudNeckInset` kept at 0.2.

## Notes

- The existing "cloud scallops stay inside the form BBox" test still passes:
  insetting only moves feet inward, the tangential lean adds no outward
  extent, and the apex (the outward extreme) is untouched, so the padded BBox
  still contains the whole outline.
