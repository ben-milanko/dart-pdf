import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('flattening moves appearances into content and clears /Annots', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addHighlight(0, const [PdfRect(72, 700, 200, 712)])
      ..addStamp(0, const PdfRect(100, 500, 260, 540), 'DRAFT');
    final withAnnots = PdfDocument.open(editor.save());
    expect(withAnnots.page(0).annotations, hasLength(2));

    final flattener = PdfEditor(withAnnots)..flattenAnnotations(0);
    final doc = PdfDocument.open(flattener.save());

    final page = doc.page(0);
    expect(page.annotations, isEmpty);
    expect(page.dict['Annots'], isNull);

    final content = latin1.decode(page.contentBytes());
    expect(content, contains('Hello, world!')); // original survives
    expect(content, startsWith('q\n')); // sandwich prefix
    expect(content, contains('/FlatAnnot0 Do'));
    expect(content, contains('/FlatAnnot1 Do'));

    final xobjects = doc.cos.resolve(
            (doc.cos.resolve(page.dict['Resources']) as CosDictionary)['XObject'])
        as CosDictionary;
    expect(xobjects.containsKey('FlatAnnot0'), isTrue);
    final form = doc.cos.resolve(xobjects['FlatAnnot0']);
    expect(form, isA<CosStream>());
  });

  test('hidden annotations and ones without /AP are left in place', () {
    // buildAppearanceAnnotationsPdf page 1 carries a hidden Square whose
    // appearance must not be painted or removed
    final doc = PdfDocument.open(buildAppearanceAnnotationsPdf());
    final before = doc.page(0).annotations;
    final hiddenCount = before.where((a) => a.isHidden).length;
    expect(hiddenCount, greaterThan(0));

    final editor = PdfEditor(doc)..flattenAnnotations(0);
    final flat = PdfDocument.open(editor.save());
    final after = flat.page(0).annotations;
    // the hidden Square and the Popup stay; everything visible was baked in
    expect(after.length, hiddenCount + 1);
    expect(after.every((a) => a.isHidden || a.subtype == 'Popup'), isTrue);
  });

  test('flattening with no eligible annotations is a no-op', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..flattenAnnotations(0);
    expect(editor.hasChanges, isFalse);
  });

  test('flattened widget states follow /AS', () {
    final doc = PdfDocument.open(buildAppearanceAnnotationsPdf());
    final editor = PdfEditor(doc)..flattenAnnotations(0);
    final flat = PdfDocument.open(editor.save());
    // the checkbox /AS /On state fills 0.5 gray - its stream must now be
    // among the page's flattened XObjects
    final resources =
        flat.cos.resolve(flat.page(0).dict['Resources']) as CosDictionary;
    final xobjects = flat.cos.resolve(resources['XObject']) as CosDictionary;
    final contents = [
      for (final key in xobjects.entries.keys)
        if (flat.cos.resolve(xobjects[key]) case final CosStream s)
          latin1.decode(flat.cos.decodeStreamData(s)),
    ];
    expect(contents.any((c) => c.contains('0.5 g')), isTrue);
  });
}
