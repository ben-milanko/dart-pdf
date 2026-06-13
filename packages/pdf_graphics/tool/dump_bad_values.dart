// Debug aid: find non-finite or huge values in text run transforms/offsets.
//   dart tool/dump_bad_values.dart <file.pdf> [pageIndex]
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final device = _Scanner();
  PdfInterpreter(cos: doc.cos, device: device)
      .drawPage(doc.page(args.length > 1 ? int.parse(args[1]) : 0));
  stdout.writeln('${device.flagged} bad runs of ${device.total}');
}

class _Scanner implements PdfDevice {
  int total = 0;
  int flagged = 0;

  @override
  void drawText(PdfTextRun run) {
    total++;
    final t = run.transform;
    final values = [t.a, t.b, t.c, t.d, t.e, t.f, run.width];
    final offsets = [for (final g in run.glyphs ?? const <PdfGlyphPlacement>[]) g.offset];
    bool bad(double v) => !v.isFinite || v.abs() > 1e6;
    if (values.any(bad) || offsets.any(bad)) {
      if (flagged++ < 8) {
        stdout.writeln('BAD "${run.text}" t=[${t.a},${t.b},${t.c},${t.d},'
            '${t.e},${t.f}] width=${run.width} offsets=$offsets');
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
