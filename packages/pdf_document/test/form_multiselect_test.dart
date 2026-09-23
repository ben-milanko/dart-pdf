import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  PdfDocument fill(void Function(PdfEditor, PdfAcroForm) edit) {
    final editor = PdfEditor(PdfDocument.open(buildListBoxFormPdf()));
    edit(editor, editor.acroForm!);
    return PdfDocument.open(editor.save());
  }

  String appearance(PdfDocument doc, PdfFormField field) {
    final cos = doc.cos;
    final ap = cos.resolve(field.widgets.first['AP']) as CosDictionary;
    final n = cos.resolve(ap['N']) as CosStream;
    return latin1.decode(cos.decodeStreamData(n));
  }

  // The exact operator the generator writes for the selection highlight.
  final highlightOp =
      latin1.decode((ContentWriter()..fillColor(0x99C1DA)).takeBytes()).trim();

  int highlights(String content) => highlightOp.allMatches(content).length;

  test('reads the MultiSelect flag and a /V array written elsewhere', () {
    final form = PdfAcroForm.of(PdfDocument.open(buildListBoxFormPdf()))!;
    final toppings = form.fieldNamed('toppings')!;
    expect(toppings.type, PdfFieldType.listBox);
    expect(toppings.isMultiSelect, isTrue);
    expect(toppings.values, ['Ham', 'Olives']);
    expect(toppings.value, 'Ham', reason: 'value stays the first entry');
    // no /I in the file: indices derive from the /V export values
    expect(toppings.selectedIndices, [1, 3]);
    expect(toppings.topIndex, 0);

    final crust = form.fieldNamed('crust')!;
    expect(crust.isMultiSelect, isFalse);
    expect(crust.values, isEmpty);
    expect(crust.selectedIndices, isEmpty);
  });

  test('setChoiceValues round-trips a /V array with sorted /I', () {
    final doc = fill((e, f) => e.setChoiceValues(
        f.fieldNamed('toppings')!, ['Onion', 'Pepperoni', 'Cheese', 'Onion']));
    final field = PdfAcroForm.of(doc)!.fieldNamed('toppings')!;
    // option order, export values (Pepperoni's export is "pep")
    expect(field.values, ['Cheese', 'pep', 'Onion']);
    expect(doc.cos.resolve(field.dict['V']), isA<CosArray>());
    final i = doc.cos.resolve(field.dict['I']) as CosArray;
    expect([for (final item in i.items) (item as CosInteger).value], [0, 2, 4]);
    expect(field.selectedIndices, [0, 2, 4]);
  });

  test('one value is written as a plain string, none clears /V and /I', () {
    var doc = fill(
        (e, f) => e.setChoiceValues(f.fieldNamed('toppings')!, ['Pepperoni']));
    var field = PdfAcroForm.of(doc)!.fieldNamed('toppings')!;
    expect(doc.cos.resolve(field.dict['V']), isA<CosString>());
    expect(field.values, ['pep']);
    expect(field.selectedIndices, [2]);

    doc = fill((e, f) => e.setChoiceValues(f.fieldNamed('toppings')!, []));
    field = PdfAcroForm.of(doc)!.fieldNamed('toppings')!;
    expect(field.values, isEmpty);
    expect(field.value, isNull);
    expect(field.dict.containsKey('I'), isFalse);
    expect(highlights(appearance(doc, field)), 0);
  });

  test('the appearance highlights every selected row', () {
    final doc = fill((e, f) => e.setChoiceValues(
        f.fieldNamed('toppings')!, ['Cheese', 'Olives', 'Onion']));
    final field = PdfAcroForm.of(doc)!.fieldNamed('toppings')!;
    final content = appearance(doc, field);
    expect(highlights(content), 3);
    for (final row in ['Cheese', 'Ham', 'Pepperoni', 'Olives', 'Onion']) {
      expect(content, contains('($row) Tj'), reason: 'every row is drawn');
    }
    expect(content, contains('/Helv 10 Tf'));
  });

  test('a single-select list box draws its rows with one highlight', () {
    final doc =
        fill((e, f) => e.setChoiceValue(f.fieldNamed('crust')!, 'Deep'));
    final field = PdfAcroForm.of(doc)!.fieldNamed('crust')!;
    expect(field.value, 'Deep');
    expect(field.selectedIndices, [1]);
    final content = appearance(doc, field);
    expect(highlights(content), 1);
    expect(content, contains('(Thin) Tj'));
    expect(content, contains('(Stuffed) Tj'));
  });

  test('/TI scrolls the first selected row into view', () {
    final doc = fill((e, f) {
      // two rows tall at 10pt
      e.resizeFormWidget('toppings', 0, const PdfRect(72, 600, 272, 630));
      e.setChoiceValues(
          e.acroForm!.fieldNamed('toppings')!, ['Olives', 'Onion']);
    });
    final field = PdfAcroForm.of(doc)!.fieldNamed('toppings')!;
    expect(field.topIndex, 3);
    final content = appearance(doc, field);
    expect(content, contains('(Olives) Tj'));
    expect(content, isNot(contains('(Cheese) Tj')));
    expect(highlights(content), 2);
  });

  test('a stale /I that disagrees with /V is ignored', () {
    final editor = PdfEditor(PdfDocument.open(buildListBoxFormPdf()));
    final field = editor.acroForm!.fieldNamed('toppings')!;
    field.dict['I'] = CosArray([const CosInteger(0)]);
    expect(field.selectedIndices, [1, 3]);
    field.dict['I'] = CosArray([const CosInteger(3), const CosInteger(1)]);
    expect(field.selectedIndices, [1, 3]);
  });

  test('multiple values need the MultiSelect flag; unknown values throw', () {
    final editor = PdfEditor(PdfDocument.open(buildListBoxFormPdf()));
    final form = editor.acroForm!;
    expect(
        () =>
            editor.setChoiceValues(form.fieldNamed('crust')!, ['Thin', 'Deep']),
        throwsArgumentError);
    expect(
        () => editor.setChoiceValues(
            form.fieldNamed('toppings')!, ['Cheese', 'Anchovy']),
        throwsArgumentError);
    expect(editor.hasChanges, isFalse);
    // one value on a single-select box is setChoiceValue
    editor.setChoiceValues(form.fieldNamed('crust')!, ['Stuffed']);
    expect(form.fieldNamed('crust')!.values, ['Stuffed']);
  });
}
