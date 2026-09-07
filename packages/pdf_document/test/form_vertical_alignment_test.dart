import 'dart:convert';
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

const _key = 'DartPdfTextVerticalAlignment';

(PdfEditor, PdfFormField) _fixture({bool multiline = true}) {
  final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
  final field = editor.addTextField(
      0, 'notes', const PdfRect(100, 200, 300, 260),
      multiline: multiline);
  editor.setTextFieldStyle(field, fontSize: 10);
  return (editor, field);
}

PdfFormField _field(PdfDocument doc) =>
    PdfAcroForm.of(doc)!.fieldNamed('notes')!;

String _appearance(PdfDocument doc, PdfFormField field, [int index = 0]) {
  final ap = doc.cos.resolve(field.widgets[index]['AP']) as CosDictionary;
  final stream = doc.cos.resolve(ap['N']) as CosStream;
  return latin1.decode(doc.cos.decodeStreamData(stream));
}

List<(double, double)> _baselines(String content) {
  var x = 0.0, y = 0.0;
  return [
    for (final m in RegExp(r'(-?[\d.]+) (-?[\d.]+) Td').allMatches(content))
      (x += double.parse(m[1]!), y += double.parse(m[2]!)),
  ];
}

void main() {
  test('explicit baseline overrides vertical mode and preserves line spacing',
      () {
    final w = ContentWriter();
    writePdfTextBox(w, const PdfRect(10, 20, 110, 70), ['a', 'b'],
        font: PdfStandardFont.helvetica,
        fontSize: 10,
        align: PdfTextAlign.left,
        padding: 3,
        lineHeight: 12,
        vAlign: PdfTextBoxVAlign.centerLine,
        firstBaselineY: 42);
    expect(
        _baselines(latin1.decode(w.takeBytes())), [(13.0, 42.0), (13.0, 30.0)]);
  });

  for (final multiline in [false, true]) {
    test('no preference preserves legacy placement (multiline=$multiline)', () {
      final (editor, field) = _fixture(multiline: multiline);
      editor.setTextValue(field, 'a\nb');
      final out = PdfDocument.open(editor.save());
      final saved = _field(out);
      expect(saved.textVerticalAlignment, isNull);
      expect(saved.dict.containsKey(_key), isFalse);
      expect(_baselines(_appearance(out, saved)).first.$2,
          closeTo(multiline ? 50.82 : 26.41, 0.001));
    });

    for (final alignment in PdfFormTextVerticalAlignment.values) {
      for (final horizontal in PdfTextAlign.values) {
        test('$alignment / $horizontal (multiline=$multiline)', () {
          final (editor, field) = _fixture(multiline: multiline);
          editor.setTextFieldStyle(field, align: horizontal);
          editor.setTextValue(field, multiline ? 'a\nb' : 'a',
              verticalAlignment: alignment);
          final out = PdfDocument.open(editor.save());
          final saved = _field(out);
          expect(saved.textVerticalAlignment, alignment);
          expect(saved.isMultiline, multiline);
          expect(saved.quadding, horizontal.quadding);
          expect(saved.widgetRect(0), const PdfRect(100, 200, 300, 260));
          expect(PdfAcroForm.of(out)!.needsAppearances, isFalse);
          final positions = _baselines(_appearance(out, saved));
          final expectedY = switch (alignment) {
            PdfFormTextVerticalAlignment.top => 50.82,
            PdfFormTextVerticalAlignment.center => multiline ? 33.57 : 27.82,
            PdfFormTextVerticalAlignment.bottom => multiline ? 16.32 : 4.82,
          };
          expect(positions.first.$2, closeTo(expectedY, 0.001));
          final width = PdfStandardFont.helvetica.measure('a', 10);
          final expectedX = switch (horizontal) {
            PdfTextAlign.left => 2.0,
            PdfTextAlign.center => (200 - width) / 2,
            PdfTextAlign.right => 198 - width,
          };
          expect(positions.first.$1, closeTo(expectedX, 0.001));
          expect(positions, hasLength(multiline ? 2 : 1));
          if (multiline) {
            expect(
                positions.first.$2 - positions.last.$2, closeTo(11.5, 0.001));
          }
        });
      }
    }
  }

  test('saved style survives reopen, refill, restyle, resize and rename', () {
    final (editor, field) = _fixture();
    editor.setTextFieldStyle(field,
        verticalAlignment: PdfFormTextVerticalAlignment.bottom);
    final reopened = PdfEditor(PdfDocument.open(editor.save()));
    final saved = _field(reopened.document);
    expect(saved.textVerticalAlignment, PdfFormTextVerticalAlignment.bottom);
    reopened.setTextValue(saved, 'a\nb');
    reopened.setTextFieldStyle(saved, color: 0xFF0000, fontSize: 12);
    reopened.resizeFormWidget('notes', 0, const PdfRect(100, 200, 300, 300));
    reopened.renameField(saved, 'renamed');
    final out = PdfDocument.open(reopened.save());
    final result = PdfAcroForm.of(out)!.fieldNamed('renamed')!;
    expect(result.textVerticalAlignment, PdfFormTextVerticalAlignment.bottom);
    expect(result.value, 'a\nb');
    expect(result.appearanceColor, 0xFF0000);
    expect(_baselines(_appearance(out, result)).last.$2, closeTo(5.384, 0.001));
  });

  test('fill can replace a saved preference and independently toggle wrapping',
      () {
    final (editor, field) = _fixture();
    editor.setTextFieldStyle(field,
        verticalAlignment: PdfFormTextVerticalAlignment.bottom);
    editor.setTextValue(field, 'a\nb',
        multiline: false,
        verticalAlignment: PdfFormTextVerticalAlignment.center);
    final out = PdfDocument.open(editor.save());
    expect(_field(out).isMultiline, isFalse);
    expect(
        _field(out).textVerticalAlignment, PdfFormTextVerticalAlignment.center);
    expect(_appearance(out, _field(out)), contains('(a b) Tj'));
  });

  for (final multiline in [false, true]) {
    test('clear restores legacy placement (multiline=$multiline)', () {
      final (editor, field) = _fixture(multiline: multiline);
      editor.setTextValue(field, 'a\nb',
          verticalAlignment: PdfFormTextVerticalAlignment.bottom);
      final reopened = PdfEditor(PdfDocument.open(editor.save()));
      reopened.clearTextFieldVerticalAlignment(_field(reopened.document));
      final out = PdfDocument.open(reopened.save());
      final saved = _field(out);
      expect(saved.textVerticalAlignment, isNull);
      expect(saved.dict.containsKey(_key), isFalse);
      expect(saved.value, 'a\nb');
      expect(saved.isMultiline, multiline);
      expect(_baselines(_appearance(out, saved)).first.$2,
          closeTo(multiline ? 50.82 : 26.41, 0.001));
    });
  }

  test('malformed and unknown metadata is ignored and preserved on refill', () {
    for (final raw in <CosObject>[
      CosString.fromText('future-value'),
      const CosInteger(2),
      const CosName('bottom'),
      CosDictionary({}),
    ]) {
      final (editor, field) = _fixture();
      field.dict[_key] = raw;
      editor.setTextValue(field, 'a\nb');
      final out = PdfDocument.open(editor.save());
      expect(_field(out).textVerticalAlignment, isNull);
      expect(_field(out).dict.containsKey(_key), isTrue);
      expect(_baselines(_appearance(out, _field(out))).first.$2,
          closeTo(50.82, 0.001));
    }
  });

  test('overflow retains the beginning and clips without moving the field', () {
    for (final alignment in PdfFormTextVerticalAlignment.values) {
      final (editor, field) = _fixture();
      editor.resizeFormWidget('notes', 0, const PdfRect(100, 200, 130, 210));
      editor.setTextValue(field, 'longunbrokenword\na\nb',
          verticalAlignment: alignment);
      final out = PdfDocument.open(editor.save());
      final content = _appearance(out, _field(out));
      expect(_baselines(content).first, (2.0, 0.82));
      expect(content, contains('1 1 28 8 re'));
      expect(content, contains('W'));
      expect(content, contains('(longunbrokenword) Tj'));
      expect(_field(out).value, 'longunbrokenword\na\nb');
      expect(_field(out).appearanceFontSize, 10);
    }
  });

  test('wrapping, line endings and blank lines precede block alignment', () {
    final (editor, field) = _fixture();
    editor.resizeFormWidget('notes', 0, const PdfRect(100, 200, 130, 280));
    editor.setTextValue(field, 'aa bb cc\r\n\rdd\n',
        verticalAlignment: PdfFormTextVerticalAlignment.bottom);
    final out = PdfDocument.open(editor.save());
    final content = _appearance(out, _field(out));
    expect(RegExp(r'\((.*?)\) Tj').allMatches(content).map((m) => m[1]),
        ['aa bb', 'cc', '', 'dd', '']);
    expect(_baselines(content).last.$2, closeTo(4.82, 0.001));
  });

  test(
      'auto-size retains its minimum and overflowing blocks remain top anchored',
      () {
    final (editor, field) = _fixture();
    editor.resizeFormWidget('notes', 0, const PdfRect(100, 200, 130, 208));
    editor.setTextFieldStyle(field,
        autoSize: true, verticalAlignment: PdfFormTextVerticalAlignment.bottom);
    editor.setTextValue(field, 'a\nb\nc');
    final out = PdfDocument.open(editor.save());
    final content = _appearance(out, _field(out));
    expect(content, contains('/Helv 4 Tf'));
    expect(_baselines(content).first.$2, closeTo(3.128, 0.001));
    expect(_field(out).appearanceFontSize, 0);
  });

  test('one field preference updates widgets of different sizes', () {
    final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
    final field = editor.acroForm!.fieldNamed('color')!;
    // Reuse the fixture's parent + two widget structure as a text field.
    field.dict['FT'] = const CosName('Tx');
    field.dict['Ff'] = const CosInteger(0);
    editor.resizeFormWidget('color', 0, const PdfRect(72, 400, 272, 440));
    editor.resizeFormWidget('color', 1, const PdfRect(72, 500, 172, 560));
    editor.setTextFieldStyle(field, fontSize: 10);
    editor.setTextValue(field, 'Shared',
        verticalAlignment: PdfFormTextVerticalAlignment.bottom);
    final out = PdfDocument.open(editor.save());
    final saved = PdfAcroForm.of(out)!.fieldNamed('color')!;
    expect(saved.widgets, hasLength(2));
    expect(saved.value, 'Shared');
    expect(saved.textVerticalAlignment, PdfFormTextVerticalAlignment.bottom);
    for (var i = 0; i < 2; i++) {
      expect(saved.widgets[i].containsKey(_key), isFalse);
      expect(_baselines(_appearance(out, saved, i)).single.$2,
          closeTo(4.82, 0.001));
    }
  });

  for (final rotation in [90, 180, 270]) {
    test('rotation $rotation preserves preference in oriented widget space',
        () {
      final (editor, field) = _fixture(multiline: false);
      editor.setTextValue(field, 'a',
          verticalAlignment: PdfFormTextVerticalAlignment.bottom);
      final reopened = PdfEditor(PdfDocument.open(editor.save()));
      reopened.rotatePages([0], rotation);
      final out = PdfDocument.open(reopened.save());
      final saved = _field(out);
      expect(saved.textVerticalAlignment, PdfFormTextVerticalAlignment.bottom);
      final rect = saved.widgetRect(0)!;
      final visualBottom =
          rotation == 180 ? 0.0 : (rect.height - rect.width) / 2;
      expect(_baselines(_appearance(out, saved)).single.$2,
          closeTo(visualBottom + 4.82, 0.001));
      expect(_appearance(out, saved), contains('cm'));
    });
  }

  test('embedded font placement survives reopening without live font objects',
      () {
    final (editor, field) = _fixture();
    final font = PdfEmbeddedFont.parse(
        File('test/fonts/DejaVuSans.ttf').readAsBytesSync());
    editor.setTextFieldStyle(field,
        font: font, verticalAlignment: PdfFormTextVerticalAlignment.bottom);
    final reopened = PdfEditor(PdfDocument.open(editor.save()));
    reopened.setTextValue(_field(reopened.document), 'Wörld\nAgain');
    final out = PdfDocument.open(reopened.save());
    final content = _appearance(out, _field(out));
    expect(content, contains('> Tj'));
    expect(_baselines(content).last.$2, closeTo(12 - font.ascent / 100, 0.001));
  });

  test('rejects non-text and read-only fields before changing their metadata',
      () {
    final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
    final button = editor.acroForm!.fieldNamed('agree')!;
    expect(
        () => editor.setTextFieldStyle(button,
            verticalAlignment: PdfFormTextVerticalAlignment.bottom),
        throwsArgumentError);
    expect(() => editor.clearTextFieldVerticalAlignment(button),
        throwsArgumentError);
    final field = editor.acroForm!.fieldNamed('name')!;
    field.dict['Ff'] = const CosInteger(PdfFormField.readOnlyFlag);
    expect(
        () => editor.setTextValue(field, 'changed',
            verticalAlignment: PdfFormTextVerticalAlignment.bottom),
        throwsStateError);
    expect(
        () => editor.clearTextFieldVerticalAlignment(field), throwsStateError);
    expect(field.dict.containsKey(_key), isFalse);
    expect(button.dict.containsKey(_key), isFalse);
  });

  test('flattening keeps the saved appearance placement', () {
    final (editor, field) = _fixture();
    editor.setTextValue(field, 'a\nb',
        verticalAlignment: PdfFormTextVerticalAlignment.bottom);
    final reopened = PdfEditor(PdfDocument.open(editor.save()));
    final before = _appearance(reopened.document, _field(reopened.document));
    reopened.flattenForm();
    final out = PdfDocument.open(reopened.save());
    expect(PdfAcroForm.of(out)?.fields ?? [], isEmpty);
    final resources =
        out.cos.resolve(out.page(0).dict['Resources']) as CosDictionary;
    final xobjects = out.cos.resolve(resources['XObject']) as CosDictionary;
    final appearances = [
      for (final entry in xobjects.entries.entries)
        if (entry.key.startsWith('FlatAnnot'))
          latin1.decode(out.cos
              .decodeStreamData(out.cos.resolve(entry.value) as CosStream)),
    ];
    expect(appearances, contains(before));
  });
}
