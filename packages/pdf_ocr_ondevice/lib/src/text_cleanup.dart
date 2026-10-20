/// Cleans one recognized line for a searchable text layer, or returns null
/// when nothing worth searching for is left.
///
/// PP-OCR's multilingual dictionary carries drawing symbols, and on technical
/// drawings the detector boxes the symbols themselves - a track-circuit dot
/// beside a label, a signal triangle at the end of a name - so the recognizer
/// writes them back as text: `F12 ●`, `▲8`, `A4381TPS▼`, or a span that is
/// nothing but `●`. Those make the layer's text wrong to copy and break
/// searching for the label. So characters from the Unicode **Geometric
/// Shapes** block (U+25A0-U+25FF: ● ▲ ▼ △ ■ ...) are removed, whitespace is
/// collapsed, and a span left with no letter or digit at all (a lone bullet,
/// an ellipsis) is dropped.
String? cleanRecognizedText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x25A0 && rune <= 0x25FF) continue;
    buffer.writeCharCode(rune);
  }
  final cleaned = buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  return _hasLetterOrDigit.hasMatch(cleaned) ? cleaned : null;
}

final _hasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
