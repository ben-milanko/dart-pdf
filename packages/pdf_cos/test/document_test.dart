import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('classic xref table', () {
    late CosDocument doc;

    setUp(() => doc = CosDocument.open(buildClassicPdf()));

    test('reads the header version', () {
      expect(doc.version, '1.4');
    });

    test('parses the trailer and catalog', () {
      expect(doc.trailer['Root'], const CosReference(1, 0));
      expect(doc.catalog.typeName, 'Catalog');
    });

    test('loads objects through the xref', () {
      final page = doc.getObject(3, 0) as CosDictionary;
      expect(page.typeName, 'Page');
      final box = doc.resolve(page['MediaBox']) as CosArray;
      expect(box.items, [
        const CosInteger(0),
        const CosInteger(0),
        const CosInteger(612),
        const CosInteger(792),
      ]);
    });

    test('resolve chases reference chains', () {
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect(pages.typeName, 'Pages');
    });

    test('decodes an unfiltered content stream', () {
      final content = doc.getObject(4, 0) as CosStream;
      final text = String.fromCharCodes(doc.decodeStreamData(content));
      expect(text, contains('Hello, world!'));
    });

    test('free and absent objects resolve to null', () {
      expect(doc.getObject(0, 65535), CosNull.instance);
      expect(doc.getObject(99, 0), CosNull.instance);
    });
  });

  group('xref stream + object stream', () {
    late CosDocument doc;

    setUp(() => doc = CosDocument.open(buildXrefStreamPdf()));

    test('parses the cross-reference stream', () {
      expect(doc.trailer['Root'], const CosReference(1, 0));
      expect(doc.version, '1.5');
    });

    test('loads objects out of the object stream', () {
      expect(doc.catalog.typeName, 'Catalog');
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect(pages.typeName, 'Pages');
      final page = doc.resolve((pages['Kids'] as CosArray)[0]) as CosDictionary;
      expect(page.typeName, 'Page');
      expect((doc.resolve(page['MediaBox']) as CosArray).length, 4);
    });

    test('a compressed object in a missing object stream resolves to null',
        () {
      // A page-scoped / progressive open leaves some object streams unfetched
      // (zeros). Objects the xref marks as living inside one must resolve to a
      // dangling null - like an in-use object at a junk offset - not throw, so
      // callers that already tolerate dangling references (forms, annotations)
      // don't fault on a partial buffer.
      final doc = CosDocument.open(_danglingCompressedPdf());
      expect(doc.catalog.typeName, 'Catalog'); // /Root is reachable
      // /Extra is marked compressed in an object stream that does not exist.
      expect(doc.resolve(doc.catalog['Extra']), isA<CosNull>());
    });

    test('a compressed object in an undecodable object stream resolves to null',
        () {
      // The object stream exists but its /FlateDecode body is garbage, so the
      // decoder throws a FormatException (not a CosParseException) - which must
      // still resolve to a dangling null rather than crashing the caller.
      final doc = CosDocument.open(_corruptObjStmPdf());
      expect(doc.catalog.typeName, 'Catalog');
      expect(doc.resolve(doc.catalog['Extra']), isA<CosNull>());
    });
  });

  group('object cache key', () {
    test('keeps the object number in the low bits', () {
      // Generation-0 keys are the object numbers themselves; the generation
      // rides above bit 32.
      expect(CosDocument.debugCacheKey(12345, 0), 12345);
      expect(CosDocument.debugCacheKey(12345, 3) % 0x100000000, 12345);
      expect(CosDocument.debugCacheKey(12345, 3),
          isNot(CosDocument.debugCacheKey(12346, 2)));
    });

    test('spreads sequential object numbers across hash buckets', () {
      // The VM int hash keeps trailing zero bits, so a key with zero low bits
      // (the old objectNumber * 65536 + generation: 726 of 4096 buckets here)
      // piles a large document's objects into one linear-probe chain.
      final buckets = {
        for (var n = 1; n <= 4096; n++)
          CosDocument.debugCacheKey(n, 0).hashCode & 4095,
      };
      expect(buckets.length, greaterThan(4000));
    });

    test('packed keys stay below 2^48, exact on dart2js', () {
      expect(CosDocument.debugCacheKey(0xFFFFFFFF, 0xFFFF),
          lessThan(0x1000000000000));
    });

    test('an object number past 2^32 does not alias a packed key', () {
      final doc = CosDocument.open(buildClassicPdf());
      // Object 5 under generation 1 packs to 2^32 + 5, the number of a ref
      // the key can't hold: that one is looked up by its own number.
      final five = doc.getObject(5, 1);
      expect(five, isA<CosDictionary>());
      expect(doc.getObject(0x100000000 + 5, 0), same(CosNull.instance));
      expect(doc.getObject(-1, 0), same(CosNull.instance));
      expect(doc.getObject(5, 1), same(five));
    });

    test('a generation past 65535 does not alias another object', () {
      final doc = CosDocument.open(buildClassicPdf());
      // `n * 65536 + g` put (3, 65536) on (4, 0); `g * 2^32 + n` is inexact
      // on dart2js from g = 2^21, where (4, 2^22) and (5, 2^22) collide.
      expect(doc.getObject(4, 0), isA<CosStream>());
      expect((doc.getObject(3, 65536) as CosDictionary).typeName, 'Page');
      const junk = 1 << 22;
      expect(doc.getObject(4, junk), isA<CosStream>());
      expect((doc.getObject(5, junk) as CosDictionary).typeName, 'Font');
      expect((doc.getObject(3, -1) as CosDictionary).typeName, 'Page');
      expect(
          doc.referenceTo(doc.getObject(5, junk)), const CosReference(5, junk));
    });

    test('adopts an object under a number past 2^32 without aliasing', () {
      final doc = CosDocument.open(buildClassicPdf());
      const ref = CosReference(0x100000000 + 3, 0);
      final added = CosDictionary({'A': const CosInteger(1)});
      doc.adoptObject(ref, added);
      expect(doc.getObject(ref.objectNumber, 0), same(added));
      expect(doc.referenceTo(added), ref);
      // (3, 1) packs to 2^32 + 3: still the page, not the adopted object.
      expect((doc.getObject(3, 1) as CosDictionary).typeName, 'Page');
    });
  });

  test('junk before the header shifts offsets', () {
    final junk = ascii('GARBAGE BYTES ');
    final pdf = buildClassicPdf();
    final shifted = (BytesBuilder()..add(junk)..add(pdf)).takeBytes();
    final doc = CosDocument.open(shifted);
    expect(doc.catalog.typeName, 'Catalog');
  });

  test('rejects non-PDF data', () {
    expect(() => CosDocument.open(ascii('not a pdf at all')),
        throwsA(isA<CosParseException>()));
  });

  group('xref recovery', () {
    /// Replaces every occurrence of [needle] in [bytes] with garbage of the
    /// same length, so offsets stay valid.
    Uint8List smash(Uint8List bytes, String needle) {
      final text = String.fromCharCodes(bytes);
      final replaced = text.replaceAll(needle, '#' * needle.length);
      expect(replaced, isNot(text), reason: 'needle "$needle" not found');
      return ascii(replaced);
    }

    test('recovers a classic file with a smashed startxref', () {
      final doc = CosDocument.open(smash(buildClassicPdf(), 'startxref'));
      expect(doc.catalog.typeName, 'Catalog');
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect(pages.typeName, 'Pages');
    });

    test('recovers a classic file whose xref table is corrupt', () {
      final doc = CosDocument.open(smash(buildClassicPdf(), 'xref\n0 6'));
      expect(doc.catalog.typeName, 'Catalog');
    });

    test('finds the catalog by type when the trailer is gone too', () {
      var bytes = smash(buildClassicPdf(), 'startxref');
      bytes = smash(bytes, 'trailer');
      final doc = CosDocument.open(bytes);
      expect(doc.trailer['Root'], const CosReference(1, 0));
      expect(doc.catalog.typeName, 'Catalog');
    });

    test('recovers compressed objects behind a broken xref stream', () {
      final doc = CosDocument.open(smash(buildXrefStreamPdf(), 'startxref'));
      // /Root comes from the xref stream's dictionary; the catalog lives
      // inside the object stream and resolves through the recovered index
      expect(doc.trailer['Root'], const CosReference(1, 0));
      expect(doc.catalog.typeName, 'Catalog');
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect(pages.typeName, 'Pages');
    });

    test('recovery reuses the object-stream decoder for the header index', () {
      // Every compressed object must resolve through the recovered index,
      // including the last one in the stream (index 2) - proving recovery
      // reuses the decoder's parsed (number, offset) pairs rather than a
      // second inline header parse.
      final doc = CosDocument.open(smash(buildXrefStreamPdf(), 'startxref'));
      final page = doc.getObject(3, 0) as CosDictionary;
      expect(page.typeName, 'Page');
      expect((doc.resolve(page['MediaBox']) as CosArray).length, 4);
      expect(doc.resolve(page['Parent']), doc.resolve(const CosReference(2, 0)));
    });

    test('a truncated object-stream header still salvages leading objects', () {
      // ObjStm declares /N 2 but the second pair's offset is junk ("z"),
      // so only object 2 parses. Recovery must keep that leading object
      // instead of dropping the whole stream (lenient on input).
      const header = '2 0 3 z '; // pair 1 = (2, 0); pair 2 offset is not an int
      const payload = '<< /Fnord 2 >> << /Zap 3 >>';
      const first = header.length;
      const objStmData = header + payload;
      final body = StringBuffer('%PDF-1.5\n')
        ..write('1 0 obj\n<< /Type /ObjStm /N 2 /First $first '
            '/Length ${objStmData.length} >>\nstream\n$objStmData\n'
            'endstream\nendobj\n');
      // No xref/startxref, so open() falls back to scan recovery.
      final doc = CosDocument.open(ascii(body.toString()));
      final salvaged = doc.getObject(2, 0) as CosDictionary;
      expect((salvaged['Fnord'] as CosInteger).value, 2);
      // Object 3 never parsed out of the broken header, so it is absent.
      expect(doc.getObject(3, 0), CosNull.instance);
    });

    test('the last definition of an object number wins', () {
      final updated = (BytesBuilder()
            ..add(smash(buildClassicPdf(), 'startxref'))
            ..add(ascii('5 0 obj\n<< /Type /Font /Subtype /Type1 '
                '/BaseFont /Courier >>\nendobj\n')))
          .takeBytes();
      final doc = CosDocument.open(updated);
      final font = doc.getObject(5, 0) as CosDictionary;
      expect((font['BaseFont'] as CosName).value, 'Courier');
    });

    test('object headers inside string content do not derail recovery', () {
      // "1 0 obj" appearing inside a content stream must not shadow the
      // real object 1 that appears later
      const decoy = 'BT (see 1 0 obj here) Tj ET';
      final body = StringBuffer('%PDF-1.4\n')
        ..write('2 0 obj\n<< /Length ${decoy.length} >>\nstream\n'
            '$decoy\nendstream\nendobj\n')
        ..write('1 0 obj\n<< /Type /Catalog /Pages 3 0 R >>\nendobj\n')
        ..write('3 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n');
      final doc = CosDocument.open(ascii(body.toString()));
      expect(doc.catalog.typeName, 'Catalog');
    });

    // The recovery scan finds `obj` and `trailer` in one skipping pass; these
    // hold it to exactly what a byte-at-a-time search of the file finds.
    test('recovers the entries and trailer an intact chain declares', () {
      final twoRevisions =
          (CosIncrementalUpdater(CosDocument.open(buildClassicPdf()))
                ..replaceObject(5, CosDictionary({'A': const CosInteger(1)}))
                ..addObject(CosDictionary({'B': const CosInteger(2)})))
              .save();
      for (final (name, bytes) in [
        ('classic', buildClassicPdf()),
        ('40 pages', buildMultiPagePdf(40)),
        ('xref stream', buildXrefStreamPdf()),
        ('two revisions', twoRevisions),
      ]) {
        final intact = CosDocument.open(bytes);
        final recovered = CosDocument.open(smash(bytes, 'startxref'));
        expect(recovered.startXref, 0, reason: name);
        final live = {
          for (final n in intact.objectNumbers)
            if (intact.xrefEntry(n)!.type != CosXrefEntryType.free) n,
        };
        expect(recovered.objectNumbers.toSet(), live, reason: name);
        for (final n in live) {
          final a = intact.xrefEntry(n)!, b = recovered.xrefEntry(n)!;
          expect(
            (b.type, b.offset, b.generation, b.streamObjectNumber),
            (a.type, a.offset, a.generation, a.streamObjectNumber),
            reason: '$name object $n',
          );
        }
        expect(recovered.trailer['Root'], intact.trailer['Root'], reason: name);
        expect(recovered.declaredSize, intact.declaredSize, reason: name);
      }
      // Both revisions' trailers merge in file order: the update's /Prev
      // survives, and its /Size wins.
      final merged = CosDocument.open(smash(twoRevisions, 'startxref'));
      expect(merged.trailer['Prev'], isA<CosInteger>());
      expect(merged.declaredSize, 7);
    });

    test('finds exactly the headers and trailers a plain search finds', () {
      final random = math.Random(20260927);
      var key = 0;
      String token() => switch (random.nextInt(44)) {
            0 => '1 0 obj',
            1 => '12 0 obj',
            2 => '3 1 obj',
            3 => ' obj',
            4 => 'obj',
            5 => 'oobj',
            6 => 'objobj',
            7 => 'ob',
            8 => 'bj',
            9 => 'j',
            10 => 'o',
            11 => 'b',
            12 => 't',
            13 => 'r',
            14 => 'a',
            15 => 'tra',
            16 => 'trai',
            17 => 'iler',
            18 => 'trailer',
            19 => 'trailertrailer',
            20 => 'ttrailer',
            21 => 'atrailer',
            22 || 23 => 'trailer<</K${key++} ${random.nextInt(9)}>>',
            24 => ' ',
            25 => '\n',
            26 => '\r\n',
            27 => '\x00',
            28 => '7',
            29 => '42',
            30 => '0 ',
            31 => '(',
            32 => ')',
            33 => '<<',
            34 => '>>',
            35 => '/',
            36 => '%',
            37 => 'endobj',
            38 => 'x',
            39 => 'a obj',
            40 => '99999999999 0 obj',
            41 => '5 123456 obj',
            42 => '0 0 obj',
            _ => '${1 + random.nextInt(30)} ${random.nextInt(3)} obj',
          };
      for (var round = 0; round < 120; round++) {
        final text = StringBuffer('%PDF-1.4\n1 0 obj\n<< >>\nendobj\n');
        final length = 20 + random.nextInt(400);
        for (var t = 0; t < length; t++) {
          text.write(token());
        }
        final bytes = latin1.encode(text.toString());
        // Every other round is sparse: holes (zeros) the scan must skip.
        List<int>? populated;
        if (round.isOdd) {
          populated = [0, 30];
          var at = 30;
          while (at < bytes.length) {
            final end = math.min(bytes.length, at + 1 + random.nextInt(40));
            if (random.nextBool() || end - at < 3) {
              if (populated.last == at) {
                populated.last = end;
              } else {
                populated.addAll([at, end]);
              }
            } else {
              bytes.fillRange(at, end, 0);
            }
            at = end;
          }
        }
        final expected = _plainRecoveryScan(bytes, populated);
        final doc = CosDocument.open(Uint8List.fromList(bytes),
            populatedRanges: populated);
        final found = {
          for (final n in doc.objectNumbers)
            n: (doc.xrefEntry(n)!.offset, doc.xrefEntry(n)!.generation),
        };
        expect(found, expected.headers, reason: 'round $round: $text');
        final trailer = {
          for (final e in doc.trailer.entries.entries)
            if (e.key != 'Size') e.key: e.value,
        };
        expect(trailer, expected.trailer, reason: 'round $round: $text');
      }
    });
  });

  group('corrupt files (pdf.js corpus classes)', () {
    /// Assembles objects (1-based) into a classic-xref file, with an
    /// optional corruption hook over the computed offsets.
    Uint8List build(List<String> objects,
        {void Function(List<int> offsets)? corrupt}) {
      final buffer = StringBuffer('%PDF-1.4\n');
      final offsets = <int>[];
      for (var i = 0; i < objects.length; i++) {
        offsets.add(buffer.length);
        buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
      }
      corrupt?.call(offsets);
      final xrefOffset = buffer.length;
      buffer
        ..write('xref\n0 ${objects.length + 1}\n')
        ..write('0000000000 65535 f \n');
      for (final offset in offsets) {
        buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
      }
      buffer
        ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
        ..write('startxref\n$xrefOffset\n%%EOF\n');
      return ascii(buffer.toString());
    }

    test('a stream whose /Length references its own object loads', () {
      // poppler-91414: `4 0 obj << /Length 4 0 R >> stream` used to
      // recurse forever (stack overflow); the re-entrant load now answers
      // null and the parser scans for "endstream" instead
      const content = 'BT (self) Tj ET';
      final doc = CosDocument.open(build([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] '
            '/Contents 4 0 R >>',
        '<< /Length 4 0 R >>\nstream\n$content\nendstream',
      ]));
      final stream = doc.getObject(4, 0) as CosStream;
      expect(String.fromCharCodes(doc.decodeStreamData(stream)), content);
    });

    test(
        'an xref offset pointing at the wrong object falls back to a '
        'header scan', () {
      // poppler-395: regenerated xrefs point entry N at some other
      // object's bytes; the loader used to throw, now it rescans
      final doc = CosDocument.open(build(
        [
          '<< /Type /Catalog /Pages 2 0 R >>',
          '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>',
          '<< /Marker (the real object 4) >>',
        ],
        // every entry in the table points at its neighbour's bytes
        corrupt: (offsets) {
          final last = offsets.removeLast();
          offsets.insert(0, last);
        },
      ));
      final four = doc.getObject(4, 0) as CosDictionary;
      expect(
          (doc.resolve(four['Marker']) as CosString).text, 'the real object 4');
      expect(doc.catalog.typeName, 'Catalog');
    });
  });
}

/// What xref recovery must find in [bytes], by the plain search it replaced:
/// every `N G obj` header whose `obj` starts at a populated offset (the last
/// definition of a number wins), and the dictionary after every `trailer`
/// keyword (merged in file order, without the /Size recovery fills in).
({Map<int, (int, int)> headers, Map<String, CosObject> trailer})
    _plainRecoveryScan(Uint8List bytes, List<int>? populated) {
  const whitespace = r'\x00\t\n\f\r ';
  const nonRegular = '$whitespace' r'()<>\[\]{}/%';
  final header = RegExp('(?<![^$nonRegular])([0-9]{1,10})[$whitespace]+'
      '([0-9]{1,5})[$whitespace]+obj(?![^$nonRegular])');
  bool isPopulated(int offset) {
    if (populated == null) return true;
    for (var i = 0; i < populated.length; i += 2) {
      if (offset >= populated[i] && offset < populated[i + 1]) return true;
    }
    return false;
  }

  final text = latin1.decode(bytes);
  final headers = <int, (int, int)>{};
  for (final match in header.allMatches(text)) {
    final number = int.parse(match[1]!);
    if (number == 0 || !isPopulated(match.end - 3)) continue;
    headers[number] = (match.start, int.parse(match[2]!));
  }
  final trailer = <String, CosObject>{};
  for (var t = text.indexOf('trailer');
      t >= 0;
      t = text.indexOf('trailer', t + 7)) {
    try {
      final candidate = CosParser(bytes, offset: t + 7).parseObject();
      if (candidate is CosDictionary) trailer.addAll(candidate.entries);
    } on Exception {
      // junk that happens to contain the keyword
    }
  }
  trailer.remove('Size');
  return (headers: headers, trailer: trailer);
}

/// A cross-reference-stream PDF whose object 4 (/Extra on the catalog) is marked
/// as compressed inside object stream 99 - which does not exist. The catalog
/// (/Root) and pages node stay uncompressed so the document opens; resolving
/// /Extra must yield a dangling null rather than throwing.
Uint8List _danglingCompressedPdf() {
  final out = StringBuffer('%PDF-1.5\n');
  final offset1 = out.length;
  out.write('1 0 obj\n<< /Type /Catalog /Pages 2 0 R /Extra 4 0 R >>\nendobj\n');
  final offset2 = out.length;
  out.write('2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n');

  final xrefOffset = out.length;
  final rows = <List<int>>[
    [0, 0, 0xFFFF], // 0: free-list head
    [1, offset1, 0], // 1: catalog
    [1, offset2, 0], // 2: pages
    [1, xrefOffset, 0], // 3: this xref stream
    [2, 99, 0], // 4: "compressed" in the non-existent stream 99
  ];
  final xrefData = <int>[];
  for (final row in rows) {
    xrefData
      ..add(row[0])
      ..addAll([
        (row[1] >> 24) & 0xFF,
        (row[1] >> 16) & 0xFF,
        (row[1] >> 8) & 0xFF,
        row[1] & 0xFF,
      ])
      ..addAll([(row[2] >> 8) & 0xFF, row[2] & 0xFF]);
  }
  out.write('3 0 obj\n<< /Type /XRef /Size 5 /W [1 4 2] /Root 1 0 R '
      '/Length ${xrefData.length} >>\nstream\n');

  return (BytesBuilder()
        ..add(ascii(out.toString()))
        ..add(xrefData)
        ..add(ascii('\nendstream\nendobj\nstartxref\n$xrefOffset\n%%EOF\n')))
      .takeBytes();
}

/// Like [_danglingCompressedPdf], but object 4 lives in a real object stream
/// (object 5) whose /FlateDecode body is garbage - so decoding it throws a
/// FormatException, exercising the non-CosParseException leniency path.
Uint8List _corruptObjStmPdf() {
  final out = StringBuffer('%PDF-1.5\n');
  final offset1 = out.length;
  out.write('1 0 obj\n<< /Type /Catalog /Pages 2 0 R /Extra 4 0 R >>\nendobj\n');
  final offset2 = out.length;
  out.write('2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n');
  final offset5 = out.length;
  const garbage = 'not valid deflate data';
  out.write('5 0 obj\n<< /Type /ObjStm /N 1 /First 6 /Filter /FlateDecode '
      '/Length ${garbage.length} >>\nstream\n$garbage\nendstream\nendobj\n');

  final xrefOffset = out.length;
  final rows = <List<int>>[
    [0, 0, 0xFFFF], // 0: free-list head
    [1, offset1, 0], // 1: catalog
    [1, offset2, 0], // 2: pages
    [1, xrefOffset, 0], // 3: this xref stream
    [2, 5, 0], // 4: compressed in object stream 5, index 0
    [1, offset5, 0], // 5: the (corrupt) object stream
  ];
  final xrefData = <int>[];
  for (final row in rows) {
    xrefData
      ..add(row[0])
      ..addAll([
        (row[1] >> 24) & 0xFF,
        (row[1] >> 16) & 0xFF,
        (row[1] >> 8) & 0xFF,
        row[1] & 0xFF,
      ])
      ..addAll([(row[2] >> 8) & 0xFF, row[2] & 0xFF]);
  }
  out.write('3 0 obj\n<< /Type /XRef /Size 6 /W [1 4 2] /Root 1 0 R '
      '/Length ${xrefData.length} >>\nstream\n');

  return (BytesBuilder()
        ..add(ascii(out.toString()))
        ..add(xrefData)
        ..add(ascii('\nendstream\nendobj\nstartxref\n$xrefOffset\n%%EOF\n')))
      .takeBytes();
}
