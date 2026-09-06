// The Print action is wired into the DartPDF app menu (and ⌘P / Ctrl+P) when a
// document is open. The native printer needs platform channels, so
// these tests inject a fake printer to assert the wiring end to end.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/printing.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  Future<void> pumpWithDoc(
    WidgetTester tester, {
    PdfPrinter? printDocument,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildClassicPdf(), title: 'Report.pdf'),
        printDocument: printDocument,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the DartPDF menu offers Print with a document open',
      (tester) async {
    await pumpWithDoc(tester);

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-print')), findsOneWidget);
    expect(find.text('Print…'), findsOneWidget);
  });

  testWidgets('no Print entry without a document open', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-print')), findsNothing);
  });

  testWidgets('selecting Print previews before handing sheets to the printer',
      (tester) async {
    Uint8List? printed;
    String? jobTitle;
    await pumpWithDoc(
      tester,
      printDocument: ({required bytes, required title}) async {
        printed = bytes;
        jobTitle = title;
      },
    );

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    // The app menu is tall (scan entries land above this on mobile), so the
    // Print item can sit below the fold - scroll it into view before tapping.
    await tester.ensureVisible(find.byKey(const ValueKey('menu-print')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-print')));
    await tester.pumpAndSettle();

    expect(printed, isNull);
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();

    expect(jobTitle, 'Report.pdf');
    expect(printed, isNotNull);
    expect(String.fromCharCodes(printed!.take(5)), '%PDF-');
  },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }));

  testWidgets('a failing printer surfaces a toast', (tester) async {
    await pumpWithDoc(
      tester,
      printDocument: ({required bytes, required title}) async {
        throw StateError('no printer available');
      },
    );

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    // The app menu is tall (scan entries land above this on mobile), so the
    // Print item can sit below the fold - scroll it into view before tapping.
    await tester.ensureVisible(find.byKey(const ValueKey('menu-print')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-print')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle(); // close preview and reject the future
    await tester.pump(); // show the snack bar

    expect(find.text('Could not print Report.pdf'), findsOneWidget);
  });

  testWidgets(
      'thumbnail selection prints those pages and preserves the session',
      (tester) async {
    Uint8List? printed;
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildMultiPagePdf(4), title: 'Report.pdf'),
        printDocument: ({required bytes, required title}) async {
          printed = bytes;
        },
      ),
    ));
    await tester.pumpAndSettle();
    final session =
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
    session.selectPage(1);
    session.togglePageSelection(3);
    final before = Uint8List.fromList(session.bytes);
    await tester.pump();
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('menu-print')));
    await tester.tap(find.byKey(const ValueKey('menu-print')));
    await tester.pumpAndSettle();
    final selected = find.byKey(const ValueKey('print-preview-selected'));
    await tester.ensureVisible(selected);
    await tester.tap(selected);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();

    final output = PdfDocument.open(printed!);
    expect(output.pageCount, 2);
    expect(PdfTextExtractor.extract(output, 0).text, 'Page 2');
    expect(PdfTextExtractor.extract(output, 1).text, 'Page 4');
    expect(session.bytes, before);
    expect(session.selectedPages, [1, 3]);
  });

  testWidgets('Ctrl+P prints the active document', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      var printCalls = 0;
      await pumpWithDoc(
        tester,
        printDocument: ({required bytes, required title}) async {
          printCalls += 1;
        },
      );

      // Focus the viewer so the shortcut has somewhere to dispatch from.
      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Linux has no print preview of its own, so the shortcut opens ours -
      // the job starts from there (see print_preview_test.dart).
      expect(printCalls, 0);
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();

      expect(printCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
