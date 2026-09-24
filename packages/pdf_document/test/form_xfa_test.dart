import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('XFA detection', () {
    test('a plain AcroForm has no XFA', () {
      final form = PdfAcroForm.of(PdfDocument.open(buildAcroFormPdf()))!;
      expect(form.hasXfa, isFalse);
      expect(form.xfaNeedsRendering, isFalse);
      expect(form.isDynamicXfa, isFalse);
    });

    test('a hybrid form has XFA but is not dynamic', () {
      final form = PdfAcroForm.of(PdfDocument.open(buildXfaFormPdf()))!;
      expect(form.hasXfa, isTrue);
      expect(form.isDynamicXfa, isFalse);
      expect(form.fields.map((f) => f.name), ['name']);
    });

    test('a single-stream XDP counts as XFA', () {
      final form =
          PdfAcroForm.of(PdfDocument.open(buildXfaFormPdf(xfaAsArray: false)))!;
      expect(form.hasXfa, isTrue);
    });

    test('XFA without AcroForm fields is dynamic', () {
      final form =
          PdfAcroForm.of(PdfDocument.open(buildXfaFormPdf(withFields: false)))!;
      expect(form.hasXfa, isTrue);
      expect(form.fields, isEmpty);
      expect(form.isDynamicXfa, isTrue);
    });

    test('/NeedsRendering makes a form with fields dynamic', () {
      final form = PdfAcroForm.of(
          PdfDocument.open(buildXfaFormPdf(needsRendering: true)))!;
      expect(form.xfaNeedsRendering, isTrue);
      expect(form.fields, isNotEmpty);
      expect(form.isDynamicXfa, isTrue);
    });
  });

  group('filling a hybrid form', () {
    test('drops /XFA and /NeedsRendering and keeps the filled value', () {
      final doc = PdfDocument.open(buildXfaFormPdf(needsRendering: true));
      final editor = PdfEditor(doc);
      editor.setTextValue(editor.acroForm!.fieldNamed('name')!, 'fresh');
      final saved = PdfDocument.open(editor.save());

      final form = PdfAcroForm.of(saved)!;
      expect(form.hasXfa, isFalse);
      expect(form.xfaNeedsRendering, isFalse);
      expect(saved.catalog.entries.containsKey('NeedsRendering'), isFalse);
      expect(form.fieldNamed('name')!.value, 'fresh');
      // the rest of the /AcroForm dictionary survives
      expect(form.defaultAppearance, '/Helv 0 Tf 0 g');
      expect(form.defaultResources, isNotNull);
    });

    test('drops a single-stream /XFA too', () {
      final editor =
          PdfEditor(PdfDocument.open(buildXfaFormPdf(xfaAsArray: false)));
      editor.setTextValue(editor.acroForm!.fieldNamed('name')!, 'fresh');
      expect(PdfAcroForm.of(PdfDocument.open(editor.save()))!.hasXfa, isFalse);
    });

    test('the incremental update rewrites the /AcroForm object', () {
      final original = buildXfaFormPdf();
      final editor = PdfEditor(PdfDocument.open(original));
      editor.setTextValue(editor.acroForm!.fieldNamed('name')!, 'fresh');
      final bytes = editor.save();
      // appended, not rewritten: the original revision is a byte prefix
      expect(bytes.sublist(0, original.length), original);
      final tail = String.fromCharCodes(bytes.sublist(original.length));
      expect(tail, contains('4 0 obj'));
      expect(tail, isNot(contains('/XFA')));
    });

    test('later fills in the same session find nothing to remove', () {
      final editor = PdfEditor(PdfDocument.open(buildXfaFormPdf()));
      final field = editor.acroForm!.fieldNamed('name')!;
      editor.setTextValue(field, 'one');
      expect(editor.removeXfa(), isFalse);
      editor.setTextValue(field, 'two');
      final saved = PdfDocument.open(editor.save());
      expect(PdfAcroForm.of(saved)!.hasXfa, isFalse);
      expect(PdfAcroForm.of(saved)!.fieldNamed('name')!.value, 'two');
    });

    test('a form without XFA is left alone', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      expect(editor.removeXfa(), isFalse);
      expect(editor.hasChanges, isFalse);
      editor.setTextValue(editor.acroForm!.fieldNamed('name')!, 'x');
      final saved = PdfDocument.open(editor.save());
      expect(saved.catalog.entries.containsKey('AcroForm'), isTrue);
    });

    test('flattening drops /XFA so the fields cannot come back', () {
      final editor = PdfEditor(PdfDocument.open(buildXfaFormPdf()))
        ..flattenForm();
      final form = PdfAcroForm.of(PdfDocument.open(editor.save()));
      expect(form?.hasXfa ?? false, isFalse);
      expect(form?.fields ?? const [], isEmpty);
    });

    test('removeXfa on a dynamic form strips the XFA packets', () {
      final editor =
          PdfEditor(PdfDocument.open(buildXfaFormPdf(withFields: false)));
      expect(editor.removeXfa(), isTrue);
      final saved = PdfDocument.open(editor.save());
      final dict =
          saved.cos.resolve(saved.catalog['AcroForm']) as CosDictionary;
      expect(dict.entries.containsKey('XFA'), isFalse);
    });
  });
}
