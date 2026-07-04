import 'dart:convert';
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';
import 'package:dart_pdf_editor_app/session_store.dart';

void main() {
  late PdfEditingPreferences prefs;
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    tempDir = Directory.systemTemp.createTempSync('dartpdf_session_test');
  });

  tearDown(() {
    prefs.dispose();
    tempDir.deleteSync(recursive: true);
  });

  // Writes a real PDF on disk so restore can read it back through the same
  // path-based opener the desktop file pickers use.
  String seedFile(String name) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(Uint8List.fromList(buildClassicPdf()));
    return path;
  }

  void seedSession(List<({String title, String path})> docs) {
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.session': jsonEncode(
          [for (final d in docs) {'t': d.title, 'p': d.path}]),
    });
  }

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(name),
      );

  // The editor never settles (it keeps rasterizing), and restore performs real
  // file I/O — which only progresses under runAsync. Pump a handful of real
  // frames so each read can complete and swap its loading placeholder.
  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  testWidgets('re-opens the documents from the last session on startup',
      (tester) async {
    final a = seedFile('a.pdf');
    final b = seedFile('b.pdf');
    seedSession([(title: 'a.pdf', path: a), (title: 'b.pdf', path: b)]);

    await pumpEditor(tester);

    expect(tabTitle('a.pdf'), findsOneWidget);
    expect(tabTitle('b.pdf'), findsOneWidget);
  });

  testWidgets('drops a session document whose file is gone, no error tab',
      (tester) async {
    seedSession([(title: 'missing.pdf', path: '${tempDir.path}/missing.pdf')]);

    await pumpEditor(tester);

    // Nothing opened — we land back on the welcome screen, no error placeholder.
    expect(tabTitle('missing.pdf'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);
  });

  testWidgets('skips restore when launched to open a specific document',
      (tester) async {
    final a = seedFile('a.pdf');
    seedSession([(title: 'a.pdf', path: a)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialDocument: (
            bytes: Uint8List.fromList(buildClassicPdf()),
            title: 'launched.pdf',
          ),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(tabTitle('launched.pdf'), findsOneWidget);
    expect(tabTitle('a.pdf'), findsNothing);
  });

  testWidgets('records the open documents so the next launch can restore them',
      (tester) async {
    // Start with no prior session, then open a file-backed document the way the
    // OS hands one over. The open set should be persisted for next time.
    final path = '${tempDir.path}/opened.pdf';
    await pumpEditor(tester); // empty session: enables persistence

    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(MethodCall('openFile', {
      'name': 'opened.pdf',
      'bytes': buildClassicPdf(),
      'path': path,
    }));
    await tester.runAsync(() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        IncomingFileService.channelName,
        message,
        (_) {},
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(tabTitle('opened.pdf'), findsOneWidget);
    final persisted = await SessionStore().load();
    expect(persisted.map((d) => d.path), [path]);
  });
}
