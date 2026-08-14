import 'package:dart_pdf_cli/dart_pdf_cli.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('DartPdfPageSelection', () {
    test('parses ranges, preserves order, and removes duplicates', () {
      final selection = DartPdfPageSelection.parse(
        '3,1-2,2',
        pageCount: 4,
        maxPages: 4,
      );

      expect(selection.indices, [2, 0, 1]);
      expect(selection.truncated, isFalse);
    });

    test('bounds implicit and explicit selections', () {
      final implicit = DartPdfPageSelection.parse(
        null,
        pageCount: 4,
        maxPages: 2,
      );
      expect(implicit.indices, [0, 1]);
      expect(implicit.truncated, isTrue);

      expect(
        () => DartPdfPageSelection.parse(
          '1-3',
          pageCount: 4,
          maxPages: 2,
        ),
        throwsA(isA<DartPdfRequestException>()),
      );
    });

    test('rejects invalid or out-of-range pages', () {
      for (final pages in ['0', '2-1', '1,,2', '5']) {
        expect(
          () => DartPdfPageSelection.parse(
            pages,
            pageCount: 4,
            maxPages: 4,
          ),
          throwsA(isA<DartPdfRequestException>()),
          reason: pages,
        );
      }
    });
  });

  group('DartPdfDocument', () {
    test('inspect returns the stable document summary', () {
      final result = const DartPdfService().open(buildClassicPdf()).inspect();

      expect(result['schemaVersion'], dartPdfJsonSchemaVersion);
      expect(result['operation'], 'inspect');
      expect(result['version'], '1.4');
      expect(result['pageCount'], 1);
      expect(result['encrypted'], isFalse);
      expect(result['forms'], {'present': false, 'fieldCount': 0});
      expect(
        result['annotations'],
        {'count': 0, 'bySubtype': <String, int>{}},
      );
      expect(
        result['signatures'],
        {'signed': false, 'count': 0, 'items': <Object>[]},
      );
    });

    test('inspect reports encryption after opening with a password', () {
      final result = const DartPdfService()
          .open(
            buildEncryptedPdf(userPassword: 'secret'),
            password: 'secret',
          )
          .inspect();

      expect(result['encrypted'], isTrue);
      expect(result['metadata'], containsPair('Title', 'Secret Title'));
    });

    test('text is page-addressable', () {
      final result = const DartPdfService()
          .open(buildMultiPagePdf(3))
          .extractText(pages: '2-3');

      expect(result['selectedPages'], [2, 3]);
      expect(result['returnedPages'], 2);
      final pages = result['pages']! as List<Object?>;
      expect(pages[0], containsPair('page', 2));
      expect(pages[0], containsPair('text', contains('Page 2')));
      expect(pages[1], containsPair('page', 3));
    });

    test('text respects page and character limits', () {
      const service = DartPdfService(
        limits: DartPdfLimits(
          maxPages: 1,
          maxTextCharsPerPage: 4,
          maxTextChars: 4,
        ),
      );
      final result = service.open(buildMultiPagePdf(3)).extractText();

      expect(result['selectedPages'], [1]);
      expect(result['characters'], 4);
      expect(result['truncated'], isTrue);
      final page =
          (result['pages']! as List<Object?>).single as Map<String, Object?>;
      expect(page['text'], 'Page');
      expect(page['truncated'], isTrue);
    });

    test('forms list is pure Dart and includes widgets/options', () {
      final result =
          const DartPdfService().open(buildAcroFormPdf()).listForms();

      expect(result['present'], isTrue);
      expect(result['total'], 6);
      final fields =
          (result['fields']! as List<Object?>).cast<Map<String, Object?>>();
      final name = fields.singleWhere((field) => field['name'] == 'name');
      expect(name['type'], 'text');
      expect(name['value'], 'prefilled');
      expect(name['widgets'], hasLength(1));
      final size = fields.singleWhere((field) => field['name'] == 'size');
      expect(size['type'], 'comboBox');
      expect(size['options'], hasLength(3));
    });

    test('annotation list can select pages and is bounded', () {
      const service = DartPdfService(
        limits: DartPdfLimits(maxAnnotations: 2),
      );
      final result =
          service.open(buildAnnotatedPdf()).listAnnotations(pages: '1');

      expect(result['selectedPages'], [1]);
      expect(result['total'], 6);
      expect(result['returned'], 2);
      expect(result['truncated'], isTrue);
      final annotations = result['annotations']! as List<Object?>;
      expect(annotations.first, containsPair('subtype', 'Link'));
    });
  });
}
