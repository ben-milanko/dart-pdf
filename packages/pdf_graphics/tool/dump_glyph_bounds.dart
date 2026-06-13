// Debug aid: flag glyph outlines with absurd bounds (parser bugs).
//   dart tool/dump_glyph_bounds.dart <file.pdf> [pageIndex]
import 'dart:io';
import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final device = _GlyphBoundsDevice();
  PdfInterpreter(cos: doc.cos, device: device)
      .drawPage(doc.page(args.length > 1 ? int.parse(args[1]) : 0));
  stdout.writeln('${device.runsWithOutlines} runs with outlines, '
      '${device.flagged} flagged');
}

class _GlyphBoundsDevice implements PdfDevice {
  int runsWithOutlines = 0;
  int flagged = 0;

  @override
  void drawText(PdfTextRun run) {
    if (!run.hasOutlines) return;
    runsWithOutlines++;
    for (final glyph in run.glyphs!) {
      // (loop body may continue)
      final outline = glyph.outline;
      if (outline == null) continue;
      var maxAbs = 0.0;
      for (final s in outline.segments) {
        final values = switch (s) {
          PdfMoveTo(:final x, :final y) => [x, y],
          PdfLineTo(:final x, :final y) => [x, y],
          PdfCubicTo() => [s.x1, s.y1, s.x2, s.y2, s.x3, s.y3],
          PdfClosePath() => const <double>[],
        };
        for (final v in values) {
          maxAbs = math.max(maxAbs, v.abs());
        }
      }
      var hasNaN = false;
      for (final s in outline.segments) {
        final vs = switch (s) {
          PdfMoveTo(:final x, :final y) => [x, y],
          PdfLineTo(:final x, :final y) => [x, y],
          PdfCubicTo() => [s.x1, s.y1, s.x2, s.y2, s.x3, s.y3],
          PdfClosePath() => const <double>[],
        };
        if (vs.any((v) => !v.isFinite)) hasNaN = true;
      }
      if (hasNaN && flagged++ < 6) {
        stdout.writeln('NaN glyph in "${run.text}" font=${run.fontName}');
        continue;
      }
      final pageExtent = maxAbs * run.transform.scaleFactor;
      if (maxAbs > 1.4 && flagged++ < 10) {
        stdout.writeln('HUGE glyph in "${run.text}" '
            'font=${run.fontName} extent=${pageExtent.toStringAsFixed(0)}pt size=${run.fontSize} '
            'color=${run.color} origin=(${run.transform.e.toStringAsFixed(0)},'
            '${run.transform.f.toStringAsFixed(0)})');
      }
    }
  }

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double a) {}
  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double a) {}
  @override
  void fillMesh(PdfMesh mesh, double a) {}

  @override
  void strokePath(PdfPath path, PdfColor color, PdfStroke stroke, double a) {}
  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawImage(PdfImageRequest request) {}

  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask, double backdropLuminance = 0, double transferScale = 1, double transferOffset = 0}) {}
}
