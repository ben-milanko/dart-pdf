import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Reconciling forms whose /AcroForm /Fields tree and on-page widget
/// annotations are disconnected copies of the same form (the macOS
/// 26.5 / Quartz "orphaned AcroField" defect). See
/// [buildOrphanedAcroFormPdf].
void main() {
  PdfDocument open() => PdfDocument.open(buildOrphanedAcroFormPdf());

  group('reading', () {
    test('adopts on-page orphan widgets and surfaces their values', () {
      final form = PdfAcroForm.of(open())!;

      final name = form.fieldNamed('name')!;
      // the off-page /Fields copy held the stale "old"; the visible widget
      // wins.
      expect(name.value, 'Jane');
      expect(name.widgetPageIndex(0), 0, reason: 'now resolves to the page');
      expect(name.widgetRect(0), const PdfRect(72, 700, 300, 724));
      expect(name.reconciledWidgets, isNotEmpty);

      final town = form.fieldNamed('town')!;
      expect(town.value, isNull);
      expect(town.widgetPageIndex(0), 0);
    });

    test('synthesizes a field for a page-only widget absent from /Fields', () {
      final form = PdfAcroForm.of(open())!;
      final extra = form.fieldNamed('extra');
      expect(extra, isNotNull, reason: 'page-only widget becomes a field');
      expect(extra!.value, 'Solo');
      expect(extra.type, PdfFieldType.text);
      expect(extra.widgetPageIndex(0), 0);
    });

    test('describeFields reports the visible page, not -1', () {
      final infos = PdfAcroForm.of(open())!.describeFields();
      expect(infos.map((i) => i.name),
          containsAll(<String>['name', 'town', 'extra']));
      expect(infos.every((i) => i.pageIndex == 0), isTrue,
          reason: 'every field now maps to the page it shows on');
    });

    test('well-formed forms are untouched (no reconciliation)', () {
      final form = PdfAcroForm.of(PdfDocument.open(buildAcroFormPdf()))!;
      for (final field in form.fields) {
        expect(field.reconciledWidgets, isEmpty);
      }
      // the prefilled single-widget field still reads its own /V
      expect(form.fieldNamed('name')!.value, 'prefilled');
    });
  });

  group('filling', () {
    PdfDocument fill(void Function(PdfEditor, PdfAcroForm) edit) {
      final editor = PdfEditor(open());
      edit(editor, editor.acroForm!);
      return PdfDocument.open(editor.save());
    }

    String appearance(PdfDocument doc, PdfFormField field, [int index = 0]) {
      final cos = doc.cos;
      final ap = cos.resolve(field.widgets[index]['AP']) as CosDictionary;
      final n = cos.resolve(ap['N']) as CosStream;
      return latin1.decode(cos.decodeStreamData(n));
    }

    test('writes through to the visible widget and reads back', () {
      final doc =
          fill((e, f) => e.setTextValue(f.fieldNamed('name')!, 'Updated'));
      final name = PdfAcroForm.of(doc)!.fieldNamed('name')!;
      expect(name.value, 'Updated', reason: 'no stale shadow on read-back');
      // the regenerated appearance lives on the on-page widget
      expect(appearance(doc, name), contains('(Updated) Tj'));
      expect(name.widgetPageIndex(0), 0);
    });

    test('a synthesized page-only field fills normally', () {
      final doc =
          fill((e, f) => e.setTextValue(f.fieldNamed('extra')!, 'Filled'));
      final extra = PdfAcroForm.of(doc)!.fieldNamed('extra')!;
      expect(extra.value, 'Filled');
      expect(appearance(doc, extra), contains('(Filled) Tj'));
    });
  });
}
