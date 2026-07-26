// A single desktop path-open goes through the progressive loader: a read-only
// first paint renders the sparse document, then the complete bytes stream in
// behind it and the tab swaps to a full edit session. Driven on Linux so the
// source is a plain RandomAccessFile (no macOS security-scoped channel).
import 'dart:async';
import 'dart:convert';
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

  testWidgets('restores a desktop session tab lazily, opening it progressively',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final path = seedFile('restored.pdf');
      SharedPreferences.setMockInitialValues({
        'dart_pdf_editor_app.session': jsonEncode([
          {'t': 'restored.pdf', 'p': path}
        ]),
      });

      await pump(tester, () async {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      });

      // The restored tab opened via the progressive path and became a full
      // edit session - it read no bytes until it was the active tab.
      expect(tabTitle('restored.pdf'), findsOneWidget);
      final log = AppDevTools.instance.log.map((e) => e.message).join('\n');
      expect(log, contains('progressive open: "restored.pdf" first paint'));
      expect(find.byType(PdfEditorView), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'restored tabs remain usable while another macOS cloud read is pending',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel('dev.milanko.dartpdf/file_access');
    final remoteStarted = Completer<void>();
    final releaseRemote = Completer<void>();
    final bytes = Uint8List.fromList(buildClassicPdf());

    try {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          final args = (call.arguments as Map).cast<Object?, Object?>();
          final bookmark = args['bookmark'] as String?;
          switch (call.method) {
            case 'fileLength':
              if (bookmark == 'remote-bookmark' && !releaseRemote.isCompleted) {
                if (!remoteStarted.isCompleted) remoteStarted.complete();
                await releaseRemote.future;
              }
              return bytes.length;
            case 'readFileRange':
              final offset = args['offset'] as int;
              final length = args['length'] as int;
              final end = (offset + length).clamp(0, bytes.length);
              if (offset >= bytes.length) return Uint8List(0);
              return Uint8List.sublistView(bytes, offset, end);
            case 'readFile':
              return bytes;
          }
          return null;
        },
      );

      // The remote document is last, so it is the active restored tab. Both
      // tab placeholders must appear before its first native read completes.
      SharedPreferences.setMockInitialValues({
        'dart_pdf_editor_app.session': jsonEncode([
          {
            't': 'local.pdf',
            'p': '/local.pdf',
            'b': 'local-bookmark',
          },
          {
            't': 'remote.pdf',
            'p': '/remote.pdf',
            'b': 'remote-bookmark',
          },
        ]),
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
        for (var i = 0;
            i < 20 &&
                (!remoteStarted.isCompleted ||
                    tabTitle('local.pdf').evaluate().isEmpty);
            i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();

      expect(remoteStarted.isCompleted, isTrue);
      expect(tabTitle('local.pdf'), findsOneWidget);
      expect(tabTitle('remote.pdf'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Switching tabs must start and finish the local read even while the
      // remote File Provider request remains unresolved.
      await tester.runAsync(() async {
        await tester.tap(tabTitle('local.pdf'));
        for (var i = 0;
            i < 30 && find.byType(PdfEditorView).evaluate().isEmpty;
            i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();

      expect(releaseRemote.isCompleted, isFalse);
      expect(find.byType(PdfEditorView), findsOneWidget);

      // Let the abandoned remote request unwind cleanly before the widget and
      // its method channel are disposed.
      releaseRemote.complete();
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
    } finally {
      if (!releaseRemote.isCompleted) releaseRemote.complete();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('drops a restored desktop file that has gone missing',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      SharedPreferences.setMockInitialValues({
        'dart_pdf_editor_app.session': jsonEncode([
          {'t': 'gone.pdf', 'p': '${tempDir.path}/gone.pdf'}
        ]),
      });

      await pump(tester, () async {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      });

      // The length probe fails for a missing file, so it is dropped silently -
      // no tab, no error placeholder.
      expect(tabTitle('gone.pdf'), findsNothing);
      expect(find.byType(PdfEditorView), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
