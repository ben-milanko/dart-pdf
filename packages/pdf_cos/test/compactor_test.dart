import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('CosCompactor', () {
    test('drops orphaned objects an incremental edit left behind', () {
      final base = CosDocument.open(buildClassicPdf());
      // add an object the tree never references, then save it as an update
      final withOrphan = (CosIncrementalUpdater(base)
            ..addObject(CosDictionary({'Orphan': const CosBoolean(true)})))
          .save();

      final doc = CosDocument.open(withOrphan);
      final result = CosCompactor(doc).run();

      // catalog, pages, page, content, font - the orphan is not copied
      expect(result.objectsAfter, 5);
      expect(result.objectsAfter, lessThan(result.objectsBefore),
          reason: 'the unreferenced object should not be copied');

      final compacted = CosDocument.open(result.bytes);
      expect(compacted.catalog.typeName, 'Catalog');
      final pages =
          compacted.resolve(compacted.catalog['Pages']) as CosDictionary;
      final kids = compacted.resolve(pages['Kids']) as CosArray;
      final leaf = compacted.resolve(kids[0]) as CosDictionary;
      expect(leaf.typeName, 'Page');
    });

    test('preserves page content byte-for-byte through the rewrite', () {
      final doc = CosDocument.open(buildClassicPdf());
      final result = CosCompactor(doc).run();
      final compacted = CosDocument.open(result.bytes);

      final pages =
          compacted.resolve(compacted.catalog['Pages']) as CosDictionary;
      final leaf = compacted
          .resolve((compacted.resolve(pages['Kids']) as CosArray)[0])
          as CosDictionary;
      final content =
          compacted.resolve(leaf['Contents']) as CosStream;
      expect(String.fromCharCodes(compacted.decodeStreamData(content)),
          'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET');
    });

    test('re-deflates an uncompressed stream and round-trips it', () {
      // a big, highly compressible unfiltered stream
      final payload = Uint8List.fromList(List.filled(4000, 0x41)); // "AAAA..."
      final builder = CosDocumentBuilder();
      final pages = CosDictionary({'Type': const CosName('Pages')});
      final pagesRef = builder.add(pages);
      final content = builder.add(CosStream(CosDictionary(), payload));
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
      final doc = CosDocument.open(builder.build(root: catalog));

      final result = CosCompactor(doc).run();
      expect(result.streamsDeflated, greaterThanOrEqualTo(1));

      final compacted = CosDocument.open(result.bytes);
      final leaf = compacted
          .resolve((compacted.resolve((compacted.resolve(compacted
                          .catalog['Pages']) as CosDictionary)['Kids'])
                  as CosArray)[0])
          as CosDictionary;
      final stream = compacted.resolve(leaf['Contents']) as CosStream;
      expect(compacted.resolve(stream.dictionary['Filter']),
          const CosName('FlateDecode'));
      expect(compacted.decodeStreamData(stream), payload);
    });

    test('shrinks a classic, uncompressed multi-page file', () {
      final original = buildMultiPagePdf(24);
      final doc = CosDocument.open(original);
      final result = CosCompactor(doc).run();
      expect(result.bytes.length, lessThan(original.length));

      final compacted = CosDocument.open(result.bytes);
      expect(compacted.trailer.typeName, 'XRef');
      // every page still resolves and shows its text
      final pages =
          compacted.resolve(compacted.catalog['Pages']) as CosDictionary;
      final kids = compacted.resolve(pages['Kids']) as CosArray;
      expect(kids.length, 24);
      final last = compacted.resolve(kids[23]) as CosDictionary;
      final content = compacted.resolve(last['Contents']) as CosStream;
      expect(String.fromCharCodes(compacted.decodeStreamData(content)),
          contains('(Page 24)'));
    });

    test('refuses an encrypted document', () {
      final doc = CosDocument.open(buildEncryptedPdf());
      expect(() => CosCompactor(doc).run(), throwsArgumentError);
    });
  });
}
