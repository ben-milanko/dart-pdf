# Signature ink: any colour, and a pen thickness

The signature pad offered three fixed inks (black, navy, dark red) and no
pen control at all - `PdfEditingController.signaturePlacement` hard-coded
`strokeWidth: w / 60`. And although the placed ink already followed the
toolbar colour, the signature tool carried no style scope, so
`toolUsesColor` was false and the strip showed no colour row while it was
armed: there was nowhere to change the colour either.

Both are now first-class.

## The record carries a pen

`PdfInkSignature` gained `strokeWidth`, in **points quoted at
`PdfInkSignature.referenceWidth` (160pt - `placeSignature`'s default
size)**. Consumers scale it with `strokeWidthFor(width)` to whatever size
they draw the signature at, so the proportions hold whether it lands on a
page, in a stamp template, or in a signature-box raster:

- `signaturePlacement` - `preferences.strokeWidth * w / referenceWidth`
- `editing_stamps.dart` `_addSignature` - was `max(0.8, width / 75)`
- `app/lib/signature_raster.dart` - was a flat `3.0` px

`decode` defaults a missing (or non-finite, or non-positive) `strokeWidth`
to `defaultStrokeWidth` = `referenceWidth / 60`, which is exactly the pen
the old hard-coded formula produced - a signature saved by an older build
still stamps as it always did.

## The pad

The pad is 360px wide and a signature is stamped 160pt wide, so the pad
draws at `360 / referenceWidth` px per point: the pen thickness on the pad
is the pen thickness on the page. The colour row keeps the three presets
and gains a fourth swatch - tinted with the current ink, carrying a
`colorize` glyph - that opens the full picker, so any colour at all is
reachable. `showPdfSignatureDialog` grew `initialColor`,
`initialStrokeWidth` and a `pickColor` hook (`PdfSignatureColorPicker`);
the toolbar wires the hook to `pickEditingColor` so the pad's picker shows
the same recents and document colours as every other colour in the editor.
Callers that don't pass one fall back to a plain `showPdfColorPicker`.

## The tool

`PdfEditTool.signature` now has a style scope (`'signature'`, remembering
`color` + `strokeWidth`, seeded `strokeWidth: defaultStrokeWidth`) and
`stroke: true` in its `styleFields`. So the strip shows the colour row and
the tune popup the stroke-width slider while the signature tool is armed,
both persisted per tool - and a placed signature can still be restyled
afterwards through the ordinary Ink path.

**The ordering gotcha:** arming a tool calls `beginStyleScope`, which
restores the scope over the live values. `_drawSignature` seeds
`controller.color` / `preferences.strokeWidth` from what the pad came back
with, so on the *first* draw (pad opens, then the tool arms) the restore
lands on top of the seed and throws it away. `_toggleSignatureTool` now
re-seeds after `_toggleTool`, via the shared `_seedSignatureStyle`. The
redraw button in `_insertToolExtras` runs with the tool already armed, so
its single seed records straight into the live scope.
