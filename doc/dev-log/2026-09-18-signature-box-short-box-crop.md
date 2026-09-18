# Signature box clipped its detail lines top *and* bottom

Follow-up to `2026-07-22-signature-text-top-crop.md`. That session fixed a
sub-point top shave caused by `centerBlock` dropping the whole per-line
leading below the baselines. This is a different, much larger crop, reported
against a short, wide "sign on this line" placement: the top of
"Digitally signed by …" and the bottom of "Reason: Approved" were both sliced
through the middle of the glyphs, while the line between them was untouched.

## Measuring it from the screenshot

The report was a screenshot, so the geometry came out of the pixels before
any code was read. Scanning a column for the box's border rows and the ink
rows gives two equations - the border spans the whole box (`h·s` px) and the
text clip is inset by `pad` on both sides (`(h - 2·pad)·s` px) - which solve
for the scale without knowing the zoom:

```
box border rows   101 - 15 = 86 px      = h·s
ink clipped at    84 - 33  = 51 px      = (h - 8)·s      (pad = 4)
                  => s = 35/8 = 4.375 px/pt,  h = 19.66 pt
line pitch        ~22.7 px = 1.3·size·s => size = 3.99 pt
```

A font size landing on exactly 4.0 is the tell: that was the auto-fit loop's
hard stop (`if (fits || size <= 4) break`), so the loop had given up *while
the block was still too tall*. `_installSignatureAppearance` was reproduced
at `196 × 19.66` and emitted exactly that - clip `86.32 4 105.68 11.66 re`,
`/Helv 4 Tf`, first baseline `14.158`, so the top line's ascent reached
`17.03` against a clip top of `15.66` (1.37 pt over) and the last line's
descender fell to `2.93` against a clip bottom of `4` (1.07 pt under).

## Cause

Three things compounding, all in `_drawSignatureText` /
`_installSignatureAppearance` (`signature_editor.dart`):

1. **A flat `pad = 4.0`.** Fine on a 100pt box, ruinous on a 20pt one: 8pt of
   margin is over 40% of the height, leaving 11.66pt for three lines.
2. **A hard 4pt stop in the fit loop.** It is the *only* exit besides `fits`,
   so an unsatisfiable box exits with an overflowing block. It bought no
   legibility - the text is drawn into a clipped box either way, so stopping
   early only converts "small" into "sliced".
3. **`centerBlock` centres the overflow**, which splits it across *both*
   edges - the worst possible failure. Top-anchoring at least keeps the
   leading lines whole.

Note how close the reported case was to the edge: at the 4pt stop three lines
need `h ≥ 19.5pt` and the box was `19.66`. It fit only because the signature
carried no `/Location`; one more detail line would have failed on a box a
third taller.

## Fix

- `pad = math.min(4.0, math.min(w, h) * 0.1)` - never spend more than a tenth
  of the shorter side on margin. Only affects boxes under 40pt. The left
  panel's graphic shares the reclaimed room (11.66pt → 15.73pt tall here).
- `_signatureMinSize = 2.0` replaces the inline `4`, documented as a
  *containment* stop rather than a legibility floor.
- `clampVerticalAlign: true` on the `writePdfTextBox` call. That flag already
  existed for form fields (`form_editor.dart`) and top-anchors an overfull
  centre/bottom block, so the clip can only ever take the tail.

## Verifying

A sweep over 6 widths × 12 heights × graphic on/off parsed the emitted clip
rect and baselines back out of each appearance and compared the nominal ink
extents (`first + size·718/1000`, `last - size·207/1000`) against the clip:
216 blocks, 0 cropped, worst margins +0.51pt top / +0.74pt bottom. Pushed to
absurd sizes (8-12pt boxes with four long detail lines) the clip does bite,
but `top == 0.00` everywhere - the overflow leaves by the bottom only, which
is what the clamp is for.

Rendered confirmation, since the report was visual: the repro page rasterized
at 8× before and after, measuring the height of each text row. Before,
the three rows were **9, 16, 11** px - first and last shaved. After, **16, 16,
16**. (flutter_test substitutes Ahem, whose blocks fill the full em and so
overstate the ink; a conservative check.)

Regression tests in `signature_test.dart` parse blocks out of the appearance
the same way (`textBlocks` / `TextBlock`) and assert non-negative top and
bottom margins - one for the reported geometry, one sweeping box shapes, and
one pinning the degenerate case to bottom-only overflow. All three fail on
the pre-fix code.
