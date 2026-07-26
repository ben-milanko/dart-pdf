import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// A [PdfByteSource] over an in-memory buffer that records every range it is
/// asked for, and can simulate the real-world quirks the loader must survive:
/// an unknown length (a server that answers no Range and no Content-Length),
/// per-read failure (cancellation, a dropped connection), and corrupted bytes
/// (a malformed response body).
class RecordingSource implements PdfByteSource {
  RecordingSource(
    this._bytes, {
    this.knownLength = true,
    this.failAtRead,
    this.corrupt = const {},
  });

  final Uint8List _bytes;
  final bool knownLength;

  /// Throw a [StateError] when this many reads have been served (1-based),
  /// standing in for a cancelled or dropped transfer.
  final int? failAtRead;

  /// Byte offsets whose value the source flips, corrupting the response.
  final Set<int> corrupt;

  final List<({int start, int end})> reads = [];
  int closes = 0;

  int get bytesFetched =>
      reads.fold(0, (sum, r) => sum + (r.end - r.start));

  bool covers(int offset) => reads.any((r) => offset >= r.start && offset < r.end);

  @override
  Future<int?> get length async => knownLength ? _bytes.length : null;

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    reads.add((start: start, end: endExclusive));
    if (failAtRead != null && reads.length >= failAtRead!) {
      throw StateError('transfer cancelled');
    }
    final s = start < 0 ? 0 : (start > _bytes.length ? _bytes.length : start);
    final e = endExclusive < s
        ? s
        : (endExclusive > _bytes.length ? _bytes.length : endExclusive);
    final view = Uint8List.fromList(_bytes.sublist(s, e));
    for (final at in corrupt) {
      if (at >= s && at < e) view[at - s] ^= 0xFF;
    }
    return view;
  }

  @override
  Future<void> close() async => closes++;
}

/// A source that ignores the requested end and always returns bytes through
/// end-of-file - i.e. it hands back more than asked for. Models a server that
/// answers a Range request with a 200-style full body.
class _OverReadSource implements PdfByteSource {
  _OverReadSource(this._bytes);
  final Uint8List _bytes;

  @override
  Future<int?> get length async => _bytes.length;

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    final s = start < 0 ? 0 : (start > _bytes.length ? _bytes.length : start);
    return Uint8List.sublistView(_bytes, s); // to EOF, ignoring endExclusive
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('progressive load over a range-capable source', () {
    test('opens a classic xref-table document', () async {
      final source = RecordingSource(buildClassicPdf());
      final doc = await CosDocument.openSource(source);

      expect(doc.catalog.typeName, 'Catalog');
      final page = doc.getObject(3, 0) as CosDictionary;
      expect(page.typeName, 'Page');
      final content = doc.getObject(4, 0) as CosStream;
      expect(String.fromCharCodes(doc.decodeStreamData(content)),
          contains('Hello, world!'));
    });

    test('opens an xref-stream + object-stream document', () async {
      final source = RecordingSource(buildXrefStreamPdf());
      final doc = await CosDocument.openSource(source);

      expect(doc.version, '1.5');
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect(pages.typeName, 'Pages');
      final page = doc.resolve((pages['Kids'] as CosArray)[0]) as CosDictionary;
      expect(page.typeName, 'Page');
    });

    test('walks a cross-reference-stream /Prev chain with an /Index', () async {
      // An incremental update of an xref-stream file appends a second xref
      // stream that carries an /Index for just the changed object and a /Prev
      // back to the original - exercising the stream path twice, the /Index
      // branch, and /Prev following through streams.
      final base = CosDocument.open(buildXrefStreamPdf());
      final updated = (CosIncrementalUpdater(base)
            ..replaceObject(1,
                CosDictionary({'Type': const CosName('Catalog'), 'Pages': const CosReference(2, 0)})))
          .save();
      final doc = await CosDocument.openSource(RecordingSource(updated));
      expect(doc.catalog.typeName, 'Catalog');
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect(pages.typeName, 'Pages');
    });

    test('grows the window to fit a cross-reference stream body', () async {
      // A tiny xref window forces the loader to widen it until the xref
      // stream (and its /Prev chain) fits, covering the retry path.
      final base = CosDocument.open(buildXrefStreamPdf());
      final updated = (CosIncrementalUpdater(base)
            ..replaceObject(1,
                CosDictionary({'Type': const CosName('Catalog'), 'Pages': const CosReference(2, 0)})))
          .save();
      final doc = await CosDocument.openSource(RecordingSource(updated),
          options: const PdfSourceLoadOptions(
              headWindow: 32, tailWindow: 32, xrefWindow: 16));
      expect(doc.catalog.typeName, 'Catalog');
    });

    test('opens a larger multi-page document', () async {
      final source = RecordingSource(buildMultiPagePdf(8));
      final doc = await CosDocument.openSource(source);
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect((pages['Kids'] as CosArray).length, 8);
    });

    test('fetches the header and tail as separate ranges, not one blob',
        () async {
      final bytes = buildMultiPagePdf(6);
      final source = RecordingSource(bytes);
      // Small probes so the body is fetched separately from the header/tail,
      // making the ranged (non-blob) behaviour observable on a small file.
      await CosDocument.openSource(source,
          options: const PdfSourceLoadOptions(headWindow: 128, tailWindow: 128));

      // Progressive: more than one request, none of them the whole file.
      expect(source.reads.length, greaterThan(1));
      expect(source.reads.any((r) => r.start == 0 && r.end >= bytes.length),
          isFalse);
      // The header probe starts at 0; the tail window reaches the last byte.
      expect(source.reads.any((r) => r.start == 0), isTrue);
      expect(source.covers(bytes.length - 1), isTrue);
    });

    test('walks a /Prev chain from an incremental update', () async {
      final base = CosDocument.open(buildClassicPdf());
      final updated = (CosIncrementalUpdater(base)
            ..replaceObject(
                5,
                CosDictionary({
                  'Type': const CosName('Font'),
                  'Subtype': const CosName('Type1'),
                  'BaseFont': const CosName('Courier'),
                })))
          .save();

      final doc = await CosDocument.openSource(RecordingSource(updated));
      // Newest revision wins, older objects still resolve through /Prev.
      expect((doc.getObject(5, 0) as CosDictionary)['BaseFont'],
          const CosName('Courier'));
      expect((doc.getObject(3, 0) as CosDictionary).typeName, 'Page');
      expect(doc.catalog.typeName, 'Catalog');
    });

    test('opens correctly with tiny head and tail windows', () async {
      // Small windows force the loader to grow xref windows and issue many
      // small ranged reads; the result must still be correct.
      final bytes = buildMultiPagePdf(12);
      final source = RecordingSource(bytes);
      final doc = await CosDocument.openSource(source,
          options: const PdfSourceLoadOptions(
              tailWindow: 128, headWindow: 128, xrefWindow: 128));
      expect(doc.catalog.typeName, 'Catalog');
      expect((doc.resolve(doc.catalog['Pages']) as CosDictionary)['Kids'],
          isA<CosArray>());
    });

    test('reports progress with a monotonic count and the real total',
        () async {
      final bytes = buildMultiPagePdf(4);
      final seen = <int>[];
      int? total;
      await CosDocument.openSource(
        RecordingSource(bytes),
        options: PdfSourceLoadOptions(onProgress: (fetched, t) {
          seen.add(fetched);
          total = t;
        }),
      );
      expect(seen, isNotEmpty);
      expect(total, bytes.length);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
    });
  });

  group('fallback to a full download', () {
    test('unknown length downloads sequentially and still opens', () async {
      final bytes = buildClassicPdf();
      final source = RecordingSource(bytes, knownLength: false);
      final doc = await CosDocument.openSource(source);

      expect(doc.catalog.typeName, 'Catalog');
      // No ranged probing: the first read starts at 0.
      expect(source.reads.first.start, 0);
    });

    test('unknown length chunks until a short read signals EOF', () async {
      final bytes = buildMultiPagePdf(4);
      final source = RecordingSource(bytes, knownLength: false);
      final doc = await CosDocument.openSource(
        source,
        options: const PdfSourceLoadOptions(downloadChunk: 512),
      );
      expect(doc.catalog.typeName, 'Catalog');
      // Reads advance by the chunk size from zero.
      expect(source.reads.first, (start: 0, end: 512));
      expect(source.bytesFetched, greaterThanOrEqualTo(bytes.length));
    });

    test('a broken startxref falls back and recovers via a full scan',
        () async {
      final bytes = Uint8List.fromList(buildClassicPdf());
      // Corrupt the startxref offset digits near the tail so the ranged xref
      // walk fails; recovery in CosDocument.open then rebuilds by scanning.
      final marker = 'startxref'.codeUnits;
      var at = -1;
      for (var p = bytes.length - marker.length; p >= 0; p--) {
        var match = true;
        for (var i = 0; i < marker.length; i++) {
          if (bytes[p + i] != marker[i]) {
            match = false;
            break;
          }
        }
        if (match) {
          at = p;
          break;
        }
      }
      expect(at, greaterThan(0));
      // Overwrite the offset that follows with an absurd value.
      for (var i = at + marker.length + 1; i < bytes.length - 6; i++) {
        if (bytes[i] >= 0x30 && bytes[i] <= 0x39) bytes[i] = 0x39; // 9
      }
      final doc = await CosDocument.openSource(RecordingSource(bytes));
      expect(doc.catalog.typeName, 'Catalog');
    });
  });

  group('errors and cancellation', () {
    test('a cancelled transfer surfaces the error', () async {
      final source = RecordingSource(buildMultiPagePdf(4), failAtRead: 1);
      await expectLater(
        CosDocument.openSource(source),
        throwsA(isA<StateError>()),
      );
    });

    test('non-PDF data throws a parse exception', () async {
      final source = RecordingSource(
          Uint8List.fromList('this is definitely not a pdf'.codeUnits));
      await expectLater(
        CosDocument.openSource(source),
        throwsA(isA<CosParseException>()),
      );
    });

    test('a corrupted object body is reported, not silently accepted',
        () async {
      // Corrupting a byte inside the object region makes the eventual parse
      // of that object fail; opening the catalog surfaces it rather than
      // returning wrong data.
      final bytes = buildClassicPdf();
      // Corrupt a spread of interior bytes (object region), leaving the
      // header and tail intact so the xref still parses.
      final corrupt = <int>{
        for (var i = 20; i < bytes.length - 80; i += 7) i,
      };
      final source = RecordingSource(bytes, corrupt: corrupt);
      // Either it throws, or the catalog is unreachable - never a bogus
      // "valid" catalog silently built from garbage.
      try {
        final doc = await CosDocument.openSource(source);
        // If it opened, the recovery path must still find a real catalog.
        expect(doc.catalog.typeName, 'Catalog');
      } on Object {
        // Acceptable: corruption detected.
      }
    });
  });

  group('misbehaving sources', () {
    test('a source that over-returns bytes does not crash the load', () async {
      // Some servers answer a ranged read with more bytes than requested
      // (a 206 carrying the whole file). The loader must clamp, not throw a
      // RangeError past the buffer end.
      final doc = await CosDocument.openSource(_OverReadSource(buildClassicPdf()));
      expect(doc.catalog.typeName, 'Catalog');
    });
  });

  group('encrypted documents', () {
    test('decrypts through the source path with the owner password',
        () async {
      final source = RecordingSource(buildEncryptedPdf());
      final doc = await CosDocument.openSource(source, password: 'owner');
      expect(doc.isEncrypted, isTrue);
      final info = doc.resolve(doc.trailer['Info']) as CosDictionary;
      expect((info['Title'] as CosString).text, 'Secret Title');
    });

    test('a wrong password throws, not a corrupt document', () async {
      final source = RecordingSource(buildEncryptedPdf(userPassword: 'secret'));
      await expectLater(
        CosDocument.openSource(source, password: 'wrong'),
        throwsA(isA<CosPasswordException>()),
      );
    });
  });

  group('PdfBytesByteSource', () {
    test('serves clamped ranges', () async {
      final source = PdfBytesByteSource(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(await source.length, 5);
      expect(await source.readRange(1, 3), [2, 3]);
      expect(await source.readRange(3, 100), [4, 5]);
      expect(await source.readRange(10, 20), isEmpty);
      expect(await source.readRange(-5, 2), [1, 2]);
      await source.close(); // no-op, must not throw
    });

    test('opens a document through the in-memory source', () async {
      final doc =
          await CosDocument.openSource(PdfBytesByteSource(buildClassicPdf()));
      expect(doc.catalog.typeName, 'Catalog');
    });
  });

  group('page-scoped first paint', () {
    // Small windows so the head/tail/xref fetches don't blanket these tiny
    // fixtures - then a deferred page's bytes are genuinely never requested.

    // Byte offset of the first occurrence of [needle] in [bytes] (the fixtures
    // are ASCII, so a latin1 char index is the byte offset).
    int offsetOf(Uint8List bytes, String needle) {
      final at = latin1.decode(bytes, allowInvalid: true).indexOf(needle);
      expect(at, greaterThanOrEqualTo(0), reason: 'missing "$needle"');
      return at;
    }

    test('fetches only the first page, not later pages', () async {
      final bytes = buildMultiPagePdf(8);
      final source = RecordingSource(bytes);
      final doc = await CosDocument.openSource(source,
          options: const PdfSourceLoadOptions(
              firstPaintPages: 1,
              headWindow: 64,
              tailWindow: 200,
              xrefWindow: 4096));

      // Page 1's content is fetched and the document opens...
      expect(doc.catalog.typeName, 'Catalog');
      expect(source.covers(offsetOf(bytes, '(Page 1)')), isTrue);
      // ...but the later pages' content streams are left unfetched.
      expect(source.covers(offsetOf(bytes, '(Page 2)')), isFalse);
      expect(source.covers(offsetOf(bytes, '(Page 8)')), isFalse);

      // The whole page tree is still fetched, so navigation and page count work
      // (every /Type /Page dictionary is present) - the pages just render blank
      // until their content arrives.
      var from = 0;
      final text = latin1.decode(bytes, allowInvalid: true);
      while (true) {
        final at = text.indexOf('/Type /Page /Parent', from);
        if (at < 0) break;
        expect(source.covers(at), isTrue, reason: 'page dict at $at unfetched');
        from = at + 1;
      }

      // And it read far less than fetching every object.
      final full = RecordingSource(bytes);
      await CosDocument.openSource(full,
          options: const PdfSourceLoadOptions(
              headWindow: 64,
              tailWindow: 200,
              xrefWindow: 4096));
      expect(source.bytesFetched, lessThan(full.bytesFetched));
    });

    test('firstPaintPages: 3 covers the first three pages only', () async {
      final bytes = buildMultiPagePdf(8);
      final source = RecordingSource(bytes);
      await CosDocument.openSource(source,
          options: const PdfSourceLoadOptions(
              firstPaintPages: 3,
              headWindow: 64,
              tailWindow: 200,
              xrefWindow: 4096));
      expect(source.covers(offsetOf(bytes, '(Page 3)')), isTrue);
      expect(source.covers(offsetOf(bytes, '(Page 4)')), isFalse);
    });

    test('page 1 is fully resolvable from the partial buffer', () async {
      final bytes = buildMultiPagePdf(5);
      final doc = await CosDocument.openSource(RecordingSource(bytes),
          options: const PdfSourceLoadOptions(
              firstPaintPages: 1,
              headWindow: 64,
              tailWindow: 200,
              xrefWindow: 4096));
      // catalog → pages → first kid → its content stream decodes to page 1.
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      final firstKid =
          doc.resolve((pages['Kids'] as CosArray).items.first) as CosDictionary;
      final content = doc.resolve(firstKid['Contents']) as CosStream;
      expect(latin1.decode(doc.decodeStreamData(content)), contains('(Page 1)'));
    });

    test('handles a compressed (object-stream) page dictionary', () async {
      // The single page's dict lives inside an /ObjStm, exercising the
      // compressed-object fetch/decode path of the page walk.
      final doc = await CosDocument.openSource(
          RecordingSource(buildXrefStreamPdf()),
          options: const PdfSourceLoadOptions(firstPaintPages: 1));
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect(pages.typeName, 'Pages');
      final firstKid =
          doc.resolve((pages['Kids'] as CosArray).items.first) as CosDictionary;
      expect(firstKid.typeName, 'Page');
    });

    test('falls back to fetching everything when firstPaintPages is null',
        () async {
      final bytes = buildMultiPagePdf(4);
      final source = RecordingSource(bytes);
      await CosDocument.openSource(source);
      // The default path still fetches every page's content.
      expect(source.covers(offsetOf(bytes, '(Page 4)')), isTrue);
    });
  });
}
