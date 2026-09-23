import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Multi-select list boxes (#933): the controller's multi-value fill and
/// the form layer's checkable option menu.
void main() {
  // 800px viewport over a 612pt page, fit to width
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  group('controller', () {
    test('setFormChoiceValues writes the whole selection', () {
      final editing = PdfEditingController(buildListBoxFormPdf());
      addTearDown(editing.dispose);
      expect(editing.setFormChoiceValues('toppings', ['Cheese', 'Pepperoni']),
          isTrue);
      expect(
          editing.acroForm!.fieldNamed('toppings')!.values, ['Cheese', 'pep']);
      // the same selection (display or export form) is not an edit
      expect(
          editing.setFormChoiceValues('toppings', ['pep', 'Cheese']), isFalse);
      // a single-select box refuses two values without throwing
      expect(editing.setFormChoiceValues('crust', ['Thin', 'Deep']), isFalse);
      expect(editing.canUndo, isTrue);
      editing.undo();
      expect(
          editing.acroForm!.fieldNamed('toppings')!.values, ['Ham', 'Olives']);
    });

    test('pickFormChoiceOption toggles on multi-select, replaces otherwise',
        () {
      final editing = PdfEditingController(buildListBoxFormPdf());
      addTearDown(editing.dispose);
      expect(editing.pickFormChoiceOption('toppings', 'Cheese'), isTrue);
      expect(editing.acroForm!.fieldNamed('toppings')!.values,
          ['Cheese', 'Ham', 'Olives']);
      expect(editing.pickFormChoiceOption('toppings', 'Ham'), isTrue);
      expect(editing.acroForm!.fieldNamed('toppings')!.values,
          ['Cheese', 'Olives']);

      expect(editing.pickFormChoiceOption('crust', 'Thin'), isTrue);
      expect(editing.pickFormChoiceOption('crust', 'Deep'), isTrue);
      expect(editing.acroForm!.fieldNamed('crust')!.values, ['Deep']);
    });
  });

  testWidgets('a multi-select list box opens a checkable menu that toggles',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = PdfEditingController(buildListBoxFormPdf());
    final viewer = PdfViewerController();
    addTearDown(session.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          controller: viewer,
          editing: session,
        ),
      ),
    ));
    await tester.pump();

    Future<void> openMenu() async {
      await tester.tapAt(view(172, 650)); // the toppings list box
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    await openMenu();
    CheckedPopupMenuItem<String> item(String export) =>
        tester.widget<CheckedPopupMenuItem<String>>(
            find.byKey(ValueKey('pdf-form-option-$export')));
    expect(item('Ham').checked, isTrue);
    expect(item('Olives').checked, isTrue);
    expect(item('Cheese').checked, isFalse);

    await tester.tap(find.byKey(const ValueKey('pdf-form-option-pep')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(session.acroForm!.fieldNamed('toppings')!.values,
        ['Ham', 'pep', 'Olives']);

    // the menu reopens with the new selection checked; a checked pick
    // takes that option back out
    await openMenu();
    expect(item('pep').checked, isTrue);
    await tester.tap(find.byKey(const ValueKey('pdf-form-option-Ham')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(session.acroForm!.fieldNamed('toppings')!.values, ['pep', 'Olives']);
  });
}
