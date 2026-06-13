// Ghent PDF Output Suite V5.0 — pure-Dart pass.
//
// One test per patch: the file must open, every page must interpret without
// throwing, and the page must actually paint something. No rasterization
// happens here (that suite is dart_pdf_editor/test/ghent_render_test.dart);
// this layer pins parsing, fonts, color spaces, shadings, and filters on
// the plain Dart VM, where failures are fast to bisect.
//
// The suite lives in test_corpora/ghent (checked in, copied from the Ghent
// Workgroup's freely downloadable V5.0 patches).
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('../../test_corpora/ghent');
  if (!root.existsSync()) {
    test('Ghent suite', skip: 'test_corpora/ghent not found', () {});
    return;
  }

  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final name = file.path.substring(root.path.length + 1);
    test(name, () {
      final doc = PdfDocument.open(file.readAsBytesSync());
      expect(doc.pageCount, greaterThan(0));
      for (var i = 0; i < doc.pageCount; i++) {
        final page = doc.page(i);
        final device = _CountingDevice();
        PdfInterpreter(cos: doc.cos, device: device)
          ..drawPage(page)
          ..drawAnnotations(page);
        expect(device.paintOps, greaterThan(0),
            reason: 'page $i painted nothing');
      }
    });
  }
}

/// Counts paint callbacks; recurses into soft-mask groups like a real
/// compositor so masked content is interpreted too.
class _CountingDevice implements PdfDevice {
  int paintOps = 0;

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    paintOps++;
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    paintOps++;
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    paintOps++;
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    paintOps++;
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawText(PdfTextRun run) {
    paintOps++;
  }

  @override
  void drawImage(PdfImageRequest request) {
    paintOps++;
  }

  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {
    drawMask();
  }
}
