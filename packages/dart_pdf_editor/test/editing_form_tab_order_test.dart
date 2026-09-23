import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tab / Shift+Tab walks the form's fields in the page /Tabs order, across
/// pages, scrolling each into view and opening its editor (#932).
void main() {
  // 800px viewport over a 612pt page, fit to width
  const scale = 800 / 612;
  const editorKey = ValueKey('pdf-form-text-editor');
  const ringKey = ValueKey('pdf-form-focus-ring');

  Future<(PdfEditingController, PdfViewerController)> pumpViewer(
      WidgetTester tester,
      {FocusNode? outside}) async {
    SharedPreferences.setMockInitialValues({});
    // /Tabs /R on page 0 (first, city, agree, color#0, color#1), then page
    // 1 in /Annots order (notes, size); read-only / hidden / push-button /
    // signature fields are not stops
    final session = PdfEditingController(buildTabOrderFormPdf());
    final viewer = PdfViewerController();
    addTearDown(session.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          // an unrelated focusable widget: Tab must not traverse to it
          TextButton(
            focusNode: outside,
            onPressed: () {},
            child: const Text('outside'),
          ),
          Expanded(
            child: PdfViewer(
              initialFit: PdfViewerFit.width,
              controller: viewer,
              editing: session,
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();
    return (session, viewer);
  }

  Future<void> settle(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(milliseconds: 100));

  Future<void> tab(WidgetTester tester, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester);
  }

  Rect editorRect(WidgetTester tester) => tester.getRect(find.byKey(editorKey));
  Rect ringRect(WidgetTester tester) => tester.getRect(find.byKey(ringKey));

  /// The viewer's viewport in global coordinates.
  Rect viewport(WidgetTester tester) => tester.getRect(find.byType(PdfViewer));

  void expectOnScreen(WidgetTester tester, Rect rect) {
    final view = viewport(tester);
    expect(rect.top, greaterThanOrEqualTo(view.top - 0.5), reason: '$rect');
    expect(rect.bottom, lessThanOrEqualTo(view.bottom + 0.5), reason: '$rect');
  }

  String? value(PdfEditingController s, String name) =>
      s.acroForm!.fieldNamed(name)!.value;

  testWidgets('Tab walks the fields in /Tabs order across pages',
      (tester) async {
    final outside = FocusNode();
    addTearDown(outside.dispose);
    final (session, viewer) = await pumpViewer(tester, outside: outside);
    final origin = viewport(tester).topLeft;

    // click into the first field (row 1, left) and type
    await tester.tapAt(origin + const Offset(186 * scale, (792 - 712) * scale));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(editorKey), findsOneWidget);
    await tester.enterText(find.byKey(editorKey), 'Ada');

    // Tab commits it and opens city (row 1, right) - not the /Annots order
    await tab(tester);
    expect(value(session, 'first'), 'Ada');
    expect(editorRect(tester).left - origin.dx, closeTo(320 * scale, 1));
    expect(outside.hasFocus, isFalse,
        reason: 'Tab stays in the form, not the app focus traversal');
    await tester.enterText(find.byKey(editorKey), 'Paris');

    // Tab to the check box: a focus ring, Space toggles it. The read-only
    // `ro` field beside it is skipped.
    await tab(tester);
    expect(value(session, 'city'), 'Paris');
    expect(find.byKey(editorKey), findsNothing);
    expect(ringRect(tester).center.dx - origin.dx, closeTo(82 * scale, 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(session.acroForm!.fieldNamed('agree')!.isChecked, isTrue);

    // radio buttons, one stop each (hidden / push button / signature skipped)
    await tab(tester);
    expect(ringRect(tester).center.dx - origin.dx, closeTo(82 * scale, 2));
    await tab(tester);
    expect(ringRect(tester).center.dx - origin.dx, closeTo(130 * scale, 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(value(session, 'color'), 'Blue');

    // next is page 1's multi-line field: the viewer scrolls it into view
    expect(viewer.currentPage, 0);
    final before = viewer.scrollMetrics!.pixels;
    await tab(tester);
    expect(find.byKey(ringKey), findsNothing);
    expect(find.byKey(editorKey), findsOneWidget);
    expect(viewer.scrollMetrics!.pixels, greaterThan(before));
    final notes = editorRect(tester);
    expectOnScreen(tester, notes);
    expect(notes.width, closeTo(468 * scale, 1));
    await tester.enterText(find.byKey(editorKey), 'line one\nline two');

    // Tab in a multi-line field moves on rather than typing a tab
    await tab(tester);
    expect(value(session, 'notes'), 'line one\nline two');
    // the combo box opens its menu; picking commits, Tab carries on
    expect(find.byKey(const ValueKey('pdf-form-option-Large')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-form-option-Large')));
    await settle(tester);
    expect(value(session, 'size'), 'Large');
    expectOnScreen(tester, ringRect(tester));

    // past the last field Tab wraps to the first, scrolling back up
    await tab(tester);
    expect(find.byKey(editorKey), findsOneWidget);
    expect(viewer.currentPage, 0);
    expectOnScreen(tester, editorRect(tester));
    expect(editorRect(tester).left - origin.dx, closeTo(72 * scale, 1));
    expect(tester.widget<TextField>(find.byKey(editorKey)).controller!.text,
        'Ada');

    // Shift+Tab goes back, wrapping to the last field (the combo box)
    await tab(tester, shift: true);
    expect(find.byKey(editorKey), findsNothing);
    expect(viewer.currentPage, 1);
    expect(find.byKey(const ValueKey('pdf-form-option-Large')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // and Shift+Tab again lands on the multi-line field before it
    await tab(tester, shift: true);
    expect(editorRect(tester).width, closeTo(468 * scale, 1));
    expect(tester.widget<TextField>(find.byKey(editorKey)).controller!.text,
        'line one\nline two');
  });

  testWidgets('Enter still commits a single-line field', (tester) async {
    final (session, _) = await pumpViewer(tester);
    final origin = viewport(tester).topLeft;
    await tester.tapAt(origin + const Offset(186 * scale, (792 - 712) * scale));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(editorKey), 'Grace');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(value(session, 'first'), 'Grace');
    expect(find.byKey(editorKey), findsNothing);
  });
}
