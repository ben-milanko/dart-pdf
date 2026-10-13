// Automatic OCR: a scanned document opened in the editor gets a text layer in
// the same tab, unless the "Automatically OCR scans" setting is off. The OCR
// service is faked (no model); the scan detection, the session guard and the
// in-place apply are real.

import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/ocr.dart';
import 'package:dart_pdf_editor_app/ocr_auto.dart';

final _word = PdfOcrSpan(text: 'Invoice', bounds: PdfRect(72, 700, 160, 716));

/// Records each start() and answers with [_word] on page 0.
class _FakeOcr extends OnDeviceOcr {
  final calls = <({bool automatic, int length})>[];

  @override
  Future<void> start(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
    void Function(Uint8List result)? onComplete,
    void Function(Map<int, List<PdfOcrSpan>> spans)? onRecognized,
    bool automatic = false,
  }) async {
    calls.add((automatic: automatic, length: bytes.length));
    onRecognized?.call({
      0: [_word]
    });
  }
}

String _pageText(PdfDocument document) =>
    PdfTextExtractor.extract(document, 0).text;

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  group('AutoOcrSetting', () {
    test('is on until the user turns it off, and remembers that', () async {
      final setting = AutoOcrSetting();
      await setting.load();
      expect(setting.value, isTrue);

      await setting.save(false);
      final reloaded = AutoOcrSetting();
      await reloaded.load();
      expect(reloaded.value, isFalse);
    });

    test('a choice made while the stored one loads wins', () async {
      SharedPreferences.setMockInitialValues(
          {'dart_pdf_editor_app.ocr.auto': true});
      final setting = AutoOcrSetting();
      final loading = setting.load();
      await setting.save(false);
      await loading;
      expect(setting.value, isFalse);
    });
  });

  group('applyOcrToSession', () {
    test('lays the spans onto the live session as one undoable edit', () {
      final controller =
          PdfEditingController(buildScannedPdf(), preferences: prefs);
      addTearDown(controller.dispose);
      final snapshot = OcrSessionSnapshot.of(controller);

      expect(
          applyOcrToSession(controller, snapshot, {
            0: [_word]
          }),
          1);
      expect(_pageText(controller.document), contains('Invoice'));
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(_pageText(controller.document), isNot(contains('Invoice')));
    });

    test('an annotation added meanwhile does not block the layer', () {
      final controller =
          PdfEditingController(buildScannedPdf(), preferences: prefs);
      addTearDown(controller.dispose);
      final snapshot = OcrSessionSnapshot.of(controller);
      controller.addRectangle(0, PdfRect(100, 100, 200, 200));

      expect(
          applyOcrToSession(controller, snapshot, {
            0: [_word]
          }),
          1);
      expect(_pageText(controller.document), contains('Invoice'));
    });

    test('pages that moved meanwhile refuse it', () {
      final controller = PdfEditingController(buildScannedPdf(pageCount: 2),
          preferences: prefs);
      addTearDown(controller.dispose);
      final snapshot = OcrSessionSnapshot.of(controller);
      controller.movePage(0, 1);
      final before = controller.revisionCount;

      expect(
          applyOcrToSession(controller, snapshot, {
            0: [_word]
          }),
          isNull);
      expect(controller.revisionCount, before);
    });

    test('a removed page refuses it', () {
      final controller = PdfEditingController(buildScannedPdf(pageCount: 2),
          preferences: prefs);
      addTearDown(controller.dispose);
      final snapshot = OcrSessionSnapshot.of(controller);
      controller.removePage(1);

      expect(
          applyOcrToSession(controller, snapshot, {
            0: [_word]
          }),
          isNull);
    });
  });

  group('EditorScreen', () {
    Future<_FakeOcr> open(WidgetTester tester, Uint8List bytes,
        {bool enabled = true}) async {
      final ocr = _FakeOcr();
      final setting = AutoOcrSetting();
      await setting.save(enabled);
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialDocument: (bytes: bytes, title: 'Scan.pdf'),
          ocr: ocr,
          autoOcr: setting,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      return ocr;
    }

    PdfEditingController session(WidgetTester tester) =>
        tester.widget<PdfViewer>(find.byType(PdfViewer)).editing!;

    testWidgets('OCRs a scan when it opens and keeps it in the same tab',
        (tester) async {
      final ocr = await open(tester, buildScannedPdf());

      expect(ocr.calls, hasLength(1));
      expect(ocr.calls.single.automatic, isTrue);
      expect(_pageText(session(tester).document), contains('Invoice'));
      expect(session(tester).isModified, isTrue);
      expect(
          find.textContaining('this scan is now searchable'), findsOneWidget);
    });

    testWidgets('leaves a born-digital document alone', (tester) async {
      final ocr = await open(tester, buildMultiPagePdf(2));
      expect(ocr.calls, isEmpty);
      expect(session(tester).isModified, isFalse);
    });

    testWidgets('does nothing once the setting is off', (tester) async {
      final ocr = await open(tester, buildScannedPdf(), enabled: false);
      expect(ocr.calls, isEmpty);
      expect(session(tester).isModified, isFalse);
    });

    testWidgets('Settings has the switch, on by default', (tester) async {
      final setting = AutoOcrSetting();
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(prefs: prefs, autoOcr: setting),
      ));
      await tester.pump();
      await tester.tap(find.byTooltip('DartPDF menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('settings-auto-ocr'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(setting.value, isFalse);
    });
  });
}
