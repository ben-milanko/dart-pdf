// The on-device engine reads a page raster into an OcrImage, runs an
// OcrModelRunner, and maps each recognized line's PIXEL box back to PDF user
// space — proven here with a fake runner (no ONNX), so the engine + geometry
// are covered without a model. applyOcr then turns the spans into an
// invisible, selectable text layer.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Returns canned lines and records whether it was loaded — exactly the
/// contract a real ONNX runner fulfils, minus the inference.
class _FakeRunner implements OcrModelRunner {
  _FakeRunner(this.lines);
  final List<RecognizedTextLine> lines;
  int loadCount = 0;
  bool disposed = false;

  @override
  Future<void> load() async => loadCount++;

  @override
  Future<List<RecognizedTextLine>> recognize(OcrImage image) async {
    expect(image.width, greaterThan(0));
    expect(image.rgba.length, image.width * image.height * 4);
    return lines;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  testWidgets('maps a pixel line box to user space and loads once',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildClassicPdf()); // 612 x 792
      final image =
          await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 2);
      final runner = _FakeRunner([
        const RecognizedTextLine(
          text: 'Scanned',
          pixelBounds: Rect.fromLTWH(100, 120, 240, 36),
          confidence: 0.9,
        ),
      ]);
      final engine = OnDeviceOcrEngine(runner);
      try {
        final page = PdfOcrPageImage(
            image: image, page: doc.page(0), pageIndex: 0, pixelRatio: 2);
        final spans = await engine.recognize(page);
        // Second call must reuse the loaded runner.
        await engine.recognize(page);
        expect(runner.loadCount, 1);

        expect(spans, hasLength(1));
        final r = spans.single.bounds;
        // pixel x 100..340 / 2 = 50..170; pixel y 120..156 top-down ->
        // user-space top = 792 - 60, bottom = 792 - 78.
        expect(r.left, closeTo(50, 0.5));
        expect(r.right, closeTo(170, 0.5));
        expect(r.top, closeTo(792 - 60, 0.5));
        expect(r.bottom, closeTo(792 - 78, 0.5));
      } finally {
        image.dispose();
        await engine.dispose();
      }
      expect(runner.disposed, isTrue);
    });
  });

  testWidgets('drops lines below minConfidence and empty text',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildClassicPdf());
      final image = await PdfPageRenderer.renderImage(doc.page(0));
      final engine = OnDeviceOcrEngine(
        _FakeRunner(const [
          RecognizedTextLine(
              text: 'keep', pixelBounds: Rect.fromLTWH(10, 10, 40, 12), confidence: 0.8),
          RecognizedTextLine(
              text: 'drop', pixelBounds: Rect.fromLTWH(10, 30, 40, 12), confidence: 0.2),
          RecognizedTextLine(
              text: '   ', pixelBounds: Rect.fromLTWH(10, 50, 40, 12), confidence: 0.9),
        ]),
        minConfidence: 0.5,
      );
      try {
        final page = PdfOcrPageImage(
            image: image, page: doc.page(0), pageIndex: 0, pixelRatio: 1);
        final spans = await engine.recognize(page);
        expect(spans.map((s) => s.text), ['keep']);
      } finally {
        image.dispose();
        await engine.dispose();
      }
    });
  });

  testWidgets('applyOcr writes an invisible, selectable layer from the engine',
      (tester) async {
    await tester.runAsync(() async {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final engine = OnDeviceOcrEngine(_FakeRunner(const [
        RecognizedTextLine(
          text: 'Invoice',
          pixelBounds: Rect.fromLTWH(120, 80, 200, 40),
          confidence: 0.95,
        ),
      ]));
      final written = await editor.applyOcr(0, engine, pixelRatio: 2);
      expect(written, 1);

      final reopened = PdfDocument.open(editor.save());
      final pageText = PdfTextExtractor.extract(reopened, 0);
      expect(pageText.text, contains('Invoice'));
      await engine.dispose();
    });
  });
}
