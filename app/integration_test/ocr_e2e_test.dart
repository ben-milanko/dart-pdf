// REAL end-to-end on-device OCR, exercising the native ONNX Runtime against
// the published `ocr-models-v1` bundle — the one path the unit tests can't
// reach (they use a fake runner, and onnxruntime can't load in `flutter
// test`). Run on a desktop/device:
//
//   cd app && fvm flutter test integration_test/ocr_e2e_test.dart -d macos
//
// It downloads the model once (cached afterwards), paints a known phrase to a
// raster, wraps it in an image-only ("scanned") PDF, runs the whole
// detect->recognize pipeline, and asserts the page text became extractable.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paints [text] as black-on-white at a generous size and returns PNG bytes —
/// a stand-in for a scanned page (no embedded text, just pixels).
Future<Uint8List> _scanPng(String text) async {
  const w = 1100, h = 220;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1100, 220),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0xFF000000),
        fontSize: 72,
        fontFamily: 'Helvetica',
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, const Offset(40, 60));
  final img = await recorder.endRecording().toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bd!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads the model and OCRs an image-only PDF on device',
      (tester) async {
    expect(PdfOcrModelManager.isSupported, isTrue,
        reason: 'on-device OCR should be supported on this desktop platform');

    final manager = PdfOcrModelManager();
    final model = PdfOcrModels.ppOcrV5Mobile;

    // 1. Download (or reuse the cache). Real network on first run.
    if (!await manager.isDownloaded(model)) {
      await manager.download(model, onProgress: (p) {
        // ignore: avoid_print
        print('  ${p.fileName}: ${((p.fraction ?? 0) * 100).round()}%');
      });
    }
    expect(await manager.isDownloaded(model), isTrue);

    // 2. Build a scanned-style, image-only PDF with known text.
    const phrase = 'Invoice Number 12345';
    final png = await _scanPng(phrase);
    final scannedPdf = PdfImageDocument.fromImageBytes([png]);

    // Sanity: the scan has no extractable text before OCR.
    final before = PdfTextExtractor.extract(PdfDocument.open(scannedPdf), 0);
    expect(before.text.trim(), isEmpty,
        reason: 'an image-only PDF must have no text layer yet');

    // 3. Run the REAL ONNX pipeline.
    final engine = await OnDeviceOcrEngine.fromDownloadedModel(manager, model);
    final editor = PdfEditor(PdfDocument.open(scannedPdf));
    final spans = await editor.applyOcr(0, engine, pixelRatio: 2);
    await engine.dispose();
    manager.close();

    // 4. The text layer is now present and extractable.
    expect(spans, greaterThan(0), reason: 'OCR should find at least one span');
    final after = PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0);
    final got = after.text;
    // ignore: avoid_print
    print('OCR extracted: "${got.trim()}" ($spans spans)');
    expect(got, contains('Invoice'));
    expect(got, contains('12345'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('OCR runs in the background (app-bar chip, PDF still shown)',
      (tester) async {
    // Pre-cache the model so the menu action starts OCR with no confirm
    // dialog (the download is a separate, one-time step).
    final manager = PdfOcrModelManager();
    final model = PdfOcrModels.ppOcrV5Mobile;
    if (!await manager.isDownloaded(model)) await manager.download(model);
    manager.close();

    // A multi-page scan so recognition lasts long enough to observe.
    final png = await _scanPng('Invoice Number 12345');
    final scanned = PdfImageDocument.fromImageBytes(List.filled(6, png));

    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: scanned, title: 'Scan.pdf'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    // Start OCR from the More menu.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-ocr')));
    await tester.pump(); // dispatch the action

    // Wait for the background job to spin up (engine load + first page).
    const chip = ValueKey('ocr-status-chip');
    var sawChip = false;
    for (var i = 0; i < 100 && !sawChip; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      sawChip = find.byKey(chip).evaluate().isNotEmpty;
    }

    // It is NON-blocking: the progress chip is in the app bar, there is no
    // OCR dialog covering the page, and the document stays on screen.
    expect(sawChip, isTrue,
        reason: 'background OCR should show an app-bar progress chip');
    expect(find.byKey(const ValueKey('ocr-progress')), findsNothing,
        reason: 'no blocking OCR progress dialog');
    expect(find.byKey(const ValueKey('ocr-download-confirm')), findsNothing,
        reason: 'model was cached, so no dialog is up while OCR runs');
    expect(find.byType(PdfEditorView), findsOneWidget,
        reason: 'the PDF stays visible/interactive while OCR runs');
    expect(find.byKey(const ValueKey('ocr-status-cancel')), findsOneWidget);

    // Let it finish: the result opens in a new "(OCR)" tab and the chip clears.
    var sawTab = false;
    for (var i = 0; i < 600 && !sawTab; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      sawTab = find.text('Scan.pdf (OCR)').evaluate().isNotEmpty;
    }
    expect(sawTab, isTrue, reason: 'OCR result should open in a new tab');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(chip), findsNothing,
        reason: 'the chip clears once the job completes');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
