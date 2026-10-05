// The OCR text-layer injection (PdfEditor.injectTextLayer): a recognized
// span becomes invisible (render mode 3) text the interpreter still emits,
// so the page is selectable/searchable/extractable but looks unchanged.
import 'dart:math' as math;

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
      final pageText =
          PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0);
      expect(pageText.text, contains('high'));
      expect(pageText.text, isNot(contains('low')));
    });
  });

  group('injectTextLayer on a /Rotate page', () {
    // A word that reads left to right on screen, as the OCR engine reports
    // it: axis-aligned user-space bounds that are tall on a quarter-turned
    // page (the on-screen width runs along user-space y) and wide otherwise.
    PdfOcrSpan spanFor(int rotation) => PdfOcrSpan(
          text: 'Recognized',
          bounds: rotation == 90 || rotation == 270
              ? const PdfRect(200, 300, 230, 500)
              : const PdfRect(200, 300, 400, 330),
        );

    // A user-space direction as the viewer shows it: /Rotate turns the page
    // clockwise, so a vector (x, y) lands at (x cos r + y sin r,
    // −x sin r + y cos r) with y up.
    (double, double) onScreen(double x, double y, int rotation) {
      final r = rotation * math.pi / 180;
      return (
        x * math.cos(r) + y * math.sin(r),
        -x * math.sin(r) + y * math.cos(r),
      );
    }

    (double, double) unit(double x, double y) {
      final length = math.sqrt(x * x + y * y);
      return (x / length, y / length);
    }

    for (final rotation in const [90, 180, 270]) {
      test('$rotation: one run over the span, reading with the page', () {
        final span = spanFor(rotation);
        final editor = PdfEditor(
            PdfDocument.open(buildMultiPagePdf(1, rotation: rotation)));
        expect(editor.injectTextLayer(0, [span]), 1);
        final text =
            PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0);

        // One run, not stacked fragments, with bounds on the span.
        final runs = text.runs.where((r) => r.text.contains('Recogn')).toList();
        expect(runs, hasLength(1));
        final run = runs.single;
        expect(run.text.trim(), 'Recognized');
        expect(run.bounds.left, closeTo(span.bounds.left, 0.5));
        expect(run.bounds.bottom, closeTo(span.bounds.bottom, 0.5));
        expect(run.bounds.right, closeTo(span.bounds.right, 0.5));
        expect(run.bounds.top, closeTo(span.bounds.top, 0.5));

        // The baseline reads left to right on screen and the glyphs stand
        // upright.
        final m = run.transform;
        final (bx, by) = unit(m.a, m.b);
        final (sx, sy) = onScreen(bx, by, rotation);
        expect(sx, closeTo(1, 1e-6));
        expect(sy, closeTo(0, 1e-6));
        final (ux, uy) = unit(m.c, m.d);
        final (vx, vy) = onScreen(ux, uy, rotation);
        expect(vx, closeTo(0, 1e-6));
        expect(vy, closeTo(1, 1e-6));

        // Searchable, highlighted over the span.
        final rect = text.findAll('Recognized').single.rects.single;
        expect(rect.left, closeTo(span.bounds.left, 0.5));
        expect(rect.bottom, closeTo(span.bounds.bottom, 0.5));
        expect(rect.right, closeTo(span.bounds.right, 0.5));
        expect(rect.top, closeTo(span.bounds.top, 0.5));
      });

      test('$rotation: a re-run is deduped against the injected layer', () {
        final span = spanFor(rotation);
        final editor = PdfEditor(
            PdfDocument.open(buildMultiPagePdf(1, rotation: rotation)))
          ..injectTextLayer(0, [span]);
        final text =
            PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0);
        const elsewhere =
            PdfOcrSpan(text: 'Other', bounds: PdfRect(450, 50, 500, 80));
        expect(
          ocrSpansNotIn(text, [span, elsewhere]).map((s) => s.text),
          ['Other'],
        );
      });
    }
  });

  group('ocrSpansNotIn', () {
    // buildClassicPdf draws "Hello, world!" at 24pt from (72, 720).
    const overHello = PdfOcrSpan(
      text: 'Hello,',
      bounds: PdfRect(72, 714, 140, 740),
    );
    const elsewhere = PdfOcrSpan(
      text: 'Scanned',
      bounds: PdfRect(100, 100, 300, 130),
    );

    test('drops spans that repeat the page text, keeps the rest', () {
      final text =
          PdfTextExtractor.extract(PdfDocument.open(buildClassicPdf()), 0);
      final kept = ocrSpansNotIn(text, const [overHello, elsewhere]);
      expect(kept.map((s) => s.text), ['Scanned']);
    });

    test('an earlier invisible OCR layer counts as existing text', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..injectTextLayer(0, const [elsewhere]);
      final text = PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0);
      const partial = PdfOcrSpan(
        text: 'Partly',
        bounds: PdfRect(250, 100, 450, 130), // a quarter over 'Scanned'
      );
      final kept = ocrSpansNotIn(text, const [elsewhere, partial]);
      expect(kept.map((s) => s.text), ['Partly']);
    });

    test('text drawn twice is not counted twice', () {
      const run = PdfOcrSpan(text: 'Twice', bounds: PdfRect(0, 0, 100, 20));
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..injectTextLayer(0, const [run])
        ..injectTextLayer(0, const [run]);
      final text = PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0);
      // 40% under the doubled run: a summed coverage (80%) would drop it.
      const span = PdfOcrSpan(text: 'Next', bounds: PdfRect(60, 0, 160, 20));
      expect(ocrSpansNotIn(text, const [span]), hasLength(1));
    });

    test('sums coverage across separate lines under one span', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..injectTextLayer(0, const [
          PdfOcrSpan(text: 'Upper', bounds: PdfRect(0, 40, 100, 60)),
          PdfOcrSpan(text: 'Lower', bounds: PdfRect(0, 0, 100, 20)),
        ]);
      final text = PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0);
      // A line-level box over both: two thirds covered, so a duplicate;
      // counting only one of the lines (a third) would keep it.
      const span =
          PdfOcrSpan(text: 'Upper Lower', bounds: PdfRect(0, 0, 100, 60));
      expect(ocrSpansNotIn(text, const [span]), isEmpty);
    });

    test('a page without text keeps everything', () {
      const text = PdfPageText(pageIndex: 0, text: '', runs: []);
      expect(ocrSpansNotIn(text, const [overHello, elsewhere]), hasLength(2));
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
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {}
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
