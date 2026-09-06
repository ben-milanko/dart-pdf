import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'editing_reflow_test.dart' show buildParagraphPdf;

void main() {
  testWidgets('region deletion removes only the selected glyph pixels',
      (tester) async {
    await tester.runAsync(() async {
      // Spacing, scale, TJ kerning and a separate following run exercise the
      // actual interpreter/rasterizer, independently of PdfPageElements.
      final doc = PdfDocument.open(
          buildParagraphPdf('BT /F1 20 Tf 2 Tc 3 Tw 80 Tz 72 700 Td '
              '[(AA) -500 ( B) 100 (CC)] TJ (DD) Tj ET'));
      final before =
          await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 2);
      final editor = PdfEditor(doc);
      // A + Tc = 15.34pt, two at 80% = 24.544; kern = 8pt;
      // space + Tc + Tw = 10.56pt at 80% = 8.448. B starts at 112.992.
      const erase = PdfRect(112.99, 690, 125.27, 725);
      expect(editor.deleteElementsInRect(PdfPageElements.of(doc, 0), erase), 1);
      final out = PdfDocument.open(editor.save());
      final after =
          await PdfPageRenderer.renderImage(out.page(0), pixelRatio: 2);
      try {
        final a = (await before.toByteData())!;
        final b = (await after.toByteData())!;
        var changedInside = 0;
        var changedOutside = 0;
        for (var y = 0; y < before.height; y++) {
          for (var x = 0; x < before.width; x++) {
            final i = (y * before.width + x) * 4;
            if (a.getUint32(i) == b.getUint32(i)) continue;
            final px = x / 2, py = 792 - y / 2;
            if (px >= erase.left - 1 &&
                px <= erase.right + 1 &&
                py >= erase.bottom &&
                py <= erase.top) {
              changedInside++;
            } else {
              changedOutside++;
            }
          }
        }
        expect(changedInside, greaterThan(50));
        expect(changedOutside, 0, reason: 'surviving text must not move');
      } finally {
        before.dispose();
        after.dispose();
      }
    });
  });
}
