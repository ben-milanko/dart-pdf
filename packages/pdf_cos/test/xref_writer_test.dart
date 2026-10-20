import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

/// Renders a writer callback to a string so the exact xref/trailer byte format
/// can be asserted verbatim - the whole point of sharing the framing.
String render(void Function(CosXrefTableWriter) body) {
  final out = BytesBuilder(copy: false);
  body(CosXrefTableWriter(out));
  return String.fromCharCodes(out.takeBytes());
}

void main() {
  group('runsOf', () {
    test('groups consecutive numbers into runs', () {
      expect(CosXrefTableWriter.runsOf([1, 2, 3]), [
        [1, 2, 3]
      ]);
      expect(CosXrefTableWriter.runsOf([1, 2, 4, 5, 9]), [
        [1, 2],
        [4, 5],
        [9]
      ]);
      expect(CosXrefTableWriter.runsOf([]), isEmpty);
    });
  });

  group('writeTable', () {
    test('from-scratch table leads with the object-0 free head', () {
      final table = render((w) => w.writeTable(
            {1: 15, 2: 74, 3: 132},
            (_) => 0,
            includeFreeHead: true,
          ));
      expect(
          table,
          'xref\n'
          '0 4\n'
          '0000000000 65535 f \n'
          '0000000015 00000 n \n'
          '0000000074 00000 n \n'
          '0000000132 00000 n \n');
    });

    test('incremental table omits the free head and splits runs', () {
      final table = render((w) => w.writeTable(
            {5: 900, 6: 950, 9: 1200},
            (n) => n == 6 ? 2 : 0,
          ));
      expect(
          table,
          'xref\n'
          '5 2\n'
          '0000000900 00000 n \n'
          '0000000950 00002 n \n'
          '9 1\n'
          '0000001200 00000 n \n');
    });
  });

  test('writeTrailer frames the dictionary with a trailing newline', () {
    final trailer = render((w) => w.writeTrailer(CosDictionary({
          'Size': const CosInteger(4),
          'Root': const CosReference(1, 0),
        })));
    expect(trailer, 'trailer\n<< /Size 4 /Root 1 0 R >>\n');
  });

  test('writeEpilogue points startxref at the offset', () {
    expect(render((w) => w.writeEpilogue(2048)),
        'startxref\n2048\n%%EOF\n');
  });
}
