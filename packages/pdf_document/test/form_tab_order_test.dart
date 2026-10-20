import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  List<String> order(String? tabs) {
    final doc = PdfDocument.open(buildTabOrderFormPdf(firstPageTabs: tabs));
    return [
      for (final s in PdfFormTabOrder.of(doc).stops)
        'p${s.pageIndex}:${s.fieldName}#${s.widgetIndex}',
    ];
  }

  const page1 = ['p1:notes#0', 'p1:size#0'];

  test('/Tabs /R reads rows top-down, each left to right', () {
    expect(order('R'), [
      'p0:first#0',
      'p0:city#0',
      'p0:agree#0',
      'p0:color#0',
      'p0:color#1',
      ...page1,
    ]);
  });

  test('/Tabs /C reads columns left to right, each top-down', () {
    expect(order('C'), [
      'p0:first#0',
      'p0:agree#0',
      'p0:color#0',
      'p0:color#1',
      'p0:city#0',
      ...page1,
    ]);
  });

  test('/Tabs /S follows the structure tree', () {
    expect(order('S'), [
      'p0:color#1',
      'p0:agree#0',
      'p0:first#0',
      'p0:city#0',
      'p0:color#0',
      ...page1,
    ]);
  });

  test('no /Tabs (or one we do not know) keeps /Annots order', () {
    const annots = [
      'p0:city#0',
      'p0:first#0',
      'p0:agree#0',
      'p0:color#0',
      'p0:color#1',
      ...page1,
    ];
    expect(order(null), annots);
    expect(order('W'), annots);
  });

  test('skips read-only, hidden, push-button and signature fields', () {
    final names = {
      for (final s in order('R')) s.split(':')[1].split('#')[0],
    };
    expect(names, {'first', 'city', 'agree', 'color', 'notes', 'size'});
  });

  test('page tabOrder reads /Tabs', () {
    final doc = PdfDocument.open(buildTabOrderFormPdf(firstPageTabs: 'C'));
    expect(doc.page(0).tabOrder, PdfTabOrder.column);
    expect(doc.page(1).tabOrder, PdfTabOrder.annotations);
  });

  group('step', () {
    final doc = PdfDocument.open(buildTabOrderFormPdf());
    final tabs = PdfFormTabOrder.of(doc);
    String? name(PdfFormTabStop? s) =>
        s == null ? null : '${s.fieldName}#${s.widgetIndex}';

    test('moves forward and back, across pages', () {
      expect(name(tabs.step(pageIndex: 0, fieldName: 'first')), 'city#0');
      expect(name(tabs.step(pageIndex: 0, fieldName: 'color', widgetIndex: 1)),
          'notes#0');
      expect(name(tabs.step(pageIndex: 1, fieldName: 'notes', backward: true)),
          'color#1');
    });

    test('wraps around at either end', () {
      expect(name(tabs.step(pageIndex: 1, fieldName: 'size')), 'first#0');
      expect(name(tabs.step(pageIndex: 0, fieldName: 'first', backward: true)),
          'size#0');
    });

    test('from a widget that is not a stop, starts at its page', () {
      expect(name(tabs.step(pageIndex: 1)), 'notes#0');
      expect(name(tabs.step(pageIndex: 0, fieldName: 'ro')), 'first#0');
      expect(name(tabs.step(pageIndex: 0, backward: true)), 'color#1');
    });

    test('a form without stops has no step', () {
      expect(PdfFormTabOrder(const []).step(pageIndex: 0), isNull);
      expect(PdfFormTabOrder.of(PdfDocument.open(buildClassicPdf())).stops,
          isEmpty);
    });
  });

  group('sortPage', () {
    PdfRect r(double l, double b, double w, double h) =>
        PdfRect(l, b, l + w, b + h);

    test('row order tolerates ragged tops within a row', () {
      // a check box sits 2pt lower than the text field beside it
      final items = [
        r(300, 702, 20, 20),
        r(72, 700, 200, 24),
        r(72, 650, 50, 20),
      ];
      final sorted =
          PdfFormTabOrder.sortPage(items, PdfTabOrder.row, rectOf: (x) => x);
      expect(sorted, [items[1], items[0], items[2]]);
    });

    test('structure order puts unranked items last, in /Annots order', () {
      final items = ['a', 'b', 'c', 'd'];
      final ranks = {'c': 0, 'a': 1};
      final sorted = PdfFormTabOrder.sortPage(items, PdfTabOrder.structure,
          rectOf: (_) => const PdfRect(0, 0, 1, 1),
          structureRank: (x) => ranks[x]);
      expect(sorted, ['c', 'a', 'b', 'd']);
    });
  });
}
