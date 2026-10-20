import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';

/// Whether baking [color] would change how a page looks anywhere: white
/// (after compositing any translucency over white, as the viewer does) is
/// what every PDF reader already paints, so it has nothing to bake.
bool pdfPageColorNeedsBaking(Color color) =>
    _composedOverWhite(color) != 0xFFFFFF;

/// Whether [document] must not have its page colour baked in: painting a
/// background changes every page's content, which invalidates (or, for a
/// certified file, breaks the permissions of) its digital signatures.
bool pdfPageColorBakeBlocked(PdfDocument document) =>
    PdfSignature.of(document).isNotEmpty;

/// [bytes] with [color] painted behind every page's content as an
/// incremental update, so other PDF readers show the paper colour the
/// viewer displays (see `PdfEditingPreferences.bakePageColor`). Translucent
/// colours are composited over white first, matching the viewer.
///
/// Pass the revision's own [source] when there is one: it reopens [bytes]
/// through [PdfDocument.openAppended], reusing an encrypted file's
/// authenticated keys; without it [bytes] must open with no password.
/// Returns [bytes] unchanged when [color] has nothing to bake. Callers check
/// [pdfPageColorBakeBlocked] first - this does not refuse signed files.
Uint8List pdfBakePageColor(Uint8List bytes, Color color,
    {PdfDocument? source}) {
  if (!pdfPageColorNeedsBaking(color)) return bytes;
  final document =
      source != null ? source.openAppended(bytes) : PdfDocument.open(bytes);
  return (PdfEditor(document)..fillPageBackground(_composedOverWhite(color)))
      .save();
}

int _composedOverWhite(Color color) {
  final argb = color.toARGB32();
  final a = (argb >> 24) & 0xFF;
  int channel(int shift) {
    final c = (argb >> shift) & 0xFF;
    return (c * a + 255 * (255 - a) + 127) ~/ 255;
  }

  return (channel(16) << 16) | (channel(8) << 8) | channel(0);
}
