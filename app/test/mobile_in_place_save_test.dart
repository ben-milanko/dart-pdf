// Android and iOS: Save writes edits straight back into the PDF the user
// picked (#1304) when the reference picker's token allows writing (a persisted
// SAF write grant / an `.open`-mode security-scoped bookmark), instead of
// sending a copy through the share sheet. Driven with the native `mobile_file`
// channel mocked and Save As (the share sheet) seamed; the runners' `writeUri`
// / `readUri` themselves need on-device verification.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/devtools.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/pdf_mobile_source.dart';
import 'package:dart_pdf_editor_app/session_store.dart';

class _Session implements SessionPersistence {
  _Session(this.documents);
  List<SessionDocument> documents;

  @override
  Future<List<SessionDocument>> load() async => documents;

  @override
  Future<void> save(List<SessionDocument> documents) async =>
      this.documents = documents;
}

void main() {
  late PdfEditingPreferences prefs;
  late Uint8List pdfBytes;
  late List<MethodCall> writes;
  // Save As calls - on a phone, the share sheet.
  late List<String> shares;
  late Object? writeError;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    pdfBytes = Uint8List.fromList(buildClassicPdf());
    writes = [];
    shares = [];
    writeError = null;
    AppDevTools.instance.clearLog();
  });

  tearDown(() {
    prefs.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileFileChannel, null);
  });

  Future<void> settle(WidgetTester tester,
      [Future<void> Function()? action]) async {
    await tester.runAsync(() async {
      await action?.call();
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  void mockPick({required bool writable, required bool seekable}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileFileChannel, (call) async {
      switch (call.method) {
        case 'pickDocuments':
          return <Map<Object?, Object?>>[
            {
              'token': 'content://docs/report',
              'name': 'report.pdf',
              'length': pdfBytes.length,
              'provider': 'com.android.externalstorage.documents',
              'writable': writable,
            }
          ];
        case 'probeSeekable':
          return seekable;
        case 'fileLength':
          return pdfBytes.length;
        case 'readRange':
          final offset = call.arguments['offset'] as int;
          final len = call.arguments['length'] as int;
          final start = offset.clamp(0, pdfBytes.length);
          final end = (offset + len).clamp(0, pdfBytes.length);
          return Uint8List.sublistView(pdfBytes, start, end);
        case 'writeUri':
          writes.add(call);
          if (writeError case final error?) throw error;
          return true;
        default:
          return null;
      }
    });
  }

  Future<PdfEditingController> openPicked(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await settle(tester, () async {
      await tester.pumpWidget(MaterialApp(
          home: EditorScreen(
        prefs: prefs,
        saveDocumentAs: (context, bytes, name) async {
          shares.add(name);
          return SaveResult.shared();
        },
      )));
    });
    await settle(tester, () async => tester.tap(find.text('Open a PDF')));
    return tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
  }

  // Each journey runs on both phone/tablet platforms. The platform override
  // must be cleared inside the test body, before the binding's invariant
  // check.
  void mobileTest(
      String description, Future<void> Function(WidgetTester) body) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('${platform.name}: $description', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  for (final seekable in [true, false]) {
    final how = seekable ? 'progressive' : 'whole-read';
    mobileTest('Save writes a writable $how pick back into the picked file',
        (tester) async {
      mockPick(writable: true, seekable: seekable);
      final controller = await openPicked(tester);
      final view = tester.widget<PdfEditorView>(find.byType(PdfEditorView));
      // The header offers Save, not Share.
      expect(view.saveButtonLabel, isNull);
      expect(view.saveButtonIcon, Icons.save_alt);

      controller.addBookmark('Edited on the tablet');
      await tester.pump();
      await settle(tester,
          () async => tester.tap(find.byKey(const ValueKey('pdf-shell-save'))));

      expect(shares, isEmpty);
      expect(writes, hasLength(1));
      final args = writes.single.arguments as Map;
      expect(args['token'], 'content://docs/report');
      final written = args['bytes'] as Uint8List;
      expect(written, controller.bytes);
      expect(written.length, greaterThan(pdfBytes.length));
      expect(find.text('Saved report.pdf'), findsOneWidget);
      // Saved: nothing left to save.
      expect(
          tester
              .widget<PdfEditorView>(find.byType(PdfEditorView))
              .alwaysAllowSave,
          isFalse);
      expect(AppDevTools.instance.log.map((e) => e.message).join('\n'),
          isNot(contains('content://docs/report')));
    });
  }

  mobileTest('a read-only pick keeps sharing a copy', (tester) async {
    mockPick(writable: false, seekable: false);
    final controller = await openPicked(tester);
    final view = tester.widget<PdfEditorView>(find.byType(PdfEditorView));
    expect(view.saveButtonIcon, Icons.share_outlined);

    controller.addBookmark('Edited');
    await tester.pump();
    await settle(tester,
        () async => tester.tap(find.byKey(const ValueKey('pdf-shell-save'))));

    expect(writes, isEmpty);
    expect(shares, hasLength(1));
  });

  mobileTest('a write the provider refuses falls back to sharing a copy',
      (tester) async {
    mockPick(writable: true, seekable: false);
    writeError = PlatformException(code: 'permission_denied');
    final controller = await openPicked(tester);

    controller.addBookmark('Edited');
    await tester.pump();
    await settle(tester,
        () async => tester.tap(find.byKey(const ValueKey('pdf-shell-save'))));

    expect(writes, hasLength(1));
    // Told, then offered the share sheet so the edits can still leave.
    expect(shares, hasLength(1));
    expect(AppDevTools.instance.log.map((e) => e.message).join('\n'),
        contains('in-place save failed: report.pdf'));
  });

  mobileTest(
      'a restored document reopens from the picked file and saves back into it',
      (tester) async {
    // The file changed on disk since the snapshot was taken (another app
    // edited it): the restore must build on what the file holds now.
    final current = Uint8List.fromList(buildMultiPagePdf(2));
    final session = _Session([
      const SessionDocument(
        title: 'report.pdf',
        path: '',
        cachePath: '/missing/snapshot.pdf',
        uri: 'content://docs/report',
      ),
    ]);
    final reads = <String>[];
    final saved = <(String, Uint8List)>[];
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await settle(tester, () async {
      await tester.pumpWidget(MaterialApp(
          home: EditorScreen(
        prefs: prefs,
        sessionStore: session,
        readDocumentUri: (uri) async {
          reads.add(uri);
          return current;
        },
        saveDocumentToUri: (bytes, uri, {required name}) async {
          saved.add((uri, Uint8List.fromList(bytes)));
          return SaveResult.savedInPlace(name);
        },
      )));
    });
    await settle(tester);

    expect(reads, ['content://docs/report']);
    final controller =
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
    expect(controller.document.pageCount, 2);
    // Still saving into the picked file, and still remembered as such.
    expect(session.documents.single.uri, 'content://docs/report');

    controller.addBookmark('After restore');
    await tester.pump();
    await settle(tester,
        () async => tester.tap(find.byKey(const ValueKey('pdf-shell-save'))));
    expect(saved, hasLength(1));
    expect(saved.single.$1, 'content://docs/report');
    expect(saved.single.$2, controller.bytes);
  });
}
