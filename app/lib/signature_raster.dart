import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart' show pdfInkStrokeWidth;

/// Rasterizes a hand-drawn [PdfInkSignature] to a transparent PNG so it can
/// ride in a visible signature box as the appearance graphic
/// ([PdfSignatureAppearance.graphic]). The ink color and pressure-varied
/// width mirror the signature pad's own preview.
///
/// [height] is the raster height in pixels; the width follows the drawing's
/// aspect ratio. Returns null when nothing was drawn or the image can't be
/// encoded.
Future<Uint8List?> rasterizeInkSignature(
  PdfInkSignature signature, {
  double height = 220,
}) async {
  if (signature.strokes.every((s) => s.isEmpty)) return null;
  final aspect = signature.aspect.clamp(0.05, 20.0);
  final w = (height * aspect).clamp(1.0, 4000.0);
  final h = height;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final color = ui.Color(0xFF000000 | signature.color);
  const baseWidth = 3.0;

  for (var i = 0; i < signature.strokes.length; i++) {
    final stroke = signature.strokes[i];
    if (stroke.isEmpty) continue;
    final pressures = signature.pressures[i];
    // normalized (0-1, y down) -> pixels
    final pts = [for (final (x, y) in stroke) ui.Offset(x * w, y * h)];
    if (pts.length == 1) {
      final r = (pressures == null
              ? baseWidth
              : pdfInkStrokeWidth(baseWidth, pressures.first)) /
          2;
      canvas.drawCircle(pts.first, r, ui.Paint()..color = color);
      continue;
    }
    for (var j = 0; j + 1 < pts.length; j++) {
      final width = pressures == null
          ? baseWidth
          : pdfInkStrokeWidth(baseWidth, (pressures[j] + pressures[j + 1]) / 2);
      canvas.drawLine(
        pts[j],
        pts[j + 1],
        ui.Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round,
      );
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(w.round(), h.round());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
