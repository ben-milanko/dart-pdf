# Visible signature box for signing / PAdES

Signatures were always invisible: `_attachSignatureField` created a widget
with `/Rect [0 0 0 0]` and no `/AP`, so Acrobat/Bluebeam showed nothing
where the signature was. Added an Acrobat/Bluebeam-style **visible
signature box** the signer can place and that fills an existing field's
rectangle.

## API

`PdfSignatureAppearance` (in `signature_editor.dart`, exported via
`editor.dart`) describes the box:

- `page` + `rect` — where to put a box on a **freshly created** field.
- `graphic` — an optional `PdfEmbeddableImage` (handwritten signature /
  logo) drawn in the left panel instead of the large name.
- `showName` / `showDate` / `showReason` / `showLocation` — which detail
  lines appear on the right.
- `backgroundColor` / `borderColor` / `textColor`.

Threaded as an optional `appearance:` argument through both
`PdfSigning.saveSigned` and `PdfPadesSigning.saveSignedPades` →
`_emitSignatureRevision` → `_attachSignatureField`.

## Behavior

- **Existing field with a visible `/Rect`** (a producer-placed signature
  field): the box is drawn into it even without an explicit
  `appearance` — defaults are used. This is the "sign the field the author
  placed" case, matching Acrobat/Bluebeam.
- **New field**: invisible `[0 0 0 0]` as before unless
  `appearance.rect` is given, then the widget is placed at that rect on
  `appearance.page` and rendered.
- **DocTimeStamp** (`docTimeStamp: true`): never gets an appearance
  (`_emitSignatureRevision` passes `appearance: null` on that path).

Backward compatible: with no `appearance` and no visible field, output is
byte-identical to before (the `[0 0 0 0]`, no-`/AP` widget).

## Rendering

`_installSignatureAppearance` builds a `/AP /N` form XObject (reusing
form_editor's `_widgetForm` / `_setNormalAppearance` — cross-extension
private calls resolve fine since everything is `part of editor.dart`):

- optional background fill, a 1pt border, a 0.5pt column divider at 42%
  width (only when both panels carry content);
- left panel: the signer name in Helvetica-Bold auto-sized down from 22pt
  and vertically centered, or the `graphic` image scaled to fit;
- right panel: `Digitally signed by <name>` / `Date: …` / `Reason: …` /
  `Location: …`, Helvetica auto-sized from 9pt, top-anchored, word-wrapped
  and clipped to the panel.

`_drawSignatureText` does the fit-shrink-wrap-clip; fonts are inline
base-14 Type1 dicts with `/Widths` (`_signatureFont`) so other viewers
space text the same way. Date is Acrobat-style `2026.07.16 09:30:00
+00'00'` (signing time is normalized to UTC first). Text past Latin-1
degrades to spaces via `ContentWriter.showText`, same limitation as the
other appearance generators.

`tool/emit_signature_box.dart` emits a sample signed PDF for eyeballing in
a real viewer.

## Tests

`signature_test.dart` — placed box (rect, BBox, shown text), placement on
a later page, filling an existing visible field, `show*` toggles, and the
unchanged invisible default. `pades_test.dart` — a B-LTA signature with a
box stays valid + LTV. Shown-text assertions join `(...) Tj` operands with
spaces so word-wrapping reads back as the original strings.
