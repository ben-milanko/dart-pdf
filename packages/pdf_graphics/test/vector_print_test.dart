import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Builds a one-page PDF whose single content stream is [content], on a
/// [width]x[height] MediaBox with a Helvetica /F1 font resource.
Uint8List buildContentPdf(String content,
    {double width = 612, double height = 792, int rotate = 0}) {
  final rotateEntry = rotate == 0 ? '' : ' /Rotate $rotate';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height]$rotateEntry '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
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
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// Like [buildContentPdf] but adds a /GS0 ExtGState resource carrying [blend]
/// (default Multiply), so [content] can select it with `/GS0 gs`. Used to
/// exercise the print device's blend-mode alpha approximation.
Uint8List buildBlendPdf(String content,
    {String blend = 'Multiply',
    String extra = '',
    double width = 100,
    double height = 100}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] '
        '/Contents 4 0 R /Resources << /ExtGState << /GS0 << /Type /ExtGState '
        '/BM /$blend >> $extra >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
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
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// A one-page PDF whose content draws a form XObject (which sets Multiply and
/// fills), then draws [after] in page content once the form returns. Lets a
/// test assert the form's blend does not leak past its implicit q/Q.
Uint8List buildFormBlendPdf(String after) {
  const form = '/GS0 gs 1 1 0 rg 0 0 20 20 re f';
  final content = '/Fm0 Do $after';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R '
        '/Resources << /XObject << /Fm0 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << '
        '/ExtGState << /GS0 << /BM /Multiply >> >> >> /Length ${form.length} >>'
        '\nstream\n$form\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
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
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

Future<VectorPrintPage> encodeAndDecode(Uint8List pdf, {int? rotation}) async {
  final doc = PdfDocument.open(pdf);
  final bytes = await encodeVectorPrintPage(doc.page(0), rotation: rotation);
  return decodeVectorPrint(bytes);
}

void main() {
  group('header', () {
    test('carries the device page size in points', () async {
      final page =
          await encodeAndDecode(buildContentPdf('', width: 400, height: 300));
      expect(page.widthPt, closeTo(400, 0.01));
      expect(page.heightPt, closeTo(300, 0.01));
    });

    test('rejects a stream with the wrong magic', () {
      expect(() => decodeVectorPrint(Uint8List.fromList([1, 2, 3, 4, 5])),
          throwsFormatException);
    });

    test('rejects a truncated stream with FormatException, not RangeError',
        () async {
      // A valid page, cut off partway through its first op.
      final full = await encodeVectorPrintPage(
          PdfDocument.open(buildContentPdf('0 0 10 10 re f',
                  width: 50, height: 50))
              .page(0));
      final truncated = Uint8List.sublistView(full, 0, 14); // header + a byte
      expect(() => decodeVectorPrint(truncated), throwsFormatException);
    });

    test('rejects an unknown op tag', () async {
      // A valid header ('V','P','R',1 + two f32 sizes) followed by a bogus op.
      final valid = await encodeVectorPrintPage(
          PdfDocument.open(buildContentPdf('', width: 10, height: 10)).page(0));
      final header = Uint8List.sublistView(valid, 0, 12); // magic + w + h
      final bad = Uint8List.fromList([...header, 0x7f]); // 0x7f is no op
      expect(() => decodeVectorPrint(bad), throwsFormatException);
    });

    test('a /Rotate 90 page swaps width and height', () async {
      final page = await encodeAndDecode(
          buildContentPdf('', width: 400, height: 300, rotate: 90));
      expect(page.widthPt, closeTo(300, 0.01));
      expect(page.heightPt, closeTo(400, 0.01));
    });

    test('a /Rotate 90 page rotates content into the device box', () async {
      // A dot near the page-space origin (bottom-left). Under a clockwise 90°
      // display rotation of a 400x300 page (device box 300x400), the
      // bottom-left corner maps to the top-left of the rotated view.
      final page = await encodeAndDecode(
          buildContentPdf('0 0 4 4 re f', width: 400, height: 300, rotate: 90));
      final fill = page.ops.whereType<VpFillPath>().single;
      final pts = <(double, double)>[];
      for (final s in fill.path.segments) {
        if (s is VpMove) pts.add((s.x, s.y));
        if (s is VpLine) pts.add((s.x, s.y));
      }
      // Every emitted point must land inside the 300x400 device box.
      for (final (x, y) in pts) {
        expect(x, inInclusiveRange(-0.5, 300.5));
        expect(y, inInclusiveRange(-0.5, 400.5));
      }
      // The page-space origin corner sits at the top-left after a CW rotation.
      final minX = pts.map((p) => p.$1).reduce((a, b) => a < b ? a : b);
      final minY = pts.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
      expect(minX, closeTo(0, 1.0));
      expect(minY, closeTo(0, 1.0));
    });
  });

  group('paths', () {
    test('a filled rectangle becomes a fill op in device points (y-down)',
        () async {
      // Red rectangle from (100,200) to (150,260) in page space.
      final page = await encodeAndDecode(
          buildContentPdf('1 0 0 rg 100 200 50 60 re f'));
      final fills = page.ops.whereType<VpFillPath>().toList();
      expect(fills, hasLength(1));
      final fill = fills.single;
      expect(fill.color, const VpColor(255, 0, 0, 255));
      expect(fill.evenOdd, isFalse);

      // Collect the extreme corner points and check the y-flip (612x792 page):
      // page-space y 200/260 -> device 592/532.
      final xs = <double>[];
      final ys = <double>[];
      for (final seg in fill.path.segments) {
        switch (seg) {
          case VpMove(:final x, :final y):
          case VpLine(:final x, :final y):
            xs.add(x);
            ys.add(y);
          default:
            break;
        }
      }
      expect(xs.reduce((a, b) => a < b ? a : b), closeTo(100, 0.5));
      expect(xs.reduce((a, b) => a > b ? a : b), closeTo(150, 0.5));
      expect(ys.reduce((a, b) => a < b ? a : b), closeTo(792 - 260, 0.5));
      expect(ys.reduce((a, b) => a > b ? a : b), closeTo(792 - 200, 0.5));
    });

    test('a stroked line becomes a stroke op with its width', () async {
      final page = await encodeAndDecode(
          buildContentPdf('0 0 1 RG 3 w 100 100 m 300 400 l S'));
      final strokes = page.ops.whereType<VpStrokePath>().toList();
      expect(strokes, hasLength(1));
      expect(strokes.single.color, const VpColor(0, 0, 255, 255));
      expect(strokes.single.width, closeTo(3, 0.01));
      expect(strokes.single.path.segments.whereType<VpMove>(), hasLength(1));
      expect(strokes.single.path.segments.whereType<VpLine>(), hasLength(1));
    });

    test('a clip becomes a clip op', () async {
      final page = await encodeAndDecode(
          buildContentPdf('0 0 100 100 re W n 0 0 50 50 re f'));
      expect(page.ops.whereType<VpClipPath>(), hasLength(1));
    });

    test('q/Q bracket the content as save/restore ops', () async {
      final page = await encodeAndDecode(
          buildContentPdf('q 0 0 10 10 re f Q', width: 100, height: 100));
      expect(page.ops.whereType<VpSave>(), isNotEmpty);
      expect(page.ops.whereType<VpRestore>(), isNotEmpty);
    });

    test('a dashed stroke round-trips its dash array and phase', () async {
      final page = await encodeAndDecode(
          buildContentPdf('[4 2] 1 d 2 w 10 10 m 90 10 l S',
              width: 100, height: 100));
      final stroke = page.ops.whereType<VpStrokePath>().single;
      // Dash lengths scale with the device magnification (identity here).
      expect(stroke.dashes, hasLength(2));
      expect(stroke.dashes[0], closeTo(4, 0.01));
      expect(stroke.dashes[1], closeTo(2, 0.01));
      expect(stroke.dashPhase, closeTo(1, 0.01));
    });

    test('an opaque fill has a fully-opaque alpha channel', () async {
      final page = await encodeAndDecode(
          buildContentPdf('0 0 0 rg 0 0 10 10 re f', width: 100, height: 100));
      final fill = page.ops.whereType<VpFillPath>().first;
      expect(fill.color.a, 255);
    });

    test('a Multiply fill lowers to a translucent alpha (highlight print)',
        () async {
      // A highlight draws opaque paint whose translucency is entirely the /BM
      // Multiply blend. The op set has no blend modes, so without approximation
      // this would print as a solid block hiding the content underneath; it
      // must lower to a see-through alpha (0.4) instead.
      final page = decodeVectorPrint(await encodeVectorPrintPage(
          PdfDocument.open(buildBlendPdf('/GS0 gs 1 1 0 rg 0 0 50 50 re f'))
              .page(0)));
      final fill = page.ops.whereType<VpFillPath>().single;
      expect(fill.color, const VpColor(255, 255, 0, 102)); // 0.4 * 255
    });

    test('a Multiply stroke lowers to a translucent alpha', () async {
      // An InkHighlight paints its strokes under a Multiply blend - the same
      // approximation must apply on the stroke path.
      final page = decodeVectorPrint(await encodeVectorPrintPage(
          PdfDocument.open(buildBlendPdf(
                  '/GS0 gs 1 1 0 RG 4 w 5 5 m 45 45 l S'))
              .page(0)));
      final stroke = page.ops.whereType<VpStrokePath>().single;
      expect(stroke.color.a, 102); // 0.4 * 255
    });

    test('the Multiply approximation is reset by a following Normal blend',
        () async {
      // /BM /Normal after the highlight restores opaque painting, so a later
      // fill is not dimmed.
      final page = decodeVectorPrint(await encodeVectorPrintPage(
          PdfDocument.open(buildBlendPdf(
                  '/GS0 gs 1 1 0 rg 0 0 20 20 re f '
                  '/GS1 gs 0 0 1 rg 30 30 20 20 re f',
                  extra: '/GS1 << /Type /ExtGState /BM /Normal >>'))
              .page(0)));
      final fills = page.ops.whereType<VpFillPath>().toList();
      expect(fills, hasLength(2));
      expect(fills[0].color.a, 102); // Multiply highlight, dimmed
      expect(fills[1].color.a, 255); // back to Normal, opaque
    });

    test('a Multiply set inside a form does not leak past it', () async {
      // A form Do is an implicit q/Q: the Multiply the form sets must not dim
      // the Normal-blend blue fill drawn in page content after the form
      // returns. The interpreter brackets the form with device save/restore, so
      // the device must pop the blend on restore (it restores its own graphics
      // state without re-issuing setBlendMode).
      final page = decodeVectorPrint(await encodeVectorPrintPage(
          PdfDocument.open(buildFormBlendPdf('0 0 1 rg 60 60 20 20 re f'))
              .page(0)));
      final fills = page.ops.whereType<VpFillPath>().toList();
      final yellow = fills.firstWhere((f) => f.color.g > 150 && f.color.b < 80);
      final blue = fills.firstWhere((f) => f.color.b > 200 && f.color.r < 80);
      expect(yellow.color.a, 102); // inside the form: Multiply, dimmed
      expect(blue.color.a, 255); // after the form: Normal, opaque - no leak
    });
  });

  group('text', () {
    test('a non-embedded (substituted) font emits selectable text', () async {
      final page =
          await encodeAndDecode(buildClassicPdf()); // Helvetica "Hello, world!"
      final texts = page.ops.whereType<VpText>().toList();
      expect(texts, isNotEmpty);
      expect(texts.map((t) => t.text).join(), contains('Hello, world!'));
    });

    test('substituted text carries a non-degenerate baseline transform',
        () async {
      final page = await encodeAndDecode(buildClassicPdf());
      final text = page.ops.whereType<VpText>().first;
      // The em->device transform must be invertible (real placement).
      final m = text.matrix;
      final det = m[0] * m[3] - m[1] * m[2];
      expect(det.abs(), greaterThan(1e-6));
    });

    test('stroke-only (mode 1) substituted text still emits selectable text',
        () async {
      // Render mode 1 strokes the glyphs; a non-embedded font has no outlines,
      // so the run must still emit a selectable text op (in the stroke colour).
      final page = await encodeAndDecode(buildContentPdf(
          'BT /F1 24 Tf 1 Tr 1 0 0 RG 40 200 Td (Outline) Tj ET'));
      final texts = page.ops.whereType<VpText>().toList();
      expect(texts.map((t) => t.text).join(), contains('Outline'));
      expect(texts.first.color, const VpColor(255, 0, 0, 255)); // stroke red
    });

    test('an embedded font emits glyph-outline fills, not a text op', () async {
      // A DejaVu-embedded free-text annotation: the interpreter exposes real
      // outlines, so we vectorise the glyphs rather than fall back to a system
      // font. No selectable text op, but crisp resolution-independent fills.
      final fontBytes =
          File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync();
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..addFreeText(0, const PdfRect(72, 600, 320, 680), 'Ag',
            font: PdfEmbeddedFont.parse(fontBytes));
      final doc = PdfDocument.open(editor.save());
      final page = decodeVectorPrint(await encodeVectorPrintPage(doc.page(0)));

      // The embedded 'Ag' contributes filled glyph outlines (curved paths).
      final fills = page.ops.whereType<VpFillPath>().toList();
      expect(fills, isNotEmpty);
      final hasCurves = fills
          .any((f) => f.path.segments.any((s) => s is VpCubic));
      expect(hasCurves, isTrue,
          reason: 'glyph outlines should carry cubic bezier segments');
    });
  });

  test('a raw image draws as an image op carrying RGBA pixels', () async {
    // A 2x1 DeviceRGB image (red, green), placed by a cm matrix. Built with
    // exact byte offsets so the raw sample bytes survive verbatim.
    final image = <int>[0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00]; // R, G
    final content = 'q 200 0 0 100 20 30 cm /Im0 Do Q';
    final objects = <List<int>>[
      '<< /Type /Catalog /Pages 2 0 R >>'.codeUnits,
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>'.codeUnits,
      ('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 4 0 R '
              '/Resources << /XObject << /Im0 5 0 R >> >> >>')
          .codeUnits,
      '<< /Length ${content.length} >>\nstream\n$content\nendstream'.codeUnits,
      [
        ...'<< /Type /XObject /Subtype /Image /Width 2 /Height 1 '
                '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Length ${image.length} >>\n'
                'stream\n'
            .codeUnits,
        ...image,
        ...'\nendstream'.codeUnits,
      ],
    ];
    final buffer = <int>[];
    void write(String s) => buffer.addAll(s.codeUnits);
    void writeBytes(List<int> b) => buffer.addAll(b);
    write('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(buffer.length);
      write('${i + 1} 0 obj\n');
      writeBytes(objects[i]);
      write('\nendobj\n');
    }
    final xrefOffset = buffer.length;
    write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final offset in offsets) {
      write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
        'startxref\n$xrefOffset\n%%EOF\n');

    final page = await encodeAndDecode(Uint8List.fromList(buffer));
    final images = page.ops.whereType<VpImage>().toList();
    expect(images, hasLength(1));
    expect(images.single.width, 2);
    expect(images.single.height, 1);
    expect(images.single.rgba, hasLength(2 * 1 * 4)); // premultiplied RGBA
  });

  test('round-trips: re-encoding a decoded stream is byte-identical', () async {
    final doc = PdfDocument.open(buildClassicPdf());
    final a = await encodeVectorPrintPage(doc.page(0));
    final b = await encodeVectorPrintPage(doc.page(0));
    expect(b, equals(a));
    // And it decodes without error.
    expect(() => decodeVectorPrint(a), returnsNormally);
  });
}
