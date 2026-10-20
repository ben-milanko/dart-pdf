import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// CosDocument.rollbackTo is applyIncrementalUpdate's undo: a render worker
// following an editor's undo takes its open document back to an earlier
// revision in place, keeping every object the undone revisions did not touch,
// instead of re-opening the shorter prefix cold.
void main() {
  /// [doc]'s bytes with [edit]'s objects saved after them.
  Uint8List update(CosDocument doc, void Function(CosIncrementalUpdater) edit) {
    final updater = CosIncrementalUpdater(doc);
    edit(updater);
    return updater.save();
  }

  CosDictionary marked(int value) => CosDictionary({'A': CosInteger(value)});

  String serialized(CosDocument doc, int number) {
    final generation = doc.xrefEntry(number)?.generation ?? 0;
    return latin1
        .decode(CosSerializer.serialize(doc.getObject(number, generation)));
  }

  /// [doc] reads exactly as a from-scratch open of the bytes it now holds.
  void expectSameAsFreshOpen(CosDocument doc, {String password = ''}) {
    final fresh =
        CosDocument.open(Uint8List.fromList(doc.bytes), password: password);
    expect(doc.startXref, fresh.startXref);
    expect(doc.objectNumbers.toSet(), fresh.objectNumbers.toSet());
    for (final number in fresh.objectNumbers) {
      // The entries themselves, not just what they load: a stale offset past
      // the prefix would still load through the lenient header rescan.
      final a = doc.xrefEntry(number)!, b = fresh.xrefEntry(number)!;
      expect((
        a.type,
        a.offset,
        a.generation,
        a.streamObjectNumber
      ), (
        b.type,
        b.offset,
        b.generation,
        b.streamObjectNumber
      ), reason: 'xref entry $number');
      expect(serialized(doc, number), serialized(fresh, number),
          reason: 'object $number');
    }
    // Key for key: the in-place merge keeps the base's key order.
    Map<String, String> entries(CosDictionary trailer) => {
          for (final MapEntry(:key, :value) in trailer.entries.entries)
            key: latin1.decode(CosSerializer.serialize(value)),
        };
    expect(entries(doc.trailer), entries(fresh.trailer));
  }

  test('rolls back one revision, keeping untouched objects warm', () {
    final original = buildClassicPdf();
    final doc = CosDocument.open(original);
    final first = update(doc, (u) => u.replaceObject(5, marked(1)));
    doc.applyIncrementalUpdate(first);
    late CosReference added;
    final second = update(doc, (u) {
      u.replaceObject(5, marked(2));
      added = u.addObject(marked(3));
    });
    doc.applyIncrementalUpdate(second);
    final page = doc.getObject(3, 0);
    expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(2));
    final revision = doc.revision;

    final rolled = doc.rollbackTo(first.length)!;

    expect(rolled.steps, 1);
    expect(rolled.changed, {5, added.objectNumber});
    expect(doc.revision, greaterThan(revision),
        reason: 'derived state keyed on the revision must invalidate');
    expect(doc.bytes.length, first.length);
    expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(1));
    expect(doc.resolve(added), same(CosNull.instance));
    expect(doc.getObject(3, 0), same(page),
        reason: 'an object no undone revision touched keeps its cache entry');
    expectSameAsFreshOpen(doc);

    // And once more, back to the revision it was opened at.
    expect(doc.rollbackTo(original.length)!.steps, 1);
    expect(doc.getObject(5, 0), isA<CosDictionary>());
    expect((doc.getObject(5, 0) as CosDictionary).typeName, 'Font');
    expect(doc.getObject(3, 0), same(page));
    expectSameAsFreshOpen(doc);
  });

  test('rolls back several revisions in one step', () {
    final original = buildClassicPdf();
    final doc = CosDocument.open(original);
    final lengths = <int>[];
    final added = <CosReference>[];
    for (var i = 0; i < 4; i++) {
      final next = update(doc, (u) {
        u.replaceObject(5, marked(i));
        added.add(u.addObject(marked(10 + i)));
      });
      doc.applyIncrementalUpdate(next);
      lengths.add(next.length);
    }

    final rolled = doc.rollbackTo(lengths[0])!;

    expect(rolled.steps, 3);
    expect(rolled.changed, {5, for (final r in added.skip(1)) r.objectNumber});
    expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(0));
    expect((doc.resolve(added[0]) as CosDictionary)['A'], const CosInteger(10));
    for (final ref in added.skip(1)) {
      expect(doc.resolve(ref), same(CosNull.instance));
    }
    expectSameAsFreshOpen(doc);
  });

  test('returns null, changing nothing, for a length it cannot roll back to',
      () {
    final original = buildClassicPdf();
    final doc = CosDocument.open(original);
    // Nothing is journaled at the revision a document was opened at.
    expect(doc.rollbackTo(original.length - 1), isNull);
    final first = update(doc, (u) => u.replaceObject(5, marked(1)));
    doc.applyIncrementalUpdate(first);
    final revision = doc.revision;
    final startXref = doc.startXref;

    for (final length in [
      original.length - 1, // not a revision boundary
      original.length + 1,
      first.length + 1, // past the document
      -1,
    ]) {
      expect(doc.rollbackTo(length), isNull, reason: 'length $length');
    }
    expect(doc.revision, revision);
    expect(doc.bytes.length, first.length);
    expect(doc.startXref, startXref);

    // The current length is a no-op, not a refusal.
    final same = doc.rollbackTo(first.length)!;
    expect(same.steps, 0);
    expect(same.changed, isEmpty);
    expect(doc.revision, revision);
  });

  test('refuses a prefix that no longer ends with its journaled startxref', () {
    final original = buildClassicPdf();
    final doc = CosDocument.open(original);
    final first = update(doc, (u) => u.replaceObject(5, marked(1)));
    doc.applyIncrementalUpdate(first);
    // Rewrite the original revision's startxref value inside the buffer: the
    // prefix of that length is no longer the revision that was journaled.
    final text = latin1.decode(doc.bytes);
    final at =
        text.lastIndexOf('startxref', original.length) + 'startxref\n'.length;
    doc.bytes[at] = doc.bytes[at] == 0x31 ? 0x32 : 0x31;

    expect(doc.rollbackTo(original.length), isNull);
    expect(doc.bytes.length, first.length);
    expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(1));
  });

  test('journals only the most recent 256 updates', () {
    final original = buildClassicPdf();
    final doc = CosDocument.open(original);
    final lengths = [original.length];
    for (var i = 0; i < 300; i++) {
      final next = update(doc, (u) => u.replaceObject(5, marked(i)));
      doc.applyIncrementalUpdate(next);
      lengths.add(next.length);
    }
    // 300 updates keep the entries of updates 45..300, whose bases are
    // lengths[44..299].
    expect(doc.rollbackTo(lengths[43]), isNull);
    expect(doc.bytes.length, lengths[300]);
    final rolled = doc.rollbackTo(lengths[44])!;
    expect(rolled.steps, 256);
    expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(43));
    expectSameAsFreshOpen(doc);
  });

  test("restores a sparse buffer's populated ranges", () {
    final original = buildClassicPdf();
    // The last few bytes (after the xref) never arrived; the ranges have a
    // hole at the end, so the update appends a range rather than extending.
    final ranges = [0, original.length - 3];
    final doc =
        CosDocument.open(Uint8List.fromList(original), populatedRanges: ranges);
    final first = update(doc, (u) => u.replaceObject(5, marked(1)));
    doc.applyIncrementalUpdate(first);
    final second = update(doc, (u) => u.replaceObject(5, marked(2)));
    doc.applyIncrementalUpdate(second);
    expect(doc.populatedRanges,
        [0, original.length - 3, original.length, second.length]);

    doc.rollbackTo(first.length);
    expect(doc.populatedRanges,
        [0, original.length - 3, original.length, first.length]);
    expect(cosSparseBufferRanges[doc.bytes], doc.populatedRanges);
    expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(1));

    doc.rollbackTo(original.length);
    expect(doc.populatedRanges, ranges);
    expect(cosSparseBufferRanges[doc.bytes], ranges);
  });

  test('evicts an undone object whose number is past 2^32', () {
    // A junk /Size past 2^32 makes the updater number new objects beyond
    // what the packed cache key holds; they live in the unpacked cache.
    final base = latin1.encode(latin1
        .decode(buildClassicPdf())
        .replaceFirst('/Size 6 ', '/Size ${0x100000003} '));
    final doc = CosDocument.open(base);
    late CosReference ref;
    final first = update(doc, (u) => ref = u.addObject(marked(1)));
    expect(ref.objectNumber, 0x100000003);
    doc.applyIncrementalUpdate(first);
    expect((doc.resolve(ref) as CosDictionary)['A'], const CosInteger(1));

    expect(doc.rollbackTo(base.length)!.changed, {ref.objectNumber});
    expect(doc.resolve(ref), same(CosNull.instance));
    expect(doc.referenceTo(doc.getObject(3, 0)), const CosReference(3, 0));
  });

  test('rolls back an encrypted document with its keys', () {
    final original = buildEncryptedPdf(revision: 4);
    final doc = CosDocument.open(original);
    final handler = doc.encryption;
    expect(handler, isNotNull);
    final title = (doc.getObject(6, 0) as CosDictionary)['Title'] as CosString;
    expect(title.text, 'Secret Title');
    final first = update(
        doc,
        (u) => u.replaceObject(
            6, CosDictionary({'Title': CosString.fromText('Draft')})));
    doc.applyIncrementalUpdate(first);
    expect(((doc.getObject(6, 0) as CosDictionary)['Title'] as CosString).text,
        'Draft');

    doc.rollbackTo(original.length);

    expect(doc.encryption, same(handler));
    expect(((doc.getObject(6, 0) as CosDictionary)['Title'] as CosString).text,
        'Secret Title');
    expectSameAsFreshOpen(doc);
  });

  test('re-applies after a rollback, over bytes a different edit rewrote', () {
    // The render worker's buffer: capacity past the live revision, the next
    // revision's tail written in place, the document viewing a prefix.
    final original = buildClassicPdf();
    final buffer = Uint8List(original.length * 4)
      ..setRange(0, original.length, original);
    final doc =
        CosDocument.open(Uint8List.sublistView(buffer, 0, original.length));
    void append(Uint8List revision) {
      buffer.setRange(original.length, revision.length,
          Uint8List.sublistView(revision, original.length));
      doc.applyIncrementalUpdate(
          Uint8List.sublistView(buffer, 0, revision.length));
    }

    late CosReference addedA;
    final a = update(doc, (u) {
      u.replaceObject(5, marked(1));
      addedA = u.addObject(marked(100));
    });
    append(a);
    // Warm everything A defined, so the rollback has to drop it.
    expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(1));
    expect(doc.resolve(addedA), isA<CosDictionary>());

    doc.rollbackTo(original.length);
    final c = update(doc, (u) => u.replaceObject(4, marked(7)));
    append(c);

    expect(doc.getObject(5, 0), isA<CosDictionary>());
    expect((doc.getObject(5, 0) as CosDictionary).typeName, 'Font');
    expect((doc.getObject(4, 0) as CosDictionary)['A'], const CosInteger(7));
    expectSameAsFreshOpen(doc);

    // Back again, and forward to the first edit (a redo of A).
    doc.rollbackTo(original.length);
    append(a);
    expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(1));
    expectSameAsFreshOpen(doc);
  });

  group('on an xref-recovered base', () {
    Uint8List smash(Uint8List bytes) => latin1
        .encode(latin1.decode(bytes).replaceAll('startxref', '#########'));

    test('refuses the revision the document was recovered at', () {
      final broken = smash(buildClassicPdf());
      final doc = CosDocument.open(broken);
      expect(doc.startXref, 0);
      final first = update(doc, (u) => u.replaceObject(5, marked(1)));
      doc.applyIncrementalUpdate(first);
      final second = update(doc, (u) => u.replaceObject(5, marked(2)));
      doc.applyIncrementalUpdate(second);

      // The broken prefix declares no startxref to match the journal's 0.
      expect(doc.rollbackTo(broken.length), isNull);
      expect(doc.bytes.length, second.length);

      // Its own sections do: the first update is still reachable.
      expect(doc.rollbackTo(first.length)!.steps, 1);
      expect((doc.getObject(5, 0) as CosDictionary)['A'], const CosInteger(1));
      final fresh = CosDocument.open(Uint8List.fromList(doc.bytes));
      expect(serialized(doc, 5), serialized(fresh, 5));
    });
  });
}
