// Debug aid: print full segment lists for wide, short fills (border bars).
//   dart tool/dump_bar_paths.dart <file.pdf> [pageIndex]
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final pageIndex = args.length > 1 ? int.parse(args[1]) : 0;
  final device = _BarDevice();
  PdfInterpreter(cos: doc.cos, device: device).drawPage(doc.page(pageIndex));
}

class _BarDevice implements PdfDevice {
  int shown = 0;

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double a) {
    var minY = double.infinity, maxY = double.negativeInfinity;
    var minX = double.infinity, maxX = double.negativeInfinity;
    for (final s in path.segments) {
      if (s is PdfMoveTo) {
        minY = s.y < minY ? s.y : minY;
        maxY = s.y > maxY ? s.y : maxY;
        minX = s.x < minX ? s.x : minX;
        maxX = s.x > maxX ? s.x : maxX;
      }
      if (s is PdfLineTo) {
        minY = s.y < minY ? s.y : minY;
        maxY = s.y > maxY ? s.y : maxY;
        minX = s.x < minX ? s.x : minX;
        maxX = s.x > maxX ? s.x : maxX;
      }
    }
    final h = maxY - minY;
    final w = maxX - minX;
    if (h > 2.5 && h < 4 && w > 50 && shown < 2) {
      shown++;
      stdout.writeln('fill rule=$rule color=$color '
          'bounds=($minX,$minY)-($maxX,$maxY):');
      for (final s in path.segments) {
        switch (s) {
          case PdfMoveTo(:final x, :final y):
            stdout.writeln('  M $x $y');
          case PdfLineTo(:final x, :final y):
            stdout.writeln('  L $x $y');
          case PdfCubicTo():
            stdout.writeln('  C ${s.x1} ${s.y1} ${s.x2} ${s.y2} '
                '${s.x3} ${s.y3}');
          case PdfClosePath():
            stdout.writeln('  Z');
        }
      }
    }
  }

  @override
  void save() {}
  @override
  void restore() {}
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
  void drawText(PdfTextRun run) {}
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
