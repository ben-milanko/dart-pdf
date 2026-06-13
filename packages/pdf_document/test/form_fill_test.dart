import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  PdfDocument fill(void Function(PdfEditor, PdfAcroForm) edit) {
    final doc = PdfDocument.open(buildAcroFormPdf());
    final editor = PdfEditor(doc);
    edit(editor, editor.acroForm!);
    return PdfDocument.open(editor.save());
  }

  String widgetAppearance(PdfDocument doc, PdfFormField field,
      [int index = 0]) {
    final cos = doc.cos;
    final ap = cos.resolve(field.widgets[index]['AP']);
    expect(ap, isA<CosDictionary>(), reason: 'widget must carry /AP');
    var n = cos.resolve((ap as CosDictionary)['N']);
    if (n is CosDictionary) {
      final state = cos.resolve(field.widgets[index]['AS']);
      n = cos.resolve(n[(state as CosName).value]);
    }
    expect(n, isA<CosStream>());
    return latin1.decode(cos.decodeStreamData(n as CosStream));
  }

  test('setTextValue updates /V and regenerates the appearance', () {
    final doc = fill((e, f) =>
        e.setTextValue(f.fieldNamed('name')!, 'John Doe'));
    final field = PdfAcroForm.of(doc)!.fieldNamed('name')!;
    expect(field.value, 'John Doe');

    final content = widgetAppearance(doc, field);
    expect(content, contains('/Tx BMC'));
    expect(content, contains('/Helv 12 Tf'));
    expect(content, contains('(John Doe) Tj'));
    expect(content, contains('W')); // clipped to the widget

    // BBox is the widget size in form space
    final n = doc.cos.resolve(
        (doc.cos.resolve(field.widgets[0]['AP']) as CosDictionary)['N']);
    final bbox = pdfRectFrom(doc.cos, (n as CosStream).dictionary['BBox']);
    expect(bbox, const PdfRect(0, 0, 228, 24));
  });

  test('resizeFormWidget rewrites /Rect and re-lays the value', () {
    final doc = fill((e, f) {
      e.setTextValue(f.fieldNamed('name')!, 'Resized');
      e.resizeFormWidget('name', 0, const PdfRect(72, 680, 172, 740));
    });
    final field = PdfAcroForm.of(doc)!.fieldNamed('name')!;
    expect(field.widgetRect(0), const PdfRect(72, 680, 172, 740));
    // the value survives and the appearance refits the new box
    final n = doc.cos.resolve(
        (doc.cos.resolve(field.widgets[0]['AP']) as CosDictionary)['N']);
    final bbox = pdfRectFrom(doc.cos, (n as CosStream).dictionary['BBox']);
    expect(bbox, const PdfRect(0, 0, 100, 60),
        reason: 'BBox tracks the new widget size, not the old');
    expect(widgetAppearance(doc, field), contains('(Resized) Tj'));
  });

  test('resizeFormWidget regenerates a check box mark at the new size', () {
    final doc = fill((e, f) {
      e.setCheckBoxValue(f.fieldNamed('agree')!, true);
      e.resizeFormWidget('agree', 0, const PdfRect(80, 540, 120, 580));
    });
    final field = PdfAcroForm.of(doc)!.fieldNamed('agree')!;
    expect(field.widgetRect(0), const PdfRect(80, 540, 120, 580));
    final cos = doc.cos;
    final n = cos.resolve(
        (cos.resolve(field.widgets[0]['AP']) as CosDictionary)['N'])
        as CosDictionary;
    final on = cos.resolve(n[field.onStates.first]) as CosStream;
    final bbox = pdfRectFrom(cos, on.dictionary['BBox']);
    expect(bbox, const PdfRect(0, 0, 40, 40));
    // the box stays checked through the resize
    expect(field.isChecked, isTrue);
  });

  test('resizeFormWidget on a missing field is a no-op', () {
    final doc = fill((e, f) =>
        e.resizeFormWidget('nope', 0, const PdfRect(0, 0, 10, 10)));
    expect(PdfAcroForm.of(doc)!.fieldNamed('name')!.widgetRect(0),
        const PdfRect(72, 700, 300, 724));
  });

  test('filling clears /NeedAppearances', () {
    final doc = fill((e, f) =>
        e.setTextValue(f.fieldNamed('name')!, 'x'));
    expect(PdfAcroForm.of(doc)!.needsAppearances, isFalse);
  });

  test('the appearance font references the /DR font', () {
    final doc = fill((e, f) =>
        e.setTextValue(f.fieldNamed('name')!, 'x'));
    final field = PdfAcroForm.of(doc)!.fieldNamed('name')!;
    final n = doc.cos.resolve(
        (doc.cos.resolve(field.widgets[0]['AP']) as CosDictionary)['N']);
    final resources =
        doc.cos.resolve((n as CosStream).dictionary['Resources']);
    final fonts =
        doc.cos.resolve((resources as CosDictionary)['Font']);
    final helv = doc.cos.resolve((fonts as CosDictionary)['Helv']);
    expect((doc.cos.resolve((helv as CosDictionary)['BaseFont']) as CosName)
        .value, 'Helvetica');
  });

  test('multiline text wraps and auto-sizes from a 0 Tf /DA', () {
    const text = 'The quick brown fox jumps over the lazy dog while the '
        'slow grey goose waddles past the riverbank fence';
    final doc = fill((e, f) =>
        e.setTextValue(f.fieldNamed('address')!, text));
    final field = PdfAcroForm.of(doc)!.fieldNamed('address')!;
    final content = widgetAppearance(doc, field);
    expect('Tj'.allMatches(content).length, greaterThanOrEqualTo(2));
    // auto-size resolved 0 to a real size
    final tf = RegExp(r'/Helv (\d+(?:\.\d+)?) Tf').firstMatch(content)!;
    expect(double.parse(tf.group(1)!), greaterThan(0));
  });

  test('single-line input flattens newlines', () {
    final doc = fill((e, f) =>
        e.setTextValue(f.fieldNamed('name')!, 'two\nlines'));
    final field = PdfAcroForm.of(doc)!.fieldNamed('name')!;
    expect(widgetAppearance(doc, field), contains('(two lines) Tj'));
  });

  test('checking a box sets /V and /AS to the on-state', () {
    final doc = fill((e, f) =>
        e.setCheckBoxValue(f.fieldNamed('agree')!, true));
    final field = PdfAcroForm.of(doc)!.fieldNamed('agree')!;
    expect(field.isChecked, isTrue);
    expect(field.value, 'Yes');
    expect((doc.cos.resolve(field.widgets[0]['AS']) as CosName).value, 'Yes');

    final cleared = fill((e, f) =>
        e.setCheckBoxValue(f.fieldNamed('agree')!, false));
    expect(PdfAcroForm.of(cleared)!.fieldNamed('agree')!.isChecked, isFalse);
  });

  test('a check box without /AP states gets generated appearances', () {
    final doc = PdfDocument.open(buildAcroFormPdf());
    final editor = PdfEditor(doc);
    final field = editor.acroForm!.fieldNamed('agree')!;
    field.dict.entries.remove('AP');
    editor.setCheckBoxValue(field, true);
    final saved = PdfDocument.open(editor.save());
    final reread = PdfAcroForm.of(saved)!.fieldNamed('agree')!;
    expect(reread.onStates, ['Yes']);
    final content = widgetAppearance(saved, reread);
    expect(content, contains('l')); // the check-mark polyline
    expect(content, contains('S'));
  });

  test('selecting a radio button flips every kid widget /AS', () {
    final doc = fill((e, f) =>
        e.setRadioValue(f.fieldNamed('color')!, 'Blue'));
    final field = PdfAcroForm.of(doc)!.fieldNamed('color')!;
    expect(field.value, 'Blue');
    expect((doc.cos.resolve(field.widgets[0]['AS']) as CosName).value, 'Off');
    expect((doc.cos.resolve(field.widgets[1]['AS']) as CosName).value, 'Blue');
  });

  test('an unknown radio state throws', () {
    final doc = PdfDocument.open(buildAcroFormPdf());
    final editor = PdfEditor(doc);
    expect(
        () => editor.setRadioValue(
            editor.acroForm!.fieldNamed('color')!, 'Green'),
        throwsArgumentError);
  });

  test('a combo box accepts display values and stores the export', () {
    final doc = fill((e, f) =>
        e.setChoiceValue(f.fieldNamed('size')!, 'Large'));
    final field = PdfAcroForm.of(doc)!.fieldNamed('size')!;
    expect(field.value, 'L'); // the export value
    expect(widgetAppearance(doc, field), contains('(Large) Tj'));
  });

  test('a non-option choice value throws without the Edit flag', () {
    final doc = PdfDocument.open(buildAcroFormPdf());
    final editor = PdfEditor(doc);
    expect(
        () => editor.setChoiceValue(
            editor.acroForm!.fieldNamed('size')!, 'Gigantic'),
        throwsArgumentError);
  });

  test('read-only fields refuse to be filled', () {
    final doc = PdfDocument.open(buildAcroFormPdf());
    final editor = PdfEditor(doc);
    expect(
        () => editor.setTextValue(
            editor.acroForm!.fieldNamed('serial')!, 'B-2000'),
        throwsStateError);
  });

  test('type mismatches throw before touching the document', () {
    final doc = PdfDocument.open(buildAcroFormPdf());
    final editor = PdfEditor(doc);
    expect(
        () => editor.setTextValue(editor.acroForm!.fieldNamed('agree')!, 'x'),
        throwsArgumentError);
    expect(
        () => editor.setCheckBoxValue(
            editor.acroForm!.fieldNamed('name')!, true),
        throwsArgumentError);
    expect(editor.hasChanges, isFalse);
  });

  test('the original bytes survive as a prefix (incremental update)', () {
    final original = buildAcroFormPdf();
    final editor = PdfEditor(PdfDocument.open(original));
    editor.setTextValue(editor.acroForm!.fieldNamed('name')!, 'incremental');
    final saved = editor.save();
    expect(saved.length, greaterThan(original.length));
    expect(saved.sublist(0, original.length), original);
  });

  test('multiline: true makes a single-line field wrap', () {
    const text = 'a value comfortably longer than the name field is wide, '
        'so wrapping must produce several lines';
    final doc = fill((e, f) =>
        e.setTextValue(f.fieldNamed('name')!, text, multiline: true));
    final field = PdfAcroForm.of(doc)!.fieldNamed('name')!;
    expect(field.isMultiline, isTrue);
    expect('Tj'.allMatches(widgetAppearance(doc, field)).length,
        greaterThanOrEqualTo(2));
  });

  test('non-Latin-1 values keep /V intact and sanitize the appearance', () {
    const text = 'checked ✓ 漢字';
    final doc =
        fill((e, f) => e.setTextValue(f.fieldNamed('name')!, text));
    final field = PdfAcroForm.of(doc)!.fieldNamed('name')!;
    // /V went out as UTF-16BE and reads back verbatim
    expect(field.value, text);
    // the byte-encoded appearance font can't show those glyphs: spaces
    final content = widgetAppearance(doc, field);
    expect(content, contains('(checked     ) Tj'));
    expect(content, isNot(contains('?')));
  });
}
