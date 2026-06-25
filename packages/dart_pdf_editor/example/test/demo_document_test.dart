import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_viewer_example/demo_document.dart';

void main() {
  group('buildDemoPdf', () {
    final doc = PdfDocument.open(buildDemoPdf());

    test('produces the six showcase pages', () {
      expect(doc.pageCount, 6);
      for (var i = 0; i < 6; i++) {
        expect(doc.page(i).cropBox.width, 612);
      }
    });

    test('page 1 keeps the interactivity links and gains the TOC', () {
      final annots = doc.page(0).annotations;
      final links =
          annots.where((a) => a.subtype == 'Link').toList(growable: false);
      // 4 app actions + 1 real web hyperlink + 4 TOC GoTo entries
      expect(links, hasLength(9));
      expect(annots.where((a) => a.subtype == 'Widget'), hasLength(1));
    });

    test('page 6 carries the editor-authored annotation set', () {
      final subtypes =
          doc.page(5).annotations.map((a) => a.subtype).toList(growable: false);
      for (final expected in [
        'Highlight', 'Underline', 'StrikeOut', 'Squiggly', 'Ink', //
        'Square', 'Circle', 'FreeText', 'Text', 'Stamp',
      ]) {
        expect(subtypes, contains(expected));
      }
      final authored = doc
          .page(5)
          .annotations
          .where((a) => a.author == 'dart-pdf demo');
      expect(authored, hasLength(10));
    });

    test('the form fields are filled with generated appearances', () {
      final form = PdfAcroForm.of(doc)!;
      String? value(String name) =>
          form.fields.firstWhere((f) => f.name == name).value;
      expect(value('name'), 'Ada Lovelace');
      expect(value('newsletter'), 'Yes');
      expect(value('color'), 'Blue');
      expect(value('favorite'), 'Green');
      // filling must have produced a normal appearance on every widget
      for (final field in form.fields) {
        for (var i = 0; i < field.widgets.length; i++) {
          expect(field.widgets[i]['AP'], isNotNull,
              reason: '${field.name} widget $i has no appearance');
        }
      }
    });
  });
}
