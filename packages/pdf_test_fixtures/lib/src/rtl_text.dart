import 'dart:typed_data';

/// Builds a one-page Type3-font PDF whose RTL words are painted by separate
/// text-showing operators.
///
/// Operators remain in logical word order while their origins move from right
/// to left. Each word's glyph codes are in visual order, matching PDFs emitted
/// by layout engines that position Arabic or Urdu one word at a time.
Uint8List buildRtlTextPdf({
  List<String> lines = const ['اهلا وسهلا', 'كيف حالك'],
}) {
  const fontSize = 24.0;
  const rightEdge = 360.0;
  const wordGap = 24.0;
  const firstBaseline = 720.0;
  const lineGap = 40.0;
  final glyphs = <(int code, String text, int width)>[];
  final operations = <String>['BT /F1 24 Tf'];
  var nextCode = 1;

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    var right = rightEdge;
    final words =
        lines[lineIndex].split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    for (final word in words) {
      final visual = word.runes.toList().reversed;
      final codes = StringBuffer();
      var width = 0;
      for (final rune in visual) {
        if (nextCode > 0xff) {
          throw ArgumentError.value(
              lines, 'lines', 'fixture exceeds 255 glyphs');
        }
        final glyphWidth = _isCombiningMark(rune) ? 0 : 500;
        glyphs.add((nextCode, String.fromCharCode(rune), glyphWidth));
        codes.write(nextCode.toRadixString(16).padLeft(2, '0'));
        width += glyphWidth;
        nextCode++;
      }
      final widthPoints = width * fontSize / 1000;
      final x = right - widthPoints;
      final y = firstBaseline - lineIndex * lineGap;
      operations.add('1 0 0 1 ${_number(x)} ${_number(y)} Tm <$codes> Tj');
      right = x - wordGap;
    }
  }
  operations.add('ET');
  final content = operations.join('\n');

  final cmapEntries = <String>[];
  final widths = <String>[];
  final names = <String>[];
  for (final (code, text, width) in glyphs) {
    final codeHex = code.toRadixString(16).padLeft(2, '0');
    final unicode = text.codeUnits
        .map((unit) => unit.toRadixString(16).padLeft(4, '0'))
        .join();
    cmapEntries.add('<$codeHex> <$unicode>');
    widths.add('$width');
    names.add('/g$code');
  }
  final cmap = [
    '/CIDInit /ProcSet findresource begin',
    '12 dict begin begincmap',
    '1 begincodespacerange <00> <FF> endcodespacerange',
    '${cmapEntries.length} beginbfchar',
    ...cmapEntries,
    'endbfchar endcmap CMapName currentdict /CMap defineresource pop',
    'end end',
  ].join('\n');
  final font = '<< /Type /Font /Subtype /Type3 '
      '/FontBBox [0 -200 1000 800] /FontMatrix [0.001 0 0 0.001 0 0] '
      '/FirstChar 1 /LastChar ${glyphs.length} '
      '/Widths [${widths.join(' ')}] '
      '/Encoding << /Type /Encoding /Differences [1 ${names.join(' ')}] >> '
      '/ToUnicode 6 0 R '
      '/CharProcs << ${[
    for (final name in names) '$name 7 0 R'
  ].join(' ')} >> /Resources << >> >>';
  const charProc = '500 0 d0 0 0 450 700 re f';
  return _assemblePdf([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    font,
    '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
    '<< /Length ${charProc.length} >>\nstream\n$charProc\nendstream',
  ]);
}

/// Builds a one-page Type3-font PDF matching Skia's positioned Arabic
/// tashkil output: every zero-advance mark is a separate text-showing run
/// immediately before its base glyph and is shifted over that glyph.
///
/// The logical text is `ٱﻟْﺣَﻣْدُ ل`; the content stream paints visual clusters
/// left-to-right as `ُد`, `ْﻣ`, `َﺣ`, `ْﻟ`, `ٱ`, a space, then `ل`.
Uint8List buildPositionedTashkilPdf() {
  const glyphs = <({String text, int width, double x, double y})>[
    (text: 'ُ', width: 0, x: 202, y: 724),
    (text: 'د', width: 500, x: 200, y: 720),
    (text: 'ْ', width: 0, x: 214, y: 724),
    (text: 'ﻣ', width: 500, x: 212, y: 720),
    (text: 'َ', width: 0, x: 226, y: 724),
    (text: 'ﺣ', width: 500, x: 224, y: 720),
    (text: 'ْ', width: 0, x: 238, y: 724),
    (text: 'ﻟ', width: 500, x: 236, y: 720),
    (text: 'ٱ', width: 500, x: 248, y: 720),
    (text: ' ', width: 250, x: 188, y: 720),
    (text: 'ل', width: 500, x: 176, y: 720),
  ];
  final operations = <String>['BT /F1 24 Tf'];
  final cmapEntries = <String>[];
  final widths = <String>[];
  final names = <String>[];
  for (var i = 0; i < glyphs.length; i++) {
    final code = i + 1;
    final glyph = glyphs[i];
    final codeHex = code.toRadixString(16).padLeft(2, '0');
    final unicode = glyph.text.codeUnits
        .map((unit) => unit.toRadixString(16).padLeft(4, '0'))
        .join();
    operations.add(
      '1 0 0 1 ${_number(glyph.x)} ${_number(glyph.y)} Tm '
      '<$codeHex> Tj',
    );
    cmapEntries.add('<$codeHex> <$unicode>');
    widths.add('${glyph.width}');
    names.add('/g$code');
  }
  operations.add('ET');
  final content = operations.join('\n');
  final cmap = [
    '/CIDInit /ProcSet findresource begin',
    '12 dict begin begincmap',
    '1 begincodespacerange <00> <FF> endcodespacerange',
    '${cmapEntries.length} beginbfchar',
    ...cmapEntries,
    'endbfchar endcmap CMapName currentdict /CMap defineresource pop',
    'end end',
  ].join('\n');
  final font = '<< /Type /Font /Subtype /Type3 '
      '/FontBBox [0 -200 1000 800] /FontMatrix [0.001 0 0 0.001 0 0] '
      '/FirstChar 1 /LastChar ${glyphs.length} '
      '/Widths [${widths.join(' ')}] '
      '/Encoding << /Type /Encoding /Differences [1 ${names.join(' ')}] >> '
      '/ToUnicode 6 0 R '
      '/CharProcs << ${[
    for (final name in names) '$name 7 0 R'
  ].join(' ')} >> /Resources << >> >>';
  const charProc = '500 0 d0 0 0 450 700 re f';
  return _assemblePdf([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    font,
    '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
    '<< /Length ${charProc.length} >>\nstream\n$charProc\nendstream',
  ]);
}

bool _isCombiningMark(int rune) => rune >= 0x064b && rune <= 0x065f;

String _number(double value) {
  final fixed = value.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

Uint8List _assemblePdf(List<String> objects) {
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
