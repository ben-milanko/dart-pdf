import 'dart:async';
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TemporaryFiles extends PathProviderPlatform {
  _TemporaryFiles(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

Finder _dirtyDot() => find.descendant(
      of: find.byKey(const ValueKey('tab-strip')),
      matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.circle && w.size == 8),
    );

void main() {
  final bytes = Uint8List.fromList(buildClassicPdf());
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  group('mobile file handoff', () {
    late Directory directory;
    late PathProviderPlatform original;
    late String result;
    late List<Map<Object?, Object?>> calls;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('dartpdf-share-result');
      original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TemporaryFiles(directory.path);
      result = '';
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'share');
        calls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return result;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null);
      PathProviderPlatform.instance = original;
      directory.deleteSync(recursive: true);
    });

    final exporters = <String, Future<SaveResult> Function(BuildContext)>{
      'PDF': (c) => saveBytesAs(c, bytes, 'form.pdf', pdfLabel: 'PDF'),
      'PDF batch': (c) =>
          shareDocumentsAs(c, [(bytes: bytes, name: 'form.pdf')]),
      'JSON': (c) =>
          saveJsonAs(c, '{"answer":42}', 'data.json', typeLabel: 'JSON'),
      'form data': (c) => saveFormDataAs(
          c, bytes, 'data.xfdf', 'application/vnd.adobe.xfdf',
          extension: 'xfdf', typeLabel: 'Form data'),
      'image': (c) => saveImageBytesAs(c, bytes, 'page.png', 'image/png',
          imageLabel: 'Image'),
    };
    for (final exporter in exporters.entries) {
      for (final outcome in ['dismissed', 'unavailable', 'selected']) {
        testWidgets('${exporter.key}: $outcome is not an unconditional save',
            (tester) async {
          result = switch (outcome) {
            'selected' => 'com.example.save-copy',
            'unavailable' => 'dev.fluttercommunity.plus/share/unavailable',
            _ => '',
          };
          late BuildContext context;
          await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
            context = c;
            return const SizedBox.expand();
          })));
          final saved = await tester.runAsync(() => exporter.value(context));
          expect(calls, hasLength(1));
          expect(calls.single['paths'], isNotEmpty);
          expect(saved!.succeeded, outcome == 'selected');
          if (outcome != 'selected') expect(saved.message, isNot('Shared'));
          expect(saved.path, isNull);
        }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
      }
    }
  });

  group('save completion owns only the captured revision', () {
    late PdfEditingPreferences preferences;
    late InMemoryUnsavedChangesStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      preferences = PdfEditingPreferences();
      store = InMemoryUnsavedChangesStore();
    });
    tearDown(() => preferences.dispose());

    Future<PdfEditingController> open(
        WidgetTester tester,
        Future<SaveResult> Function(BuildContext, Uint8List, String)
            save) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: EditorScreen(
        prefs: preferences,
        unsavedChangesStore: store,
        initialDocument: (bytes: bytes, title: 'form.pdf'),
        saveDocumentAs: save,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return tester
          .widget<PdfEditorView>(find.byType(PdfEditorView))
          .controller!;
    }

    testWidgets('edits during a save remain dirty and recoverable',
        (tester) async {
      final completion = Completer<SaveResult>();
      Uint8List? written;
      final controller = await open(tester, (c, bytes, name) {
        written = Uint8List.fromList(bytes);
        return completion.future;
      });
      controller.addBookmark('Saved revision');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-save')));
      await tester.pump();
      expect(written, isNotNull);
      controller.addBookmark('Edit made while saving');
      await tester.pump(const Duration(seconds: 2));
      expect(controller.bytes.length, greaterThan(written!.length));
      completion.complete(SaveResult.downloaded('form.pdf'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(_dirtyDot(), findsOneWidget);
      final records = await store.list();
      expect(records, hasLength(1));
      expect(records.single.length, controller.bytes.length);
      expect(records.single.savedLength, written!.length);
    });

    testWidgets('a second Save cannot open another destination while pending',
        (tester) async {
      final completion = Completer<SaveResult>();
      var calls = 0;
      final controller = await open(tester, (c, bytes, name) {
        calls++;
        return completion.future;
      });
      controller.addBookmark('First edit');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-save')));
      await tester.tap(find.byKey(const ValueKey('pdf-shell-save')));
      await tester.pump();
      expect(calls, 1);
      completion.complete(SaveResult.cancelled);
      await tester.pump();
      expect(_dirtyDot(), findsOneWidget);
    });

    testWidgets('dismissed destination leaves a recoverable edited document',
        (tester) async {
      final controller =
          await open(tester, (c, bytes, name) async => SaveResult.cancelled);
      controller.addBookmark('Keep this edit');
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('pdf-shell-save')));
      await tester.pump(const Duration(seconds: 2));
      expect(_dirtyDot(), findsOneWidget);
      expect(await store.list(), hasLength(1));
      expect(find.text('Shared'), findsNothing);
    });
  });
}
