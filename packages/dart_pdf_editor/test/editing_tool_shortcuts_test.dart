import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  group('pdfEditToolShortcuts map', () {
    test('every tool is bound to a distinct combo', () {
      // every PdfEditTool has a shortcut now
      for (final tool in PdfEditTool.values) {
        expect(pdfEditToolShortcuts.keys, contains(tool),
            reason: '$tool must have a shortcut');
      }
      // no two tools share the same (key + shift) combo
      final combos = pdfEditToolShortcuts.values.toList();
      expect(combos.toSet(), hasLength(combos.length),
          reason: 'no two tools may share a combo');
    });

    test('every tool reports a non-empty uppercase label', () {
      for (final tool in pdfEditToolShortcuts.keys) {
        final label = pdfEditToolShortcutLabel(tool);
        expect(label, isNotNull);
        expect(label, isNotEmpty);
        // the letter part is uppercase (a Shift-extended label carries a
        // leading ⇧ glyph)
        final shortcut = pdfEditToolShortcuts[tool]!;
        expect(label, endsWith(shortcut.trigger.keyLabel.toUpperCase()));
        expect(label!.startsWith('⇧'), shortcut.shift);
      }
    });

    test('common tools sit on plain letters', () {
      expect(pdfEditToolShortcuts[PdfEditTool.select],
          const PdfToolShortcut(LogicalKeyboardKey.keyV));
      expect(pdfEditToolShortcuts[PdfEditTool.ink],
          const PdfToolShortcut(LogicalKeyboardKey.keyP));
      expect(pdfEditToolShortcuts[PdfEditTool.rectangle],
          const PdfToolShortcut(LogicalKeyboardKey.keyR));
      expect(pdfEditToolShortcuts[PdfEditTool.snapshot],
          const PdfToolShortcut(LogicalKeyboardKey.keyG));
      expect(pdfEditToolShortcuts[PdfEditTool.signature],
          const PdfToolShortcut(LogicalKeyboardKey.keyH));
      // primary tools carry no Shift
      expect(pdfEditToolShortcuts[PdfEditTool.rectangle]!.shift, isFalse);
    });

    test('group variants extend their group letter with Shift', () {
      // Shift+L polyline beside L line; Shift+M calibrate beside M measure;
      // Shift+H highlighter beside P pen.
      expect(pdfEditToolShortcuts[PdfEditTool.polyline],
          const PdfToolShortcut(LogicalKeyboardKey.keyL, shift: true));
      expect(pdfEditToolShortcuts[PdfEditTool.cloudPolygon],
          const PdfToolShortcut(LogicalKeyboardKey.keyD, shift: true));
      expect(pdfEditToolShortcuts[PdfEditTool.measureArea],
          const PdfToolShortcut(LogicalKeyboardKey.keyA, shift: true));
      expect(pdfEditToolShortcuts[PdfEditTool.calibrate],
          const PdfToolShortcut(LogicalKeyboardKey.keyM, shift: true));
      expect(pdfEditToolShortcutLabel(PdfEditTool.polyline), '⇧L');
    });

    test('activator matches the key and shift state', () {
      final plain =
          const PdfToolShortcut(LogicalKeyboardKey.keyL).activator
              as SingleActivator;
      expect(plain.trigger, LogicalKeyboardKey.keyL);
      expect(plain.shift, isFalse);

      final shifted =
          const PdfToolShortcut(LogicalKeyboardKey.keyL, shift: true).activator
              as SingleActivator;
      expect(shifted.trigger, LogicalKeyboardKey.keyL);
      expect(shifted.shift, isTrue);
    });

    test('labels can be read from a custom shortcut map', () {
      expect(
        pdfEditToolShortcutLabel(
          PdfEditTool.rectangle,
          shortcuts: const {
            PdfEditTool.rectangle: PdfToolShortcut(LogicalKeyboardKey.keyB)
          },
        ),
        'B',
      );
      expect(
        pdfEditToolShortcutLabel(
          PdfEditTool.ink,
          shortcuts: const {
            PdfEditTool.rectangle: PdfToolShortcut(LogicalKeyboardKey.keyB)
          },
        ),
        isNull,
      );
    });
  });

  group('tool shortcuts in the viewer', () {
    const scale = 800 / 612;
    // an empty patch mid-page to focus the viewer without selecting anything
    final empty = const Offset(450 * scale, (792 - 400) * scale);

    Future<PdfEditingController> pumpEditor(
      WidgetTester tester, {
      Map<PdfEditTool, PdfToolShortcut> toolShortcuts = pdfEditToolShortcuts,
    }) async {
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
              toolShortcuts: toolShortcuts,
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

      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pump();
      expect(editing.tool, PdfEditTool.snapshot);
    });

    testWidgets('a Shift-extended key arms its variant tool', (tester) async {
      final editing = await pumpEditor(tester);
      await focusViewer(tester);

      // Shift+L arms the polyline; plain L still arms the line
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(editing.tool, PdfEditTool.polyline);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(editing.tool, PdfEditTool.line);
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

    testWidgets('custom tool shortcuts replace the defaults', (tester) async {
      final editing = await pumpEditor(
        tester,
        toolShortcuts: const {
          PdfEditTool.rectangle: PdfToolShortcut(LogicalKeyboardKey.keyB)
        },
      );
      await focusViewer(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(editing.tool, isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(editing.tool, PdfEditTool.rectangle);
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
