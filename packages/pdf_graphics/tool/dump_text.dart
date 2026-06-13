// Debug aid: dump text runs (with metrics) for one page.
//   dart tool/dump_text.dart <file.pdf> [pageIndex] [maxRuns]
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final pageIndex = args.length > 1 ? int.parse(args[1]) : 0;
  final maxRuns = args.length > 2 ? int.parse(args[2]) : 30;
  final device = _DumpDevice(maxRuns);
  PdfInterpreter(cos: doc.cos, device: device).drawPage(doc.page(pageIndex));
  stdout.writeln('--- ${device.total} runs total');
}

class _DumpDevice implements PdfDevice {
  _DumpDevice(this.maxRuns);

  final int maxRuns;
  int total = 0;

  @override
  void drawText(PdfTextRun run) {
    total++;
    if (total > maxRuns) return;
    final t = run.transform;
    stdout.writeln(
        '"${run.text}" font=${run.fontName} size=${run.fontSize} '
        'width=${run.width.toStringAsFixed(3)}em '
        'origin=(${t.e.toStringAsFixed(1)}, ${t.f.toStringAsFixed(1)}) '
        'scale=(${t.a.toStringAsFixed(2)}, ${t.d.toStringAsFixed(2)}) color=${run.color}');
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
