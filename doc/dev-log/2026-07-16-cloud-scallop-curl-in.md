# Revision cloud: curl the scallop necks inward

## What changed

The cloudy `/BE` border ("revision cloud") scallops were plain outward puffs
whose feet met flat on the polygon edge, so the valleys between puffs were
straight-cornered cusps sitting exactly on the baseline. The request was to
make them "curl in a little" so each scallop reads as a rounder, near-closed
puff with a pinched inward cusp between neighbours (the classic
Bluebeam/Acrobat revision-cloud look).

Added a single tuning constant `_cloudNeckInset = 0.2`: the shared foot
between two puffs is now pulled *inward* (toward the interior) by
`bulge * _cloudNeckInset`. The apex is still measured from the polygon edge
midpoint before the feet move, so the outward extent - and therefore
`_cloudPadding` / the form BBox - is unchanged (no clipped puffs, no padding
retune).

## Where

- `pdf_document` `annotation_editor.dart`: `_appendCloudPath` computes the
  apex from the raw edge midpoint (`mx`/`my`) and subtracts `nx*inset` /
  `ny*inset` from each foot; new `_cloudNeckInset` constant next to
  `_cloudBulgeFactor`.
- `dart_pdf_editor` `editing_overlay.dart`: `_cloudPath` mirrors the same
  inset (its own `_cloudNeckInset` constant) so the live preview and
  afterimage curl identically to the committed appearance.

## Tuning

Replicated the Dart path math in a JS/SVG harness (same approach as the
2026-07-09 cloud-shape session), rendered a `footInset` sweep (0.12–0.28)
with Chromium, and picked 0.2: a clear curl-in while the puffs still round
cleanly and the valleys don't spike. Value 0 reproduces the previous shape
exactly, so this is a pure additive tweak.

## Notes

- The existing "cloud scallops stay inside the form BBox" test still passes:
  insetting only moves feet inward, and the apex (the outward extreme) is
  untouched, so the padded BBox still contains the whole outline.
