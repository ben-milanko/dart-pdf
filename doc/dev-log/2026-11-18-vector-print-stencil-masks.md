# Vector print: stencil masks printed white

A user printed one page of a signalling correlation pack (an A1 GEC drawing
from 1984, scanned and stored as 126 CCITT G4 `/ImageMask` strips, 3337x20
each, painted with `0 0 0 scn`) and got only the markups - stamps, clouds and
measured voltages - on blank paper.

## Cause

`decodePdfImagePixels` turns an `/ImageMask` into **white** RGBA carrying the
coverage in alpha; the fill colour is the device's job (`PdfImageRequest.
isStencil` + `stencilColor`, which the canvas device applies with a `srcIn`
colour filter). `_EncodingDevice.drawImage` in
`pdf_graphics/src/vector_print.dart` ignored both and blitted the coverage as
is, so every stencil reached the `VPR1` stream as opaque white. Every
vector-print consumer (Windows GDI, Linux Cairo) was affected; the on-screen
render was not.

## Fix

`tintVectorPrintStencil` paints a stencil's coverage in `stencilColor` at the
fill alpha (after the Multiply/Darken print flattening, like any fill) into a
**new** straight-alpha buffer. It reads only the alpha channel, so the
pure-Dart decode (straight white) and the `dart:ui` readback in
`vector_print_ui.dart` (premultiplied) tint the same, and it never writes the
input, because that path shares one pixel buffer between every draw of the
same image (`pixelsByKey`) and two draws of one mask may use different fills.

Tests: `vector_print_test.dart` `stencil masks` group. On the reporter's page,
all 311,409 covered stencil pixels were white before and are black now.
