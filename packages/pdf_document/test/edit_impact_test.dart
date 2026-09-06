import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('PdfEditImpact', () {
    test('annotation creation reports visual and sync impact only', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..addSquare(1, const PdfRect(100, 100, 200, 200));

      expect(editor.impact.visualPages, {1});
      expect(editor.impact.contentPages, isEmpty);
      expect(editor.impact.annotationPages, {1});
      expect(editor.impact.pageStructureChanged, isFalse);
      expect(editor.impact.destructive, isFalse);
    });

    test('annotation metadata reports sync impact without repainting', () {
      final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..addSquare(0, const PdfRect(100, 100, 200, 200));
      final document = PdfDocument.open(first.save());
      final annotation = document.page(0).annotations.single;
      final editor = PdfEditor(document)
        ..setAnnotationAuthor(0, annotation, 'Ben');

      expect(editor.impact.visualPages, isEmpty);
      expect(editor.impact.contentPages, isEmpty);
      expect(editor.impact.annotationPages, {0});
    });

    test('page content reports base raster impact without annotation diff', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
        ..stampPage(1, (stamp) => stamp.text('impact', x: 10, y: 10));

      expect(editor.impact.visualPages, {1});
      expect(editor.impact.contentPages, {1});
      expect(editor.impact.annotationPages, isEmpty);
    });

    test('multiple mutations merge their page sets', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..addSquare(0, const PdfRect(10, 10, 20, 20))
        ..addCircle(2, const PdfRect(30, 30, 50, 50));

      expect(editor.impact.visualPages, {0, 2});
      expect(editor.impact.contentPages, isEmpty);
      expect(editor.impact.annotationPages, {0, 2});
    });

    test('page reorder reports identity-preserving structural impact', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..movePage(0, 2);

      expect(editor.impact.visualPages, isEmpty);
      expect(editor.impact.contentPages, isEmpty);
      expect(editor.impact.annotationPages, isEmpty);
      expect(editor.impact.pageStructureChanged, isTrue);
      expect(editor.impact.pageOrderOnly, isTrue);
    });

    test('page insertion keeps conservative document-wide impact', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..insertBlankPage(at: 1);

      expect(editor.impact.visualPages, isNull);
      expect(editor.impact.contentPages, isNull);
      expect(editor.impact.annotationPages, isNull);
      expect(editor.impact.pageStructureChanged, isTrue);
      expect(editor.impact.pageOrderOnly, isFalse);
    });

    test('a reorder combined with page editing retains the dirty lane', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..movePage(0, 2)
        ..addSquare(0, const PdfRect(20, 20, 80, 80));

      expect(editor.impact.pageStructureChanged, isTrue);
      expect(editor.impact.pageOrderOnly, isTrue);
      expect(editor.impact.visualPages, {0});
      expect(editor.impact.annotationPages, {0});
    });

    test('form filling reports widget repaint without content invalidation',
        () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final field = editor.acroForm!.fieldNamed('name')!;
      editor.setTextValue(field, 'Impact');

      expect(editor.impact.visualPages, {0});
      expect(editor.impact.contentPages, isEmpty);
      expect(editor.impact.annotationPages, isEmpty);
    });

    test('form removal reports widget-list invalidation', () {
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      editor.removeField(editor.acroForm!.fieldNamed('name')!);

      expect(editor.impact.visualPages, {0});
      expect(editor.impact.contentPages, isEmpty);
      expect(editor.impact.annotationPages, {0});
    });

    test('outline edits report metadata-only impact', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..addOutlineItem('Start', pageIndex: 0);

      expect(editor.impact.visualPages, isEmpty);
      expect(editor.impact.contentPages, isEmpty);
      expect(editor.impact.annotationPages, isEmpty);
    });

    test('redaction burn is destructive without claiming structure change', () {
      final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..addRedaction(0, const [PdfRect(60, 715, 200, 748)]);
      final editor = PdfEditor(PdfDocument.open(first.save()));

      editor.applyRedactions();

      expect(editor.impact.visualPages, {0});
      expect(editor.impact.contentPages, {0});
      expect(editor.impact.annotationPages, {0});
      expect(editor.impact.destructive, isTrue);
      expect(editor.impact.pageStructureChanged, isFalse);
    });
  });
}
