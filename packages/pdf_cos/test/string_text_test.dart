import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

CosString bytesString(List<int> bytes) => CosString(Uint8List.fromList(bytes));

void main() {
  group('CosString.text decoding', () {
    test('plain ASCII is unchanged', () {
      expect(bytesString('Hello'.codeUnits).text, 'Hello');
    });

    test('Latin-1 high bytes (0xA1-0xFF) stay Latin-1', () {
      // 0xE9 = é, 0xFC = ü - identical in PDFDocEncoding and Latin-1.
      expect(bytesString([0x63, 0x61, 0x66, 0xE9]).text, 'café');
      expect(bytesString([0xFC]).text, 'ü');
    });

    test('PDFDocEncoding punctuation is not decoded as C1 controls', () {
      // Byte 0x85 is an en dash in PDFDocEncoding, not U+0085 (NEL), which
      // rendered as a missing-glyph "tofu" box in form-field dropdowns.
      expect(bytesString([0x85]).text, '–'); // en dash
      expect(bytesString([0x84]).text, '—'); // em dash
      expect(bytesString([0x80]).text, '•'); // bullet
      expect(bytesString([0x92]).text, '™'); // trademark
      expect(bytesString([0x8D]).text, '“'); // left double quote
      expect(bytesString([0x8E]).text, '”'); // right double quote
      expect(bytesString([0xA0]).text, '€'); // Euro
    });

    test('a real dropdown option decodes with an en dash', () {
      // "V6 ASB <0x85> Absolute Signal Blocking"
      final bytes = <int>[
        0x56, 0x36, 0x20, 0x41, 0x53, 0x42, 0x20, 0x85, 0x20, //
        0x41, 0x62, 0x73, 0x6F, 0x6C, 0x75, 0x74, 0x65, //
      ];
      expect(bytesString(bytes).text, 'V6 ASB – Absolute');
      expect(bytesString(bytes).text.contains(''), isFalse);
    });

    test('undefined PDFDocEncoding slots pass through as-is', () {
      // 0x7F, 0x9F, 0xAD have no PDFDocEncoding glyph; keep the raw byte.
      expect(bytesString([0xAD]).text, '­'); // soft hyphen
      expect(bytesString([0x7F]).text, '');
    });

    test('UTF-16BE with a BOM still decodes as UTF-16', () {
      // BOM + "A" + en dash (U+2013).
      final bytes = [0xFE, 0xFF, 0x00, 0x41, 0x20, 0x13];
      expect(bytesString(bytes).text, 'A–');
    });

    test('fromText round-trips an en dash through UTF-16BE', () {
      expect(CosString.fromText('a–b').text, 'a–b');
    });
  });
}
