// A phone/tablet pick of a *seekable* cloud file goes through the reference
// picker + native ranged reads (#364): the runner hands back a token instead of
// a whole-file copy, the loader first-paints from ranges, then the complete
// bytes stream in behind it and the tab swaps to a full edit session (and
// snapshots for reopen). Driven on Android with the native `mobile_file`
// channel mocked to serve a real PDF by range; the native handlers themselves
// need on-device verification.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/devtools.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/pdf_mobile_source.dart';

void main() {
  late PdfEditingPreferences prefs;
  late Uint8List pdfBytes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    pdfBytes = Uint8List.fromList(buildClassicPdf());
    AppDevTools.instance.clearLog();
  });

  tearDown(() {
    prefs.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileFileChannel, null);
  });

  Future<void> pump(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  // Mocks the native reference picker: one seekable PDF served by range.
  void mockSeekablePick() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileFileChannel, (call) async {
      switch (call.method) {
        case 'pickDocuments':
          return <Map<Object?, Object?>>[
            {
              'token': 'cloud-token',
              'name': 'cloud.pdf',
              'length': pdfBytes.length,
              'seekable': true,
            }
          ];
        case 'fileLength':
          return pdfBytes.length;
        case 'readRange':
          final offset = call.arguments['offset'] as int;
          final len = call.arguments['length'] as int;
          final start = offset.clamp(0, pdfBytes.length);
          final end = (offset + len).clamp(0, pdfBytes.length);
          return Uint8List.sublistView(pdfBytes, start, end);
        default:
          return null;
      }
    });
  }

  testWidgets(
      'opens a seekable mobile pick progressively and swaps to an edit session',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      mockSeekablePick();

      await pump(tester, () async {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      });

      // Tap the welcome screen's Open button, which drives the mobile
      // reference pick path.
      await pump(tester, () async {
        await tester.tap(find.text('Open a PDF'));
      });

      // The tab opened through the progressive path (first paint, then the full
      // read) and ended on a real edit session, not a read-only preview.
      final log = AppDevTools.instance.log.map((e) => e.message).join('\n');
      expect(log, contains('progressive open: "cloud.pdf" first paint'));
      expect(log, contains('full read complete'));
      expect(find.byType(PdfEditorView), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
