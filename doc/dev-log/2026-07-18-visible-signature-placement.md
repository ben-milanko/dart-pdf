# Visible signature placement (draw-a-box to sign)

Adds Acrobat/Bluebeam-style placement of a **visible** digital signature: arm
a tool, drag a rectangle on the page, then pick an identity + appearance and
cryptographically sign into that box. Previously the app only produced
invisible signatures (no on-page appearance).

## Layers

**Model (`pdf_document`)** — the visible box already existed
(`PdfSignatureAppearance` + `_installSignatureAppearance` in
`signature_editor.dart`: two-column name/details box, optional left-panel
`graphic`, colors). Added `PdfSignatureAppearance.backgroundImage`: an opaque
image drawn first, covering the whole box (aspect-fill, clipped to the /Rect)
behind the border/divider/text/graphic — a company-logo backdrop. Rendered as
a `SigBg` image XObject. Test: signature_test.dart "a background image covers
the box behind the text, clipped".

**Controller (`dart_pdf_editor`)** — threaded `PdfSignatureAppearance?
appearance` through the three sign methods (`addDigitalSignature`,
`addSelfSignedSignature`, `addKeylessSignature`) and
`PdfDigitalSignatureIdentity.sign`, forwarding to the already
appearance-capable `PdfEditor.saveSignedPades`/`saveSelfSigned`/
`saveSelfSignedPades`. Test: editing_digital_signature_test.dart "a placed
appearance signs into a visible box (rect + /AP)".

**Tool + overlay (`dart_pdf_editor`)** — new `PdfEditTool.signatureBox`
(distinct from the existing ink `signature` tap-tool). It's a drag-rect tool:
added to `_panStart`'s draggable set, `_commitRect` calls a new host callback
`PdfSignaturePlacer onPlaceSignature(context, {pageIndex, pageRect})` with the
rect converted to PDF user space by `PdfPageGeometry.toPageRect` (rotation-
aware). Threaded `onPlaceSignature` like `onSnapshot` through pdf_viewer.dart /
pdf_editor_view.dart / editing_overlay.dart. Toolbar: an Insert-group button
(`Icons.draw_outlined`). Registered a `_SimpleTool(signatureBox)` behavior row
— **every** `PdfEditTool` needs one or `PdfEditToolBehavior.of` null-throws
(this is what `editing_tool_behavior_test` enforces over `PdfEditTool.values`;
adding an enum value without the row breaks it). Drag marquee shares the
snapshot case in `_paintShapePreview`; precise cursor comes from the default
branch. Tests: editing_signature_box_test.dart (drag → callback with correct
page/rect round-trip; inert with no handler).

**App (`app/`)** — `PdfEditorView(onPlaceSignature:)` routes to
`_digitallySign(tab, placement:)`, which opens the existing digital-signature
dialog with `placement` + a `logoPicker` (`pickImageBytes`). When placement is
set the dialog shows an **Appearance** section: "Draw signature…" (reuses
`showPdfSignatureDialog`; the `PdfInkSignature` is rasterized to a transparent
PNG by `signature_raster.dart` → appearance `graphic`) and "Add logo…"
(`PdfEmbeddableImage.decode` of picked PNG/JPEG → `backgroundImage`), plus a
live `_AppearancePreview`. Reason/location come from the dialog's existing
fields. `_submit` builds the `PdfSignatureAppearance` and returns it in
`DigitalSignatureOptions.appearance`, which `_digitallySign` forwards to
whichever identity path (keyless / self-signed / BYO) is active. Test:
digital_signature_test.dart "placement shows the Appearance section and returns
an appearance".

## Notes / gotchas
- The `graphic` (hand-drawn mark) replaces the *name* in the left panel, but
  the right panel still lists "Digitally signed by … / date / reason /
  location" — so name+details and a drawn mark coexist, as asked.
- `CosDictionary` and other pdf_cos types are not re-exported through
  `dart_pdf_editor`'s public API; editor tests assert on `widget['AP']`
  presence rather than the COS type.
- `dart test` at the pdf_document root default `-j` can exhaust compile
  resources and report spurious "loading …" failures; `-j 4` runs clean (754
  pass).
