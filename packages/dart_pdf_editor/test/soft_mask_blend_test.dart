import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_graphics/pdf_graphics.dart';

const _fullRect = PdfPath([
  PdfMoveTo(0, 0),
  PdfLineTo(100, 0),
  PdfLineTo(100, 100),
  PdfLineTo(0, 100),
  PdfClosePath(),
]);

const _rightHalf = PdfPath([
  PdfMoveTo(50, 0),
  PdfLineTo(100, 0),
  PdfLineTo(100, 100),
  PdfLineTo(50, 100),
  PdfClosePath(),
]);

void main() {
  testWidgets('a soft-masked source blends with the page after masking',
      (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawRect(
          const ui.Rect.fromLTWH(0, 0, 100, 100),
          ui.Paint()..color = const ui.Color.fromARGB(255, 200, 200, 200),
        );
      final device = CanvasPdfDevice(canvas);
      device
        ..setBlendMode(PdfBlendMode.multiply)
        ..beginSoftMasked()
        ..fillPath(
          _fullRect,
          const PdfColor(0.8, 0.4, 0.2),
          PdfFillRule.nonzero,
          1,
        )
        // State left by the captured source must not become the mask form's
        // initial blend mode.
        ..setBlendMode(PdfBlendMode.multiply)
        ..endSoftMasked(
          luminosity: true,
          backdrop: const PdfRect(0, 0, 100, 100),
          drawMask: () {
            device.fillPath(
              _rightHalf,
              const PdfColor.gray(1),
              PdfFillRule.nonzero,
              1,
            );
          },
        );

      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
              .buffer
              .asUint8List();

      List<int> at(int x, int y) {
        final i = (y * image.width + x) * 4;
        return bytes.sublist(i, i + 4);
      }

      // The black, unpainted mask backdrop leaves the left half untouched.
      expect(at(25, 50), [200, 200, 200, 255]);
      // The right half is the source multiplied by the existing page, not the
      // unblended source colour (204, 102, 51). This is the ordering used by
      // the GWG inner-shadow, bevel, satin, and feather samples.
      expect(at(75, 50), [160, 80, 40, 255]);

      image.dispose();
      picture.dispose();
    });
  });
}
