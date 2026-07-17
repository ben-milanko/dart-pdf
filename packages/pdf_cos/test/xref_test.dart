import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// CosXrefReader is the cross-reference machinery lifted out of CosDocument:
// locating startxref, parsing a single section (classic table or /XRef stream,
// including /W widths and /Index ranges), and walking the /Prev+/XRefStm chain
// newest-to-oldest into one merged {entries, trailer} view. Being pure over a
// byte buffer, a /W-width, /Index-range, or /Prev-cycle bug is provokable from
// a bare section plus trailer - without hand-crafting a whole valid document.

/// Wraps a raw cross-reference stream body (/W [1 1 1] rows) as an indirect
/// object at offset 0, so [CosXrefReader.parseSection] can read it directly.
Uint8List _xrefStreamSection(String dict, List<int> rows) {
  return (BytesBuilder()
        ..add(ascii('7 0 obj\n<< /Type /XRef $dict /Length ${rows.length} '
            '>>\nstream\n'))
        ..add(Uint8List.fromList(rows))
        ..add(ascii('\nendstream\nendobj\n')))
      .takeBytes();
}

void main() {
  group('findStartXref', () {
    test('reads the value declared after the keyword', () {
      final bytes = buildClassicPdf();
      final reader = CosXrefReader(bytes);
      // The startxref points at the `xref` keyword.
      final offset = reader.findStartXref();
      expect(bytes.sublist(offset, offset + 4), ascii('xref'));
    });

    test('throws when the keyword is missing', () {
      final bytes = ascii('%PDF-1.4\njunk with no start marker\n%%EOF\n');
      expect(() => CosXrefReader(bytes).findStartXref(),
          throwsA(isA<CosParseException>()));
    });
  });

  group('parseSection - classic table', () {
    test('parses entries and the trailer', () {
      final bytes = buildClassicPdf();
      final reader = CosXrefReader(bytes);
      final section = reader.parseSection(reader.findStartXref());

      expect(section.trailer['Root'], const CosReference(1, 0));
      // object 0 is the free-list head; 1..5 are in-use definitions.
      expect(section.entries[0]!.type, CosXrefEntryType.free);
      for (var n = 1; n <= 5; n++) {
        expect(section.entries[n]!.type, CosXrefEntryType.inUse);
        expect(section.entries[n]!.offset, greaterThan(0));
      }
    });

    test('rejects an offset outside the file', () {
      final bytes = buildClassicPdf();
      final reader = CosXrefReader(bytes);
      expect(() => reader.parseSection(bytes.length + 10),
          throwsA(isA<CosParseException>()));
      expect(
          () => reader.parseSection(-1), throwsA(isA<CosParseException>()));
    });
  });

  group('parseSection - xref stream', () {
    test('decodes /W-width fields and the default /Index', () {
      final bytes = buildXrefStreamPdf();
      final reader = CosXrefReader(bytes);
      final section = reader.parseSection(reader.findStartXref());

      // /W [1 4 2]: object 4 is the object stream (in use); 1..3 live compressed
      // inside it; 5 is the xref stream itself.
      expect(section.entries[4]!.type, CosXrefEntryType.inUse);
      for (var n = 1; n <= 3; n++) {
        expect(section.entries[n]!.type, CosXrefEntryType.compressed);
        expect(section.entries[n]!.streamObjectNumber, 4);
      }
      expect(section.entries[1]!.indexInStream, 0);
      expect(section.entries[3]!.indexInStream, 2);
      expect(section.entries[5]!.type, CosXrefEntryType.inUse);
    });

    test('honours an explicit /Index range', () {
      // Two rows starting at object 10: an in-use offset and a compressed slot.
      final bytes = _xrefStreamSection(
        '/Size 12 /W [1 1 1] /Index [10 2]',
        [1, 0x20, 0, 2, 4, 1],
      );
      final section = CosXrefReader(bytes).parseSection(0);

      expect(section.entries.keys.toSet(), {10, 11});
      expect(section.entries[10]!.type, CosXrefEntryType.inUse);
      expect(section.entries[10]!.offset, 0x20);
      expect(section.entries[11]!.type, CosXrefEntryType.compressed);
      expect(section.entries[11]!.streamObjectNumber, 4);
      expect(section.entries[11]!.indexInStream, 1);
    });

    test('a zero-width type field defaults to in use (§7.5.8.3)', () {
      // /W [0 1 1]: no type column, so every row is an in-use entry.
      final bytes = _xrefStreamSection(
        '/Size 6 /W [0 1 1] /Index [3 1]',
        [0x40, 0],
      );
      final section = CosXrefReader(bytes).parseSection(0);
      expect(section.entries[3]!.type, CosXrefEntryType.inUse);
      expect(section.entries[3]!.offset, 0x40);
    });
  });

  group('read / walkFrom - chain traversal', () {
    test('read merges the whole chain, newest section wins', () {
      // An incremental update appends a second xref section pointing /Prev at
      // the base; the appended definition of object 5 must win.
      final original = buildClassicPdf();
      final updated = (CosIncrementalUpdater(CosDocument.open(original))
            ..replaceObject(
              5,
              CosDictionary({'BaseFont': const CosName('Courier')}),
            ))
          .save();

      final base = CosXrefReader(original).read();
      final merged = CosXrefReader(updated).read();

      expect(merged.trailer['Prev'], isA<CosInteger>());
      expect(merged.startXref, CosXrefReader(updated).findStartXref());
      // Object 5's newest entry sits in the appended region, past the base.
      expect(merged.entries[5]!.offset, greaterThan(base.entries[5]!.offset));
      expect(merged.entries[5]!.offset, greaterThanOrEqualTo(original.length));
      // Untouched objects still resolve through the retained base section.
      expect(merged.entries[3]!.type, CosXrefEntryType.inUse);
    });

    test('stopAt prunes the already-loaded tail of the chain', () {
      final original = buildClassicPdf();
      final updated = (CosIncrementalUpdater(CosDocument.open(original))
            ..replaceObject(5, CosDictionary({'A': const CosInteger(7)})))
          .save();

      final oldStart = CosXrefReader(original).findStartXref();
      final reader = CosXrefReader(updated);
      final newStart = reader.findStartXref();

      final full = reader.walkFrom(newStart);
      final appended = reader.walkFrom(newStart, stopAt: oldStart);

      // The full walk sees every object; stopping at the base section leaves
      // only what the appended revision redefined.
      expect(full.entries.keys, containsAll([1, 2, 3, 4, 5]));
      expect(appended.entries.keys, contains(5));
      expect(appended.entries.keys, isNot(contains(3)));
    });

    test('a /Prev cycle terminates via the visited-offset guard', () {
      // A section whose trailer chains /Prev back to its own offset would loop
      // forever without the guard.
      final buffer = StringBuffer('%PDF-1.4\n');
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>',
      ];
      final offsets = <int>[];
      for (var i = 0; i < objects.length; i++) {
        offsets.add(buffer.length);
        buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
      }
      final xrefOffset = buffer.length;
      buffer
        ..write('xref\n0 ${objects.length + 1}\n')
        ..write('0000000000 65535 f \n');
      for (final offset in offsets) {
        buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
      }
      // /Prev points back at this very section.
      buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R '
          '/Prev $xrefOffset >>\n');

      final xref = CosXrefReader(ascii(buffer.toString())).walkFrom(xrefOffset);
      expect(xref.entries[1]!.type, CosXrefEntryType.inUse);
      expect(xref.trailer['Root'], const CosReference(1, 0));
    });
  });

  group('shift', () {
    test('offsets are relative to the header, not the file start', () {
      // Junk before %PDF- shifts every file position; xref offsets stay
      // relative to the header, so the reader must be told the shift.
      final classic = buildClassicPdf();
      final shifted = (BytesBuilder()
            ..add(ascii('leading junk bytes\n'))
            ..add(classic))
          .takeBytes();
      final shift = shifted.length - classic.length;

      final xref = CosXrefReader(shifted, shift: shift).read();
      expect(xref.trailer['Root'], const CosReference(1, 0));
      expect(xref.entries[1]!.type, CosXrefEntryType.inUse);
    });
  });
}
