// The app-wide command palette: one ⌘K index over the menu's actions, the
// dock's tools, the panels and the view options.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/command_palette.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  group('ranking', () {
    test('a whole-name match beats a prefix, which beats a word boundary', () {
      final exact = scoreCommand('Print…', 'print…')!;
      final prefix = scoreCommand('Print…', 'pri')!;
      final word = scoreCommand('Export page as image…', 'page')!;
      final anywhere = scoreCommand('Digitally sign…', 'gital')!;
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(word));
      expect(word, greaterThan(anywhere));
    });

    test('letters found in order still reach a command', () {
      expect(scoreCommand('Cloud polygon', 'cpg'), isNotNull);
      expect(scoreCommand('Cloud polygon', 'zzz'), isNull);
    });
  });

  group('in the app', () {
    late PdfEditingPreferences prefs;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      prefs = PdfEditingPreferences();
    });
    tearDown(() => prefs.dispose());

    Future<void> pump(WidgetTester tester, {bool withDoc = true}) async {
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialDocument:
              withDoc ? (bytes: buildClassicPdf(), title: 'Report.pdf') : null,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> openWithKeyboard(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+K opens it, and it indexes menu actions and tools alike',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await pump(tester);
        await openWithKeyboard(tester);

        expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
        // The menu's actions lead the index - including one this branch
        // never wired by hand: Insert document joins because the menu and
        // the palette read the same descriptors.
        expect(find.byKey(const ValueKey('palette-result-menu-print')),
            findsOneWidget);
        expect(
            find.byKey(const ValueKey('palette-result-menu-insert-document')),
            findsOneWidget);

        // A tool from the dock's catalogue is in the same list (the rows are
        // built lazily, so ask for it by name rather than scrolling).
        await tester.enterText(
            find.byKey(const ValueKey('command-palette-field')), 'rect');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('palette-result-tool-rectangle')),
            findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('typing narrows to matches across surfaces', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await pump(tester);
        await openWithKeyboard(tester);

        await tester.enterText(
            find.byKey(const ValueKey('command-palette-field')), 'sig');
        await tester.pumpAndSettle();

        expect(
            find.byKey(const ValueKey('palette-result-menu-digital-signature')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('palette-result-tool-signature')),
            findsOneWidget);
        // Unrelated commands are gone.
        expect(find.byKey(const ValueKey('palette-result-menu-print')),
            findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('running a tool result arms that tool', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await pump(tester);
        await openWithKeyboard(tester);

        await tester.enterText(
            find.byKey(const ValueKey('command-palette-field')), 'rectangle');
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('palette-result-tool-rectangle')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('command-palette')), findsNothing);
        final controller =
            tester.widget<PdfViewer>(find.byType(PdfViewer)).editing!;
        expect(controller.tool, PdfEditTool.rectangle);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('with nothing open, document commands still list - dimmed',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await pump(tester, withDoc: false);
        await openWithKeyboard(tester);

        await tester.enterText(
            find.byKey(const ValueKey('command-palette-field')), 'print');
        await tester.pumpAndSettle();

        final row = find.byKey(const ValueKey('palette-result-menu-print'));
        expect(row, findsOneWidget);
        expect(find.text('Needs an open document'), findsWidgets);
        // Dimmed means unrunnable, not hidden.
        expect(tester.widget<InkWell>(row).onTap, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
