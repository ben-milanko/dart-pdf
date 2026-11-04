// The viewer's keyboard commands are Intents: a host binds its own keys to
// them (PdfViewer.shortcuts, or a Shortcuts above the viewer) and replaces
// what they do (an Actions above it - the viewer's actions are overridable).
// The stock bindings are covered by the existing keyboard tests.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  const scale = 800 / 612;
  // an empty patch mid-page to focus the viewer without selecting anything
  const empty = Offset(450 * scale, (792 - 400) * scale);

  Future<PdfEditingController> pump(
    WidgetTester tester, {
    Map<ShortcutActivator, Intent>? shortcuts,
    Widget Function(Widget viewer)? wrap,
  }) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(100, 650, 180, 700));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    final view = ListenableBuilder(
      listenable: editing,
      builder: (context, _) => PdfViewer(
        initialFit: PdfViewerFit.width,
        document: editing.document,
        controller: viewer,
        editing: editing,
        shortcuts: shortcuts,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: wrap?.call(view) ?? view),
    ));
    await tester.pump();
    await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
    await tester.pump();
    editing.selectAnnotationAt(0, 140, 675);
    await tester.pump();
    return editing;
  }

  int annotations(PdfEditingController editing) =>
      editing.document.page(0).annotations.length;

  test('the stock bindings cover every command', () {
    final intents = pdfViewerDefaultShortcuts.values.map((i) => i.runtimeType);
    expect(
        intents.toSet(),
        containsAll(<Type>[
          PdfCopyIntent,
          PdfCutIntent,
          PdfPasteIntent,
          PdfSelectAllIntent,
          PdfDismissIntent,
          PdfUndoIntent,
          PdfRedoIntent,
          PdfDeleteSelectionIntent,
          PdfAutosizeTextBoxIntent,
          PdfRotateSelectionIntent,
          PdfNudgeSelectionIntent,
          PdfArmLastToolIntent,
        ]));
    expect(
        pdfViewerDefaultShortcuts[
            const SingleActivator(LogicalKeyboardKey.backspace)],
        isA<PdfDeleteSelectionIntent>());
  });

  test('lastUsedTool is the tool before the current one, Select aside', () {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    expect(editing.lastUsedTool, isNull);
    editing.tool = PdfEditTool.rectangle;
    expect(editing.lastUsedTool, isNull, reason: 'nothing used before it');
    editing.tool = PdfEditTool.select;
    expect(editing.lastUsedTool, PdfEditTool.rectangle);
    editing.tool = PdfEditTool.ink;
    expect(editing.lastUsedTool, PdfEditTool.rectangle,
        reason: 'Select is skipped');
    editing.tool = PdfEditTool.rectangle;
    expect(editing.lastUsedTool, PdfEditTool.ink, reason: 'flips between two');
    editing.markupTool = PdfMarkupKind.highlight;
    expect(editing.lastUsedTool, PdfEditTool.rectangle);
  });

  testWidgets('X re-arms the last used tool', (tester) async {
    final editing = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(editing.tool, isNot(PdfEditTool.ink),
        reason: 'no tool used yet: the key does nothing');

    editing.tool = PdfEditTool.ink;
    editing.tool = PdfEditTool.select;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(editing.tool, PdfEditTool.ink);

    editing.tool = PdfEditTool.ellipse;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(editing.tool, PdfEditTool.ink);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(editing.tool, PdfEditTool.ellipse);
  });

  testWidgets('PdfViewer.shortcuts rebinds keys', (tester) async {
    final editing = await pump(tester, shortcuts: {
      ...pdfViewerDefaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.backspace):
          const DoNothingAndStopPropagationIntent(),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true):
          const PdfDeleteSelectionIntent(),
    });
    expect(annotations(editing), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(annotations(editing), 1, reason: 'Backspace no longer deletes');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(annotations(editing), 0);
  });

  testWidgets('a Shortcuts above the viewer reaches its intents',
      (tester) async {
    final editing = await pump(tester,
        wrap: (viewer) => Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.f8):
                    PdfNudgeSelectionIntent(25, 0),
              },
              child: viewer,
            ));
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    expect(editing.document.page(0).annotations.single.rect.left,
        closeTo(125, 0.01));
  });

  testWidgets('an Actions above the viewer overrides what a command does',
      (tester) async {
    final deletes = <PdfDeleteSelectionIntent>[];
    final editing = await pump(tester,
        wrap: (viewer) => Actions(
              actions: {
                PdfDeleteSelectionIntent:
                    CallbackAction<PdfDeleteSelectionIntent>(
                        onInvoke: (intent) {
                  deletes.add(intent);
                  return null;
                }),
              },
              child: viewer,
            ));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(deletes, hasLength(1));
    expect(annotations(editing), 1, reason: 'the host action ran instead');
  });

  testWidgets('without a selection the arrow keys are let through',
      (tester) async {
    var scrolled = 0;
    final editing = await pump(tester,
        wrap: (viewer) => Actions(
              actions: {
                ScrollIntent: CallbackAction<ScrollIntent>(onInvoke: (_) {
                  scrolled++;
                  return null;
                }),
              },
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.arrowDown):
                      ScrollIntent(direction: AxisDirection.down),
                },
                child: viewer,
              ),
            ));
    editing.clearAnnotationSelection();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(scrolled, 1, reason: 'a disabled nudge leaves the key unhandled');
    expect(editing.document.page(0).annotations.single.rect.top,
        closeTo(700, 0.01));
  });
}
