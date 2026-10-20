// Regression test for issue #462: a non-Normal blend mode set inside a form
// XObject must not leak out and multiply content painted after the form.
//
// The interpreter brackets a `Do` with save()/restore() and restores its own
// graphics state on the way out, but a device's blend mode is not part of the
// canvas save stack (CanvasPdfDevice tracks it in a plain field). Before the
// fix, a `/BM /Multiply` set at a form's top level survived the form exit, so a
// Normal-blend fill painted afterwards rendered multiplied against the backdrop
// instead of opaque. The interpreter now re-issues the restored blend on form /
// appearance / group / pattern exits (mirroring the `q`/`Q` handler).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// One page (200x160):
/// 1. a red backdrop over the whole page,
/// 2. `/G1 Do` - a form that sets `/BM /Multiply` at its TOP LEVEL (no inner
///    `q`/`Q`, so only the form exit can restore the blend) and fills a green
///    rect in the corner, then
/// 3. an opaque WHITE rect (Normal blend, no ExtGState) over the red backdrop.
///
/// White painted with Multiply over red = red (white is Multiply's identity),
/// so if the form's Multiply leaks, the "white" rect renders red. With the
/// blend correctly restored on the form exit it renders white.
Uint8List buildBlendLeakPdf() {
  // No q/Q around the /A gs: the leak is precisely that the FORM exit (not a Q)
  // must restore the device blend.
  const form = '/A gs 0 1 0 rg 10 10 40 40 re f';
  const content = '1 0 0 rg 0 0 200 160 re f '
      '/G1 Do '
      '1 1 1 rg 60 50 80 60 re f';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 160] /Contents 4 0 R '
        '/Resources << /XObject << /G1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /XObject /Subtype /Form /FormType 1 /BBox [0 0 200 160] '
        '/Resources << /ExtGState << /A 6 0 R >> >> '
        '/Length ${form.length} >>\nstream\n$form\nendstream',
    '<< /Type /ExtGState /BM /Multiply >>',
  ];
  final buffer = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

void main() {
  testWidgets(
      'a Multiply blend set inside a form does not leak onto later content',
      (tester) async {
    // renderImage does real GPU-async work, which needs the real event loop
    // (testWidgets runs in FakeAsync otherwise).
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildBlendLeakPdf());
      final image =
          await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 1);
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = data.buffer.asUint8List();
      List<int> at(int x, int y) {
        final i = (y * image.width + x) * 4;
        return [px[i], px[i + 1], px[i + 2]];
      }

      // The white rect is PDF x[60,140] y[50,110]; centre PDF (100,80) maps to
      // image (100, 160-80) = (100, 80), clear of the form's green corner rect.
      final white = at(100, 80);
      expect(white[1], greaterThan(200),
          reason: 'green channel should be ~255 (opaque white), not ~0 '
              '(white multiplied by the red backdrop = red) - blend leaked');
      expect(white[2], greaterThan(200),
          reason: 'blue channel should be ~255 (opaque white), not ~0');

      // Sanity: the red backdrop away from both rects is still red.
      final backdrop = at(180, 140);
      expect(backdrop[0], greaterThan(200));
      expect(backdrop[1], lessThan(60));
    });
  });
}
