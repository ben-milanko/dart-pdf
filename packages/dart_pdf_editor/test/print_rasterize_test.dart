// rasterizePdfForPrinting flattens a document into a fresh, image-only PDF -
// the copy the app prints on Windows, where the OS backend's bundled PDFium
// crashes on the broken-but-renderable files this engine opens. The raster
// copy has to open cleanly, keep the page count and (near enough) the page
// sizes, and carry an image per page instead of the original text/fonts.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  /// The XObject subtypes referenced by [page]'s /Resources.
  Set<String> imageXObjects(PdfDocument doc, PdfPage page) {
    final cos = doc.cos;
    final resources = cos.resolve(page.resources['XObject']);
    if (resources is! CosDictionary) return const {};
    final kinds = <String>{};
    for (final value in resources.entries.values) {
      final xobject = cos.resolve(value);
      if (xobject is CosStream) {
        final subtype = cos.resolve(xobject.dictionary['Subtype']);
        if (subtype is CosName) kinds.add(subtype.value);
      }
    }
    return kinds;
  }

  testWidgets('produces a valid image-only PDF, one image per page',
      (tester) async {
    await tester.runAsync(() async {
      final source = PdfDocument.open(buildMultiPagePdf(3));

      final raster = await rasterizePdfForPrinting(source, dpi: 72);

      final out = PdfDocument.open(raster);
      expect(out.pageCount, 3);
      for (var i = 0; i < out.pageCount; i++) {
        final page = out.page(i);
        // Each page draws exactly one image and no longer carries the
        // original text/font - it is a flat raster.
        expect(imageXObjects(out, page), {'Image'});
        final content = String.fromCharCodes(page.contentBytes());
        expect(content, contains('Do')); // the XObject paint
        expect(content, isNot(contains('Tj'))); // no text left
      }
    });
  });

  testWidgets('keeps each page at its original size', (tester) async {
    await tester.runAsync(() async {
      // Heights cycle 792, 396, 1008 (all 612 wide).
      final source = PdfDocument.open(buildVariedHeightPdf(3));

      final raster = await rasterizePdfForPrinting(source, dpi: 72);

      final out = PdfDocument.open(raster);
      const expectedHeights = [792.0, 396.0, 1008.0];
      for (var i = 0; i < out.pageCount; i++) {
        final box = out.page(i).mediaBox;
        // Rasterising rounds to whole pixels, so allow a point of slack.
        expect(box.width, closeTo(612, 1.5));
        expect(box.height, closeTo(expectedHeights[i], 1.5));
      }
    });
  });

  testWidgets('rasterises broken input its own engine still renders',
      (tester) async {
    await tester.runAsync(() async {
      // A missing /Length and no /endobj - lenient on input, so this opens
      // and renders even though a strict reader would reject it. The whole
      // point of the raster print path is to survive such files.
      final broken = Uint8List.fromList(
        '%PDF-1.4\n'
                '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n'
                '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n'
                '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
                '/Contents 4 0 R >>endobj\n'
                '4 0 obj<< >>stream\n0 0 1 rg 50 50 100 100 re f\nendstream '
                'endobj\n'
            .codeUnits,
      );

      final raster = await rasterizePdfForPrinting(
        PdfDocument.open(broken),
        dpi: 72,
      );

      final out = PdfDocument.open(raster);
      expect(out.pageCount, 1);
      expect(imageXObjects(out, out.page(0)), {'Image'});
    });
  });
}
