import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('CosCompactor', () {
    test('re-deflates Flate while preserving predictor bytes and parameters',
        () {
      final predictorRows = Uint8List.fromList([
        for (var row = 0; row < 80; row++) ...[0, ...List.filled(24, row)],
      ]);
      final builder = CosDocumentBuilder();
      final input = Uint8List.fromList(
          const ZLibEncoder().encodeBytes(predictorRows, level: 0));
      final streamRef = builder.add(CosStream(
          CosDictionary({
            'Filter': CosArray([const CosName('FlateDecode')]),
            'DecodeParms': CosArray([
              CosDictionary({
                'Predictor': const CosInteger(12),
                'Columns': const CosInteger(24),
              })
            ]),
          }),
          input));
      final root = builder.add(CosDictionary({
        'Type': const CosName('Catalog'),
        'Sample': streamRef,
      }));
      final doc = CosDocument.open(builder.build(root: root));
      final original = doc.resolve(doc.catalog['Sample']) as CosStream;
      final compacted = CosDocument.open(CosCompactor(doc).run().bytes);
      final stream =
          compacted.resolve(compacted.catalog['Sample']) as CosStream;
      expect(stream.rawBytes.length, lessThan(input.length));
      expect(const ZLibDecoder().decodeBytes(stream.rawBytes), predictorRows);
      expect(
          compacted.decodeStreamData(stream), doc.decodeStreamData(original));
    });

    test('can preserve encoded stream bytes without recompression', () {
      final doc = CosDocument.open(buildMultiPagePdf(6));
      final result = CosCompactor(doc, recompressStreams: false).run();
      expect(result.streamsDeflated, 0);
    });

    test('preserves cyclic indirect arrays', () {
      final builder = CosDocumentBuilder();
      final array = CosArray();
      final ref = builder.add(array);
      array.items.add(ref);
      final root = builder.add(CosDictionary({
        'Type': const CosName('Catalog'),
        'Cycle': ref,
      }));
      final doc = CosDocument.open(builder.build(root: root));
      final result = CosDocument.open(CosCompactor(doc).run().bytes);
      final copied = result.resolve(result.catalog['Cycle']) as CosArray;
      expect(result.resolve(copied[0]), same(copied));
    });

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
      final leaf =
          compacted.resolve((compacted.resolve(pages['Kids']) as CosArray)[0])
              as CosDictionary;
      final content = compacted.resolve(leaf['Contents']) as CosStream;
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
      final leaf = compacted.resolve((compacted.resolve(
          (compacted.resolve(compacted.catalog['Pages'])
              as CosDictionary)['Kids']) as CosArray)[0]) as CosDictionary;
      final stream = compacted.resolve(leaf['Contents']) as CosStream;
      expect(compacted.resolve(stream.dictionary['Filter']),
          const CosName('FlateDecode'));
      expect(compacted.decodeStreamData(stream), payload);
    });

    test('drops stale /DecodeParms when it imposes FlateDecode', () {
      // an unfiltered stream that (malformed) also carries decode params: the
      // params must not survive onto our re-deflated payload.
      final payload = Uint8List.fromList(List.filled(4000, 0x42));
      final builder = CosDocumentBuilder();
      final pages = CosDictionary({'Type': const CosName('Pages')});
      final pagesRef = builder.add(pages);
      final content = builder.add(CosStream(
        CosDictionary({
          'DecodeParms': CosDictionary({'Predictor': const CosInteger(12)}),
        }),
        payload,
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
      final catalog = builder.add(
          CosDictionary({'Type': const CosName('Catalog'), 'Pages': pagesRef}));
      final doc = CosDocument.open(builder.build(root: catalog));

      final result = CosCompactor(doc).run();
      expect(result.streamsDeflated, greaterThanOrEqualTo(1));

      final compacted = CosDocument.open(result.bytes);
      final leaf = compacted.resolve((compacted.resolve(
          (compacted.resolve(compacted.catalog['Pages'])
              as CosDictionary)['Kids']) as CosArray)[0]) as CosDictionary;
      final stream = compacted.resolve(leaf['Contents']) as CosStream;
      expect(stream.dictionary['DecodeParms'], isNull);
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
