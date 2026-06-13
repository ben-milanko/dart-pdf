// The OCR text-layer injection (PdfEditor.injectTextLayer): a recognized
// span becomes invisible (render mode 3) text the interpreter still emits,
// so the page is selectable/searchable/extractable but looks unchanged.
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('injectTextLayer', () {
    test('makes a span selectable, searchable, and positioned', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc);
      final written = editor.injectTextLayer(0, [
        const PdfOcrSpan(
          text: 'Recognized',
          bounds: PdfRect(100, 100, 300, 130),
        ),
      ]);
      expect(written, 1);

      final reopened = PdfDocument.open(editor.save());
      final pageText = PdfTextExtractor.extract(reopened, 0);

      // Extractable.
      expect(pageText.text, contains('Recognized'));
      // The original visible text survived alongside the new layer.
      expect(pageText.text, contains('Hello, world!'));

      // Searchable, with the highlight box sitting on the OCR bounds.
      final matches = pageText.findAll('Recognized');
      expect(matches, hasLength(1));
      final rect = matches.single.rects.single;
      expect(rect.left, closeTo(100, 0.5));
      expect(rect.bottom, closeTo(100, 0.5));
      expect(rect.right, closeTo(300, 0.5));
      expect(rect.top, closeTo(130, 0.5));
    });

    test('the injected run is invisible (render mode 3)', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc)
        ..injectTextLayer(0, [
          const PdfOcrSpan(text: 'Hidden', bounds: PdfRect(50, 50, 250, 80)),
        ]);
      final reopened = PdfDocument.open(editor.save());

      final recorder = _TextRecorder();
      PdfInterpreter(cos: reopened.cos, device: recorder)
          .drawPage(reopened.page(0));

      final ocr = recorder.runs.firstWhere((r) => r.text.contains('Hidden'));
      expect(ocr.invisible, isTrue);
      // A painting device skips invisible runs (canvas_device early-return),
      // so nothing of the OCR layer reaches the page.
      final painted =
          recorder.runs.where((r) => !r.invisible).map((r) => r.text);
      expect(painted, isNot(contains('Hidden')));
      // The original content still paints.
      expect(painted.any((t) => t.contains('Hello')), isTrue);
    });

    test('skips empty and low-confidence spans', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc);
      final written = editor.injectTextLayer(
        0,
        const [
          PdfOcrSpan(text: '   ', bounds: PdfRect(0, 0, 10, 10)),
          PdfOcrSpan(
              text: 'low', bounds: PdfRect(0, 0, 50, 20), confidence: 0.2),
          PdfOcrSpan(
              text: 'high', bounds: PdfRect(0, 0, 50, 20), confidence: 0.9),
        ],
        minConfidence: 0.5,
      );
      expect(written, 1);
      final pageText = PdfTextExtractor.extract(
          PdfDocument.open(editor.save()), 0);
      expect(pageText.text, contains('high'));
      expect(pageText.text, isNot(contains('low')));
    });
  });
}

class _TextRecorder implements PdfDevice {
  final runs = <PdfTextRun>[];

  @override
  void drawText(PdfTextRun run) => runs.add(run);

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
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {}
}
