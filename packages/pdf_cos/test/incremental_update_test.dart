import 'dart:convert';
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
    const generations = [0, 1, 3, 65535, 65536, 1 << 22];
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

  test('evicts a changed object whose number is past 2^32', () {
    // A junk /Size past 2^32 makes the updater number new objects beyond what
    // the packed cache key holds. The render worker applies every revision in
    // place, so the eviction has to reach those cache entries too.
    final base = latin1.encode(latin1
        .decode(buildClassicPdf())
        .replaceFirst('/Size 6 ', '/Size ${0x100000003} '));
    final adding = CosIncrementalUpdater(CosDocument.open(base));
    final ref = adding.addObject(CosDictionary({'Rev': const CosInteger(1)}));
    expect(ref.objectNumber, 0x100000003);
    final first = adding.save();
    final second = (CosIncrementalUpdater(CosDocument.open(first))
          ..replaceObject(
              ref.objectNumber, CosDictionary({'Rev': const CosInteger(2)})))
        .save();

    final doc = CosDocument.open(base);
    expect(doc.resolve(ref), same(CosNull.instance));
    doc.applyIncrementalUpdate(first);
    expect((doc.resolve(ref) as CosDictionary)['Rev'], const CosInteger(1));
    final page = doc.getObject(3, 1);
    expect((page as CosDictionary).typeName, 'Page');

    doc.applyIncrementalUpdate(second);
    expect((doc.resolve(ref) as CosDictionary)['Rev'], const CosInteger(2));
    expect(doc.getObject(3, 1), same(page),
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

  // An xref-recovered document (startXref 0) takes updates in place too: the
  // updater chains its section with /Prev 0, which is where the walk stops.
  group('on a recovered document', () {
    /// Replaces every occurrence of [needle] with same-length garbage, so
    /// offsets stay valid but the cross-reference chain no longer opens.
    Uint8List smash(Uint8List bytes, String needle) {
      final text = latin1.decode(bytes);
      final replaced = text.replaceAll(needle, '#' * needle.length);
      expect(replaced, isNot(text), reason: 'needle "$needle" not found');
      return latin1.encode(replaced);
    }

    String serialized(CosDocument doc, int number) {
      final generation = doc.xrefEntry(number)?.generation ?? 0;
      return latin1
          .decode(CosSerializer.serialize(doc.getObject(number, generation)));
    }

    /// Every object [doc] knows serializes as it does in a from-scratch open
    /// of the same bytes - which, chained to /Prev 0, recovers them all again.
    void expectSameAsFreshOpen(CosDocument doc) {
      final fresh = CosDocument.open(Uint8List.fromList(doc.bytes));
      final numbers = {...doc.objectNumbers, ...fresh.objectNumbers};
      expect(numbers, isNotEmpty);
      for (final number in numbers) {
        expect(serialized(doc, number), serialized(fresh, number),
            reason: 'object $number');
      }
      expect(doc.trailer['Root'], fresh.trailer['Root']);
      expect(doc.declaredSize, fresh.declaredSize);
    }

    for (final (name, build, edited) in [
      ('classic', buildClassicPdf, 5),
      // Object 3 lives in an object stream until the edit rewrites it.
      ('xref-stream / object-stream', buildXrefStreamPdf, 3),
    ]) {
      test('applies an edit to a $name file in place', () {
        final broken = smash(build(), 'startxref');
        final doc = CosDocument.open(broken);
        expect(doc.startXref, 0, reason: 'opened through xref recovery');
        final revision = doc.revision;
        doc.getObject(edited, 0); // warm the entry the edit must evict

        final updater = CosIncrementalUpdater(doc)
          ..replaceObject(edited, CosDictionary({'A': const CosInteger(7)}));
        final added =
            updater.addObject(CosDictionary({'New': const CosBoolean(true)}));
        final updated = updater.save();
        final changed = doc.applyIncrementalUpdate(updated);

        expect(changed, containsAll([edited, added.objectNumber]));
        expect(doc.revision, revision + 1);
        expect(doc.startXref, greaterThan(0),
            reason: 'the appended section is a real chain head');
        expect((doc.getObject(edited, 0) as CosDictionary)['A'],
            const CosInteger(7));
        expect((doc.resolve(added) as CosDictionary)['New'],
            const CosBoolean(true));
        expect(doc.catalog.typeName, 'Catalog');
        expectSameAsFreshOpen(doc);

        // The next edit chains /Prev to the section the first one wrote, and
        // folds in like any intact document's.
        final firstSection = doc.startXref;
        final second = (CosIncrementalUpdater(doc)
              ..replaceObject(
                  edited, CosDictionary({'A': const CosInteger(8)})))
            .save();
        final secondSection = CosXrefReader(second)
            .parseSection(CosXrefReader(second).findStartXref());
        expect(secondSection.trailer['Prev'], CosInteger(firstSection));
        expect(doc.applyIncrementalUpdate(second), contains(edited));
        expect((doc.getObject(edited, 0) as CosDictionary)['A'],
            const CosInteger(8));
        expectSameAsFreshOpen(doc);
      });
    }

    /// [base] plus one object (number [number]) and a classic section for it
    /// whose trailer carries [prev] - another writer's append.
    Uint8List foreignAppend(Uint8List base, int number, {int? prev}) {
      final out = StringBuffer(latin1.decode(base));
      final objectOffset = out.length;
      out.write('$number 0 obj\n<< /Foreign true >>\nendobj\n');
      final xrefOffset = out.length;
      out
        ..write('xref\n$number 1\n')
        ..write('${objectOffset.toString().padLeft(10, '0')} 00000 n \n')
        ..write('trailer\n<< /Size ${number + 1} /Root 1 0 R'
            '${prev == null ? '' : ' /Prev $prev'} >>\n')
        ..write('startxref\n$xrefOffset\n%%EOF\n');
      return latin1.encode(out.toString());
    }

    test("takes another writer's section chained with /Prev 0", () {
      final doc = CosDocument.open(smash(buildClassicPdf(), 'startxref'));
      final updated = foreignAppend(doc.bytes, 6, prev: 0);
      expect(doc.applyIncrementalUpdate(updated), {6});
      expect((doc.getObject(6, 0) as CosDictionary)['Foreign'],
          const CosBoolean(true));
      expectSameAsFreshOpen(doc);
    });

    test('refuses a section that reaches into the recovered bytes', () {
      // The smashed file still holds its intact classic table; a section
      // chained to it would pull that chain's entries over the recovered ones
      // (a fresh open would follow the chain instead of recovering).
      final original = buildClassicPdf();
      final oldTable = CosXrefReader(original).findStartXref();
      final doc = CosDocument.open(smash(original, 'startxref'));
      final revision = doc.revision;
      final length = doc.bytes.length;

      expect(
        () => doc.applyIncrementalUpdate(
            foreignAppend(doc.bytes, 6, prev: oldTable)),
        throwsA(isA<CosParseException>()),
      );
      expect(doc.revision, revision);
      expect(doc.bytes.length, length);
      expect(doc.startXref, 0);
    });

    test('refuses an append that adds no cross-reference section', () {
      final doc = CosDocument.open(smash(buildClassicPdf(), 'startxref'));
      final updated = latin1.encode('${latin1.decode(doc.bytes)}'
          '6 0 obj\n<< /Loose true >>\nendobj\nstartxref\n0\n%%EOF\n');
      expect(() => doc.applyIncrementalUpdate(updated),
          throwsA(isA<CosParseException>()));
      expect(doc.startXref, 0);
    });
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
