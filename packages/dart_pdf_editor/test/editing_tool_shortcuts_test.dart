import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  group('pdfEditToolShortcuts map', () {
    test('every tool maps to a distinct key with an uppercase label', () {
      final keys = pdfEditToolShortcuts.values.toList();
      expect(keys.toSet(), hasLength(keys.length),
          reason: 'no two tools may share a key');
      for (final tool in pdfEditToolShortcuts.keys) {
        final label = pdfEditToolShortcutLabel(tool);
        expect(label, isNotNull);
        expect(label, label!.toUpperCase());
        expect(label, hasLength(1));
      }
    });

    test('the common tools are covered; rare variants are not', () {
      expect(pdfEditToolShortcuts.keys, contains(PdfEditTool.select));
      expect(pdfEditToolShortcuts.keys, contains(PdfEditTool.ink));
      expect(pdfEditToolShortcuts.keys, contains(PdfEditTool.rectangle));
      expect(pdfEditToolShortcuts.keys, contains(PdfEditTool.freeText));
      // the multi-segment / extra measure variants live one tap away
      expect(pdfEditToolShortcuts.keys, isNot(contains(PdfEditTool.polyline)));
      expect(pdfEditToolShortcuts.keys, isNot(contains(PdfEditTool.polygon)));
      expect(pdfEditToolShortcuts.keys,
          isNot(contains(PdfEditTool.measureArea)));
    });

    test('tools with no shortcut report a null label', () {
      expect(pdfEditToolShortcutLabel(PdfEditTool.polyline), isNull);
    });
  });

  group('tool shortcuts in the viewer', () {
    const scale = 800 / 612;
    // an empty patch mid-page to focus the viewer without selecting anything
    final empty = const Offset(450 * scale, (792 - 400) * scale);

    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    /// Taps an empty patch to give the viewer keyboard focus. Mouse-kind
    /// so it resolves without the touch double-tap timer.
    Future<void> focusViewer(WidgetTester tester) async {
      await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
      await tester.pump();
    }

    testWidgets('a single key arms its tool', (tester) async {
      final editing = await pumpEditor(tester);
      await focusViewer(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(editing.tool, PdfEditTool.rectangle);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      expect(editing.tool, PdfEditTool.freeText);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(editing.tool, PdfEditTool.ink);
    });

    testWidgets('pressing a tool key again drops back to Select',
        (tester) async {
      final editing = await pumpEditor(tester);
      await focusViewer(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(editing.tool, PdfEditTool.rectangle);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(editing.tool, PdfEditTool.select);
    });

    testWidgets('V always arms Select', (tester) async {
      final editing = await pumpEditor(tester);
      await focusViewer(tester);

      editing.tool = PdfEditTool.ink;
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(editing.tool, PdfEditTool.select);
    });

    testWidgets('tool shortcuts are ignored while editing text',
        (tester) async {
      final editing = await pumpEditor(tester);
      await focusViewer(tester);
      editing.tool = PdfEditTool.select;
      await tester.pump();

      // an open in-place text editor owns every key
      editing.setEditingText(true);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(editing.tool, PdfEditTool.select);
    });
  });
}
