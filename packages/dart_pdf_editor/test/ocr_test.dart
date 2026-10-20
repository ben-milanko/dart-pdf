// End-to-end OCR: PdfEditor.applyOcr rasterizes a page, hands it to a
// PdfOcrEngine, and writes the recognized text as an invisible selectable
// layer. A fake engine here returns one canned word; the test proves the
// word is selectable/searchable afterwards and that the layer is invisible
// (the raster is byte-identical to one rendered without OCR).
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Returns one word at a fixed raster pixel box, mapped to user space by
/// the page geometry - exactly how a real engine would hand back results.
class _FakeOcrEngine implements PdfOcrEngine {
  _FakeOcrEngine(this.word, this.pixels);
  final String word;
  final Rect pixels;

  @override
  Future<List<PdfOcrSpan>> recognize(PdfOcrPageImage page) async => [
        PdfOcrSpan(
          text: word,
          bounds: page.userSpaceRect(pixels),
          confidence: 0.95,
        ),
      ];
}

class _RecordingRasterizer extends PdfOcrRasterizer {
  int calls = 0;
  int? pageIndex;
  double? pixelRatio;

  @override
  Future<PdfOcrPageImage> rasterize(PdfPage page,
      {required int pageIndex, required double pixelRatio}) async {
    calls++;
    this.pageIndex = pageIndex;
    this.pixelRatio = pixelRatio;
    final image =
        await PdfPageRenderer.renderImage(page, pixelRatio: pixelRatio);
    return PdfOcrPageImage(
      image: image,
      page: page,
      pageIndex: pageIndex,
      pixelRatio: pixelRatio,
    );
  }
}

Future<Uint8List> _rasterBytes(PdfDocument doc) async {
  final image = await PdfPageRenderer.renderImage(doc.page(0));
  try {
    final data = await image.toByteData();
    return data!.buffer.asUint8List().sublist(0);
  } finally {
    image.dispose();
  }
}

void main() {
  test('userSpaceRect maps a top-left raster box to the page top', () async {
    final doc = PdfDocument.open(buildClassicPdf()); // 612 x 792
    final image = await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 2);
    try {
      final page = PdfOcrPageImage(
          image: image, page: doc.page(0), pageIndex: 0, pixelRatio: 2);
      // A 200x60 px box in the top-left corner (raster y-down).
      final rect = page.userSpaceRect(const Rect.fromLTWH(0, 0, 200, 60));
      expect(rect.left, closeTo(0, 0.5));
      expect(rect.right, closeTo(100, 0.5)); // 200 px / 2
      expect(rect.top, closeTo(792, 0.5)); // page top
      expect(rect.bottom, closeTo(762, 0.5)); // 792 - 60/2
    } finally {
      image.dispose();
    }
  });

  testWidgets('applyOcr writes an invisible, selectable layer', (tester) async {
    await tester.runAsync(() async {
      final original = buildClassicPdf();
      final before = await _rasterBytes(PdfDocument.open(original));

      final editor = PdfEditor(PdfDocument.open(original));
      final rasterizer = _RecordingRasterizer();
      final written = await editor.applyOcr(
        0,
        // Clear of the page's own "Hello, world!", which applyOcr would
        // treat as already-extracted text.
        _FakeOcrEngine('Scanned', const Rect.fromLTWH(100, 1200, 240, 36)),
        pixelRatio: 2,
        rasterizer: rasterizer,
      );
      expect(written, 1);
      expect(rasterizer.calls, 1);
      expect(rasterizer.pageIndex, 0);
      expect(rasterizer.pixelRatio, 2);

      final reopened = PdfDocument.open(editor.save());

      // Selectable / searchable.
      final pageText = PdfTextExtractor.extract(reopened, 0);
      expect(pageText.text, contains('Scanned'));
      expect(pageText.findAll('Scanned'), hasLength(1));

      // Invisible: the OCR layer changes nothing on the raster.
      final after = await _rasterBytes(reopened);
      expect(after, equals(before));
    });
  });

  testWidgets('applyOcr does not duplicate text the page already has',
      (tester) async {
    await tester.runAsync(() async {
      // "Hello, world!" is real text at 24pt from (72, 720); at 2 px/pt its
      // first word sits at roughly this raster box.
      final helloPixels = const Rect.fromLTWH(144, 100, 140, 56);
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      expect(
        await editor.applyOcr(0, _FakeOcrEngine('Hello,', helloPixels)),
        0,
      );

      // A scanned word lands once; OCR run again over the result adds
      // nothing, because the first pass's invisible layer is existing text.
      final scanned =
          _FakeOcrEngine('Scanned', const Rect.fromLTWH(100, 1200, 240, 36));
      expect(await editor.applyOcr(0, scanned), 1);
      final again = PdfEditor(PdfDocument.open(editor.save()));
      expect(await again.applyOcr(0, scanned), 0);

      final pageText =
          PdfTextExtractor.extract(PdfDocument.open(again.save()), 0);
      expect(pageText.findAll('Hello'), hasLength(1));
      expect(pageText.findAll('Scanned'), hasLength(1));

      // Opting out writes the span regardless.
      expect(
        await again.applyOcr(0, scanned, skipExistingText: false),
        1,
      );
    });
  });
}
