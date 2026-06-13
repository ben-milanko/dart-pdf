// Debug aid: report text runs that fall outside the active clip bounds.
//   dart tool/dump_clipped_text.dart <file.pdf> [pageIndex]
import 'dart:io';
import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final device = _ClipDevice();
  PdfInterpreter(cos: doc.cos, device: device)
      .drawPage(doc.page(args.length > 1 ? int.parse(args[1]) : 0));
}

class _Bounds {
  double minX = double.negativeInfinity;
  double minY = double.negativeInfinity;
  double maxX = double.infinity;
  double maxY = double.infinity;

  _Bounds clone() => _Bounds()
    ..minX = minX
    ..minY = minY
    ..maxX = maxX
    ..maxY = maxY;

  bool contains(double x, double y) =>
      x >= minX && x <= maxX && y >= minY && y <= maxY;

  @override
  String toString() => '($minX,$minY)-($maxX,$maxY)';
}

class _ClipDevice implements PdfDevice {
  final stack = <_Bounds>[];
  var clip = _Bounds();
  int shown = 0;

  @override
  void save() {
    stack.add(clip.clone());
  }

  @override
  void restore() {
    if (stack.isNotEmpty) clip = stack.removeLast();
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final s in path.segments) {
      final points = switch (s) {
        PdfMoveTo(:final x, :final y) => [(x, y)],
        PdfLineTo(:final x, :final y) => [(x, y)],
        PdfCubicTo() => [(s.x1, s.y1), (s.x2, s.y2), (s.x3, s.y3)],
        PdfClosePath() => const <(double, double)>[],
      };
      for (final (x, y) in points) {
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
    clip.minX = math.max(clip.minX, minX);
    clip.minY = math.max(clip.minY, minY);
    clip.maxX = math.min(clip.maxX, maxX);
    clip.maxY = math.min(clip.maxY, maxY);
  }

  @override
  void drawText(PdfTextRun run) {
    final inside = clip.contains(run.transform.e, run.transform.f);
    if (!inside && shown++ < 8) {
      stdout.writeln('CLIPPED "${run.text}" at '
          '(${run.transform.e.toStringAsFixed(1)}, '
          '${run.transform.f.toStringAsFixed(1)}) clip=$clip');
    }
  }

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
