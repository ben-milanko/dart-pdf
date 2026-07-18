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
