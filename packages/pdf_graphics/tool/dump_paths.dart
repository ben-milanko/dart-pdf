// Debug aid: dump fill/stroke operations (bounds + paint) for one page.
//   dart tool/dump_paths.dart <file.pdf> [pageIndex] [maxOps]
import 'dart:io';
import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final pageIndex = args.length > 1 ? int.parse(args[1]) : 0;
  final maxOps = args.length > 2 ? int.parse(args[2]) : 40;
  final device = _DumpDevice(maxOps);
  PdfInterpreter(cos: doc.cos, device: device).drawPage(doc.page(pageIndex));
  stdout.writeln('--- ${device.fills} fills, ${device.strokes} strokes');
}

String _bounds(PdfPath path) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  void point(double x, double y) {
    minX = math.min(minX, x);
    minY = math.min(minY, y);
    maxX = math.max(maxX, x);
    maxY = math.max(maxY, y);
  }

  for (final s in path.segments) {
    switch (s) {
      case PdfMoveTo(:final x, :final y) || PdfLineTo(:final x, :final y):
        point(x, y);
      case PdfCubicTo():
        point(s.x1, s.y1);
        point(s.x2, s.y2);
        point(s.x3, s.y3);
      case PdfClosePath():
        break;
    }
  }
  return '(${minX.toStringAsFixed(1)},${minY.toStringAsFixed(1)})-'
      '(${maxX.toStringAsFixed(1)},${maxY.toStringAsFixed(1)}) '
      'w=${(maxX - minX).toStringAsFixed(2)} '
      'h=${(maxY - minY).toStringAsFixed(2)}';
}

class _DumpDevice implements PdfDevice {
  _DumpDevice(this.maxOps);

  final int maxOps;
  int fills = 0;
  int strokes = 0;

  int get _shown => fills + strokes;

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double a) {
    fills++;
    if (_shown <= maxOps) {
      stdout.writeln('fill   ${_bounds(path)} color=$color');
    }
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double a) {
    fills++;
    if (_shown <= maxOps) {
      stdout.writeln('grad   ${_bounds(path)} '
          '${gradient.isRadial ? 'radial' : 'axial'}');
    }
  }

  @override
  void fillMesh(PdfMesh mesh, double a) {}

  @override
  void strokePath(PdfPath path, PdfColor color, PdfStroke stroke, double a) {
    strokes++;
    if (_shown <= maxOps) {
      stdout.writeln('stroke ${_bounds(path)} width=${stroke.width} '
          'dash=${stroke.dashArray} color=$color');
    }
  }

  int _depth = 0;

  @override
  void save() {
    _depth++;
  }

  @override
  void restore() {
    _depth--;
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    if (_shown <= maxOps) {
      stdout.writeln('clip@$_depth ${_bounds(path)}');
    }
  }

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
