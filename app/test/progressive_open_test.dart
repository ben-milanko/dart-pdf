// A single desktop path-open goes through the progressive loader: a read-only
// first paint renders the sparse document, then the complete bytes stream in
// behind it and the tab swaps to a full edit session. Driven on Linux so the
// source is a plain RandomAccessFile (no macOS security-scoped channel).
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/devtools.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

void main() {
  late PdfEditingPreferences prefs;
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    tempDir = Directory.systemTemp.createTempSync('dartpdf_progressive_test');
    AppDevTools.instance.clearLog();
  });

  tearDown(() {
    prefs.dispose();
    tempDir.deleteSync(recursive: true);
  });

  String seedFile(String name) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(Uint8List.fromList(buildClassicPdf()));
    return path;
  }

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(name),
      );

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

  // Hands the editor a file-with-path the way the OS does (no bytes), which the
  // open path treats as a progressive open on desktop.
  Future<void> openIncoming(WidgetTester tester, String path, String name) {
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(MethodCall('openFile', {
      'name': name,
      'path': path,
    }));
    return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      message,
      (_) {},
    );
  }

  testWidgets('opens progressively and swaps to a full edit session',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final path = seedFile('big.pdf');

      await pump(tester, () async {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      });
      await pump(tester, () => openIncoming(tester, path, 'big.pdf'));

      // The tab opened...
      expect(tabTitle('big.pdf'), findsOneWidget);
      // ...through the progressive path (first paint, then the full read)...
      final log = AppDevTools.instance.log.map((e) => e.message).join('\n');
      expect(log, contains('progressive open: "big.pdf" first paint'));
      expect(log, contains('full read complete'));
      // ...and ended on a real edit session, not a read-only preview.
      expect(find.byType(PdfEditorView), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
