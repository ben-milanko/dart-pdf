// Debug aid: log soft-mask group activity for one page.
//   dart tool/dump_masks.dart <file.pdf> [pageIndex]
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final device = _MaskDevice();
  PdfInterpreter(cos: doc.cos, device: device)
      .drawPage(doc.page(args.length > 1 ? int.parse(args[1]) : 0));
  stdout.writeln('begin=${device.begins} end=${device.ends} '
      'luminosity=${device.luminosityCount} '
      'textInsideMaskGroups=${device.maskedText}');
}

class _MaskDevice implements PdfDevice {
  int begins = 0;
  int ends = 0;
  int luminosityCount = 0;
  int maskedText = 0;
  int _maskDepth = 0;

  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {
    begins++;
    _maskDepth++;
  }

  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask, double backdropLuminance = 0, double transferScale = 1, double transferOffset = 0}) {
    ends++;
    if (luminosity) luminosityCount++;
    _maskDepth--;
    drawMask();
  }

  @override
  void drawText(PdfTextRun run) {
    if (_maskDepth > 0) maskedText++;
  }

  @override
  void setBlendMode(PdfBlendMode mode) {}
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
}
