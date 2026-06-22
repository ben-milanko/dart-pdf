import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// 2x2 RGBA PNG (from png_test.dart): red, half-green / transparent blue,
// near-black at alpha 77
final _png = base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGUlEQVR4nGP4z8DwHwgb'
    'WBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

void main() {
  group('field creation', () {
    test('addTextField creates the AcroForm on a form-less document', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc);
      final field = editor.addTextField(
          0, 'notes', const PdfRect(50, 600, 350, 640),
          multiline: true);
      expect(field.type, PdfFieldType.text);
      expect(field.isMultiline, isTrue);
      editor.setTextValue(field, 'hello forms');

      final out = PdfDocument.open(editor.save());
      final form = PdfAcroForm.of(out)!;
      final reread = form.fieldNamed('notes')!;
      expect(reread.value, 'hello forms');
      expect(form.defaultResources, isNotNull,
          reason: 'generated /AcroForm carries /DR');
      final info = form.describeFields().single;
      expect(info.pageIndex, 0);
      expect(info.rect, const PdfRect(50, 600, 350, 640));
    });

    test('addCheckBoxField generates check appearances and fills', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc);
      final field =
          editor.addCheckBoxField(0, 'done', const PdfRect(50, 500, 70, 520));
      expect(field.onStates, ['Yes']);
      editor.setCheckBoxValue(field, true);

      final out = PdfDocument.open(editor.save());
      final reread = PdfAcroForm.of(out)!.fieldNamed('done')!;
      expect(reread.isChecked, isTrue);
    });

    test('field names must be unique', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      expect(
          () => editor.addTextField(0, 'name', const PdfRect(0, 0, 10, 10)),
          throwsArgumentError);
    });
  });

  group('image buttons', () {
    test('setButtonImage builds an aspect-fit appearance with /SMask', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc);
      // 100x40 button, square image → 40x40 centered at x 30
      final field = editor.addPushButtonField(
          0, 'user/signature', const PdfRect(100, 400, 200, 440));
      editor.setButtonImage(field, PdfEmbeddableImage.png(_png));

      final out = PdfDocument.open(editor.save());
      final reread = PdfAcroForm.of(out)!.fieldNamed('user/signature')!;
      final ap = out.cos.resolve(reread.widgets[0]['AP']) as CosDictionary;
      final n = out.cos.resolve(ap['N']) as CosStream;
      final content = latin1.decode(out.cos.decodeStreamData(n));
      expect(content, contains('40 0 0 40 30 0 cm'));
      expect(content, contains('/Img0 Do'));
      final resources = out.cos.resolve(n.dictionary['Resources']);
      final xobjects =
          out.cos.resolve((resources as CosDictionary)['XObject']);
      final image =
          out.cos.resolve((xobjects as CosDictionary)['Img0']) as CosStream;
      expect(image.dictionary['Width'], const CosInteger(2));
      expect(out.cos.resolve(image.dictionary['SMask']), isA<CosStream>());
    });

    test('only push buttons accept images', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final name = editor.acroForm!.fieldNamed('name')!;
      expect(() => editor.setButtonImage(name, PdfEmbeddableImage.png(_png)),
          throwsArgumentError);
    });
  });

  group('rename', () {
    test('renames in place and survives a round-trip', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      editor.renameField(editor.acroForm!.fieldNamed('name')!, 'step/1/name');
      final out = PdfDocument.open(editor.save());
      final form = PdfAcroForm.of(out)!;
      expect(form.fieldNamed('name'), isNull);
      expect(form.fieldNamed('step/1/name')!.value, 'prefilled');
    });

    test('rejects empty names and collisions', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final field = editor.acroForm!.fieldNamed('name')!;
      expect(() => editor.renameField(field, ''), throwsArgumentError);
      expect(() => editor.renameField(field, 'agree'), throwsArgumentError);
      // renaming to its own name is a no-op, not a collision
      editor.renameField(field, 'name');
    });
  });

  group('removal', () {
    test('removeField detaches the widget and the field entry', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      editor.removeField(editor.acroForm!.fieldNamed('name')!);
      final out = PdfDocument.open(editor.save());
      expect(PdfAcroForm.of(out)!.fieldNamed('name'), isNull);
      final annots = out.cos.resolve(out.page(0).dict['Annots']) as CosArray;
      // the fixture page listed 7 widgets; the text widget is gone
      expect(annots.length, 6);
    });

    test('removing a radio group detaches every kid widget', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      editor.removeField(editor.acroForm!.fieldNamed('color')!);
      final out = PdfDocument.open(editor.save());
      expect(PdfAcroForm.of(out)!.fieldNamed('color'), isNull);
      final annots = out.cos.resolve(out.page(0).dict['Annots']) as CosArray;
      expect(annots.length, 5, reason: 'both kid widgets detached');
    });

    test('a widget no page lists is skipped silently', () {
      final doc = PdfDocument.open(buildAcroFormPdf());
      final editor = PdfEditor(doc);
      final field = editor.acroForm!.fieldNamed('name')!;
      final annots = doc.cos.resolve(doc.page(0).dict['Annots']) as CosArray;
      annots.items.removeWhere(
          (item) => identical(doc.cos.resolve(item), field.dict));
      editor.removeField(field); // must not throw
      // the field is gone and not resurrected: with its widget on no page,
      // orphan-widget reconciliation has nothing to re-adopt.
      expect(editor.acroForm!.fieldNamed('name'), isNull);
    });
  });

  group('type change', () {
    test('text becomes an image-capable push button, same name and rect',
        () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final rebuilt = editor.changeFieldType(
          editor.acroForm!.fieldNamed('name')!, PdfFieldType.pushButton);
      expect(rebuilt.type, PdfFieldType.pushButton);
      editor.setButtonImage(rebuilt, PdfEmbeddableImage.png(_png));

      final out = PdfDocument.open(editor.save());
      final form = PdfAcroForm.of(out)!;
      final info =
          form.describeFields().firstWhere((i) => i.name == 'name');
      expect(info.type, PdfFieldType.pushButton);
      expect(info.pageIndex, 0);
      expect(info.rect, const PdfRect(72, 700, 300, 724));
    });

    test('checkbox to text and back', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      var field = editor.changeFieldType(
          editor.acroForm!.fieldNamed('agree')!, PdfFieldType.text);
      expect(field.type, PdfFieldType.text);
      field = editor.changeFieldType(field, PdfFieldType.checkBox);
      expect(field.type, PdfFieldType.checkBox);
      expect(field.onStates, ['Yes']);
    });

    test('same type is a no-op; unsupported targets throw', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final name = editor.acroForm!.fieldNamed('name')!;
      expect(editor.changeFieldType(name, PdfFieldType.text), name);
      expect(editor.hasChanges, isFalse);
      expect(() => editor.changeFieldType(name, PdfFieldType.comboBox),
          throwsArgumentError);
    });
  });

  group('flattening', () {
    test('flattenForm paints filled values and removes every field', () {
      final doc = PdfDocument.open(buildAcroFormPdf());
      final editor = PdfEditor(doc);
      final form = editor.acroForm!;
      editor.setTextValue(form.fieldNamed('name')!, 'Jane');
      editor.setCheckBoxValue(form.fieldNamed('agree')!, true);
      // a non-widget annotation must survive form flattening
      editor.addSquare(0, const PdfRect(400, 100, 500, 200));
      editor.flattenForm();

      final out = PdfDocument.open(editor.save());
      expect(PdfAcroForm.of(out)!.fields, isEmpty);
      final annots = out.cos.resolve(out.page(0).dict['Annots']) as CosArray;
      expect(annots.length, 1, reason: 'only the square remains');
      // the page now draws the flattened appearance forms…
      final content = latin1.decode(out.page(0).contentBytes());
      expect(content, contains('/FlatAnnot0 Do'));
      // …and the text value lives inside one of them
      expect(_flattenedContent(out), contains('(Jane) Tj'));
    });

    test('broken widgets cannot derail flattening', () {
      final doc = PdfDocument.open(buildAcroFormPdf());
      // corrupt one widget: junk /Rect and a dangling /AP reference
      final field = PdfAcroForm.of(doc)!.fieldNamed('agree')!;
      field.dict['Rect'] = CosString.fromText('junk');
      field.dict['AP'] = const CosReference(999, 0);
      final editor = PdfEditor(doc);
      editor.setTextValue(editor.acroForm!.fieldNamed('name')!, 'ok');
      editor.flattenForm(); // must not throw

      final out = PdfDocument.open(editor.save());
      expect(PdfAcroForm.of(out)!.fields, isEmpty);
      expect(_flattenedContent(out), contains('(ok) Tj'));
    });
  });
}

/// Concatenated content of every FlatAnnot form XObject on page 0.
String _flattenedContent(PdfDocument doc) {
  final resources = doc.cos.resolve(doc.page(0).dict['Resources']);
  final xobjects =
      doc.cos.resolve((resources as CosDictionary)['XObject']);
  final out = StringBuffer();
  for (final entry in (xobjects as CosDictionary).entries.entries) {
    if (!entry.key.startsWith('FlatAnnot')) continue;
    final stream = doc.cos.resolve(entry.value);
    if (stream is CosStream) {
      out.writeln(latin1.decode(doc.cos.decodeStreamData(stream)));
    }
  }
  return out.toString();
}
