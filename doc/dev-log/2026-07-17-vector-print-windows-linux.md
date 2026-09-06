# Vector printing on Windows and Linux (#303)

Follow-up to #291, which put vector printing on the platforms whose OS can
print a PDF natively (iOS/macOS/Android/web). Windows and Linux have no
native PDF-print API - the reason the old `printing` plugin bundled PDFium -
so they rasterised each page to a JPEG and blitted it: no selectable text,
big spool jobs, soft linework, slow (render + JPEG-encode up front was the
dominant cost). This makes them print **vector** too, without reintroducing
a third-party PDF engine.

## Shape of the solution

The engine already lowers a page to a flat device-callback stream
(`PdfInterpreter` -> `PdfDevice`; captured by `RecordingPdfDevice`). The new
piece is a second, tiny, **font-free serialization** of that stream that a
native OS vector canvas can replay directly.

- `pdf_graphics/src/vector_print.dart` - `encodeVectorPrintPage(page)`
  interprets the page and writes a compact binary op stream (magic `VPR1`).
  All geometry is pre-transformed into **device points** (top-left origin,
  y **down**, 1 unit = 1 pt) with `/Rotate` and the crop box already folded
  in - the matrix form of the viewer's `_applyPageTransform`, unit-tested by
  a coordinate round-trip. The consumer only applies one uniform
  points->pixels scale + fit/centre; it never does matrix math.
- The op set is deliberately small: `save/restore`, `fillPath`,
  `strokePath`, `clipPath`, `text`, `image` (see the byte-layout doc on
  `encodeVectorPrintPage`). `pdf_graphics/src/vector_print_reader.dart`
  (`decodeVectorPrint`) is the reference reader the native replayers mirror,
  and what the Dart tests assert against.

### The hard part: text

- **Embedded fonts** (the interpreter exposes real glyph outlines) are
  emitted as **filled glyph-outline paths** - exact, crisp, resolution-
  independent, and the native side needs no fonts. Matches the on-screen
  renderer's `_drawGlyphOutlines`.
- **Substituted fonts** (non-embedded standard-14, which the engine has no
  outlines for) are emitted as a `text` op carrying the Unicode string,
  baseline transform and colour, so the native side draws them with a system
  font - **selectable and searchable** in the spool. The device font
  matrix's y-basis length gives the on-page em size and its x-basis angle the
  rotation (extracted rather than fed raw, to sidestep GDI/Cairo font-matrix
  sign quirks that we can't test here).

Transparency, shadings and blend modes flatten the way a printer would:
gradients/meshes -> average colour, group and soft-mask alpha dropped (the
masked content still paints, opaque). Images are decoded to RGBA and blitted
- the one thing that legitimately stays raster.

## Wiring (one job, capability-driven)

`app/lib/native_print_io.dart`: after `printPdf` reports unimplemented on
desktop, `beginJob` now returns a `vector: true` capability. When set, we
send `printPageVector` (the op stream) per page; otherwise the old
`printPage` raster path runs unchanged. So one print dialog / job covers
both, and an **older runner that omits `vector` keeps rasterising** - the
existing `native_print_io_test.dart` cases pass untouched because their mock
`beginJob` returns no `vector` key. The `dart:ui`-backed image decode lives
in `dart_pdf_editor/src/vector_print_ui.dart`
(`encodePageForVectorPrinting`), so baseline-JPEG underlays - the one image
class the pure-Dart decoder declines - still reach the stream.

## Native replayers

- **Windows** (`windows/runner/native_print.cpp`, `RenderVectorPage`): maps
  points->printer pixels with a single fit-and-centre transform and issues
  GDI `FillPath`/`StrokePath` (`ExtCreatePen` for width/cap/join),
  `SelectClipPath`, `TextOutW` (a rotated `LOGFONTW` from the matrix), and
  `StretchDIBits` for images. `NativePrinter` now tags each accumulated page
  raster-vs-vector; `printPageVector` -> `AddVectorPage`.
- **Linux** (`linux/runner/my_application.cc`, `draw_vector_page`): Cairo is
  already the `GtkPrintOperation` surface, so the print context is in points
  - fit-and-centre, then replay as `cairo_fill`/`cairo_stroke`/`cairo_clip`,
  `cairo_show_text`, and an ARGB32 surface for images. A page is detected as
  vector by its `VPR1` header (no collision with JPEG/PNG signatures), so no
  separate tag array is needed.

## Not covered here

The native replayers can't be built/exercised in the Dart CI container, so
they're validated by code review + the Dart reference reader; on-device print
verification is the remaining step. Known approximations to revisit: stroke
dashing on Windows (solid fallback), sheared/rotated image placement on
Windows (bounding-box blit), and shear in substituted text. Embedded-font
text prints as outlines (vector, not OS-selectable); a future pass could add
an invisible selectable overlay for it.
