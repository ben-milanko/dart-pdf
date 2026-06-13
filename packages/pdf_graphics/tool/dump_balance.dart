// Debug aid: track device save/restore depth and flag underflow.
//   dart tool/dump_balance.dart <file.pdf> [pageIndex]
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final device = _BalanceDevice();
  PdfInterpreter(cos: doc.cos, device: device)
      .drawPage(doc.page(args.length > 1 ? int.parse(args[1]) : 0));
  stdout.writeln('final depth=${device.depth} minDepth=${device.minDepth} '
      'saves=${device.saves} restores=${device.restores}');
}

class _BalanceDevice implements PdfDevice {
  int depth = 0;
  int minDepth = 0;
  int saves = 0;
  int restores = 0;
  int drawsAtOrBelowZero = 0;

  void _track() {
    if (depth < minDepth) {
      minDepth = depth;
      stdout.writeln('UNDERFLOW: depth=$depth after $restores restores');
    }
  }

  @override
  void save() {
    saves++;
    depth++;
  }

  @override
  void restore() {
    restores++;
    depth--;
    _track();
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
