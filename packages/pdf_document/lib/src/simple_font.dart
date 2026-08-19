import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'content_writer.dart';
import 'fonts/encodings.dart';
import 'type0_font.dart';

/// One simple (byte-coded, non-/Type0) font, parsed once from its font
/// dictionary and shared by everything that reads or rewrites its text.
///
/// A simple font draws one byte per glyph, but that byte is *not* the
/// character: §9.6.6 lets the document remap every code through
/// `/Encoding` `/Differences`, and a subsetted font routinely renumbers its
/// codes from scratch, so a page that reads `05/08/2026` can be shown by the
/// bytes `2D 3D 3E 2D 2F 3E 3F 2D 3F 40`. Reading those bytes as Latin-1 -
/// what the content editor used to do - yields `-=>-/>?-?@`, and writing a
/// replacement back as Latin-1 draws whatever glyphs those codes happen to
/// name (issue: "B = 8, 9 = I, 0 = Space").
///
/// This resolves a code to text the same way the renderer does (§9.10.2):
/// `/ToUnicode` first, then an explicit `/Differences` glyph name, then the
/// built-in Symbol/ZapfDingbats encodings, then the base encoding's glyph
/// names, and finally the Latin-1 identity that most base-14 text relies on.
/// [encode] runs the same table backwards so a replacement is written in the
/// font's own codes.
class SimpleFont {
  SimpleFont._(this.codeToText, this._codeForText, this._widthOf)
      : _maxTextLength = _codeForText.keys
            .fold(1, (max, text) => text.length > max ? text.length : max);

  /// code (0-255) -> the Unicode text it draws. Codes the font gives no
  /// reading for are absent.
  final Map<int, String> codeToText;

  /// The reverse table, for re-encoding replacements. Built only from codes
  /// the font actually *declares* - see [decode] - so a replacement is never
  /// written as a code the font has no glyph for. Lowest code wins when two
  /// codes draw the same text, so a round-tripped run keeps the bytes it came
  /// in with wherever the font offers a choice.
  final Map<String, int> _codeForText;

  final double Function(int code) _widthOf;

  /// The longest reading any one code carries, so [encode] knows how far to
  /// look ahead when matching a multi-character glyph.
  final int _maxTextLength;

  /// The advance (thousandths of an em) of [code].
  double widthOf(int code) => _widthOf(code);

  /// The text [code] draws, or the empty string when the font maps it to
  /// nothing. Never null, so a run always flattens to *something*.
  String textFor(int code) => codeToText[code] ?? '';

  /// Encodes [text] into this font's own codes, or null when the font can
  /// draw no code for one of its characters. Null means "leave the run
  /// alone" - the same contract [Type0Font] uses for a glyph its embedded
  /// program lacks, and far better than writing a byte that draws something
  /// else.
  Uint8List? encode(String text) {
    final out = <int>[];
    // walk by rune so a code that draws a multi-char string (a ligature in
    // /ToUnicode, say) is matched before its first character is.
    var i = 0;
    while (i < text.length) {
      var matched = false;
      // longest-first: a code drawing "ffi" must beat the one drawing "f".
      for (var len = _maxTextLength; len >= 1; len--) {
        if (i + len > text.length) continue;
        final code = _codeForText[text.substring(i, i + len)];
        if (code == null) continue;
        out.add(code);
        i += len;
        matched = true;
        break;
      }
      if (!matched) return null;
    }
    return Uint8List.fromList(out);
  }

  /// Builds the code tables for [fontDict]. Never null: a font that declares
  /// no encoding at all still gets the Latin-1 identity every base-14 run
  /// relies on, so this is a safe drop-in wherever bytes were read directly.
  factory SimpleFont.decode(CosDocument cos, CosDictionary? fontDict) {
    final codeToText = <int, String>{};
    final baseFont = _baseFontName(cos, fontDict);

    // 1. the base encoding's glyph names, and 2. /Differences over the top -
    // the document naming the glyph itself always wins.
    final encoding = fontDict == null ? null : cos.resolve(fontDict['Encoding']);
    final differences = _parseDifferences(cos, encoding);
    final names = <int, String>{};
    void fill(String? Function(int) table) {
      for (var code = 0; code <= 255; code++) {
        final name = table(code);
        if (name != null) names[code] = name;
      }
    }

    if (encoding is CosName) {
      if (encoding.value == 'WinAnsiEncoding') {
        fill(winAnsiGlyphName);
      } else if (encoding.value == 'StandardEncoding' ||
          encoding.value == 'MacRomanEncoding') {
        fill(standardGlyphName);
      }
    } else if (encoding is CosDictionary) {
      final base = cos.resolve(encoding['BaseEncoding']);
      fill(base is CosName && base.value == 'WinAnsiEncoding'
          ? winAnsiGlyphName
          : standardGlyphName);
    }
    names.addAll(differences);

    // Codes the font *states* a glyph for, as opposed to ones that merely
    // fall through to the Latin-1 identity below. Only these may be written
    // back: a subset that renumbered its codes has no glyph at the ASCII
    // position of a character it never kept, so encoding a replacement there
    // would draw notdef (or nothing) rather than the character asked for.
    final declared = names.keys.toSet();

    for (var code = 0; code <= 255; code++) {
      final text = _textForCode(code, names, differences, baseFont);
      if (text != null) codeToText[code] = text;
    }
    if (_isNamed(baseFont, 'symbol') || _isNamed(baseFont, 'zapfdingbats')) {
      // their built-in encodings are the font's own glyph set
      declared.addAll(codeToText.keys);
    }

    // 3. /ToUnicode outranks everything above: it is the producer stating
    // outright what the code reads as, which is the whole point of it on a
    // subsetted font whose codes mean nothing on their own.
    if (fontDict != null) {
      final toUni = cos.resolve(fontDict['ToUnicode']);
      if (toUni is CosStream) {
        try {
          parseToUnicodeCmap(cos.decodeStreamData(toUni)).forEach((code, text) {
            if (code >= 0 && code <= 255 && text.isNotEmpty) {
              codeToText[code] = text;
              declared.add(code);
            }
          });
        } on Exception {
          // a broken /ToUnicode just leaves the encoding-derived table
        }
      }
    }

    // A font that declares no encoding at all - the bare base-14 case - is
    // taken at the Latin-1 identity in both directions, which is what every
    // run this library writes itself relies on.
    final encodable = declared.isEmpty ? codeToText.keys : declared;

    final codeForText = <String, int>{};
    // ascending so the lowest code wins a tie
    for (final code in encodable.toList()..sort()) {
      final text = codeToText[code];
      if (text != null && text.isNotEmpty) {
        codeForText.putIfAbsent(text, () => code);
      }
    }

    return SimpleFont._(codeToText, codeForText, widthsFor(cos, fontDict));
  }

  /// One code's reading, from the glyph-name tables the renderer uses
  /// (`PdfFontInfo._computeCharFor`, minus the CID branches).
  static String? _textForCode(
    int code,
    Map<int, String> names,
    Map<int, String> differences,
    String? baseFont,
  ) {
    // An explicit /Differences entry names the glyph outright, so it beats
    // the built-in encodings below.
    final difference = differences[code];
    if (difference != null) {
      final mapped = glyphNameUnicode(difference);
      if (mapped != null) return String.fromCharCode(mapped);
    }
    if (_isNamed(baseFont, 'zapfdingbats')) {
      final mapped = zapfDingbatsUnicode(code);
      if (mapped != null) return String.fromCharCode(mapped);
    }
    if (_isNamed(baseFont, 'symbol')) {
      final mapped = symbolUnicode(code);
      if (mapped != null) return String.fromCharCode(mapped);
    }
    final name = names[code];
    if (name != null) {
      final mapped = glyphNameUnicode(name);
      if (mapped != null) return String.fromCharCode(mapped);
    }
    // Latin-1 ≈ Standard/WinAnsi enough for anything left over.
    if (code >= 0x20 && code <= 0xFF) return String.fromCharCode(code);
    return null;
  }

  /// An advance-width lookup (thousandths of an em) for [font]: its own
  /// /Widths when present, else base-14 metrics keyed off /BaseFont, falling
  /// back to Helvetica. Public so callers that only need metrics (paragraph
  /// reflow) skip building the encoding tables.
  static double Function(int code) widthsFor(
      CosDocument cos, CosDictionary? font) {
    if (font != null) {
      final widths = cos.resolve(font['Widths']);
      if (widths is CosArray) {
        final firstChar = _num(cos.resolve(font['FirstChar'])).round();
        var missing = 0.0;
        final descriptor = cos.resolve(font['FontDescriptor']);
        if (descriptor is CosDictionary) {
          missing = _num(cos.resolve(descriptor['MissingWidth']));
        }
        final table = [for (final w in widths.items) _num(cos.resolve(w))];
        return (code) {
          final i = code - firstChar;
          return i >= 0 && i < table.length ? table[i] : missing;
        };
      }
      final base = cos.resolve(font['BaseFont']);
      if (base is CosName) {
        final standard = PdfStandardFont.tryFromName(base.value);
        if (standard != null) {
          return (code) => standard.widthOf(code).toDouble();
        }
      }
    }
    return (code) => PdfStandardFont.helvetica.widthOf(code).toDouble();
  }

  /// Parses an /Encoding dictionary's /Differences into code -> glyph name.
  static Map<int, String> _parseDifferences(
      CosDocument cos, CosObject? encoding) {
    final dict = cos.resolve(encoding);
    if (dict is! CosDictionary) return const {};
    final differences = cos.resolve(dict['Differences']);
    if (differences is! CosArray) return const {};
    final result = <int, String>{};
    var code = 0;
    for (final item in differences.items) {
      final resolved = cos.resolve(item);
      if (resolved is CosInteger) {
        code = resolved.value;
      } else if (resolved is CosName) {
        result[code++] = resolved.value;
      }
    }
    return result;
  }

  static String? _baseFontName(CosDocument cos, CosDictionary? font) {
    if (font == null) return null;
    final base = cos.resolve(font['BaseFont']);
    return base is CosName ? base.value : null;
  }

  /// True when [baseFont]'s name, past any `ABCDEF+` subset tag, is [name].
  static bool _isNamed(String? baseFont, String name) {
    if (baseFont == null) return false;
    final plus = baseFont.indexOf('+');
    return (plus >= 0 ? baseFont.substring(plus + 1) : baseFont)
            .toLowerCase() ==
        name;
  }

  static double _num(CosObject? o) => switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0,
      };
}
