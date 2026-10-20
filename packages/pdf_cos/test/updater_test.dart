import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// [pdf] with its trailer's `/Size 6` rewritten to [size]. The trailer (or
/// the xref stream's dictionary) sits after every object and at the offset
/// startxref names, so no offset moves.
Uint8List withSize(Uint8List pdf, int size) =>
    latin1.encode(latin1.decode(pdf).replaceFirst('/Size 6 ', '/Size $size '));

void main() {
  group('incremental update of a classic-table file', () {
    test('original bytes are preserved verbatim', () {
      final original = buildClassicPdf();
      final doc = CosDocument.open(original);
      final updater = CosIncrementalUpdater(doc)
        ..replaceObject(5, CosDictionary({'A': const CosInteger(1)}));
      final updated = updater.save();
      expect(updated.length, greaterThan(original.length));
      expect(updated.sublist(0, original.length), original);
    });

    test('replaced objects win, untouched objects survive', () {
      final doc = CosDocument.open(buildClassicPdf());
      final updater = CosIncrementalUpdater(doc)
        ..replaceObject(
            5,
            CosDictionary({
              'Type': const CosName('Font'),
              'Subtype': const CosName('Type1'),
              'BaseFont': const CosName('Courier'),
            }));
      final reopened = CosDocument.open(updater.save());

      final font = reopened.getObject(5, 0) as CosDictionary;
      expect(font['BaseFont'], const CosName('Courier'));
      // untouched object still loads through the /Prev chain
      expect((reopened.getObject(3, 0) as CosDictionary).typeName, 'Page');
      expect(reopened.catalog.typeName, 'Catalog');
    });

    test('added objects get fresh numbers above /Size', () {
      final doc = CosDocument.open(buildClassicPdf());
      final updater = CosIncrementalUpdater(doc);
      final ref =
          updater.addObject(CosDictionary({'New': const CosBoolean(true)}));
      expect(ref.objectNumber, 6); // fixture declares /Size 6

      final reopened = CosDocument.open(updater.save());
      final added = reopened.resolve(ref) as CosDictionary;
      expect(added['New'], const CosBoolean(true));
      expect(reopened.declaredSize, 7);
    });

    test('trailer overrides apply, /Prev chains back', () {
      final doc = CosDocument.open(buildClassicPdf());
      final updater = CosIncrementalUpdater(doc);
      final info = updater
          .addObject(CosDictionary({'Title': CosString.fromText('Edited')}));
      updater.setTrailerEntry('Info', info);

      final reopened = CosDocument.open(updater.save());
      expect(reopened.trailer['Prev'], CosInteger(doc.startXref));
      final infoDict = reopened.resolve(reopened.trailer['Info']);
      expect((infoDict as CosDictionary)['Title'], CosString.fromText('Edited'));
      expect(reopened.trailer['Root'], doc.trailer['Root']);
    });

    test('a second update chains onto the first', () {
      final doc1 = CosDocument.open(buildClassicPdf());
      final updater1 = CosIncrementalUpdater(doc1)
        ..replaceObject(5, CosDictionary({'Rev': const CosInteger(1)}));

      final doc2 = CosDocument.open(updater1.save());
      final updater2 = CosIncrementalUpdater(doc2)
        ..replaceObject(5, CosDictionary({'Rev': const CosInteger(2)}));

      final reopened = CosDocument.open(updater2.save());
      expect((reopened.getObject(5, 0) as CosDictionary)['Rev'],
          const CosInteger(2));
      expect(reopened.catalog.typeName, 'Catalog');
    });

    test('markChanged maps a mutated object back to its number', () {
      final doc = CosDocument.open(buildClassicPdf());
      final page = doc.getObject(3, 0) as CosDictionary;
      page['Rotate'] = const CosInteger(90);

      final updater = CosIncrementalUpdater(doc);
      final ref = updater.markChanged(page);
      expect(ref, const CosReference(3, 0));

      final reopened = CosDocument.open(updater.save());
      expect((reopened.getObject(3, 0) as CosDictionary)['Rotate'],
          const CosInteger(90));
    });

    test('markChanged rejects foreign objects', () {
      final doc = CosDocument.open(buildClassicPdf());
      expect(() => CosIncrementalUpdater(doc).markChanged(CosDictionary()),
          throwsArgumentError);
    });
  });

  group('incremental update of an xref-stream file', () {
    test('update is written as a cross-reference stream', () {
      final doc = CosDocument.open(buildXrefStreamPdf());
      final updater = CosIncrementalUpdater(doc);
      // object 3 originally lives inside an object stream
      updater.replaceObject(
          3,
          CosDictionary({
            'Type': const CosName('Page'),
            'Parent': const CosReference(2, 0),
            'MediaBox': CosArray([
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(300),
              const CosInteger(400),
            ]),
          }));
      final updated = updater.save();

      final reopened = CosDocument.open(updated);
      expect(reopened.trailer.typeName, 'XRef');
      final page = reopened.getObject(3, 0) as CosDictionary;
      final box = reopened.resolve(page['MediaBox']) as CosArray;
      expect(box[2], const CosInteger(300));
      // objects still inside the original object stream remain reachable
      expect(reopened.catalog.typeName, 'Catalog');
    });
  });

  group('a junk /Size at or past 2^32', () {
    // The updater numbers new objects from /Size (distrusting it only on the
    // low side), so a writer that stored -1 as a uint32 hands it numbers past
    // what the packed object-cache key holds. They must still resolve.
    for (final size in [0xFFFFFFFF, 0x100000003]) {
      for (final (layout, build) in [
        ('classic table', buildClassicPdf),
        ('xref stream', buildXrefStreamPdf),
      ]) {
        test('$layout, /Size $size: added objects resolve live and reopened',
            () {
          final doc = CosDocument.open(withSize(build(), size));
          expect(doc.declaredSize, size);
          final updater = CosIncrementalUpdater(doc);
          final first = CosDictionary({'N': const CosInteger(1)});
          final second = CosDictionary({'N': const CosInteger(2)});
          final firstRef = updater.addObject(first);
          final secondRef = updater.addObject(second);
          expect(firstRef.objectNumber, size);
          expect(secondRef.objectNumber, size + 1);
          expect(doc.resolve(firstRef), same(first));
          expect(doc.resolve(secondRef), same(second));
          expect(doc.referenceTo(second), secondRef);
          // (3, 1) packs to 2^32 + 3: the page, never an added object.
          expect((doc.getObject(3, 1) as CosDictionary).typeName, 'Page');

          final reopened = CosDocument.open(updater.save());
          expect((reopened.resolve(firstRef) as CosDictionary)['N'],
              const CosInteger(1));
          expect((reopened.resolve(secondRef) as CosDictionary)['N'],
              const CosInteger(2));
          expect((reopened.getObject(3, 1) as CosDictionary).typeName, 'Page');
          expect(reopened.catalog.typeName, 'Catalog');
        });
      }
    }
  });
}
