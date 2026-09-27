import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// CosDocument.applyIncrementalUpdate feeds an append-only incremental revision
// into an already-open document in place (a render worker reflecting one page's
// edit without re-parsing the whole xref chain). CosIncrementalUpdater produces
// exactly that shape - a prefix-append with a new xref section pointing /Prev at
// the old one.
void main() {
  test('merges an appended revision in place, evicting the changed object', () {
    final original = buildClassicPdf();
    final updated = (CosIncrementalUpdater(CosDocument.open(original))
          ..replaceObject(
            5,
            CosDictionary({
              'Type': const CosName('Font'),
              'Subtype': const CosName('Type1'),
              'BaseFont': const CosName('Courier'),
            }),
          ))
        .save();

    final doc = CosDocument.open(original);
    final revision = doc.revision;
    // Warm the cache for the object about to change, so the eviction path runs.
    doc.getObject(5, 0);
    doc.catalog;

    final changed = doc.applyIncrementalUpdate(updated);

    expect(changed, contains(5));
    expect(doc.revision, revision + 1);
    expect(doc.bytes.length, updated.length);
    expect(doc.startXref, greaterThan(0));
    // The redefined object resolves to the appended value (its cache entry was
    // evicted), while untouched objects still load through the retained ones.
    expect(
      (doc.getObject(5, 0) as CosDictionary)['BaseFont'],
      const CosName('Courier'),
    );
    expect((doc.getObject(3, 0) as CosDictionary).typeName, 'Page');
    expect(doc.catalog.typeName, 'Catalog');
    // The refreshed trailer chains /Prev back to the base revision and keeps the
    // doc-level keys (/Root) the incremental trailer carries over.
    expect(doc.trailer['Prev'], isA<CosInteger>());
    expect(doc.trailer['Root'], isNotNull);
  });

  test('evicts a changed object cached under a non-zero generation', () {
    // The eviction decodes the object number back out of the packed cache key,
    // so the generation bits must not leak into it. getObject does not check a
    // reference's generation against the xref, so any of these can be cached.
    const generations = [0, 1, 3, 65535];
    final original = buildClassicPdf();
    final updated = (CosIncrementalUpdater(CosDocument.open(original))
          ..replaceObject(5, CosDictionary({'A': const CosInteger(7)})))
        .save();

    final doc = CosDocument.open(original);
    for (final generation in generations) {
      expect((doc.getObject(5, generation) as CosDictionary)['A'], isNull);
    }
    final page = doc.getObject(3, 0);

    doc.applyIncrementalUpdate(updated);

    for (final generation in generations) {
      expect(
        (doc.getObject(5, generation) as CosDictionary)['A'],
        const CosInteger(7),
        reason: 'generation $generation',
      );
    }
    expect(doc.getObject(3, 0), same(page),
        reason: 'an untouched object keeps its cache entry');
  });

  test('resolves objects the appended revision adds', () {
    final original = buildClassicPdf();
    final updater = CosIncrementalUpdater(CosDocument.open(original));
    final ref =
        updater.addObject(CosDictionary({'New': const CosBoolean(true)}));
    final updated = updater.save();

    final doc = CosDocument.open(original);
    final changed = doc.applyIncrementalUpdate(updated);
    expect(changed, contains(ref.objectNumber));
    expect((doc.resolve(ref) as CosDictionary)['New'], const CosBoolean(true));
  });

  test('leaves the document equivalent to a fresh open of the new bytes', () {
    final original = buildClassicPdf();
    final updated = (CosIncrementalUpdater(CosDocument.open(original))
          ..replaceObject(5, CosDictionary({'A': const CosInteger(7)})))
        .save();

    final incremental = CosDocument.open(original)
      ..applyIncrementalUpdate(updated);
    final fresh = CosDocument.open(updated);

    expect(
      (incremental.getObject(5, 0) as CosDictionary)['A'],
      (fresh.getObject(5, 0) as CosDictionary)['A'],
    );
    expect(incremental.declaredSize, fresh.declaredSize);
  });

  test('rejects a buffer that is not an append', () {
    final original = buildClassicPdf();
    final doc = CosDocument.open(original);
    final revision = doc.revision;
    final shorter = Uint8List.sublistView(original, 0, original.length - 1);
    expect(
      () => doc.applyIncrementalUpdate(shorter),
      throwsA(isA<CosParseException>()),
    );
    expect(doc.revision, revision,
        reason: 'a rejected transition did not advance the graph');
  });
}
