// PdfReader.headerBuilder (the reader's header from the same PdfHeaderParts
// PdfEditorView hands out) and PdfHeaderParts.saveButton (a save button that
// stays live without changes, while ⌘S keeps waiting for one).

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PdfReader.headerBuilder', () {
    testWidgets('composes a header from the reader parts', (tester) async {
      PdfHeaderParts? seen;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReader(
            bytes: buildMultiPagePdf(2),
            headerBuilder: (context, parts) {
              seen = parts;
              return parts.bar(
                leading: [if (parts.pageNumber case final p?) p],
                trailing: [
                  const Text('host action', key: ValueKey('host-action')),
                  if (parts.panelSwitch case final p?) p,
                ],
              );
            },
          ),
        ),
      ));
      await tester.pump();
      expect(seen, isNotNull);
      expect(seen!.compact, isFalse);
      expect(seen!.search, isNotNull);
      expect(seen!.zoom, isNotNull);
      expect(seen!.viewOptions, isNotNull);
      // a reader has nothing to save
      expect(seen!.save, isNull);
      expect(seen!.saveButton(enabledWhenUnchanged: true), isNull);
      expect(find.byKey(const ValueKey('host-action')), findsOneWidget);
      expect(find.byType(PdfPageNumberField), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          findsOneWidget);
      // left out by the host
      expect(find.byType(PdfSearchField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('compact: the controls part opens the Controls sheet',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReader(
            bytes: buildMultiPagePdf(1),
            headerBuilder: (context, parts) {
              expect(parts.compact, isTrue);
              return parts.bar(
                leading: [if (parts.pageNumber case final p?) p],
                trailing: [if (parts.controls() case final c?) c],
              );
            },
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-controls')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-save')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without a headerBuilder the stock header stands',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfReader(bytes: buildMultiPagePdf(1))),
      ));
      await tester.pump();
      expect(find.byType(PdfSearchField), findsOneWidget);
      expect(find.byType(PdfPageNumberField), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('PdfHeaderParts.saveButton', () {
    Future<List<Uint8List>> pump(WidgetTester tester,
        {required bool enabledWhenUnchanged}) async {
      final saved = <Uint8List>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditorView(
            bytes: buildMultiPagePdf(1),
            onSave: saved.add,
            headerBuilder: (context, parts) => parts.bar(trailing: [
              if (parts.saveButton(enabledWhenUnchanged: enabledWhenUnchanged)
                  case final save?)
                save,
            ]),
          ),
        ),
      ));
      await tester.pump();
      return saved;
    }

    Future<void> pressSave(WidgetTester tester) async {
      await tester.tap(find.byType(PdfViewer), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    final save = find.byKey(const ValueKey('pdf-shell-save'));

    testWidgets('stays live without changes; the shortcut does not',
        (tester) async {
      final saved = await pump(tester, enabledWhenUnchanged: true);
      expect(tester.getSemantics(save), isSemantics(isEnabled: true));
      await pressSave(tester);
      expect(saved, isEmpty);
      await tester.tap(save);
      await tester.pump();
      expect(saved, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('by default it is the stock save part', (tester) async {
      final saved = await pump(tester, enabledWhenUnchanged: false);
      expect(tester.getSemantics(save), isSemantics(isEnabled: false));
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();
      expect(saved, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
