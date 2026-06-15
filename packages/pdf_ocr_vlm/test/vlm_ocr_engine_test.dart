// VlmOcrEngine talks to an OCR HTTP service and maps the boxes it returns
// back into PDF user space. These tests stand in a MockClient for the
// service, so they exercise the request shape, the response parsing (both
// the simple contract and the dots.ocr OpenAI shape), and the pixel→user
// geometry — with no network and no GPU.
import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_ocr_vlm/pdf_ocr_vlm.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  // buildClassicPdf is 612 x 792 pt; render at 2 px/pt → 1224 x 1584 px.
  Future<PdfOcrPageImage> renderPage() async {
    final doc = PdfDocument.open(buildClassicPdf());
    final image = await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 2);
    return PdfOcrPageImage(
      image: image,
      page: doc.page(0),
      pageIndex: 0,
      pixelRatio: 2,
    );
  }

  testWidgets('simple contract: request shape and pixel→user mapping',
      (tester) async {
    await tester.runAsync(() async {
      final page = await renderPage();
      Map<String, dynamic>? sentBody;

      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'spans': [
              {'text': 'Hello', 'bbox': [0, 0, 200, 60], 'confidence': 0.9},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final engine = VlmOcrEngine(
        endpoint: Uri.parse('http://localhost:9/ocr'),
        client: client,
      );
      final spans = await engine.recognize(page);

      // The default request body carries the raster and its dimensions.
      expect(sentBody!['width'], page.width);
      expect(sentBody!['height'], page.height);
      expect(sentBody!['image_format'], 'png');
      expect((sentBody!['image'] as String).isNotEmpty, isTrue);

      // The top-left 200x60 px box maps to the top of the page (y up).
      expect(spans, hasLength(1));
      expect(spans.single.text, 'Hello');
      expect(spans.single.confidence, closeTo(0.9, 1e-9));
      expect(spans.single.bounds.left, closeTo(0, 0.5));
      expect(spans.single.bounds.right, closeTo(100, 0.5)); // 200 px / 2
      expect(spans.single.bounds.top, closeTo(792, 0.5)); // page top
      expect(spans.single.bounds.bottom, closeTo(762, 0.5)); // 792 - 60/2

      page.image.dispose();
    });
  });

  testWidgets('dotsOcr: OpenAI chat shape, JSON-in-content, category filter',
      (tester) async {
    await tester.runAsync(() async {
      final page = await renderPage();
      Map<String, dynamic>? sentBody;

      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        // dots.ocr replies with a JSON array of layout cells inside the
        // assistant message content (here wrapped in a ```json fence).
        final content = '```json\n${jsonEncode([
              {'bbox': [0, 0, 200, 60], 'category': 'Title', 'text': 'Report'},
              {'bbox': [0, 100, 200, 160], 'category': 'Picture', 'text': ''},
              {'bbox': [0, 200, 400, 260], 'category': 'Text', 'text': 'Body'},
            ])}\n```';
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'role': 'assistant', 'content': content}},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final engine = VlmOcrEngine.dotsOcr(
        endpoint: Uri.parse('http://localhost:9/v1/chat/completions'),
        client: client,
      );
      final spans = await engine.recognize(page);

      // OpenAI chat request: an image_url part is present.
      final messages = sentBody!['messages'] as List;
      final parts = (messages.first as Map)['content'] as List;
      expect(parts.any((p) => (p as Map)['type'] == 'image_url'), isTrue);

      // The Picture cell is dropped; the two text cells survive.
      expect(spans.map((s) => s.text), containsAll(['Report', 'Body']));
      expect(spans.where((s) => s.text == ''), isEmpty);
      expect(spans, hasLength(2));

      page.image.dispose();
    });
  });

  testWidgets('applyOcr writes a selectable layer via the engine',
      (tester) async {
    await tester.runAsync(() async {
      final original = buildClassicPdf();
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'spans': [
              {'text': 'Scanned', 'bbox': [100, 120, 340, 156]},
            ],
          }),
          200,
        );
      });

      final editor = PdfEditor(PdfDocument.open(original));
      final written = await editor.applyOcr(
        0,
        VlmOcrEngine(endpoint: Uri.parse('http://localhost:9/ocr'),
            client: client),
        pixelRatio: 2,
      );
      expect(written, 1);

      final reopened = PdfDocument.open(editor.save());
      final pageText = PdfTextExtractor.extract(reopened, 0);
      expect(pageText.text, contains('Scanned'));
    });
  });

  testWidgets('a non-200 response throws VlmOcrException', (tester) async {
    await tester.runAsync(() async {
      final page = await renderPage();
      final client = MockClient((request) async =>
          http.Response('upstream model not loaded', 503));
      final engine = VlmOcrEngine(
        endpoint: Uri.parse('http://localhost:9/ocr'),
        client: client,
      );
      await expectLater(
        engine.recognize(page),
        throwsA(isA<VlmOcrException>()),
      );
      page.image.dispose();
    });
  });

  test('default parser reads polygon points and varied keys', () {
    // No page geometry needed: parse straight to pixel boxes.
    final words = defaultVlmResponseParser({
      'results': [
        {
          'transcription': 'poly',
          'points': [[10, 20], [110, 22], [108, 60], [12, 58]],
          'score': 0.8,
        },
      ],
    }, _NullPage());
    expect(words, hasLength(1));
    expect(words.single.text, 'poly');
    expect(words.single.confidence, closeTo(0.8, 1e-9));
    expect(words.single.pixelBounds, const Rect.fromLTRB(10, 20, 110, 60));
  });
}

/// A stand-in [PdfOcrPageImage] for the pure parser test, which never reads
/// the page (it returns pixel boxes, mapped to user space elsewhere).
class _NullPage implements PdfOcrPageImage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
