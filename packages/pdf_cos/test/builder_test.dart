import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

void main() {
  group('CosDocumentBuilder', () {
    test('assigns object numbers in registration order from 1', () {
      final builder = CosDocumentBuilder();
      final a = builder.add(CosDictionary({'Type': const CosName('Pages')}));
      final b = builder.add(CosDictionary({'Type': const CosName('Catalog')}));
      expect(a, const CosReference(1, 0));
      expect(b, const CosReference(2, 0));
    });

    test('builds a reopenable file with a shared xref table and trailer', () {
      final builder = CosDocumentBuilder();
      final pages = CosDictionary({'Type': const CosName('Pages')});
      final pagesRef = builder.add(pages);
      final page = builder.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(200),
          const CosInteger(300),
        ]),
      }));
      pages['Kids'] = CosArray([page]);
      pages['Count'] = const CosInteger(1);
      final catalog = builder.add(CosDictionary({
        'Type': const CosName('Catalog'),
        'Pages': pagesRef,
      }));

      final bytes = builder.build(root: catalog);

      final reopened = CosDocument.open(bytes);
      expect(reopened.catalog.typeName, 'Catalog');
      expect((reopened.getObject(2, 0) as CosDictionary).typeName, 'Page');
      // three objects registered plus the object-0 free head
      expect(reopened.declaredSize, 4);
      expect(reopened.trailer['Prev'], isNull);
    });

    test('emits the from-scratch framing produced by CosXrefTableWriter', () {
      final builder = CosDocumentBuilder();
      final catalog = builder.add(CosDictionary({
        'Type': const CosName('Catalog'),
        'Pages': const CosReference(1, 0),
      }));
      final text = String.fromCharCodes(builder.build(root: catalog));

      expect(text, startsWith('%PDF-1.7\n'));
      // the free-list head and the shared entry encoding
      expect(text, contains('xref\n0 2\n0000000000 65535 f \n'));
      expect(text, matches(RegExp(r'\n\d{10} 00000 n \n')));
      expect(text, contains('trailer\n'));
      expect(text, endsWith('%%EOF\n'));
    });

    test('honours a caller-supplied /Info reference and version', () {
      final builder = CosDocumentBuilder();
      final info =
          builder.add(CosDictionary({'Title': CosString.fromText('Doc')}));
      final catalog = builder.add(CosDictionary({
        'Type': const CosName('Catalog'),
      }));
      final bytes = builder.build(root: catalog, info: info, version: '1.5');

      expect(String.fromCharCodes(bytes), startsWith('%PDF-1.5\n'));
      final reopened = CosDocument.open(bytes);
      final infoDict = reopened.resolve(reopened.trailer['Info']);
      expect((infoDict as CosDictionary)['Title'], CosString.fromText('Doc'));
    });
  });

  group('CosDocumentBuilder object streams', () {
    CosReference buildOnePage(CosDocumentBuilder builder, {String? title}) {
      final pages = CosDictionary({'Type': const CosName('Pages')});
      final pagesRef = builder.add(pages);
      final page = builder.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(200),
          const CosInteger(300),
        ]),
      }));
      pages['Kids'] = CosArray([page]);
      pages['Count'] = const CosInteger(1);
      return builder.add(CosDictionary({
        'Type': const CosName('Catalog'),
        'Pages': pagesRef,
      }));
    }

    test('packs non-stream objects into a compressed xref-stream file', () {
      final builder = CosDocumentBuilder();
      final catalog = buildOnePage(builder);
      final bytes = builder.build(root: catalog, objectStreams: true);

      final text = String.fromCharCodes(bytes.sublist(0, 16));
      // object streams force a >= 1.5 header
      expect(text, startsWith('%PDF-1.7\n'));
      // no classic table; the cross-reference is itself a stream
      expect(String.fromCharCodes(bytes), isNot(contains('\ntrailer\n')));

      final reopened = CosDocument.open(bytes);
      expect(reopened.trailer.typeName, 'XRef');
      // the catalog and page came back out of an object stream
      expect(reopened.catalog.typeName, 'Catalog');
      final pages = reopened.resolve(reopened.catalog['Pages']) as CosDictionary;
      final kids = reopened.resolve(pages['Kids']) as CosArray;
      final page = reopened.resolve(kids[0]) as CosDictionary;
      expect(page.typeName, 'Page');
    });

    test('keeps streams top-level and addressable', () {
      final builder = CosDocumentBuilder();
      final pages = CosDictionary({'Type': const CosName('Pages')});
      final pagesRef = builder.add(pages);
      final content = builder.add(CosStream(
        CosDictionary(),
        Uint8List.fromList('BT /F1 12 Tf (hi) Tj ET'.codeUnits),
      ));
      final page = builder.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'Contents': content,
        'MediaBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(200),
          const CosInteger(300),
        ]),
      }));
      pages['Kids'] = CosArray([page]);
      pages['Count'] = const CosInteger(1);
      final catalog = builder.add(CosDictionary({
        'Type': const CosName('Catalog'),
        'Pages': pagesRef,
      }));

      final bytes = builder.build(root: catalog, objectStreams: true);
      final reopened = CosDocument.open(bytes);
      final page2 = reopened.resolve(
              (reopened.resolve((reopened.resolve(reopened.catalog['Pages'])
                      as CosDictionary)['Kids']) as CosArray)[0])
          as CosDictionary;
      final stream = reopened.resolve(page2['Contents']) as CosStream;
      expect(String.fromCharCodes(reopened.decodeStreamData(stream)),
          'BT /F1 12 Tf (hi) Tj ET');
    });
  });
}
