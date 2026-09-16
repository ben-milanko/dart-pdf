// #912: small glyph fills read as grey haze, because exact analytic coverage
// is the *correct* answer for a stem thinner than a device pixel.
//
// At 1 px/pt a 12 pt face draws stems around 0.7 px wide, so Skia spreads them
// over two columns at ~35% each. Measured over a page of 12 pt body text, that
// is a mean ink luminance of ~154 where a hinted rasterizer (FreeType, via
// Okular or Chrome) produces ~80. We match pdf.js's own baseline for the same
// page to within 1%, so this is not a defect against that reference - it is
// the ceiling of unhinted outline filling, which is what both of us do.
//
// [CanvasPdfDevice.glyphStemDarkening] trades exactness for legibility by
// compositing each glyph a second time. These tests pin the two properties
// that make it a *darkening* rather than an embolden: ink gets darker, and the
// glyph does not grow.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _text = 'Hamburgefonstiv handgloves mimimum 12pt';
const _pageWidth = 320.0;
const _pageHeight = 40.0;

Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

/// A page setting [_text] at [size] pt.
///
/// With [embedded] the face is the repo's own DejaVu Sans, a real text face
/// with real stems, so the run reaches the device as glyph outlines. Without
/// it the face is an unembedded standard-14, which the device draws through a
/// substituted system font instead - the other half of the darkening, and one
/// that would otherwise diverge from embedded text on the same page.
///
/// [fillAlpha] below 1 emits an ExtGState `ca`, which must switch the
/// darkening off: compositing a translucent shape twice would darken its whole
/// body rather than its edges.
Uint8List _textPdf(double size, {bool embedded = true, double fillAlpha = 1}) {
  final graphicsState = fillAlpha < 1 ? '/GS0 gs ' : '';
  final content = 'BT $graphicsState/F1 $size Tf 0 0 0 rg 8 14 Td '
      '($_text) Tj ET';
  final resources = StringBuffer('/Font << /F1 5 0 R >>');
  if (fillAlpha < 1) {
    resources.write(' /ExtGState << /GS0 << /ca $fillAlpha >> >>');
  }
  final bodies = <Uint8List>[
    _ascii('<< /Type /Catalog /Pages 2 0 R >>'),
    _ascii('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    _ascii('<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 $_pageWidth $_pageHeight] /Contents 4 0 R '
        '/Resources << $resources >> >>'),
    _ascii('<< /Length ${content.length} >>\nstream\n$content\nendstream'),
    if (!embedded)
      _ascii('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
  ];
  if (embedded) {
    final font = Uint8List.fromList(
        File('../dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf')
            .readAsBytesSync());
    bodies.addAll([
      _ascii('<< /Type /Font /Subtype /TrueType /BaseFont /DejaVuSans '
          '/FirstChar 32 /LastChar 126 /Encoding /WinAnsiEncoding '
          '/FontDescriptor 7 0 R >>'),
      (BytesBuilder()
            ..add(_ascii('<< /Length ${font.length} /Length1 ${font.length} >>'
                '\nstream\n'))
            ..add(font)
            ..add(_ascii('\nendstream')))
          .takeBytes(),
      _ascii('<< /Type /FontDescriptor /FontName /DejaVuSans /Flags 32 '
          '/FontBBox [-1021 -463 1793 1232] /ItalicAngle 0 /Ascent 928 '
          '/Descent -236 /CapHeight 700 /StemV 80 /FontFile2 6 0 R >>'),
    ]);
  }
  final out = BytesBuilder()..add(_ascii('%PDF-1.7\n'));
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(out.length);
    out
      ..add(_ascii('${i + 1} 0 obj\n'))
      ..add(bodies[i])
      ..add(_ascii('\nendobj\n'));
  }
  final xref = out.length;
  final trailer = StringBuffer()
    ..write('xref\n0 ${bodies.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    trailer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  trailer
    ..write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xref\n%%EOF\n');
  out.add(_ascii(trailer.toString()));
  return out.takeBytes();
}

/// Inked-pixel count and mean ink luminance of a rendered page: how much of
/// the paper the glyphs touch, and how dark that ink is.
Future<(int inked, double meanLuminance)> _ink(double size,
    {required bool darken,
    double ratio = 1,
    bool embedded = true,
    double fillAlpha = 1}) async {
  CanvasPdfDevice.glyphStemDarkening = darken;
  final document = PdfDocument.open(
      _textPdf(size, embedded: embedded, fillAlpha: fillAlpha));
  final picture = await PdfPageRenderer.renderPicture(document.page(0));
  final image = await PdfPageRenderer.rasterize(
      picture, const Size(_pageWidth, _pageHeight), ratio);
  final data = (await image.toByteData())!;
  var inked = 0;
  var sum = 0.0;
  for (var i = 0; i < image.width * image.height; i++) {
    final luminance = (data.getUint8(i * 4) +
            data.getUint8(i * 4 + 1) +
            data.getUint8(i * 4 + 2)) /
        3;
    if (luminance > 250) continue; // paper
    inked++;
    sum += luminance;
  }
  picture.dispose();
  image.dispose();
  return (inked, sum / inked);
}

void main() {
  tearDown(() => CanvasPdfDevice.glyphStemDarkening = false);

  group('glyphDarkeningFor', () {
    CanvasPdfDevice device({double pixelRatio = 1}) {
      final recorder = ui.PictureRecorder();
      addTearDown(() => recorder.endRecording().dispose());
      return CanvasPdfDevice(Canvas(recorder), pixelRatio: pixelRatio);
    }

    test('is inert until the flag is set', () {
      expect(device().glyphDarkeningFor(12), 0);
    });

    test('applies in full below the threshold and tapers out above it', () {
      CanvasPdfDevice.glyphStemDarkening = true;
      final page = device();

      expect(page.glyphDarkeningFor(8), CanvasPdfDevice.glyphStemDarkeningAlpha,
          reason: 'body text carries the full correction');
      expect(
          page.glyphDarkeningFor(12), CanvasPdfDevice.glyphStemDarkeningAlpha);
      expect(page.glyphDarkeningFor(20),
          closeTo(CanvasPdfDevice.glyphStemDarkeningAlpha / 2, 1e-9),
          reason: 'halfway between 12 and 28 device px');
      expect(page.glyphDarkeningFor(28), 0);
      expect(page.glyphDarkeningFor(48), 0,
          reason: 'display sizes resolve their own stems and stay exact');
    });

    test('is a device-space rule, so a retina raster tapers sooner', () {
      CanvasPdfDevice.glyphStemDarkening = true;
      // 12 pt at ratio 2 is 24 device px - already inside the taper.
      expect(device(pixelRatio: 2).glyphDarkeningFor(12),
          closeTo(CanvasPdfDevice.glyphStemDarkeningAlpha / 4, 1e-9));
    });

    test('a scale-independent picture keeps exact coverage (#660)', () {
      CanvasPdfDevice.glyphStemDarkening = true;
      expect(device(pixelRatio: 0).glyphDarkeningFor(8), 0,
          reason: 'no fixed output scale means no size threshold to test');
    });
  });

  group('a page of 12 pt text', () {
    test('gets materially darker ink', () async {
      final (_, plain) = await _ink(12, darken: false);
      final (_, darkened) = await _ink(12, darken: true);

      // ~154 -> ~117 on a full corpus page; the exact numbers depend on the
      // face, so assert the size of the move rather than the endpoints.
      expect(darkened, lessThan(plain - 20),
          reason: 'mean ink luminance $plain -> $darkened');
    });

    test('does not grow, which is what separates this from an embolden',
        () async {
      final (plain, _) = await _ink(12, darken: false);
      final (darkened, _) = await _ink(12, darken: true);

      // Dilating the outline instead (stroking the fill, FreeType's CFF
      // approach) was measured at +47% inked pixels for no luminance gain -
      // fatter and hazier, not darker. Compositing the same shape again moves
      // coverage, not edges.
      expect(darkened, lessThan(plain * 1.1),
          reason: 'inked pixels $plain -> $darkened');
    });

    test('darkens a substituted face too, so a mixed page stays even',
        () async {
      final (_, plain) = await _ink(12, darken: false, embedded: false);
      final (_, darkened) = await _ink(12, darken: true, embedded: false);

      expect(darkened, lessThan(plain),
          reason: 'mean ink luminance $plain -> $darkened');
    });

    test('keeps a translucent fill exact', () async {
      final (plainInk, plain) = await _ink(12, darken: false, fillAlpha: 0.5);
      final (darkenedInk, darkened) =
          await _ink(12, darken: true, fillAlpha: 0.5);

      // Compositing twice would darken the whole body, not just the stems.
      expect(darkened, closeTo(plain, 0.5));
      expect(darkenedInk, plainInk);
    });

    test('leaves display sizes alone', () async {
      final (_, plain) = await _ink(40, darken: false);
      final (_, darkened) = await _ink(40, darken: true);

      expect(darkened, closeTo(plain, 0.5),
          reason: '40 pt is past the taper, so nothing may change');
    });
  });
}
