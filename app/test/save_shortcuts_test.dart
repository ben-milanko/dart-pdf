import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';

import 'test_finders.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() {
    prefs.dispose();
  });

  testWidgets('Ctrl+Shift+S routes to the app Save as flow', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      var saveDialogCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/file_selector'),
        (call) async {
          if (call.method == 'getSavePath') {
            saveDialogCalls += 1;
            expect(
                call.arguments, containsPair('suggestedName', 'shortcut.pdf'));
            return null; // user cancelled; enough to prove Save as was reached.
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/file_selector'),
          null,
        );
      });

      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialDocument: (bytes: buildClassicPdf(), title: 'shortcut.pdf'),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(saveDialogCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Ctrl+S saves a brand-new untitled document before any edit',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      var saveAsCalls = 0;
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          saveDocumentAs: (context, bytes, suggestedName) async {
            saveAsCalls++;
            expect(suggestedName, 'Untitled.pdf');
            return SaveResult.cancelled;
          },
        ),
      ));
      await tester.pump();

      // Create a new, unedited document from the app menu.
      await tester.tap(find.byTooltip('DartPDF menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-new-document')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-document-create')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));

      // Plain Ctrl+S with no edits yet must still reach the Save flow: a
      // never-saved document has no on-disk origin to overwrite.
      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(saveAsCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Save As continues the current tab at the new path',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      var saveAsCalls = 0;
      final savedPaths = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialDocument: (bytes: buildClassicPdf(), title: 'Original.pdf'),
          saveDocumentAs: (context, bytes, suggestedName) async {
            saveAsCalls++;
            expect(suggestedName, 'Original.pdf');
            return SaveResult.saved('/tmp/Renamed.pdf');
          },
          saveDocumentToPath: (bytes, path, {bookmark}) async {
            savedPaths.add(path);
            return SaveResult.saved(path);
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final before =
          tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;

      await tester.tap(find.byTooltip('DartPDF menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-save-as')));
      await tester.pumpAndSettle();

      expect(saveAsCalls, 1);
      expect(findMiddleEllipsisText('Renamed.pdf'), findsWidgets);
      expect(findMiddleEllipsisText('Original.pdf'), findsNothing);
      final continued =
          tester.widget<PdfEditorView>(find.byType(PdfEditorView));
      expect(continued.documentId, 'Renamed.pdf');
      expect(identical(continued.controller, before), isTrue);

      // Keep editing in that same session, then plain Save must target the
      // Save As destination rather than the original file.
      before.addFreeText(
        0,
        const PdfRect(72, 650, 240, 700),
        'Continued after Save As',
      );
      await tester.pump();
      continued.onSave!(before.bytes);
      await tester.pump();

      expect(savedPaths, ['/tmp/Renamed.pdf']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
