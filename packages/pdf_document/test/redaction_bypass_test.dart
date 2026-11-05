import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// Regression tests for redaction bypasses (#1255 follow-up): each builds a
/// one-page PDF hiding a marker under a redaction box in some construct the
/// burn once missed, burns it, and checks the marker is nowhere in the
/// saved file - raw bytes or any decoded stream.

/// A one-page PDF: object 1 catalog, 2 pages, 3 page, 4 content, then
/// [extra] from object 5 on.
Uint8List _onePage({
  required String content,
  String resources = '/Font << /F1 5 0 R >>',
  List<String> extra = const [_helvetica],
  String catalogExtra = '',
  String pageExtra = '',
}) {
  final bodies = [
    '<< /Type /Catalog /Pages 2 0 R $catalogExtra >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << $resources >> $pageExtra >>',
    _stream('', content),
    ...extra,
  ];
  final buffer = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${bodies[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer
    ..write('xref\n0 ${bodies.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final o in offsets) {
    buffer.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

const _helvetica = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';

String _stream(String dict, String data) =>
    '<< $dict /Length ${data.length} >>\nstream\n$data\nendstream';

/// The raw file plus every stream it holds, decoded, as Latin-1 text.
String _everything(Uint8List bytes) {
  final out = StringBuffer(latin1.decode(bytes));
  final cos = PdfDocument.open(bytes).cos;
  for (final n in cos.objectNumbers) {
    final o = cos.resolve(CosReference(n, 0));
    if (o is! CosStream) continue;
    try {
      out.write(latin1.decode(cos.decodeStreamData(o)));
    } on Object {
      // left raw
    }
  }
  return out.toString();
}

/// Burns one redaction [rect] over [pdf] and returns everything readable.
String _burn(Uint8List pdf, PdfRect rect) {
  expect(PdfDocument.open(pdf).pageCount, 1);
  _before = _everything(pdf);
  final editor = PdfEditor(PdfDocument.open(pdf))..addRedaction(0, [rect]);
  final burned = editor.burnRedactions();
  expect(PdfDocument.open(burned).pageCount, 1);
  return _everything(burned);
}

/// What the last fixture held before its burn.
String _before = '';

void _gone(String all, String marker) {
  // the fixture really carries it, so its absence means something
  expect(_before.toLowerCase(), contains(marker.toLowerCase()),
      reason: 'fixture lacks $marker');
  expect(all.toLowerCase(), isNot(contains(marker.toLowerCase())),
      reason: '$marker leaked');
}

void main() {
  test('outlined vector shapes under a box are removed', () {
    final all = _burn(
      _onePage(
        content: '0 0 1 rg 100 700 m 150 700 l 150 720 l 133.33 711 l h f\n'
            // a curve sweeping through the box between control points
            // outside it
            '100 650 m 120 760 140 540 160 650 c S\n'
            // a table rule crossing the box stays
            '50 705 m 300 705 l S\n',
        extra: const [],
      ),
      const PdfRect(90, 640, 200, 730),
    );
    _gone(all, '133.33');
    _gone(all, '760');
    expect(all, contains('300 705 l'));
  });

  test('a soft-mask group is burned like a form', () {
    final all = _burn(
      _onePage(
        resources: '/ExtGState << /GS0 << /SMask << /S /Luminosity '
            '/G 6 0 R >> >> >> /Font << /F1 5 0 R >>',
        content: 'q /GS0 gs 0 g 100 700 200 20 re f Q',
        extra: [
          _helvetica,
          _stream(
              '/Type /XObject /Subtype /Form /BBox [0 0 612 792] '
                  '/Group << /S /Transparency /CS /DeviceGray >> '
                  '/Resources << /Font << /F1 5 0 R >> >>',
              'BT /F1 12 Tf 102 705 Td (SECRETSMASK) Tj ET'),
        ],
      ),
      const PdfRect(90, 690, 310, 730),
    );
    _gone(all, 'SECRETSMASK');
  });

  test('a font set through an ExtGState is measured', () {
    final all = _burn(
      _onePage(
        resources: '/ExtGState << /GS1 << /Font [5 0 R 24] >> >>',
        content: 'BT /GS1 gs 100 700 Td (XSECRETGSFONT) Tj ET',
      ),
      const PdfRect(125, 690, 400, 730),
    );
    _gone(all, 'GSFONT');
  });

  test('a form naming an XObject only its invoker defines is burned', () {
    final all = _burn(
      _onePage(
        resources: '/XObject << /Fm 5 0 R /Fm2 6 0 R >>',
        content: '/Fm Do',
        extra: [
          _stream(
              '/Type /XObject /Subtype /Form /BBox [0 0 612 792] '
                  '/Resources << >>',
              '/Fm2 Do'),
          _stream(
              '/Type /XObject /Subtype /Form /BBox [0 0 612 792] '
                  '/Resources << /Font << /F1 7 0 R >> >>',
              'BT /F1 12 Tf 100 700 Td (SECRETCHAIN) Tj ET'),
          _helvetica,
        ],
      ),
      const PdfRect(90, 690, 300, 730),
    );
    _gone(all, 'SECRETCHAIN');
  });

  test('a composite font with an embedded CMap is judged generously', () {
    final all = _burn(
      _onePage(
        resources: '/Font << /F2 5 0 R >>',
        content: 'BT /F2 20 Tf 100 700 Td (AAAAASECRETCMAP) Tj ET',
        extra: [
          '<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding 6 0 R '
              '/DescendantFonts [7 0 R] >>',
          _stream(
              '/Type /CMap /CMapName /OneByte',
              '1 begincodespacerange <00> <FF> endcodespacerange '
                  '1 begincidrange <00> <FF> 0 endcidrange'),
          '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X '
              '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
              '/Supplement 0 >> /DW 1000 >>',
        ],
      ),
      const PdfRect(250, 690, 420, 730),
    );
    _gone(all, 'SECRETCMAP');
  });

  test('vertical composite text is judged down its column', () {
    final all = _burn(
      _onePage(
        resources: '/Font << /F2 5 0 R >>',
        content: 'BT /F2 20 Tf 100 700 Td '
            '<00530045004300520045005400560045005200540049> Tj ET',
        extra: [
          '<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-V '
              '/DescendantFonts [6 0 R] >>',
          '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X '
              '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
              '/Supplement 0 >> /DW 50 >>',
        ],
      ),
      const PdfRect(80, 500, 130, 610),
    );
    _gone(all, '0053004500430052');
  });

  test('a form shows text in its invoker\'s font object', () {
    final widths = List.filled(95, '1').join(' ');
    final all = _burn(
      _onePage(
        resources: '/Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >>',
        content: 'BT /F1 12 Tf ET /Fm Do',
        extra: [
          _helvetica,
          _stream(
              '/Type /XObject /Subtype /Form /BBox [0 0 612 792] '
                  '/Resources << /Font << /F1 7 0 R >> >>',
              'BT 100 700 Td (SNAMESECRET) Tj ET'),
          '<< /Type /Font /Subtype /Type1 /BaseFont /Thin /FirstChar 32 '
              '/LastChar 126 /Widths [$widths] >>',
        ],
      ),
      const PdfRect(108, 690, 300, 730),
    );
    _gone(all, 'SECRET');
  });

  test('a tiling pattern painting under a box goes', () {
    final all = _burn(
      _onePage(
        resources: '/Pattern << /P0 5 0 R >>',
        content: '/Pattern cs /P0 scn 100 700 200 20 re f',
        extra: [
          _stream(
              '/PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 100 20] '
                  '/XStep 100 /YStep 20 /Resources << /Font << /F1 6 0 R >> >>',
              'BT /F1 10 Tf 0 5 Td (SECRETPAT) Tj ET'),
          _helvetica,
        ],
      ),
      const PdfRect(150, 690, 200, 730),
    );
    _gone(all, 'SECRETPAT');
  });

  test('a picture-carrying shading goes; a plain gradient stays', () {
    final all = _burn(
      _onePage(
        resources: '/Shading << /Sh0 << /ShadingType 1 /ColorSpace /DeviceGray '
            '/Function 5 0 R >> /Sh1 << /ShadingType 2 /ColorSpace /DeviceGray '
            '/Coords [0 0 1 0] /Function << /FunctionType 2 /Domain [0 1] '
            '/C0 [0] /C1 [1] /N 1 >> >> >>',
        content: 'q 100 700 100 20 re W n /Sh0 sh Q\n'
            // a gradient band crossing the box, its geometry outside it
            'q 50 600 400 20 re W n /Sh1 sh Q',
        extra: [
          _stream(
              '/FunctionType 0 /Domain [0 1 0 1] /Range [0 1] /Size [4 4] '
                  '/BitsPerSample 8',
              'SECRETSHADING!!!'),
        ],
      ),
      const PdfRect(90, 590, 300, 730),
    );
    _gone(all, 'SECRETSHADING');
    expect(all, contains('/Sh1 sh'));
  });

  test('a redacted image copy drops its alternates', () {
    final all = _burn(
      _onePage(
        resources: '/XObject << /Im 5 0 R >>',
        content: 'q 100 0 0 10 100 700 cm /Im Do Q',
        extra: [
          _stream(
              '/Type /XObject /Subtype /Image /Width 10 /Height 1 '
                  '/ColorSpace /DeviceGray /BitsPerComponent 8 '
                  '/Alternates [<< /Image 6 0 R >>]',
              'ABCDEFGHIJ'),
          _stream(
              '/Type /XObject /Subtype /Image /Width 20 /Height 1 '
                  '/ColorSpace /DeviceGray /BitsPerComponent 8',
              'SECRETALTERNATEIMAGE'),
        ],
      ),
      const PdfRect(90, 690, 150, 730),
    );
    _gone(all, 'SECRETALTERNATE');
    _gone(all, 'ABCDE');
    expect(all, contains('FGHIJ'));
  });

  test('structure text of removed content goes by MCID', () {
    final all = _burn(
      _onePage(
        resources: '/XObject << /Im 5 0 R >>',
        content: '/Figure << /MCID 0 >> BDC '
            'q 100 0 0 10 100 700 cm /Im Do Q EMC',
        catalogExtra: '/StructTreeRoot 6 0 R',
        pageExtra: '/StructParents 0',
        extra: [
          _stream(
              '/Type /XObject /Subtype /Image /Width 1 /Height 1 '
                  '/ColorSpace /DeviceGray /BitsPerComponent 8',
              'x'),
          '<< /Type /StructTreeRoot /K [7 0 R] /ParentTree 8 0 R >>',
          '<< /Type /StructElem /S /Figure /P 6 0 R /Pg 3 0 R /K 0 '
              '/Alt (Photo of SECRETALTTEXT) /ActualText (SECRETACTUAL) >>',
          '<< /Nums [0 [7 0 R]] >>',
        ],
      ),
      const PdfRect(90, 690, 210, 730),
    );
    _gone(all, 'SECRETALTTEXT');
    _gone(all, 'SECRETACTUAL');
  });

  test('named marked-content properties are stripped', () {
    final all = _burn(
      _onePage(
        resources: '/Font << /F1 5 0 R >> '
            '/Properties << /MC0 << /ActualText (SECRETPROPS) >> >>',
        content: '/Span /MC0 BDC BT /F1 12 Tf 100 700 Td (XXXX) Tj ET EMC',
      ),
      const PdfRect(90, 690, 200, 730),
    );
    _gone(all, 'SECRETPROPS');
  });

  test('a field whose only shown widget is redacted loses its value', () {
    final all = _burn(
      _onePage(
        content: '',
        catalogExtra: '/AcroForm << /Fields [5 0 R] >>',
        pageExtra: '/Annots [6 0 R]',
        extra: const [
          '<< /FT /Tx /T (f) /V (SECRETFIELD) /Kids [6 0 R 7 0 R] >>',
          '<< /Type /Annot /Subtype /Widget /Parent 5 0 R '
              '/Rect [100 700 200 720] /P 3 0 R >>',
          '<< /Type /Annot /Subtype /Widget /Parent 5 0 R /F 2 '
              '/Rect [0 0 0 0] >>',
        ],
        resources: '',
      ),
      const PdfRect(90, 690, 210, 730),
    );
    _gone(all, 'SECRETFIELD');
  });

  test('glyph outlines are tested near their origin, not across /Widths', () {
    final widths = List.filled(95, '100000').join(' ');
    final all = _burn(
      _onePage(
        resources: '/Font << /FW 5 0 R >>',
        content: 'BT /FW 12 Tf -1193 Tc 100 700 Td (WIDESECRET) Tj ET',
        extra: [
          '<< /Type /Font /Subtype /Type1 /BaseFont /Wide /FirstChar 32 '
              '/LastChar 126 /Widths [$widths] >>',
        ],
      ),
      const PdfRect(90, 690, 200, 730),
    );
    _gone(all, 'SECRET');
  });

  test('a Type 3 glyph is tested where its procedure draws', () {
    final widths = List.filled(26, '1000').join(' ');
    final diffs = List.filled(26, '/a').join(' ');
    final all = _burn(
      _onePage(
        resources: '/Font << /T3 5 0 R >>',
        content: 'BT /T3 20 Tf 100 600 Td (SECRETTHREE) Tj ET',
        extra: [
          '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 0 0] '
              '/FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << /a 6 0 R >> '
              '/Encoding << /Differences [65 $diffs] >> /FirstChar 65 '
              '/LastChar 90 /Widths [$widths] >>',
          _stream('', '1000 0 0 3000 900 4000 d1 0 3000 900 1000 re f'),
        ],
      ),
      const PdfRect(90, 655, 340, 685),
    );
    _gone(all, 'SECRETTHREE');
  });

  test('size-0 text spaced out by Tc is placed glyph by glyph', () {
    final all = _burn(
      _onePage(
        content: 'BT /F1 0 Tf 10 Tc 100 700 Td (ZEROSIZESECRET) Tj ET',
      ),
      const PdfRect(130, 690, 300, 730),
    );
    _gone(all, 'SIZESECRET');
  });

  test('form text clipped away by its BBox is still burned', () {
    final all = _burn(
      _onePage(
        resources: '/XObject << /Fm 5 0 R >>',
        content: '/Fm Do',
        extra: [
          _stream(
              '/Type /XObject /Subtype /Form /BBox [400 100 410 110] '
                  '/Resources << /Font << /F1 6 0 R >> >>',
              'BT /F1 12 Tf 100 700 Td (SECRETCLIPPED) Tj ET'),
          _helvetica,
        ],
      ),
      const PdfRect(90, 690, 300, 730),
    );
    _gone(all, 'SECRETCLIPPED');
  });

  test('a box over the upper body of large glyphs takes them', () {
    final all = _burn(
      _onePage(content: 'BT /F1 100 Tf 72 500 Td (BIGSECRET) Tj ET'),
      const PdfRect(60, 540, 750, 620),
    );
    _gone(all, 'BIGSECRET');
    _gone(all, 'SECRET');
  });

  test('an open popup under a box takes the comment it shows', () {
    final all = _burn(
      _onePage(
        content: '',
        resources: '',
        pageExtra: '/Annots [5 0 R 6 0 R]',
        extra: const [
          '<< /Type /Annot /Subtype /Text /Rect [500 500 520 520] '
              '/Contents (SECRETPOPUP) /Popup 6 0 R >>',
          '<< /Type /Annot /Subtype /Popup /Rect [100 690 200 720] '
              '/Parent 5 0 R /Open true >>',
        ],
      ),
      const PdfRect(90, 680, 210, 730),
    );
    _gone(all, 'SECRETPOPUP');
  });

  test('the replaced content stream goes even when referenced elsewhere', () {
    final all = _burn(
      _onePage(
        content: 'BT /F1 12 Tf 100 700 Td (SECRETEXTRA) Tj ET',
        catalogExtra: '/Extra 4 0 R',
      ),
      const PdfRect(90, 690, 300, 730),
    );
    _gone(all, 'SECRETEXTRA');
  });

  test('text in a font the page does not define is judged generously', () {
    final all = _burn(
      _onePage(
        content: 'BT /Missing 12 Tf 100 700 Td (AAAAAAAAAAAASECRETNOFONT) Tj '
            'ET',
        extra: const [],
        resources: '',
      ),
      const PdfRect(200, 690, 260, 730),
    );
    _gone(all, 'SECRETNOFONT');
  });

  test('text a box does not touch survives every generous path', () {
    final all = _burn(
      _onePage(
        content: 'BT /F1 12 Tf 100 700 Td (SECRETTOP) Tj ET\n'
            'BT /F1 12 Tf 100 300 Td (CONTROLLOW) Tj ET',
      ),
      const PdfRect(90, 690, 300, 730),
    );
    _gone(all, 'SECRETTOP');
    expect(all, contains('CONTROLLOW'));
  });

  group('round 2', () {
    const box = PdfRect(90, 690, 300, 730);
    String text(String prefix) =>
        '$prefix BT /F1 12 Tf 100 700 Td (SECRETOPS) Tj ET';

    test('an over-long cm is read as viewers read it', () {
      final all =
          _burn(_onePage(content: text('0 0 0 0 0 0 1 0 0 1 0 0 cm')), box);
      _gone(all, 'SECRETOPS');
    });

    test('a cm with mistyped operands is dropped, as viewers drop it', () {
      final all = _burn(_onePage(content: text('/a /b /c /d /e /f cm')), box);
      _gone(all, 'SECRETOPS');
    });

    test('an over-long Td moves where viewers move', () {
      final all = _burn(
        _onePage(content: 'BT /F1 12 Tf 400 100 700 Td (SECRETTD) Tj ET'),
        box,
      );
      _gone(all, 'SECRETTD');
    });

    test('a Tj with two strings shows the last', () {
      final all = _burn(
        _onePage(content: 'BT /F1 12 Tf 100 700 Td (X) (XXSECRET) Tj ET'),
        box,
      );
      _gone(all, 'XXSECRET');
    });

    test('a Do with two names draws the last', () {
      final all = _burn(
        _onePage(
          resources: '/XObject << /Safe 5 0 R /Sec 6 0 R >>',
          content: 'q 100 0 0 20 100 700 cm /Safe /Sec Do Q',
          extra: [
            _stream(
                '/Type /XObject /Subtype /Form /BBox [0 0 1 1] '
                    '/Matrix [1 0 0 1 5000 5000]',
                ''),
            _stream(
                '/Type /XObject /Subtype /Image /Width 10 /Height 1 '
                    '/ColorSpace /DeviceGray /BitsPerComponent 8',
                'SECRETDOIM'),
          ],
        ),
        box,
      );
      _gone(all, 'SECRETDOIM');
    });

    test('inline image data is delimited the way every viewer agrees', () {
      final all = _burn(
        _onePage(
          content: 'q BI /W 1 /H 1 /CS /G /BPC 8 ID XEI\n'
              'BT /F1 12 Tf 100 700 Td (SECRETINLINE) Tj ET\nEI\nQ',
        ),
        box,
      );
      _gone(all, 'SECRETINLINE');
    });

    test('a clip outline under a box is not printed through a fill', () {
      final all = _burn(
        _onePage(
          content: 'q 150 700 m 161.777 725 l 170 700 l h W n '
              '0 0 612 792 re f Q',
          extra: const [],
        ),
        const PdfRect(140, 690, 200, 730),
      );
      _gone(all, '161.777');
      expect(all, contains('0 0 612 792 re'));
    });

    test('a dash pattern placing marks under a box goes, array and all', () {
      final all = _burn(
        _onePage(
          content: '20 w [0 140 3.777 2 5 2 7 1000] 0 d '
              '100 700 m 400 700 l S',
          extra: const [],
        ),
        const PdfRect(230, 680, 300, 720),
      );
      _gone(all, '3.777');
    });

    test('a stitched gradient is a picture', () {
      final all = _burn(
        _onePage(
          resources: '/Shading << /Sh0 << /ShadingType 2 '
              '/ColorSpace /DeviceGray /Coords [0 0 612 0] /Function << '
              '/FunctionType 3 /Domain [0 1] /Bounds [0.31337 0.5] '
              '/Encode [0 1 0 1 0 1] /Functions [<< /FunctionType 2 '
              '/Domain [0 1] /C0 [0] /C1 [0] /N 1 >> << /FunctionType 2 '
              '/Domain [0 1] /C0 [1] /C1 [1] /N 1 >> << /FunctionType 2 '
              '/Domain [0 1] /C0 [0] /C1 [0] /N 1 >>] >> >> >>',
          content: 'q 50 700 400 1 re W n /Sh0 sh Q',
          extra: const [],
        ),
        box,
      );
      _gone(all, '0.31337');
    });

    test('each Type 3 glyph is tested over its own box', () {
      final widths = List.filled(26, '1000').join(' ');
      final diffs = '65 ${List.filled(25, '/a').join(' ')} /z';
      final all = _burn(
        _onePage(
          resources: '/Font << /T3 5 0 R >>',
          content: 'BT /T3 20 Tf 100 600 Td (SECRETTALL) Tj ET',
          extra: [
            '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 0 0] '
                '/FontMatrix [0.001 0 0 0.001 0 0] '
                '/CharProcs << /a 6 0 R /z 7 0 R >> '
                '/Encoding << /Differences [$diffs] >> /FirstChar 65 '
                '/LastChar 90 /Widths [$widths] >>',
            _stream('', '1000 0 0 0 900 1000 d1 0 0 900 1000 re f'),
            _stream('', '1000 0 0 0 900 10000 d1 0 0 900 10000 re f'),
          ],
        ),
        const PdfRect(90, 598, 340, 622),
      );
      _gone(all, 'SECRETTALL');
    });

    test('a composite string with a stray byte is judged generously', () {
      final all = _burn(
        _onePage(
          resources: '/Font << /F2 5 0 R >>',
          content: 'BT /F2 20 Tf 100 700 Td '
              '${List.filled(10, '<41> Tj').join(' ')} '
              '<00530045004300520045005400440044> Tj ET',
          extra: [
            '<< /Type /Font /Subtype /Type0 /BaseFont /X '
                '/Encoding /Identity-H /DescendantFonts [6 0 R] >>',
            '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X '
                '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
                '/Supplement 0 >> /DW 1000 >>',
          ],
        ),
        const PdfRect(290, 690, 500, 730),
      );
      _gone(all, '0053004500430052');
    });

    test('an image that is its own structure item loses its alt text', () {
      final all = _burn(
        _onePage(
          resources: '/XObject << /Im 5 0 R >>',
          content: 'q 100 0 0 10 100 700 cm /Im Do Q',
          catalogExtra: '/StructTreeRoot 6 0 R',
          extra: [
            _stream(
                '/Type /XObject /Subtype /Image /Width 1 /Height 1 '
                    '/ColorSpace /DeviceGray /BitsPerComponent 8 '
                    '/StructParent 3',
                'x'),
            '<< /Type /StructTreeRoot /K [7 0 R] /ParentTree 8 0 R >>',
            '<< /Type /StructElem /S /Figure /P 6 0 R '
                '/K << /Type /OBJR /Obj 5 0 R >> '
                '/Alt (Photo of SECRETOBJRALT) >>',
            '<< /Nums [3 7 0 R] >>',
          ],
        ),
        const PdfRect(90, 690, 210, 730),
      );
      _gone(all, 'SECRETOBJRALT');
    });

    test('MCIDs in a form without /StructParents are the page\'s', () {
      final all = _burn(
        _onePage(
          resources: '/XObject << /Fm 5 0 R >>',
          content: '/Fm Do',
          catalogExtra: '/StructTreeRoot 7 0 R',
          pageExtra: '/StructParents 0',
          extra: [
            _stream(
                '/Type /XObject /Subtype /Form /BBox [0 0 612 792] '
                    '/Resources << /XObject << /Im 6 0 R >> >>',
                '/Figure << /MCID 0 >> BDC '
                    'q 100 0 0 10 100 700 cm /Im Do Q EMC'),
            _stream(
                '/Type /XObject /Subtype /Image /Width 1 /Height 1 '
                    '/ColorSpace /DeviceGray /BitsPerComponent 8',
                'x'),
            '<< /Type /StructTreeRoot /K [8 0 R] /ParentTree 9 0 R >>',
            '<< /Type /StructElem /S /Figure /P 7 0 R /K 0 '
                '/Alt (Photo of SECRETFORMMCID) >>',
            '<< /Nums [0 [8 0 R]] >>',
          ],
        ),
        const PdfRect(90, 690, 210, 730),
      );
      _gone(all, 'SECRETFORMMCID');
    });

    test('hidden information goes wherever it sits', () {
      final all = _burn(
        _onePage(
          content: text(''),
          catalogExtra: '/AF [6 0 R] /Outlines 8 0 R',
          pageExtra: '/Annots [10 0 R 11 0 R]',
          extra: [
            _helvetica,
            '<< /Type /Filespec /F (a.txt) /EF << /F 7 0 R >> >>',
            _stream('/Type /EmbeddedFile', 'SECRETAF'),
            '<< /Type /Outlines /First 9 0 R /Last 9 0 R /Count 1 >>',
            '<< /Title (Go) /Parent 8 0 R '
                '/A << /S /JavaScript /JS (app.alert\\(1\\); //SECRETJSOUT) >> >>',
            '<< /Type /Annot /Subtype /FileAttachment /Rect [500 100 520 120] '
                '/FS << /Type /Filespec /F (b.txt) /EF << /F 12 0 R >> >> >>',
            '<< /Type /Annot /Subtype /Link /Rect [500 200 520 220] '
                '/A << /S /JavaScript /JS (//SECRETJSLINK) >> >>',
            _stream('/Type /EmbeddedFile', 'SECRETFA'),
          ],
        ),
        box,
      );
      for (final marker in [
        'SECRETAF',
        'SECRETFA',
        'SECRETJSOUT',
        'SECRETJSLINK',
      ]) {
        _gone(all, marker);
      }
    });

    test('copies of the removed text are scrubbed from every string', () {
      final all = _burn(
        _onePage(
          content: text(''),
          catalogExtra: '/PageLabels << /Nums [0 << /P (SECRETOPS-) >>] >> '
              '/Dests << /SECRETOPS [3 0 R /Fit] >>',
          pageExtra: '/Annots [6 0 R]',
          extra: [
            _helvetica,
            '<< /Type /Annot /Subtype /Text /Rect [500 100 520 120] '
                '/Contents (note: SECRETOPS) >>',
          ],
        ),
        box,
      );
      _gone(all, 'SECRETOPS');
    });

    test('a sibling widget off the page does not keep the value', () {
      final all = _burn(
        _onePage(
          content: '',
          resources: '',
          catalogExtra: '/AcroForm << /Fields [5 0 R] >>',
          pageExtra: '/Annots [6 0 R 7 0 R]',
          extra: const [
            '<< /FT /Tx /T (f) /V (SECRETOFFPAGE) /Kids [6 0 R 7 0 R] >>',
            '<< /Type /Annot /Subtype /Widget /Parent 5 0 R '
                '/Rect [100 700 200 720] /P 3 0 R >>',
            '<< /Type /Annot /Subtype /Widget /Parent 5 0 R '
                '/Rect [5000 5000 5100 5020] /P 3 0 R >>',
          ],
        ),
        box,
      );
      _gone(all, 'SECRETOFFPAGE');
    });

    test('another draw of a redacted image gets the redacted copy', () {
      final all = _burn(
        _onePage(
          resources: '/XObject << /Im 5 0 R >>',
          content: 'q 100 0 0 10 100 700 cm /Im Do Q '
              'q 100 0 0 10 5000 5000 cm /Im Do Q',
          extra: [
            _stream(
                '/Type /XObject /Subtype /Image /Width 10 /Height 1 '
                    '/ColorSpace /DeviceGray /BitsPerComponent 8',
                'ABCDEFGHIJ'),
          ],
        ),
        const PdfRect(90, 690, 150, 730),
      );
      _gone(all, 'ABCDE');
      expect(all, contains('FGHIJ'));
    });

    test('geometry that overflows to infinity counts as under the box', () {
      // PDF numbers have no exponent: 1e40 written out, applied 8 times
      final big = '1${'0' * 40}.0';
      final all = _burn(
        _onePage(
          content: '${List.filled(8, '$big 0 0 $big 0 0 cm').join(' ')} '
              'BT /F1 12 Tf 0 0 Td (SECRETINF) Tj ET',
        ),
        box,
      );
      _gone(all, 'SECRETINF');
    });
  });
}
