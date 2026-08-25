import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

class _WarmUpBackend extends PdfCanvasTileRasterBackend {
  int warmUps = 0;
  int sceneWarmUps = 0;

  @override
  bool get supportsWarmUp => true;

  @override
  bool get supportsSessionWarmUp => true;

  @override
  Future<void> warmUp() async {
    warmUps++;
  }

  @override
  PdfTileRasterSession createSession(PdfRetainedScene scene) =>
      _WarmUpSession(this, super.createSession(scene));
}

class _WarmUpSession implements PdfTileRasterSession, PdfTileRasterWarmUp {
  _WarmUpSession(this.backend, this.delegate);

  final _WarmUpBackend backend;
  final PdfTileRasterSession delegate;

  @override
  PdfRetainedScene get scene => delegate.scene;

  @override
  Future<void> warmUp() async {
    backend.sceneWarmUps++;
  }

  @override
  Future<ui.Image> rasterizeRegion(
    ui.Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) =>
      delegate.rasterizeRegion(
        region,
        pixelRatio: pixelRatio,
        tracePage: tracePage,
      );

  @override
  void dispose() => delegate.dispose();
}

void main() {
  testWidgets('viewer warms a new tile backend only after it is active',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final first = _WarmUpBackend();
    final second = _WarmUpBackend();

    Future<void> pump(
      _WarmUpBackend backend, {
      required bool active,
      bool waitForWarmUp = true,
    }) async {
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
      if (!waitForWarmUp) return;
      await tester.pump(PdfViewer.tileBackendWarmIdleDelay);
      await tester.pump(PdfPageView.tileSessionWarmIdleDelay);
    }

    await pump(first, active: false);
    expect(first.warmUps, 0, reason: 'a parked viewer must do no GPU work');

    await pump(first, active: true, waitForWarmUp: false);
    expect(first.warmUps, 0,
        reason: 'useful pixels alone are not an idle edge');
    expect(first.sceneWarmUps, 0);

    await pump(first, active: false);
    expect(first.warmUps, 0,
        reason: 'parking during the quiet window cancels preparation');
    expect(first.sceneWarmUps, 0);

    await pump(first, active: true);
    expect(first.warmUps, 1);
    expect(first.sceneWarmUps, 1,
        reason: 'the useful page raster lands before its session is prepared');

    await pump(first, active: true);
    expect(first.warmUps, 1, reason: 'ordinary rebuilds keep the same warm-up');
    expect(first.sceneWarmUps, 1);

    await pump(second, active: true);
    expect(first.warmUps, 1);
    expect(second.warmUps, 1, reason: 'a replacement backend gets prepared');
    expect(second.sceneWarmUps, 1);
  });
}
