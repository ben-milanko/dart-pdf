import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'demo_brand_assets.dart';

/// Where the demo's Flutter overlays sit, in PDF page coordinates. The
/// document's artwork draws matching slots at the same rects, so the
/// page-space ↔ view-space registration is visible on screen.
abstract final class DemoLayout {
  /// Page 1: badge showing the app counter the PDF links increment.
  static const counterBadge = PdfRect(300, 600, 380, 636);

  // page 2 widget slots
  static const clock = PdfRect(180, 630, 360, 670);
  static const counter = PdfRect(180, 570, 360, 610);
  static const toggle = PdfRect(180, 510, 280, 550);
  static const note = PdfRect(180, 440, 460, 490);
}

// page 1 link annotation rects (also drawn as buttons in the artwork)
const _incrementLink = PdfRect(72, 600, 280, 636);
const _messageLink = PdfRect(72, 540, 280, 576);
const _goToLink = PdfRect(72, 480, 280, 516);
const _nextPageLink = PdfRect(72, 420, 280, 456);
const _jsButton = PdfRect(72, 360, 280, 396);

String _rect(PdfRect r) => '[${r.left} ${r.bottom} ${r.right} ${r.top}]';

String _text(double x, double y, double size, String s, {String font = 'F1'}) =>
    'BT /$font $size Tf $x $y Td ($s) Tj ET\n';

/// A filled, stroked box with a centered-ish label: the demo's "button".
String _button(PdfRect r, String label) =>
    'q 0.92 0.94 1.00 rg ${r.left} ${r.bottom} ${r.width} ${r.height} re f '
    '0.25 0.35 0.85 RG 1 w ${r.left} ${r.bottom} ${r.width} ${r.height} re S Q\n'
    '${_text(r.left + 12, r.bottom + r.height / 2 - 4, 12, label)}';

/// An empty outlined slot a Flutter widget will sit in.
String _slot(PdfRect r) =>
    'q 0.55 0.55 0.55 RG 0.75 w ${r.left} ${r.bottom} ${r.width} ${r.height} re S Q\n';

String _link(PdfRect r, String action) =>
    '<< /Type /Annot /Subtype /Link /Rect ${_rect(r)} /A $action >>';

String _n(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

/// A full circle as four cubic Béziers, ready for `f`/`S`/`B`.
String _circle(double cx, double cy, double r) {
  final k = r * 0.5523;
  return '${_n(cx + r)} ${_n(cy)} m '
      '${_n(cx + r)} ${_n(cy + k)} ${_n(cx + k)} ${_n(cy + r)} ${_n(cx)} ${_n(cy + r)} c '
      '${_n(cx - k)} ${_n(cy + r)} ${_n(cx - r)} ${_n(cy + k)} ${_n(cx - r)} ${_n(cy)} c '
      '${_n(cx - r)} ${_n(cy - k)} ${_n(cx - k)} ${_n(cy - r)} ${_n(cx)} ${_n(cy - r)} c '
      '${_n(cx + k)} ${_n(cy - r)} ${_n(cx + r)} ${_n(cy - k)} ${_n(cx + r)} ${_n(cy)} c h ';
}

/// A five-point star centered on (cx, cy): drawn point-to-point so the
/// nonzero/even-odd difference shows (`f*` leaves the pentagon hollow).
String _star(double cx, double cy, double radius) {
  final b = StringBuffer();
  for (var i = 0; i < 5; i++) {
    final a = math.pi / 2 + i * 4 * math.pi / 5;
    final x = cx + radius * math.cos(a), y = cy + radius * math.sin(a);
    b.write('${_n(x)} ${_n(y)} ${i == 0 ? 'm' : 'l'} ');
  }
  return '${b}h ';
}

/// 48×48 hue wheel: angle → hue, radius → saturation, white outside.
String _hueWheelHex() {
  const n = 48;
  final b = StringBuffer();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final dx = (x - (n - 1) / 2) / (n / 2);
      final dy = ((n - 1) / 2 - y) / (n / 2);
      final r = math.sqrt(dx * dx + dy * dy);
      double rv, gv, bv;
      if (r > 1) {
        rv = gv = bv = 1;
      } else {
        final h = ((math.atan2(dy, dx) / (2 * math.pi)) + 1) % 1;
        final s = r;
        final sector = (h * 6).floor() % 6;
        final f = h * 6 - (h * 6).floorToDouble();
        final p = 1 - s, q = 1 - s * f, t = 1 - s * (1 - f);
        (rv, gv, bv) = switch (sector) {
          0 => (1, t, p),
          1 => (q, 1, p),
          2 => (p, 1, t),
          3 => (p, q, 1),
          4 => (t, p, 1),
          _ => (1, p, q),
        };
      }
      for (final v in [rv, gv, bv]) {
        b.write(((v * 255).round()).toRadixString(16).padLeft(2, '0'));
      }
    }
    b.write('\n');
  }
  b.write('>');
  return b.toString();
}

/// 16×16 1-bit smiley for the /ImageMask stencil (1 = ink, /Decode [1 0]).
String _stencilHex() {
  const rows = [
    0x07E0, 0x1818, 0x2004, 0x4002, 0x4C32, 0x8C31, 0x8001, 0x8001, //
    0x9009, 0x8811, 0x47E2, 0x4002, 0x2004, 0x1818, 0x07E0, 0x0000,
  ];
  return '${rows.map((r) => r.toRadixString(16).padLeft(4, '0')).join('\n')}\n>';
}

String _stream(String dict, String data) =>
    '<< $dict /Length ${data.length} >>\nstream\n$data\nendstream';

// ---------------------------------------------------------------------------

/// Builds the 6-page feature-showcase demo document.
///
/// Pages 1–2 are the interactivity demo: page 1 is plain PDF — link and
/// widget annotations any conforming viewer understands; the app reacts to
/// them through PdfViewer.onAction. Page 2 is the inverse direction:
/// Flutter widgets pinned over the page.
///
/// Pages 3–6 showcase the render and editing pipeline: vector graphics,
/// gradients and transparency; the standard fonts and text operators;
/// image XObjects with masks; and a page of annotations and form fields
/// authored at build time through the dart-pdf editor API.
Uint8List buildDemoPdf() {
  // The masthead banner (top) and the corner app mark are stamped onto this
  // page as image XObjects in _authorShowcase — real PNGs don't fit this
  // text-only COS builder. The banner carries the wordmark + tagline, so the
  // page no longer draws a plain-text title of its own.
  final page1 = StringBuffer()
    ..write(_text(72, 650, 12,
        'The blue boxes are PDF link annotations. Tapping them drives the Flutter app.'))
    ..write(_button(_incrementLink, 'Increment the counter'))
    ..write(_slot(DemoLayout.counterBadge))
    ..write(_text(390, 614, 10, 'a live Flutter widget'))
    ..write(_button(_messageLink, 'Show a message'))
    ..write(_button(_goToLink, 'Go to the widgets page'))
    ..write(_button(_nextPageLink, 'Next page - a named action'))
    ..write(_button(_jsButton, 'Run JavaScript'))
    ..write(_text(72, 334, 10,
        'The script reaches the app as source text - dart-pdf never executes JavaScript.'))
    ..write(_text(72, 292, 12, 'More feature pages:'));
  const tocEntries = [
    (3, 'Vector graphics & color'),
    (4, 'Typography & text'),
    (5, 'Images'),
    (6, 'Annotations & forms'),
  ];
  final tocLinks = <String>[];
  for (var i = 0; i < tocEntries.length; i++) {
    final (page, label) = tocEntries[i];
    final y = 266.0 - i * 24;
    page1
      ..write('q 0.15 0.25 0.65 rg ')
      ..write(_text(90, y, 12, '$page   $label'))
      ..write('Q q 0.15 0.25 0.65 RG 0.5 w 90 ${_n(y - 2.5)} m '
          '${_n(90 + 16 + label.length * 6.2)} ${_n(y - 2.5)} l S Q\n');
    tocLinks.add(_link(PdfRect(88, y - 6, 320, y + 14),
        '<< /S /GoTo /D [@PG$page@ 0 R /Fit] >>'));
  }

  final page2 = StringBuffer()
    ..write(_text(72, 730, 22, 'Flutter widgets pinned to the page'))
    ..write(_text(72, 702, 12,
        'Each gray slot holds a live Flutter widget positioned in PDF coordinates.'))
    ..write(_text(72, 686, 12,
        'They scroll and zoom with the page - try pinch or ctrl+wheel.'))
    ..write(_text(72, 646, 12, 'Live clock'))
    ..write(_slot(DemoLayout.clock))
    ..write(_text(72, 586, 12, 'Counter'))
    ..write(_slot(DemoLayout.counter))
    ..write(_text(72, 526, 12, 'Switch'))
    ..write(_slot(DemoLayout.toggle))
    ..write(_text(72, 461, 12, 'Note'))
    ..write(_slot(DemoLayout.note))
    ..write(_text(72, 400, 10,
        'The counter here is the same app state the PDF link on page 1 increments.'));

  // ----- page 3: vector graphics, gradients, transparency, color spaces
  final page3 = StringBuffer()
    ..write(_text(72, 730, 22, 'Vector graphics & color'))
    ..write(_text(72, 702, 12,
        'Everything on this page is drawn by the dart-pdf interpreter.'))
    ..write(_text(72, 670, 12, 'Strokes, dashes & joins'))
    // dash rows
    ..write('q 0.15 0.2 0.5 RG 4 w 72 648 m 270 648 l S Q\n')
    ..write(_text(280, 645, 9, '4 w, butt caps'))
    ..write('q 0.15 0.2 0.5 RG 3 w [10 6] 0 d 72 628 m 270 628 l S Q\n')
    ..write(_text(280, 625, 9, '[10 6] dash'))
    ..write('q 0.15 0.2 0.5 RG 4 w 1 J [0.5 7] 0 d 72 608 m 270 608 l S Q\n')
    ..write(_text(280, 605, 9, '[0.5 7] round caps'));
  const joins = [
    (0, 638, 'miter join'),
    (1, 612, 'round join'),
    (2, 586, 'bevel join')
  ];
  for (final (j, y0, label) in joins) {
    page3
      ..write(
          'q 0.3 0.34 0.5 RG 9 w $j j 350 $y0 m 375 ${y0 + 18} l 400 $y0 l S Q\n')
      ..write(_text(412, y0 + 4.0, 9, label));
  }
  page3
    ..write(_text(72, 562, 12, 'Paths & fills'))
    ..write('q 0.25 0.3 0.7 rg ${_star(140, 482, 52)}f* Q\n')
    ..write(_text(98, 414, 9, 'even-odd fill'))
    ..write('q 0.8 0.2 0.3 rg 260 444 m '
        '200 505 215 555 260 520 c 305 555 320 505 260 444 c f Q\n')
    ..write(_text(222, 414, 9, 'cubic Beziers'))
    ..write(_text(340, 562, 12, 'Gradients'))
    ..write('q 340 495 200 45 re W n /ShAx sh Q '
        'q 0.4 0.4 0.4 RG 0.5 w 340 495 200 45 re S Q\n')
    ..write(_text(340, 482, 9, 'type 2 axial, type 3 stitching function'))
    ..write('q 340 398 100 70 re W n /ShRad sh Q '
        'q 0.4 0.4 0.4 RG 0.5 w 340 398 100 70 re S Q\n')
    ..write(_text(450, 428, 9, 'type 3 radial'))
    ..write(_text(72, 380, 12, 'Transparency & blending'))
    ..write('q /GSmul gs '
        '0 0.62 0.86 rg ${_circle(130, 295, 42)}f '
        '0.85 0.11 0.38 rg ${_circle(180, 295, 42)}f '
        '0.99 0.84 0 rg ${_circle(155, 330, 42)}f Q\n')
    ..write(_text(95, 238, 9, 'Multiply blend'))
    ..write('q 0.1 0.1 0.12 rg 330 300 210 16 re f Q\n')
    ..write('q 0.85 0.2 0.15 rg 340 272 50 58 re f Q\n')
    ..write('q /GSa55 gs 0.85 0.2 0.15 rg 410 272 50 58 re f Q\n')
    ..write('q /GSa25 gs 0.85 0.2 0.15 rg 480 272 50 58 re f Q\n')
    ..write(_text(348, 258, 9, 'ca 1'))
    ..write(_text(414, 258, 9, 'ca 0.55'))
    ..write(_text(484, 258, 9, 'ca 0.25'))
    ..write(_text(72, 180, 12, 'Device color spaces'));
  const cmyk = [
    ('1 0 0 0', 'C'), ('0 1 0 0', 'M'), ('0 0 1 0', 'Y'), //
    ('0 0 0 1', 'K'), ('0.2 0.45 0 0.12', 'mix'),
  ];
  for (var i = 0; i < cmyk.length; i++) {
    final x = 72 + i * 50;
    page3
      ..write('q ${cmyk[i].$1} k $x 110 40 40 re f Q\n')
      ..write(_text(x + 14.0, 98, 8, cmyk[i].$2));
  }
  for (var i = 0; i < 5; i++) {
    final x = 330 + i * 42;
    page3.write('q ${_n(i * 0.25)} g $x 110 40 40 re f '
        '0.6 G 0.5 w $x 110 40 40 re S Q\n');
  }
  page3.write(_text(330, 98, 8, 'DeviceGray ramp'));

  // ----- page 4: typography
  final page4 = StringBuffer()
    ..write(_text(72, 730, 22, 'Typography & text'))
    ..write(_text(72, 702, 12,
        'The 14 standard fonts ship with AFM metrics; spacing and transforms below.'));
  const fontSamples = [
    ('F1', 'Helvetica  -  The quick brown fox jumps over the lazy dog'),
    ('F2', 'Helvetica Bold  -  The quick brown fox'),
    ('F3', 'Helvetica Oblique  -  The quick brown fox'),
    ('F4', 'Times Roman  -  The quick brown fox jumps over the lazy dog'),
    ('F5', 'Times Bold  -  The quick brown fox'),
    ('F6', 'Times Italic  -  The quick brown fox'),
    ('F7', 'Courier  -  fixed pitch 0123456789'),
  ];
  for (var i = 0; i < fontSamples.length; i++) {
    page4.write(_text(72, 660 - i * 27.0, 15, fontSamples[i].$2,
        font: fontSamples[i].$1));
  }
  page4
    ..write(_text(72, 450, 12, 'Rendering modes (Tr)'))
    ..write('q 0.2 0.25 0.6 rg 0.75 0.15 0.2 RG 0.9 w '
        'BT /F2 28 Tf 72 405 Td (Fill) Tj 1 Tr 80 0 Td (Outline) Tj '
        '2 Tr 130 0 Td (Fill + stroke) Tj ET Q\n')
    ..write(_text(72, 360, 12, 'Spacing & scaling'))
    ..write(
        'BT /F1 13 Tf 2.5 Tc 72 330 Td (2.5 Tc letter spacing) Tj 0 Tc ET\n')
    ..write(
        'BT /F1 13 Tf 8 Tw 72 305 Td (8 Tw spreads word gaps wide) Tj 0 Tw ET\n')
    ..write(
        'BT /F1 13 Tf 140 Tz 72 280 Td (140 Tz stretches glyphs) Tj 100 Tz ET\n')
    ..write('BT /F1 13 Tf 72 255 Td (E = mc) Tj 6 Ts (2) Tj 0 Ts '
        '(  -  superscript via Ts rise) Tj ET\n')
    ..write(_text(72, 210, 12, 'Text transforms'))
    ..write(
        'BT 1 0 0.35 1 72 170 Tm /F1 16 Tf (skewed with the text matrix) Tj ET\n')
    ..write('q 0.5 0.3 0.1 rg BT 0.866 0.5 -0.5 0.866 300 90 Tm /F2 16 Tf '
        '(rotated 30 degrees) Tj ET Q\n');

  // ----- page 5: images
  final page5 = StringBuffer()
    ..write(_text(72, 730, 22, 'Images'))
    ..write(_text(72, 702, 12,
        'Raster images are XObjects; dart-pdf decodes Flate, DCT (JPEG), CCITT,'))
    ..write(_text(72, 686, 12,
        'JBIG2, JPX and LZW. These samples are ASCIIHex so the demo stays text-only.'))
    ..write('q 160 0 0 160 72 500 cm /Im1 Do Q\n')
    ..write(_text(72, 486, 9, '48 x 48 /DeviceRGB, scaled to 160 pt'));
  for (var i = 0; i < 8; i++) {
    final shade = i.isEven ? '0.36 0.42 0.75' : '0.93 0.94 1';
    page5.write('q $shade rg 300 ${500 + i * 20} 160 20 re f Q\n');
  }
  page5
    ..write('q 160 0 0 160 300 500 cm /Im2 Do Q\n')
    ..write(_text(300, 486, 9, 'color-key /Mask: white is transparent'))
    ..write(_text(72, 440, 12, 'Stencil masks & inline images'))
    ..write('q 0.10 0.45 0.25 rg 80 0 0 80 72 340 cm /Im3 Do Q\n')
    ..write('q 0.85 0.45 0.1 rg 110 0 0 110 180 320 cm /Im3 Do Q\n')
    ..write(
        _text(72, 300, 9, '1-bit /ImageMask painted through the fill color'))
    ..write('q 80 0 0 80 340 340 cm BI /W 4 /H 4 /CS /RGB /BPC 8 /F /AHx ID\n'
        'e63030 ffffff e63030 ffffff\n'
        'ffffff e63030 ffffff e63030\n'
        'e63030 ffffff e63030 ffffff\n'
        'ffffff e63030 ffffff e63030 >\nEI Q\n')
    ..write(_text(340, 300, 9, 'inline image (BI .. ID .. EI)'));

  // ----- page 6: annotations & forms (authored via the editor below)
  final page6 = StringBuffer()
    ..write(_text(72, 730, 22, 'Annotations & forms'))
    ..write(_text(72, 702, 12,
        'Everything below was authored through the dart-pdf editor API'))
    ..write(_text(72, 686, 12, 'while this demo document was generated.'))
    ..write(_text(72, 640, 12, 'This line is highlighted.'))
    ..write(_text(72, 610, 12, 'This line is underlined.'))
    ..write(_text(72, 580, 12, 'This one is struck out.'))
    ..write(_text(72, 550, 12, 'And this one is squiggly.'))
    ..write(_text(72, 360, 12, 'Form fields - filled by the form editor:'))
    ..write(_text(72, 318, 11, 'Name'))
    ..write(_text(72, 282, 11, 'Newsletter'))
    ..write(_text(72, 246, 11, 'Color'))
    ..write(_text(184, 245, 10, 'Red'))
    ..write(_text(264, 245, 10, 'Blue'))
    ..write(_text(72, 210, 11, 'Favorite'))
    ..write(_text(72, 160, 9,
        'Text, checkbox, radio and combo appearances were generated by'))
    ..write(_text(72, 146, 9,
        'setTextValue / setCheckBoxValue / setRadioValue / setChoiceValue.'));

  // ----- assemble the COS objects -------------------------------------
  final objects = <String>[];
  int add(String body) {
    objects.add(body);
    return objects.length; // object number
  }

  // standard fonts
  int font(String base) =>
      add('<< /Type /Font /Subtype /Type1 /BaseFont /$base >>');
  final f1 = font('Helvetica');
  final f2 = font('Helvetica-Bold');
  final f3 = font('Helvetica-Oblique');
  final f4 = font('Times-Roman');
  final f5 = font('Times-Bold');
  final f6 = font('Times-Italic');
  final f7 = font('Courier');

  // images
  final wheelHex = _hueWheelHex();
  final im1 = add(_stream(
      '/Type /XObject /Subtype /Image /Width 48 /Height 48 '
      '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode',
      wheelHex));
  final im2 = add(_stream(
      '/Type /XObject /Subtype /Image /Width 48 /Height 48 '
      '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode '
      '/Mask [210 255 210 255 210 255]',
      wheelHex));
  final im3 = add(_stream(
      '/Type /XObject /Subtype /Image /Width 16 /Height 16 '
      '/ImageMask true /Decode [1 0] /BitsPerComponent 1 '
      '/Filter /ASCIIHexDecode',
      _stencilHex()));

  // radio button appearance states (18×18 circles, shared by both kids)
  final radioBase =
      'q 0.96 0.97 1 rg 0.35 0.4 0.6 RG 1 w ${_circle(9, 9, 7.5)}B Q';
  final radioOff = add(
      _stream('/Type /XObject /Subtype /Form /BBox [0 0 18 18]', radioBase));
  final radioOn = add(_stream('/Type /XObject /Subtype /Form /BBox [0 0 18 18]',
      '$radioBase q 0.1 0.15 0.4 rg ${_circle(9, 9, 3.6)}f Q'));

  // form fields: text / checkbox / radio group / combo
  const mk = '/MK << /BC [0.35 0.4 0.6] /BG [0.96 0.97 1] >>';
  final radioRed = add('<< /Type /Annot /Subtype /Widget /F 4 '
      '/Rect [160 240 178 258] /Parent @RADIO@ 0 R /AS /Off '
      '/AP << /N << /Red $radioOn 0 R /Off $radioOff 0 R >> >> >>');
  final radioBlue = add('<< /Type /Annot /Subtype /Widget /F 4 '
      '/Rect [240 240 258 258] /Parent @RADIO@ 0 R /AS /Off '
      '/AP << /N << /Blue $radioOn 0 R /Off $radioOff 0 R >> >> >>');
  final radioGroup = add('<< /FT /Btn /T (color) /Ff 32768 /V /Off '
      '/Kids [$radioRed 0 R $radioBlue 0 R] >>');
  final nameField = add('<< /Type /Annot /Subtype /Widget /F 4 /FT /Tx '
      '/T (name) /Rect [160 312 380 336] /DA (/Helv 12 Tf 0 g) $mk >>');
  final checkbox = add('<< /Type /Annot /Subtype /Widget /F 4 /FT /Btn '
      '/T (newsletter) /Rect [160 276 178 294] /V /Off /AS /Off $mk >>');
  final combo = add('<< /Type /Annot /Subtype /Widget /F 4 /FT /Ch '
      '/T (favorite) /Ff 131072 /Rect [160 202 320 226] '
      '/Opt [(Red) (Green) (Blue)] /DA (/Helv 11 Tf 0 g) $mk >>');

  // per-page resources and annotations
  final allFonts = '/Font << /F1 $f1 0 R /F2 $f2 0 R /F3 $f3 0 R '
      '/F4 $f4 0 R /F5 $f5 0 R /F6 $f6 0 R /F7 $f7 0 R >>';
  const rainbow = [
    '1 0.2 0.15',
    '1 0.85 0.2',
    '0.15 0.7 0.3',
    '0.15 0.55 0.9',
    '0.5 0.2 0.75'
  ];
  final stitched =
      StringBuffer('<< /FunctionType 3 /Domain [0 1] /Functions [');
  for (var i = 0; i < rainbow.length - 1; i++) {
    stitched.write('<< /FunctionType 2 /Domain [0 1] '
        '/C0 [${rainbow[i]}] /C1 [${rainbow[i + 1]}] /N 1 >> ');
  }
  stitched.write('] /Bounds [0.25 0.5 0.75] /Encode [0 1 0 1 0 1 0 1] >>');
  final page3Resources = '/Font << /F1 $f1 0 R >> '
      '/ExtGState << /GSmul << /BM /Multiply >> '
      '/GSa55 << /ca 0.55 >> /GSa25 << /ca 0.25 >> >> '
      '/Shading << '
      '/ShAx << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [340 0 540 0] '
      '/Function $stitched /Extend [true true] >> '
      '/ShRad << /ShadingType 3 /ColorSpace /DeviceRGB '
      '/Coords [390 433 0 390 433 52] /Function << /FunctionType 2 '
      '/Domain [0 1] /C0 [1 0.95 0.65] /C1 [0.55 0.15 0.45] /N 1 >> '
      '/Extend [false true] >> >>';

  final page1Annots = '/Annots [ '
      '${_link(_incrementLink, '<< /S /URI /URI (app://counter/increment) >>')} '
      '${_link(_messageLink, '<< /S /URI /URI (app://message?text=Hello%20from%20the%20PDF) >>')} '
      '${_link(_goToLink, '<< /S /GoTo /D [@PG2@ 0 R /XYZ null null null] >>')} '
      '${_link(_nextPageLink, '<< /S /Named /N /NextPage >>')} '
      '<< /Type /Annot /Subtype /Widget /FT /Btn /T (demoJs) '
      '/Rect ${_rect(_jsButton)} /A << /S /JavaScript '
      r'/JS (app.alert\(Hello from PDF JavaScript\)) >> >> '
      '${tocLinks.join(' ')} ]';
  final page6Annots = '/Annots [$nameField 0 R $checkbox 0 R '
      '$radioRed 0 R $radioBlue 0 R $combo 0 R]';

  final pageSpecs = [
    (page1, '/Font << /F1 $f1 0 R >>', page1Annots),
    (page2, '/Font << /F1 $f1 0 R >>', ''),
    (page3, page3Resources, ''),
    (page4, allFonts, ''),
    (
      page5,
      '/Font << /F1 $f1 0 R >> '
          '/XObject << /Im1 $im1 0 R /Im2 $im2 0 R /Im3 $im3 0 R >>',
      ''
    ),
    (page6, '/Font << /F1 $f1 0 R >>', page6Annots),
  ];
  final pageNumbers = <int>[];
  for (final (content, resources, annots) in pageSpecs) {
    final stream = add(_stream('', content.toString())
        .replaceFirst('<<  /Length', '<< /Length'));
    pageNumbers.add(add('<< /Type /Page /Parent @PAGES@ 0 R '
        '/MediaBox [0 0 612 792] /Contents $stream 0 R '
        '/Resources << $resources >> '
        '${annots.isEmpty ? '' : '$annots '}>>'));
  }
  final pagesTree = add('<< /Type /Pages '
      '/Kids [${pageNumbers.map((n) => '$n 0 R').join(' ')}] '
      '/Count ${pageNumbers.length} >>');
  final catalog = add('<< /Type /Catalog /Pages $pagesTree 0 R '
      '/AcroForm << /Fields [$nameField 0 R $checkbox 0 R '
      '$radioGroup 0 R $combo 0 R] '
      '/DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv $f1 0 R >> >> >> >>');

  // patch forward references, then serialize with a correct xref
  final patched = [
    for (final o in objects)
      o
          .replaceAll('@PAGES@', '$pagesTree')
          .replaceAll('@RADIO@', '$radioGroup')
          .replaceAll('@PG2@', '${pageNumbers[1]}')
          .replaceAll('@PG3@', '${pageNumbers[2]}')
          .replaceAll('@PG4@', '${pageNumbers[3]}')
          .replaceAll('@PG5@', '${pageNumbers[4]}')
          .replaceAll('@PG6@', '${pageNumbers[5]}'),
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < patched.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${patched[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${patched.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${patched.length + 1} /Root $catalog 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  final base = Uint8List.fromList(buffer.toString().codeUnits);

  return _authorShowcase(base);
}

/// Adds page 6's annotations and fills its form fields through the public
/// editor API — the demo document doubles as a smoke test of the authoring
/// pipeline.
Uint8List _authorShowcase(Uint8List base) {
  const page = 5; // page 6, zero-based
  const author = 'dart-pdf demo';
  final document = PdfDocument.open(base);
  final editor = PdfEditor(document)
    ..addHighlight(page, const [PdfRect(70, 636, 218, 654)],
        contents: 'A highlight', author: author)
    ..addUnderline(page, const [PdfRect(70, 606, 212, 624)], author: author)
    ..addStrikeOut(page, const [PdfRect(70, 576, 205, 594)], author: author)
    ..addSquiggly(page, const [PdfRect(70, 546, 215, 564)], author: author)
    ..addInk(
        page,
        const <List<(double, double)>>[
          [
            (350, 610),
            (358, 642),
            (366, 606),
            (374, 645),
            (382, 608),
            (390, 640),
            (398, 610),
            (406, 636),
            (414, 614),
          ]
        ],
        color: 0x2060C0,
        strokeWidth: 2.5,
        author: author)
    ..addSquare(page, const PdfRect(440, 595, 530, 655),
        strokeColor: 0xD05020, author: author)
    ..addCircle(page, const PdfRect(340, 470, 440, 555),
        strokeColor: 0x2060C0,
        fillColor: 0x2060C0,
        opacity: 0.3,
        author: author)
    ..addFreeText(page, const PdfRect(450, 460, 540, 555),
        'Free text - wrapped and clipped to its box.',
        fillColor: 0xFFFBE6, borderColor: 0x806820, author: author)
    ..addNote(page, 550, 655, 'A sticky note', author: author)
    ..addStamp(page, const PdfRect(72, 460, 230, 505), 'APPROVED',
        color: 0x208040, author: author);

  // Brand the title page: the banner masthead across the top and the app
  // mark as a corner bug. Both are page content (not annotations), so the
  // page-1 link/widget counts are untouched. Heights follow the source
  // aspect (banner 960×300 ⇒ 3.2:1; mark square).
  final banner = PdfEmbeddableImage.png(demoBannerPng());
  final mark = PdfEmbeddableImage.png(demoLogoPng());
  editor.stampPage(0, (s) {
    s.image(banner, x: 126, y: 674, width: 360);
    s.image(mark, x: 524, y: 82, width: 40);
  });

  final form = editor.acroForm!;
  PdfFormField field(String name) =>
      form.fields.firstWhere((f) => f.name == name);
  editor
    ..setTextValue(field('name'), 'Ada Lovelace')
    ..setCheckBoxValue(field('newsletter'), true)
    ..setRadioValue(field('color'), 'Blue')
    ..setChoiceValue(field('favorite'), 'Green');
  return editor.save();
}
