// Predefined CJK CMap decoding (Shift-JIS, EUC-JP, GBK, Big5, UHC, and the
// Unicode CMaps) for non-embedded Type0 fonts.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/src/fonts/cjk_cmap.dart';
import 'package:test/test.dart';

void main() {
  group('ShiftJisCmap', () {
    const cmap = ShiftJisCmap();

    test('handles only RKSJ-family encoding names', () {
      expect(ShiftJisCmap.handles('90ms-RKSJ-H'), isTrue);
      expect(ShiftJisCmap.handles('90pv-RKSJ-V'), isTrue);
      expect(ShiftJisCmap.handles('Ext-RKSJ-H'), isTrue);
      expect(ShiftJisCmap.handles('Identity-H'), isFalse);
      expect(ShiftJisCmap.handles('UniJIS-UCS2-H'), isFalse);
      expect(ShiftJisCmap.handles(null), isFalse);
    });

    test('splits bytes by the Shift-JIS codespace', () {
      // 日本語テスト = 93FA 967B 8CEA 8365 8358 8367 (all two-byte).
      final bytes = Uint8List.fromList(
          [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67]);
      expect(cmap.split(bytes),
          [0x93FA, 0x967B, 0x8CEA, 0x8365, 0x8358, 0x8367]);
    });

    test('splits mixed single- and double-byte runs', () {
      // 'A' (0x41) + half-width katakana ｱ (0xB1) + 日 (0x93FA).
      final bytes = Uint8List.fromList([0x41, 0xB1, 0x93, 0xFA]);
      expect(cmap.split(bytes), [0x41, 0xB1, 0x93FA]);
    });

    test('maps two-byte codes to Unicode', () {
      expect(cmap.unicode(0x93FA), '日');
      expect(cmap.unicode(0x967B), '本');
      expect(cmap.unicode(0x8CEA), '語');
      expect(cmap.unicode(0x8365), 'テ');
      expect(cmap.unicode(0x8358), 'ス');
      expect(cmap.unicode(0x8367), 'ト');
    });

    test('maps single-byte ASCII and half-width katakana', () {
      expect(cmap.unicode(0x41), 'A');
      expect(cmap.unicode(0xB1), 'ｱ'); // U+FF71
      expect(cmap.unicode(0xDF), 'ﾟ'); // U+FF9F (last half-width kana)
    });

    test('returns empty for unmapped two-byte codes', () {
      expect(cmap.unicode(0x8540), isEmpty); // a reserved/undefined pair
    });
  });

  group('EucJpCmap', () {
    const cmap = EucJpCmap();

    test('handles only the EUC-H/V names', () {
      expect(EucJpCmap.handles('EUC-H'), isTrue);
      expect(EucJpCmap.handles('EUC-V'), isTrue);
      expect(EucJpCmap.handles('90ms-RKSJ-H'), isFalse);
      expect(EucJpCmap.handles('GBpc-EUC-H'), isFalse);
    });

    test('splits ASCII, SS2 half-width kana, and double-byte runs', () {
      // 'A' + ｱ (0x8E 0xB1) + 日 (0xC6 0xFC).
      final bytes = Uint8List.fromList([0x41, 0x8E, 0xB1, 0xC6, 0xFC]);
      expect(cmap.split(bytes), [0x41, 0x8EB1, 0xC6FC]);
    });

    test('consumes the SS3 (0x8F) JIS X 0212 prefix without decoding it', () {
      // 0x8F + two trailing bytes is one (unmapped) code, then 'A'.
      final bytes = Uint8List.fromList([0x8F, 0xA1, 0xA1, 0x41]);
      expect(cmap.split(bytes), [0x8FA1, 0x41]);
      expect(cmap.unicode(0x8FA1), isEmpty);
    });

    test('maps codes to Unicode', () {
      expect(cmap.unicode(0x41), 'A');
      expect(cmap.unicode(0xC6FC), '日');
      expect(cmap.unicode(0xCBDC), '本');
      expect(cmap.unicode(0x8EB1), 'ｱ'); // SS2 half-width kana
    });
  });

  group('GbkCmap', () {
    const cmap = GbkCmap();

    test('handles GB-registry names but not UniGB', () {
      expect(GbkCmap.handles('GBK-EUC-H'), isTrue);
      expect(GbkCmap.handles('GBKp-EUC-H'), isTrue);
      expect(GbkCmap.handles('GBpc-EUC-H'), isTrue);
      expect(GbkCmap.handles('UniGB-UCS2-H'), isFalse);
    });

    test('splits and maps double-byte codes', () {
      final bytes = Uint8List.fromList([0x41, 0xC4, 0xE3, 0xBA, 0xC3]);
      expect(cmap.split(bytes), [0x41, 0xC4E3, 0xBAC3]);
      expect(cmap.unicode(0x41), 'A');
      expect(cmap.unicode(0xC4E3), '你');
      expect(cmap.unicode(0xBAC3), '好');
    });
  });

  group('Big5Cmap', () {
    const cmap = Big5Cmap();

    test('handles B5-token names', () {
      expect(Big5Cmap.handles('B5pc-H'), isTrue);
      expect(Big5Cmap.handles('ETen-B5-H'), isTrue);
      expect(Big5Cmap.handles('HKscs-B5-H'), isTrue);
      expect(Big5Cmap.handles('GBK-EUC-H'), isFalse);
    });

    test('splits and maps double-byte codes', () {
      final bytes = Uint8List.fromList([0x41, 0xA4, 0xA4, 0xA4, 0xE5]);
      expect(cmap.split(bytes), [0x41, 0xA4A4, 0xA4E5]);
      expect(cmap.unicode(0xA4A4), '中');
      expect(cmap.unicode(0xA4E5), '文');
    });
  });

  group('UhcCmap', () {
    const cmap = UhcCmap();

    test('handles KSC-registry names but not UniKS', () {
      expect(UhcCmap.handles('KSC-EUC-H'), isTrue);
      expect(UhcCmap.handles('KSCms-UHC-H'), isTrue);
      expect(UhcCmap.handles('UniKS-UCS2-H'), isFalse);
    });

    test('splits and maps double-byte codes', () {
      final bytes = Uint8List.fromList([0x41, 0xC7, 0xD1, 0xB1, 0xDB]);
      expect(cmap.split(bytes), [0x41, 0xC7D1, 0xB1DB]);
      expect(cmap.unicode(0xC7D1), '한');
      expect(cmap.unicode(0xB1DB), '글');
    });
  });

  group('UnicodeCmap', () {
    test('UCS2 reads two-byte big-endian as Unicode', () {
      final cmap = UnicodeCmap.forName('UniJIS-UCS2-H')!;
      expect(cmap.utf16, isFalse);
      // 日本 = U+65E5 U+672C, big-endian two-byte codes.
      final bytes = Uint8List.fromList([0x65, 0xE5, 0x67, 0x2C]);
      expect(cmap.split(bytes), [0x65E5, 0x672C]);
      expect(cmap.unicode(0x65E5), '日');
      expect(cmap.unicode(0x672C), '本');
    });

    test('UTF16 combines surrogate pairs', () {
      final cmap = UnicodeCmap.forName('UniGB-UTF16-H')!;
      expect(cmap.utf16, isTrue);
      // U+1F600 = surrogate pair D83D DE00; plus a BMP code after it.
      final bytes = Uint8List.fromList([0xD8, 0x3D, 0xDE, 0x00, 0x00, 0x41]);
      expect(cmap.split(bytes), [0x1F600, 0x41]);
      expect(cmap.unicode(0x1F600), '😀');
    });

    test('forName ignores non-UCS2/UTF16 Uni names', () {
      expect(UnicodeCmap.forName('UniJIS-UTF8-H'), isNull);
    });
  });

  group('CjkCmap.forName', () {
    test('routes each predefined family and skips Identity', () {
      expect(CjkCmap.forName('90ms-RKSJ-H'), isA<ShiftJisCmap>());
      expect(CjkCmap.forName('EUC-H'), isA<EucJpCmap>());
      expect(CjkCmap.forName('GBKp-EUC-H'), isA<GbkCmap>());
      expect(CjkCmap.forName('ETen-B5-H'), isA<Big5Cmap>());
      expect(CjkCmap.forName('KSCms-UHC-H'), isA<UhcCmap>());
      expect(CjkCmap.forName('UniCNS-UCS2-H'), isA<UnicodeCmap>());
      expect(CjkCmap.forName('Identity-H'), isNull);
      expect(CjkCmap.forName(null), isNull);
    });
  });

  test('extracts Japanese from a non-embedded 90ms-RKSJ Type0 font', () {
    final file = File('../../test_corpora/pdfjs/90ms_rksj_h_sample.pdf');
    final doc = PdfDocument.open(file.readAsBytesSync());
    final text = PdfTextExtractor.extract(doc, 0);
    expect(text.text, contains('Hello ASCII'));
    expect(text.text, contains('日本語テスト'));
  });
}
