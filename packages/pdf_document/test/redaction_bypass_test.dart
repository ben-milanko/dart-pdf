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

/// Burns one redaction [rect] over page 0 of [pdf] and returns everything
/// readable in the result.
String _burn(Uint8List pdf, PdfRect rect,
    {bool removeHiddenInformation = true}) {
  final pages = PdfDocument.open(pdf).pageCount;
  _before = _everything(pdf);
  final editor = PdfEditor(PdfDocument.open(pdf))..addRedaction(0, [rect]);
  final burned =
      editor.burnRedactions(removeHiddenInformation: removeHiddenInformation);
  expect(PdfDocument.open(burned).pageCount, pages);
  return _everything(burned);
}

/// A PDF from raw object bodies (object i+1 = bodies[i]); 1 is the catalog.
Uint8List _objects(List<String> bodies) {
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

  group('round 3', () {
    const box = PdfRect(90, 690, 300, 730);
    String note(String contents, {String extra = ''}) =>
        '<< /Type /Annot /Subtype /Text /Rect [500 100 520 120] '
        '/Contents $contents $extra >>';

    test('a base-14 font is measured through its own encoding', () {
      final ae = String.fromCharCodes(List.filled(20, 0xE1));
      final all = _burn(
        _onePage(content: 'BT /F1 12 Tf 50 700 Td ($ae SECRETSTD) Tj ET'),
        const PdfRect(285, 690, 380, 730),
      );
      _gone(all, 'SECRETSTD');
    });

    test('a /Differences code is not measured from the WinAnsi table', () {
      final all = _burn(
        _onePage(
          content: 'BT /F1 12 Tf 50 700 Td '
              '(00000000000000000000 SECRETDIF) Tj ET',
          extra: const [
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
                '/Encoding << /Differences [48 /W] >> >>',
          ],
        ),
        const PdfRect(275, 690, 370, 730),
      );
      _gone(all, 'SECRETDIF');
    });

    test('non-numeric /Widths entries make the font generous', () {
      final widths = List.filled(95, 'null').join(' ');
      final all = _burn(
        _onePage(
          content: 'BT /F1 12 Tf 50 700 Td (AAAA SECRETMW) Tj ET',
          extra: [
            '<< /Type /Font /Subtype /TrueType /BaseFont /Foo /FirstChar 32 '
                '/LastChar 126 /Widths [$widths] /FontDescriptor << '
                '/Type /FontDescriptor /MissingWidth 700 >> >>',
          ],
        ),
        const PdfRect(85, 690, 200, 730),
      );
      _gone(all, 'SECRETMW');
    });

    test('codes past /LastChar are placed generously', () {
      final widths = ['278', ...List.filled(94, '600')].join(' ');
      final all = _burn(
        _onePage(
          content: 'BT /F1 12 Tf 50 700 Td (SECRETLC) Tj ET',
          extra: [
            '<< /Type /Font /Subtype /TrueType /BaseFont /Foo /FirstChar 32 '
                '/LastChar 32 /Widths [$widths] >>',
          ],
        ),
        const PdfRect(45, 690, 62, 730),
      );
      _gone(all, 'CRETL');
    });

    test('a direct property list in shared resources is stripped', () {
      final all = _burn(
        _objects([
          '<< /Type /Catalog /Pages 2 0 R >>',
          '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
              '/Contents 5 0 R /Resources 7 0 R >>',
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
              '/Contents 6 0 R /Resources 7 0 R >>',
          _stream(
              '', '/Span /MC0 BDC BT /F1 12 Tf 100 700 Td (XXXX) Tj ET EMC'),
          _stream('', ''),
          '<< /Font << /F1 8 0 R >> /Properties << /MC0 << '
              '/ActualText (SECRETSHAREDPROPS) >> >> >>',
          _helvetica,
        ]),
        box,
      );
      _gone(all, 'SECRETSHAREDPROPS');
    });

    test('direct resources inherited from the page tree are fixed', () {
      final all = _burn(
        _objects([
          '<< /Type /Catalog /Pages 2 0 R >>',
          '<< /Type /Pages /Kids [3 0 R] /Count 1 /Resources << '
              '/Font << /F1 6 0 R >> '
              '/Properties << /MC0 << /ActualText (SECRETINHPROPS) >> >> '
              '/Shading << /Sh0 << /ShadingType 1 /ColorSpace /DeviceGray '
              '/Function 5 0 R >> >> '
              '/ExtGState << /GS0 << /D [[0 140 3.777 2] 0] >> >> >> >>',
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
              '/Contents 4 0 R >>',
          _stream(
              '',
              '/Span /MC0 BDC BT /F1 12 Tf 100 700 Td (XXXX) Tj ET EMC\n'
                  'q 100 700 100 20 re W n /Sh0 sh Q\n'
                  '/GS0 gs 20 w 100 700 m 400 700 l S'),
          _stream(
              '/FunctionType 0 /Domain [0 1 0 1] /Range [0 1] /Size [4 4] '
                  '/BitsPerSample 8',
              'SECRETSHADING!!!'),
          _helvetica,
        ]),
        box,
      );
      _gone(all, 'SECRETINHPROPS');
      _gone(all, 'SECRETSHADING');
      _gone(all, '3.777');
    });

    test('a resource reached through a reference chain is substituted', () {
      final all = _burn(
        _objects([
          '<< /Type /Catalog /Pages 2 0 R >>',
          '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
              '/Contents 4 0 R /Resources << /XObject << /Fm 5 0 R >> >> '
              '/Annots [8 0 R] >>',
          _stream('', '/Fm Do'),
          '6 0 R',
          _stream(
              '/Type /XObject /Subtype /Form /BBox [0 0 612 792] '
                  '/Resources << /Font << /F1 7 0 R >> >>',
              'BT /F1 12 Tf 100 700 Td (SECRETALIAS) Tj ET'),
          _helvetica,
          '<< /Type /Annot /Subtype /Stamp /F 2 /Rect [500 100 520 120] '
              '/AP << /N 6 0 R >> >>',
        ]),
        box,
      );
      _gone(all, 'SECRETALIAS');
    });

    for (final parent in ['2 0 R', '3 0 R']) {
      test('a widget whose /Parent is $parent leaves the page tree whole', () {
        final pdf = _onePage(
          content: '',
          resources: '',
          pageExtra: '/Annots [5 0 R]',
          extra: [
            '<< /Type /Annot /Subtype /Widget /FT /Tx /Parent $parent '
                '/V (SECRETPARENT) /Rect [100 700 200 720] >>',
          ],
        );
        final all = _burn(pdf, box);
        _gone(all, 'SECRETPARENT');
      });
    }

    test('a removed annotation takes the appearance it shares', () {
      final all = _burn(
        _onePage(
          content: '',
          resources: '',
          pageExtra: '/Annots [5 0 R 6 0 R]',
          extra: [
            '<< /Type /Annot /Subtype /Stamp /Rect [100 700 200 720] '
                '/AP << /N 7 0 R >> >>',
            '<< /Type /Annot /Subtype /Stamp /F 2 /Rect [500 100 600 120] '
                '/AP << /N 7 0 R >> >>',
            _stream(
                '/Type /XObject /Subtype /Form /BBox [0 0 100 20] '
                    '/Resources << /Font << /F1 8 0 R >> >>',
                'BT /F1 12 Tf 2 5 Td (SECRETAPSHARE) Tj ET'),
            _helvetica,
          ],
        ),
        box,
      );
      _gone(all, 'SECRETAPSHARE');
    });

    for (final (label, sibling) in [
      ('optional content', '/OC 8 0 R'),
      ('a real-valued hidden flag', '/F 2.0'),
    ]) {
      test('a sibling widget hidden by $label does not keep the value', () {
        final all = _burn(
          _onePage(
            content: '',
            resources: '',
            catalogExtra: '/AcroForm << /Fields [5 0 R] >> '
                '/OCProperties << /OCGs [8 0 R] /D << /OFF [8 0 R] >> >>',
            pageExtra: '/Annots [6 0 R 7 0 R]',
            extra: [
              '<< /FT /Tx /T (f) /V (SECRETSIBLING) /Kids [6 0 R 7 0 R] >>',
              '<< /Type /Annot /Subtype /Widget /Parent 5 0 R '
                  '/Rect [100 700 200 720] /P 3 0 R >>',
              '<< /Type /Annot /Subtype /Widget /Parent 5 0 R '
                  '/Rect [300 300 400 320] /P 3 0 R $sibling >>',
              '<< /Type /OCG /Name (Hidden) >>',
            ],
          ),
          box,
        );
        _gone(all, 'SECRETSIBLING');
      });
    }

    test('array and stream field values are scrubbed from copies', () {
      final all = _burn(
        _onePage(
          content: '',
          resources: '',
          catalogExtra: '/AcroForm << /Fields [5 0 R 6 0 R] >>',
          pageExtra: '/Annots [5 0 R 6 0 R 8 0 R]',
          extra: [
            '<< /Type /Annot /Subtype /Widget /FT /Ch /T (c) '
                '/V [(SECRETMULTI)] /Rect [100 700 200 720] >>',
            '<< /Type /Annot /Subtype /Widget /FT /Tx /T (t) /V 7 0 R '
                '/Rect [100 695 200 699] >>',
            _stream('', 'SECRETVSTREAM'),
            note('(picked SECRETMULTI and SECRETVSTREAM)'),
          ],
        ),
        box,
      );
      _gone(all, 'SECRETMULTI');
      _gone(all, 'SECRETVSTREAM');
    });

    test('UTF-16LE and PDFDocEncoding copies are scrubbed', () {
      String le(String t) =>
          '<FFFE${t.codeUnits.map((c) => '${c.toRadixString(16).padLeft(2, '0')}00').join()}>';
      final pdfDocDash = String.fromCharCode(0x85);
      final all = _burn(
        _onePage(
          content: 'BT /F2 12 Tf 100 700 Td (SECRETLE 123\x9645\x966789) Tj '
              'ET',
          resources: '/Font << /F2 5 0 R >>',
          pageExtra: '/Annots [6 0 R 7 0 R]',
          extra: [
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
                '/Encoding /WinAnsiEncoding >>',
            note(le('SECRETLE')),
            note('(ssn 123${pdfDocDash}45${pdfDocDash}6789)'),
          ],
        ),
        const PdfRect(90, 690, 400, 730),
      );
      _gone(all, '53004500430052004500540000004c004500'.substring(0, 16));
      _gone(all, '123${pdfDocDash}45');
    });

    test('copies spelled with markup, references or escapes are scrubbed', () {
      final all = _burn(
        _onePage(
          content: 'BT /F1 12 Tf 100 700 Td (SECRETRICH) Tj ET\n'
              'BT /F1 12 Tf 100 710 Td (SECRETURI) Tj ET',
          catalogExtra: '/Outlines 7 0 R',
          pageExtra: '/Annots [6 0 R]',
          extra: [
            _helvetica,
            note('(x)',
                extra: '/RC (<body><p>SEC<span>RET</span>RICH</p></body>)'),
            '<< /Type /Outlines /First 8 0 R /Last 8 0 R /Count 1 >>',
            '<< /Title (Go) /Parent 7 0 R /A << /S /URI '
                '/URI (https://x.example/q=SEC%52ETURI) >> >>',
          ],
        ),
        box,
      );
      _gone(all, 'RET</span>RICH');
      _gone(all, 'SEC%52ETURI');
    });

    test('XMP spelling the text with character references goes', () {
      final xmp = '<x:xmpmeta xmlns:x="adobe:ns:meta/"><dc:title>'
          '&#83;ECRETXMP</dc:title></x:xmpmeta>';
      final all = _burn(
        _onePage(
          content: 'BT /F1 12 Tf 100 700 Td (SECRETXMP) Tj ET',
          catalogExtra: '/Metadata 6 0 R',
          extra: [_helvetica, _stream('/Type /Metadata /Subtype /XML', xmp)],
        ),
        box,
        removeHiddenInformation: false,
      );
      _gone(all, '&#83;ECRETXMP');
    });

    test('a named destination spelled with the text goes from links', () {
      final all = _burn(
        _onePage(
          content: 'BT /F1 12 Tf 100 700 Td (SECRETDESTNAME) Tj ET',
          catalogExtra: '/Dests << /SECRETDESTNAME [3 0 R /Fit] >>',
          pageExtra: '/Annots [6 0 R]',
          extra: [
            _helvetica,
            '<< /Type /Annot /Subtype /Link /Rect [500 100 520 120] '
                '/Dest /SECRETDESTNAME >>',
          ],
        ),
        box,
      );
      _gone(all, 'SECRETDESTNAME');
    });
  });

  group('round 4', () {
    const box = PdfRect(90, 690, 300, 730);
    for (final (kind, geometry) in [
      ('Line', '/L [100 700 290 700] /Cap true'),
      ('Ink', '/InkList [[100 700 150 720 200 700 250 720]]'),
      ('Polygon', '/Vertices [100 700 150 720 200 700]'),
    ]) {
      test('a $kind annotation drawn from its geometry under a box goes', () {
        final all = _burn(
          _onePage(
            content: '',
            resources: '',
            pageExtra: '/Annots [5 0 R]',
            extra: [
              '<< /Type /Annot /Subtype /$kind /Rect [400 100 410 110] '
                  '$geometry /Contents (SECRETGEOM$kind) >>',
            ],
          ),
          box,
        );
        _gone(all, 'SECRETGEOM$kind');
      });
    }

    test('a NoRotate annotation turned onto a box goes', () {
      final all = _burn(
        _onePage(
          content: '',
          resources: '',
          pageExtra: '/Rotate 90 /Annots [5 0 R]',
          extra: [
            '<< /Type /Annot /Subtype /Stamp /F 16 /Rect [100 600 300 620] '
                '/AP << /N 6 0 R >> >>',
            _stream(
                '/Type /XObject /Subtype /Form /BBox [0 0 200 20] '
                    '/Resources << /Font << /F1 7 0 R >> >>',
                'BT /F1 12 Tf 2 5 Td (SECRETNOROT) Tj ET'),
            _helvetica,
          ],
        ),
        const PdfRect(95, 630, 140, 800),
      );
      _gone(all, 'SECRETNOROT');
    });

    test('an annotation with an unreadable /Rect goes', () {
      final all = _burn(
        _onePage(
          content: '',
          resources: '',
          pageExtra: '/Annots [5 0 R]',
          extra: [
            '<< /Type /Annot /Subtype /Stamp /Rect [100 (x) 200 720] '
                '/AP << /N 6 0 R >> >>',
            _stream(
                '/Type /XObject /Subtype /Form /BBox [0 0 100 720] '
                    '/Resources << /Font << /F1 7 0 R >> >>',
                'BT /F1 12 Tf 5 700 Td (SECRETRECTNAN) Tj ET'),
            _helvetica,
          ],
        ),
        box,
      );
      _gone(all, 'SECRETRECTNAN');
    });

    test('a kept annotation\'s clipped appearance text under a box goes', () {
      final all = _burn(
        _onePage(
          content: '',
          resources: '',
          pageExtra: '/Annots [5 0 R]',
          extra: [
            '<< /Type /Annot /Subtype /Stamp /Rect [400 100 500 120] '
                '/AP << /N 6 0 R >> >>',
            _stream(
                '/Type /XObject /Subtype /Form /BBox [0 0 100 20] '
                    '/Resources << /Font << /F1 7 0 R >> >>',
                'BT /F1 12 Tf -290 600 Td (SECRETAPCLIP) Tj ET'),
            _helvetica,
          ],
        ),
        box,
      );
      _gone(all, 'SECRETAPCLIP');
    });

    test('direct invoker resources a form strips stay stripped in copies', () {
      final all = _burn(
        _onePage(
          resources: '/Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> '
              '/Properties << /MC0 << /ActualText (SECRETPAGEPROP) >> '
              '/MC1 << /ActualText (SECRETFORMPROP) >> >> '
              '/ExtGState << /G0 << /D [[0 140 3.111 2] 0] >> '
              '/G1 << /D [[0 140 3.777 2] 0] >> >>',
          content: '/Span /MC0 BDC BT /F1 12 Tf 100 700 Td (XXXX) Tj ET EMC\n'
              '/G0 gs 20 w 100 700 m 400 700 l S\n/Fm Do',
          extra: [
            _helvetica,
            _stream(
                '/Type /XObject /Subtype /Form /BBox [0 0 612 792] '
                    '/Resources << /Font << /F1 5 0 R >> >>',
                '/Span /MC1 BDC BT /F1 12 Tf 100 710 Td (YYYY) Tj ET EMC\n'
                    '/G1 gs 20 w 100 710 m 400 710 l S'),
          ],
        ),
        box,
      );
      _gone(all, 'SECRETPAGEPROP');
      _gone(all, 'SECRETFORMPROP');
      _gone(all, '3.111');
      _gone(all, '3.777');
    });

    test('a base-14 name that is not exact is not trusted', () {
      final i200 = 'i' * 200;
      for (final name in ['HELVETICA', 'ABCDEF+Helvetica']) {
        final all = _burn(
          _onePage(
            content: 'BT /F1 6 Tf 20 700 Td ($i200 SECRETCASE) Tj ET',
            extra: ['<< /Type /Font /Subtype /Type1 /BaseFont /$name >>'],
          ),
          const PdfRect(340, 690, 420, 730),
        );
        _gone(all, 'SECRETCASE');
      }
    });

    test('a base-14 font in an untrusted encoding is judged generously', () {
      final a100 = 'a' * 100;
      final all = _burn(
        _onePage(
          resources: '/Font << /F1 5 0 R /FM 6 0 R >>',
          content: 'BT /FM 12 Tf 10 700 Td ($a100) Tj /F1 12 Tf '
              '(SECRETMACX) Tj ET',
          extra: [
            _helvetica,
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
                '/Encoding /MacExpertEncoding >>',
          ],
        ),
        const PdfRect(10, 690, 200, 730),
      );
      _gone(all, 'SECRETMACX');
    });

    test('a real /FirstChar is not trusted', () {
      final widths = List.filled(95, '1000').join(' ');
      final i40 = 'i' * 40;
      final all = _burn(
        _onePage(
          content: 'BT /F1 12 Tf 30 700 Td ($i40 SECRETFC) Tj ET',
          extra: [
            '<< /Type /Font /Subtype /TrueType /BaseFont /Foo '
                '/FirstChar 32.0 /LastChar 126 /Widths [$widths] >>',
          ],
        ),
        const PdfRect(10, 690, 200, 730),
      );
      _gone(all, 'SECRETFC');
    });

    for (final (label, cid) in [
      ('a real /DW', '/DW 0.0'),
      ('a null in /W', '/W [1 [null]]'),
    ]) {
      test('Identity-H with $label is judged generously', () {
        final codes = List.filled(30, '0001').join();
        final all = _burn(
          _onePage(
            resources: '/Font << /F2 5 0 R >>',
            content: 'BT /F2 12 Tf 20 700 Td <$codes> Tj '
                '<0053004500430052004500540057> Tj ET',
            extra: [
              '<< /Type /Font /Subtype /Type0 /BaseFont /X '
                  '/Encoding /Identity-H /DescendantFonts [6 0 R] >>',
              '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X '
                  '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
                  '/Supplement 0 >> $cid >>',
            ],
          ),
          const PdfRect(380, 690, 600, 730),
        );
        _gone(all, '00530045004300520045');
      });
    }

    test('marked content a form opens and the page closes is stripped', () {
      final all = _burn(
        _onePage(
          resources: '/Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >>',
          content: '/Fm Do BT /F1 12 Tf 100 700 Td (XXXX) Tj ET EMC',
          extra: [
            _helvetica,
            _stream('/Type /XObject /Subtype /Form /BBox [0 0 612 792]',
                '/Span << /ActualText (SECRETOPENMC) >> BDC'),
          ],
        ),
        box,
      );
      _gone(all, 'SECRETOPENMC');
    });

    test('a content stream shared with another page is burned there too', () {
      final all = _burn(
        _objects([
          '<< /Type /Catalog /Pages 2 0 R >>',
          '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
              '/Contents 5 0 R /Resources << /Font << /F1 6 0 R >> >> >>',
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
              '/Contents 5 0 R /Resources << /Font << /F1 6 0 R >> >> >>',
          _stream('', 'BT /F1 12 Tf 100 700 Td (SECRETSHARED) Tj ET'),
          _helvetica,
        ]),
        box,
      );
      _gone(all, 'SECRETSHARED');
    });
  });
}
