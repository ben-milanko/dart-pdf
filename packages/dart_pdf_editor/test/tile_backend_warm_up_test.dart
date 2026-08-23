import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

class _WarmUpBackend extends PdfCanvasTileRasterBackend {
  int warmUps = 0;

  @override
  Future<void> warmUp() async {
    warmUps++;
  }
}

void main() {
  testWidgets('viewer warms a new tile backend only after it is active',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final first = _WarmUpBackend();
    final second = _WarmUpBackend();

    Future<void> pump(_WarmUpBackend backend, {required bool active}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            document: document,
            active: active,
            pagePreviews: false,
            autoRenderWorker: false,
            tileRasterBackend: backend,
          ),
        ),
      ));
      await tester.pump();
    }

    await pump(first, active: false);
    expect(first.warmUps, 0, reason: 'a parked viewer must do no GPU work');

    await pump(first, active: true);
    expect(first.warmUps, 1);

    await pump(first, active: true);
    expect(first.warmUps, 1, reason: 'ordinary rebuilds keep the same warm-up');

    await pump(second, active: true);
    expect(first.warmUps, 1);
    expect(second.warmUps, 1, reason: 'a replacement backend gets prepared');
  });
}
