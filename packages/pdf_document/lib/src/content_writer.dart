import 'dart:convert';
import 'dart:typed_data';

/// Logical text direction for text appearances authored by this package.
///
/// [auto] uses the first strong directional character in the text. When no
/// strong RTL character is present, it resolves to [ltr].
enum PdfTextDirection { ltr, rtl, auto }

extension PdfTextDirectionResolution on PdfTextDirection {
  /// Resolves [auto] from [text], otherwise returns this value unchanged.
  PdfTextDirection resolve(String text) {
    if (this != PdfTextDirection.auto) return this;
    return pdfTextLooksRtl(text) ? PdfTextDirection.rtl : PdfTextDirection.ltr;
  }
}

/// True when [text]'s first strong directional character is RTL.
bool pdfTextLooksRtl(String text) {
  for (final rune in text.runes) {
    if (_isRtlRune(rune)) return true;
    if (_isLtrRune(rune)) return false;
  }
  return false;
}

/// Converts one logical line to the visual order needed by simple PDF text
/// showing operators, which always advance in stream order.
///
/// This is a small Unicode-bidi subset tailored for appearance streams with
/// simple fonts: RTL letter runs are reversed, LTR/number runs keep their
/// internal order, and run order is reversed for RTL paragraphs. It handles
/// common Hebrew/mixed-number cases without adding a shaping dependency.
String pdfVisualText(String text, PdfTextDirection direction) {
  final resolved = direction.resolve(text);
  if (resolved == PdfTextDirection.ltr) return text;

  final runs = <_BidiRun>[];
  final buffer = StringBuffer();
  _BidiKind? current;

  void flush() {
    if (current == null) return;
    runs.add(_BidiRun(current!, buffer.toString()));
    buffer.clear();
    current = null;
  }

  for (final rune in text.runes) {
    final kind = _bidiKind(rune);
    if (current != null && kind != current) flush();
    current = kind;
    buffer.writeCharCode(rune);
  }
  flush();

  final out = StringBuffer();
  for (final run in runs.reversed) {
    out.write(run.kind == _BidiKind.rtl ? _reverseRunes(run.text) : run.text);
  }
  return out.toString();
}

String _reverseRunes(String text) =>
    String.fromCharCodes(text.runes.toList().reversed);

enum _BidiKind { ltr, rtl, neutral }

class _BidiRun {
  const _BidiRun(this.kind, this.text);

  final _BidiKind kind;
  final String text;
}

_BidiKind _bidiKind(int rune) {
  if (_isRtlRune(rune)) return _BidiKind.rtl;
  if (_isLtrRune(rune) || _isNumberRune(rune)) return _BidiKind.ltr;
  return _BidiKind.neutral;
}

bool _isNumberRune(int rune) => rune >= 0x30 && rune <= 0x39;

bool _isLtrRune(int rune) =>
    (rune >= 0x0041 && rune <= 0x005A) ||
    (rune >= 0x0061 && rune <= 0x007A) ||
    (rune >= 0x00C0 && rune <= 0x02AF) ||
    (rune >= 0x0370 && rune <= 0x03FF) ||
    (rune >= 0x0400 && rune <= 0x052F);

bool _isRtlRune(int rune) =>
    (rune >= 0x0590 && rune <= 0x08FF) ||
    (rune >= 0xFB1D && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF) ||
    (rune >= 0x10800 && rune <= 0x10FFF) ||
    (rune >= 0x1E800 && rune <= 0x1EDFF);

/// Builds content-stream bytes operator by operator.
///
/// Coordinates are PDF user space. Output is plain Latin-1 text; characters
/// outside Latin-1 in shown text degrade to '?' (appearance streams are
/// authored with WinAnsi-encoded base-14 fonts for now).
class ContentWriter {
  final StringBuffer _buffer = StringBuffer();

  void op(String operator, [List<double> operands = const []]) {
    for (final value in operands) {
      _buffer
        ..write(fmt(value))
        ..write(' ');
    }
    _buffer
      ..write(operator)
      ..write('\n');
  }

  void save() => op('q');
  void restore() => op('Q');

  /// Writes pre-formed operator text verbatim, on its own line. Used for
  /// operators with name operands (`/Tx BMC`) and for replaying /DA
  /// fragments that are already valid content-stream syntax.
  void raw(String text) {
    _buffer
      ..write(text)
      ..write('\n');
  }

  /// References /[name] in the resources' /ExtGState dictionary.
  void extGState(String name) => _buffer.write('/$name gs\n');

  void fillColor(int rgb) => op('rg', rgbComponents(rgb));
  void strokeColor(int rgb) => op('RG', rgbComponents(rgb));
  void lineWidth(double width) => op('w', [width]);
  void lineCap(int cap) => op('J', [cap.toDouble()]);
  void lineJoin(int join) => op('j', [join.toDouble()]);

  void dash(List<double> pattern, [double phase = 0]) {
    _buffer.write('[');
    for (var i = 0; i < pattern.length; i++) {
      if (i > 0) _buffer.write(' ');
      _buffer.write(fmt(pattern[i]));
    }
    _buffer.write('] ${fmt(phase)} d\n');
  }

  /// Round caps and joins — the right look for freehand ink strokes.
  void roundLines() {
    lineCap(1);
    lineJoin(1);
  }

  void moveTo(double x, double y) => op('m', [x, y]);
  void lineTo(double x, double y) => op('l', [x, y]);
  void curveTo(
          double x1, double y1, double x2, double y2, double x3, double y3) =>
      op('c', [x1, y1, x2, y2, x3, y3]);
  void closePath() => op('h');
  void rect(double x, double y, double width, double height) =>
      op('re', [x, y, width, height]);

  /// Magic number for approximating a quarter circle with one Bézier.
  static const _kappa = 0.5522847498307936;

  void ellipse(double cx, double cy, double rx, double ry) {
    final kx = rx * _kappa;
    final ky = ry * _kappa;
    moveTo(cx + rx, cy);
    curveTo(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry);
    curveTo(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy);
    curveTo(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry);
    curveTo(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy);
    closePath();
  }

  void roundedRect(
      double x, double y, double width, double height, double radius) {
    final r = radius.clamp(0.0, width / 2).clamp(0.0, height / 2);
    final k = r * _kappa;
    moveTo(x + r, y);
    lineTo(x + width - r, y);
    curveTo(x + width - r + k, y, x + width, y + r - k, x + width, y + r);
    lineTo(x + width, y + height - r);
    curveTo(x + width, y + height - r + k, x + width - r + k, y + height,
        x + width - r, y + height);
    lineTo(x + r, y + height);
    curveTo(x + r - k, y + height, x, y + height - r + k, x, y + height - r);
    lineTo(x, y + r);
    curveTo(x, y + r - k, x + r - k, y, x + r, y);
    closePath();
  }

  void fill() => op('f');
  void stroke() => op('S');
  void fillAndStroke() => op('B');
  void clip() {
    op('W');
    op('n');
  }

  void beginText() => op('BT');
  void endText() => op('ET');

  /// References /[name] in the resources' /Font dictionary.
  void font(String name, double size) =>
      _buffer.write('/$name ${fmt(size)} Tf\n');

  void leading(double value) => op('TL', [value]);
  void textAt(double x, double y) => op('Td', [x, y]);

  void showText(String text) {
    _buffer.write('(');
    for (final code in text.codeUnits) {
      switch (code) {
        case 0x28 || 0x29 || 0x5C: // ( ) \
          _buffer
            ..write('\\')
            ..writeCharCode(code);
        case 0x0A:
          _buffer.write('\\n');
        case 0x0D:
          _buffer.write('\\r');
        default:
          _buffer.writeCharCode(code <= 0xFF ? code : 0x3F /* ? */);
      }
    }
    _buffer.write(') Tj\n');
  }

  void nextLine() => op('T*');

  /// References /[name] in the resources' /XObject dictionary.
  void drawXObject(String name) => _buffer.write('/$name Do\n');

  void concatMatrix(
          double a, double b, double c, double d, double e, double f) =>
      op('cm', [a, b, c, d, e, f]);

  Uint8List takeBytes() =>
      Uint8List.fromList(latin1.encode(_buffer.toString()));

  static List<double> rgbComponents(int rgb) => [
        ((rgb >> 16) & 0xFF) / 255,
        ((rgb >> 8) & 0xFF) / 255,
        (rgb & 0xFF) / 255,
      ];

  /// Formats a number the way content streams like them: no exponent,
  /// no trailing zeros.
  static String fmt(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e9) {
      return value.toInt().toString();
    }
    var s = value.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }
}

/// AFM advance widths for Helvetica, characters 32–126, in thousandths of
/// an em (Adobe base-14 metrics).
const List<int> helveticaWidths = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, //
  278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, //
  584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, //
  500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, //
  667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, //
  278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, //
  278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
];

/// AFM advance widths for Helvetica-Bold, characters 32–126.
const List<int> helveticaBoldWidths = [
  278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, //
  278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, //
  584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, //
  556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, //
  667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, //
  333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556, //
  333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
];

/// AFM advance widths for Times-Roman, characters 32–126.
const List<int> timesRomanWidths = [
  250, 333, 408, 500, 500, 833, 778, 333, 333, 333, 500, 564, 250, 333, //
  250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, //
  564, 564, 564, 444, 921, 722, 667, 667, 722, 611, 556, 722, 722, 333, //
  389, 722, 611, 889, 722, 722, 556, 722, 667, 556, 611, 722, 722, 944, //
  722, 722, 611, 333, 278, 333, 469, 500, 333, 444, 500, 444, 500, 444, //
  333, 500, 500, 278, 278, 500, 278, 778, 500, 500, 500, 500, 333, 389, //
  278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541,
];

/// AFM advance widths for Times-Bold, characters 32–126.
const List<int> timesBoldWidths = [
  250, 333, 555, 500, 500, 1000, 833, 278, 333, 333, 500, 570, 250, 333, //
  250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, //
  570, 570, 570, 500, 930, 722, 667, 722, 722, 667, 611, 778, 778, 389, //
  500, 778, 667, 944, 722, 778, 611, 778, 722, 556, 667, 722, 722, 1000, //
  722, 722, 667, 333, 278, 333, 581, 500, 333, 500, 556, 444, 556, 444, //
  333, 500, 556, 278, 333, 556, 278, 833, 556, 500, 556, 556, 444, 389, //
  333, 556, 500, 722, 500, 500, 444, 394, 220, 394, 520,
];

/// AFM advance widths for Times-Italic, characters 32–126.
const List<int> timesItalicWidths = [
  250, 333, 420, 500, 500, 833, 778, 333, 333, 333, 500, 675, 250, 333, //
  250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, //
  675, 675, 675, 500, 920, 611, 611, 667, 722, 611, 611, 722, 722, 333, //
  444, 667, 556, 833, 667, 722, 611, 722, 611, 500, 556, 722, 611, 833, //
  611, 556, 556, 389, 278, 389, 422, 500, 333, 500, 500, 444, 500, 444, //
  278, 500, 500, 278, 278, 444, 278, 722, 500, 500, 500, 500, 389, 389, //
  278, 500, 444, 667, 444, 444, 389, 400, 275, 400, 541,
];

/// AFM advance widths for Times-BoldItalic, characters 32–126.
const List<int> timesBoldItalicWidths = [
  250, 389, 555, 500, 500, 833, 778, 278, 333, 333, 500, 570, 250, 333, //
  250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, //
  570, 570, 570, 500, 832, 667, 667, 667, 722, 667, 667, 722, 778, 389, //
  500, 667, 611, 889, 722, 722, 611, 722, 667, 556, 611, 722, 667, 889, //
  667, 611, 611, 333, 278, 333, 570, 500, 333, 500, 500, 444, 500, 444, //
  333, 500, 556, 278, 278, 500, 278, 778, 556, 500, 500, 500, 389, 389, //
  278, 556, 444, 667, 500, 444, 389, 348, 220, 348, 570,
];

/// Measures [text] in points at [fontSize], using base-14 Helvetica
/// metrics. Characters outside 32–126 count as an average width.
double measureHelvetica(String text, double fontSize, {bool bold = false}) {
  final table = bold ? helveticaBoldWidths : helveticaWidths;
  var total = 0;
  for (final code in text.codeUnits) {
    total += code >= 32 && code <= 126 ? table[code - 32] : 556;
  }
  return total * fontSize / 1000;
}

/// The three base-14 type families the editors write text with — a
/// sans-serif, serif, and monospace pick that every viewer renders
/// without embedding. The bold/italic variants of each are individual
/// [PdfStandardFont] values; this is the axis the UI's family picker
/// selects, orthogonal to the bold/italic toggles.
enum PdfStandardFontFamily {
  /// Helvetica.
  sans('Sans'),

  /// Times.
  serif('Serif'),

  /// Courier.
  mono('Mono');

  const PdfStandardFontFamily(this.label);

  /// A short human label for a font picker.
  final String label;
}

/// The standard one-byte fonts the editors write text with — the bold,
/// italic, and bold-italic variants of a sans-serif, serif, and
/// monospace pick from the PDF base-14 set, which every viewer renders
/// without embedding.
enum PdfStandardFont {
  helvetica('Helvetica', 'Helv', 718, helveticaWidths, 556,
      PdfStandardFontFamily.sans),
  helveticaBold('Helvetica-Bold', 'HelvBold', 718, helveticaBoldWidths, 556,
      PdfStandardFontFamily.sans,
      bold: true),
  helveticaOblique('Helvetica-Oblique', 'HelvObl', 718, helveticaWidths, 556,
      PdfStandardFontFamily.sans,
      italic: true),
  helveticaBoldOblique('Helvetica-BoldOblique', 'HelvBoldObl', 718,
      helveticaBoldWidths, 556, PdfStandardFontFamily.sans,
      bold: true, italic: true),
  times('Times-Roman', 'TiRo', 683, timesRomanWidths, 500,
      PdfStandardFontFamily.serif),
  timesBold('Times-Bold', 'TimesBold', 683, timesBoldWidths, 500,
      PdfStandardFontFamily.serif,
      bold: true),
  timesItalic('Times-Italic', 'TimesItalic', 683, timesItalicWidths, 500,
      PdfStandardFontFamily.serif,
      italic: true),
  timesBoldItalic('Times-BoldItalic', 'TimesBoldItalic', 683,
      timesBoldItalicWidths, 500, PdfStandardFontFamily.serif,
      bold: true, italic: true),
  courier('Courier', 'Cour', 629, null, 600, PdfStandardFontFamily.mono),
  courierBold(
      'Courier-Bold', 'CourBold', 629, null, 600, PdfStandardFontFamily.mono,
      bold: true),
  courierOblique(
      'Courier-Oblique', 'CourObl', 629, null, 600, PdfStandardFontFamily.mono,
      italic: true),
  courierBoldOblique('Courier-BoldOblique', 'CourBoldObl', 629, null, 600,
      PdfStandardFontFamily.mono,
      bold: true, italic: true);

  const PdfStandardFont(this.baseFont, this.resourceName, this.ascent,
      this._widths, this._fallbackWidth, this.family,
      {bool bold = false, bool italic = false})
      : isBold = bold,
        isItalic = italic;

  /// The /BaseFont name.
  final String baseFont;

  /// The appearance-resource name used in /DA, following Acrobat's
  /// short-name conventions (Helv, TiRo, Cour) with explicit suffixes
  /// for the bold/italic variants.
  final String resourceName;

  /// Ascender height in thousandths of an em — where the first baseline
  /// sits below the top of a text box.
  final int ascent;

  final List<int>? _widths; // null: monospaced at [_fallbackWidth]
  final int _fallbackWidth;

  /// The type family (sans/serif/mono) this is a variant of.
  final PdfStandardFontFamily family;

  /// Whether this is a bold variant.
  final bool isBold;

  /// Whether this is an italic (or oblique) variant.
  final bool isItalic;

  /// AFM advance width of character [code] in thousandths of an em.
  int widthOf(int code) {
    final widths = _widths;
    if (widths == null) return _fallbackWidth;
    return code >= 32 && code <= 126 ? widths[code - 32] : _fallbackWidth;
  }

  /// Advance widths for characters 32–126 (the font dict's /Widths).
  List<int> get widths => _widths ?? List.filled(95, _fallbackWidth);

  /// The variant of [family] with the requested [bold]/[italic] style.
  static PdfStandardFont styled(PdfStandardFontFamily family,
      {bool bold = false, bool italic = false}) {
    for (final font in values) {
      if (font.family == family &&
          font.isBold == bold &&
          font.isItalic == italic) {
        return font;
      }
    }
    return helvetica; // unreachable: every (family, bold, italic) exists
  }

  /// This font with bold turned on or off, same family and italic.
  PdfStandardFont withBold(bool bold) =>
      styled(family, bold: bold, italic: isItalic);

  /// This font with italic turned on or off, same family and bold.
  PdfStandardFont withItalic(bool italic) =>
      styled(family, bold: isBold, italic: italic);

  /// Maps a /DA resource name or /BaseFont name leniently — other
  /// producers write /Times-Roman, /Georgia, /CourierNew and the like —
  /// defaulting to [helvetica]. Bold and italic/oblique are recovered
  /// from the name when present.
  static PdfStandardFont fromName(String name) =>
      tryFromName(name) ?? helvetica;

  /// Like [fromName], but null for names that don't clearly belong to
  /// one of the three families (e.g. an embedded font's `/F1`) — callers
  /// that would *regenerate* text in the mapped font use this to leave
  /// unrecognized fonts alone rather than silently substitute.
  static PdfStandardFont? tryFromName(String name) {
    final n = name.toLowerCase();
    PdfStandardFontFamily? family;
    if (n.contains('tiro') || n.contains('times') || n.contains('serif')) {
      family = PdfStandardFontFamily.serif;
    } else if (n.contains('cour') || n.contains('mono')) {
      family = PdfStandardFontFamily.mono;
    } else if (n.contains('helv') ||
        n.contains('arial') ||
        n.contains('sans')) {
      family = PdfStandardFontFamily.sans;
    }
    if (family == null) return null;
    final bold = n.contains('bold');
    final italic = n.contains('italic') ||
        n.contains('oblique') ||
        n.contains('ital') ||
        n.contains('obl');
    return styled(family, bold: bold, italic: italic);
  }
}

/// Measures [text] in points at [fontSize] with [font]'s base-14 metrics.
double measureStandardText(String text, double fontSize,
    {PdfStandardFont font = PdfStandardFont.helvetica}) {
  var total = 0;
  for (final code in text.codeUnits) {
    total += font.widthOf(code);
  }
  return total * fontSize / 1000;
}
