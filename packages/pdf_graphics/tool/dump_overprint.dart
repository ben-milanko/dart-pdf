// Debug aid: dump fill/stroke operations with their overprint state.
//   dart tool/dump_overprint.dart <file.pdf> [pageIndex]
import 'dart:io';
import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final pageIndex = args.length > 1 ? int.parse(args[1]) : 0;
  final device = _DumpDevice();
  PdfInterpreter(cos: doc.cos, device: device).drawPage(doc.page(pageIndex));
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
      '(${maxX.toStringAsFixed(1)},${maxY.toStringAsFixed(1)})';
}

class _DumpDevice implements PdfDevice {
  bool fill = false;
  bool stroke = false;
  int mode = 0;
  int n = 0;

  String get _op => 'op=$fill OP=$stroke OPM=$mode';

  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {
    this.fill = fill;
    this.stroke = stroke;
    this.mode = mode;
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double a) {
    stdout.writeln('[${n++}] fill   ${_bounds(path)} $color '
        'segs=${path.segments.length} $_op');
  }

  @override
  void strokePath(PdfPath path, PdfColor color, PdfStroke s, double a) {
    stdout.writeln('[${n++}] stroke ${_bounds(path)} $color $_op');
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}
