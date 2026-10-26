// The sticky-note popup: a note's text shows in a card beside its icon
// while the mouse rests on it, and for as long as the note is selected.

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 800px viewport over a 612pt page (fit-width)
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  // addNote(0, 100, 700, ...) puts a 20pt icon at page x 100..120,
  // y 680..700
  final onNote = view(110, 690);
  final offNote = view(300, 400);
  final popup = find.byKey(const ValueKey('pdf-note-popup'));

  Future<PdfEditingController> pumpViewer(
    WidgetTester tester, {
    bool showNotePopups = true,
    void Function(PdfEditingController)? setUp,
  }) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..preferences.author = 'Ann'
      ..addNote(0, 100, 700, 'Check the fault isolation');
    setUp?.call(editing);
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
            showNotePopups: showNotePopups,
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(5, 5));
    addTearDown(g.removePointer);
    await tester.pump();
    return g;
  }

  testWidgets('hovering a note pops up its text after a short delay',
      (tester) async {
    await pumpViewer(tester);
    final g = await mouse(tester);
    await g.moveTo(onNote);
    await tester.pump();
    expect(popup, findsNothing, reason: 'a sweeping pointer flashes nothing');

    await tester.pump(const Duration(milliseconds: 350));
    expect(popup, findsOneWidget);
    expect(find.text('Check the fault isolation'), findsOneWidget);
    expect(find.textContaining('Ann'), findsOneWidget);
    // beside the icon, not over it
    expect(tester.getTopLeft(popup).dx, greaterThan(view(120, 0).dx));

    await g.moveTo(offNote);
    await tester.pump();
    expect(popup, findsOneWidget, reason: 'a grace period to reach the card');
    await tester.pump(const Duration(milliseconds: 300));
    expect(popup, findsNothing);
  });

  testWidgets('the card stays up while the pointer is on it', (tester) async {
    await pumpViewer(tester);
    final g = await mouse(tester);
    await g.moveTo(onNote);
    await tester.pump(const Duration(milliseconds: 350));
    expect(popup, findsOneWidget);

    await g.moveTo(tester.getCenter(popup));
    await tester.pump(const Duration(milliseconds: 600));
    expect(popup, findsOneWidget);
  });

  testWidgets('a selected note keeps its card up and lists replies',
      (tester) async {
    final editing = await pumpViewer(tester);
    final note = editing.document.page(0).annotations.single;
    editing.replyToAnnotation(0, note, 'Isolated at CB12');
    editing.tool = PdfEditTool.select;
    expect(editing.selectAnnotationAt(0, 110, 690), isTrue);
    await tester.pump();

    expect(popup, findsOneWidget);
    expect(find.text('Check the fault isolation'), findsOneWidget);
    expect(find.text('Isolated at CB12'), findsOneWidget);

    editing.clearAnnotationSelection();
    await tester.pump();
    expect(popup, findsNothing);
  });

  testWidgets('no card while a drawing tool is armed', (tester) async {
    final editing = await pumpViewer(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    final g = await mouse(tester);
    await g.moveTo(onNote);
    await tester.pump(const Duration(milliseconds: 350));
    expect(popup, findsNothing);
  });

  testWidgets('showNotePopups: false turns the card off', (tester) async {
    await pumpViewer(tester, showNotePopups: false);
    final g = await mouse(tester);
    await g.moveTo(onNote);
    await tester.pump(const Duration(milliseconds: 350));
    expect(popup, findsNothing);
  });

  testWidgets('the card text is selectable and copies with the keyboard',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpViewer(tester);
    final g = await mouse(tester);
    await g.moveTo(onNote);
    await tester.pump(const Duration(milliseconds: 350));
    expect(popup, findsOneWidget);
    expect(find.descendant(of: popup, matching: find.byType(SelectableRegion)),
        findsNothing,
        reason: 'the selection region wraps the card, not the reverse');
    expect(find.ancestor(of: popup, matching: find.byType(SelectionArea)),
        findsOneWidget);

    // drag across the comment from its start to its end
    final text = find.byKey(const ValueKey('pdf-note-popup-text'));
    await g.moveTo(tester.getTopLeft(text) + const Offset(1, 4));
    await g.down(tester.getTopLeft(text) + const Offset(1, 4));
    await tester.pump();
    // wander off the card mid-drag: the card stays up
    await g.moveTo(tester.getBottomRight(popup) + const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 600));
    expect(popup, findsOneWidget);
    await g.moveTo(tester.getBottomRight(text) - const Offset(1, 4));
    await g.up();
    await tester.pump();

    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(copied, 'Check the fault isolation');
  });

  testWidgets('a shape carrying a comment pops up the same card',
      (tester) async {
    final editing = await pumpViewer(tester, setUp: (editing) {
      editing
        ..addRectangle(0, const PdfRect(200, 400, 300, 500))
        ..addRectangle(0, const PdfRect(200, 100, 300, 200));
    });
    // comment the first rectangle only (slot 1; the note is slot 0)
    editing.tool = PdfEditTool.select;
    expect(editing.selectAnnotation(0, 1), isTrue);
    expect(editing.setSelectedContents('Check the clearance here'), isTrue);
    editing.clearAnnotationSelection();
    await tester.pump(const Duration(milliseconds: 300));

    final g = await mouse(tester);
    await g.moveTo(view(250, 450));
    await tester.pump(const Duration(milliseconds: 350));
    expect(popup, findsOneWidget);
    expect(find.text('Check the clearance here'), findsOneWidget);

    // a bare shape has nothing to show
    await g.moveTo(view(250, 150));
    await tester.pump(const Duration(milliseconds: 600));
    expect(popup, findsNothing);
  });

  test('eligibility: notes and commented markups, not free text or replies',
      () {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addNote(0, 100, 700, 'A note')
      ..addRectangle(0, const PdfRect(200, 400, 300, 500))
      ..addFreeText(0, const PdfRect(200, 200, 300, 260), 'Shown on page');
    addTearDown(editing.dispose);
    final annotations = editing.document.page(0).annotations;
    expect(pdfIsNotePopupTarget(annotations[0]), isTrue);
    expect(pdfIsNotePopupTarget(annotations[1]), isFalse,
        reason: 'a shape without a comment has nothing to show');
    expect(pdfIsNotePopupTarget(annotations[2]), isFalse,
        reason: 'free text already shows its contents on the page');
    editing.replyToAnnotation(0, annotations[0], 'A reply');
    final reply =
        editing.document.page(0).annotations.firstWhere((a) => a.isReply);
    expect(pdfIsNotePopupTarget(reply), isFalse);
  });

  testWidgets('the layout flips the card left of an icon near the edge', (
    tester,
  ) async {
    const delegate = PdfNotePopupLayout(Rect.fromLTWH(760, 100, 24, 24));
    final at = delegate.getPositionForChild(
        const Size(800, 600), const Size(200, 100));
    expect(at, const Offset(760 - 8 - 200, 100));
  });
}
