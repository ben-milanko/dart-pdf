import 'dart:typed_data';

import 'exceptions.dart';
import 'token.dart';

/// Tokenizer for PDF syntax (ISO 32000-1 §7.2).
class CosLexer {
  CosLexer(this.bytes, [this.position = 0]);

  final Uint8List bytes;

  /// Next byte to be read. Mutable so parsers can resynchronize after
  /// consuming raw (non-tokenized) byte ranges like stream payloads.
  int position;

  static bool isWhitespace(int byte) =>
      byte == 0x00 ||
      byte == 0x09 ||
      byte == 0x0A ||
      byte == 0x0C ||
      byte == 0x0D ||
      byte == 0x20;

  static bool isDelimiter(int byte) =>
      byte == 0x28 ||
      byte == 0x29 || // ( )
      byte == 0x3C ||
      byte == 0x3E || // < >
      byte == 0x5B ||
      byte == 0x5D || // [ ]
      byte == 0x7B ||
      byte == 0x7D || // { }
      byte == 0x2F ||
      byte == 0x25; // / %

  static bool isRegular(int byte) => !isWhitespace(byte) && !isDelimiter(byte);

  static bool _isDigit(int b) => b >= 0x30 && b <= 0x39;

  static int? hexDigit(int b) {
    if (b >= 0x30 && b <= 0x39) return b - 0x30;
    if (b >= 0x41 && b <= 0x46) return b - 0x41 + 10;
    if (b >= 0x61 && b <= 0x66) return b - 0x61 + 10;
    return null;
  }

  void skipWhitespaceAndComments() {
    while (position < bytes.length) {
      final b = bytes[position];
      if (isWhitespace(b)) {
        position++;
      } else if (b == 0x25) {
        // % comment runs to end of line
        while (position < bytes.length &&
            bytes[position] != 0x0A &&
            bytes[position] != 0x0D) {
          position++;
        }
      } else {
        break;
      }
    }
  }

  /// Consumes one end-of-line sequence (CRLF, LF, or lone CR) if present.
  ///
  /// Needed after the `stream` keyword, where the EOL is a syntactic marker
  /// rather than skippable whitespace.
  void skipEol() {
    if (position < bytes.length && bytes[position] == 0x0D) {
      position++;
      if (position < bytes.length && bytes[position] == 0x0A) position++;
    } else if (position < bytes.length && bytes[position] == 0x0A) {
      position++;
    }
  }

  /// Returns the next token.
  ///
  /// When [reuse] is supplied, the returned object is that same mutable
  /// buffer. The caller must consume it before the next call that reuses it.
  CosToken nextToken([CosTokenBuffer? reuse]) {
    skipWhitespaceAndComments();
    final start = position;
    if (position >= bytes.length) {
      return _token(reuse, CosTokenType.eof, start);
    }
    final b = bytes[position];
    switch (b) {
      case 0x5B:
        position++;
        return _token(reuse, CosTokenType.arrayOpen, start);
      case 0x5D:
        position++;
        return _token(reuse, CosTokenType.arrayClose, start);
      case 0x3C:
        if (position + 1 < bytes.length && bytes[position + 1] == 0x3C) {
          position += 2;
          return _token(reuse, CosTokenType.dictOpen, start);
        }
        return _hexString(start, reuse);
      case 0x3E:
        if (position + 1 < bytes.length && bytes[position + 1] == 0x3E) {
          position += 2;
          return _token(reuse, CosTokenType.dictClose, start);
        }
        throw CosParseException('unexpected ">"', start);
      case 0x28:
        return _literalString(start, reuse);
      case 0x29:
        throw CosParseException('unexpected ")"', start);
      case 0x2F:
        return _name(start, reuse);
      // { and } only occur inside PostScript calculator functions; surface
      // them as keywords so a function parser can handle them.
      case 0x7B:
        position++;
        return _token(reuse, CosTokenType.keyword, start, '{');
      case 0x7D:
        position++;
        return _token(reuse, CosTokenType.keyword, start, '}');
      default:
        if (b == 0x2B || b == 0x2D || b == 0x2E || _isDigit(b)) {
          return _number(start, reuse);
        }
        return _keyword(start, reuse);
    }
  }

  CosToken _token(CosTokenBuffer? reuse, CosTokenType type, int offset,
      [Object? value]) {
    if (reuse == null) return CosToken(type, offset, value);
    reuse.setToken(type, offset, value);
    return reuse;
  }

  CosToken _number(int start, CosTokenBuffer? reuse) {
    // Content streams are number-dense (every coordinate, colour, index), so
    // this is the tokenizer's hottest path. Scan the digit/sign/dot run once
    // and parse straight from the bytes - no per-char StringBuffer.
    var isReal = false;
    var p = position;
    while (p < bytes.length) {
      final b = bytes[p];
      if (_isDigit(b) || b == 0x2B || b == 0x2D) {
        // digit or sign
      } else if (b == 0x2E) {
        isReal = true;
      } else {
        break;
      }
      p++;
    }
    position = p;

    if (!isReal) {
      // Parse the integer directly when it can't overflow (≤18 digits); this
      // is bit-for-bit identical to int.tryParse over the same byte range.
      final v = _parseIntRange(start, p);
      if (v != null) return _token(reuse, CosTokenType.integer, start, v);
      // Overflowing or malformed: fall back to the exact string semantics.
      final raw = String.fromCharCodes(bytes, start, p);
      final iv = int.tryParse(raw);
      if (iv == null) throw CosParseException('malformed number "$raw"', start);
      return _token(reuse, CosTokenType.integer, start, iv);
    }

    // PDF reals have no exponent (§7.3.3): sign, digits, one dot. With ≤15
    // significant digits, digits/10^frac is one exact integer divided by one
    // exact power of ten - a single correctly-rounded division, bit-for-bit
    // identical to double.parse - without the string allocation. Content
    // streams are real-dense (every coordinate), so this is hot.
    final fast = _parseRealRange(start, p);
    if (fast != null) return _token(reuse, CosTokenType.real, start, fast);

    final raw = String.fromCharCodes(bytes, start, p);
    var s = raw;
    if (s.startsWith('.')) s = '0$s';
    if (s.startsWith('-.')) s = '-0${s.substring(1)}';
    if (s.endsWith('.')) s = '${s}0';
    final v = double.tryParse(s);
    if (v == null) throw CosParseException('malformed number "$raw"', start);
    return _token(reuse, CosTokenType.real, start, v);
  }

  static const List<double> _pow10 = [
    1.0, 10.0, 100.0, 1e3, 1e4, 1e5, 1e6, 1e7, //
    1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15,
  ];

  /// Parses the real in `bytes[start..end)` when it is a plain
  /// `sign? digits* ('.' digits*)?` with ≤15 total digits; null otherwise
  /// (multiple dots, embedded signs, digit-heavy) so the caller can fall
  /// back to the string path with identical semantics.
  double? _parseRealRange(int start, int end) {
    var i = start;
    var negative = false;
    final first = bytes[i];
    if (first == 0x2B || first == 0x2D) {
      negative = first == 0x2D;
      i++;
    }
    var digits = 0;
    var nDigits = 0;
    var fracCount = 0;
    var sawDot = false;
    var sawDigit = false;
    for (; i < end; i++) {
      final b = bytes[i];
      if (b == 0x2E) {
        if (sawDot) return null;
        sawDot = true;
      } else {
        final d = b - 0x30;
        if (d < 0 || d > 9) return null;
        digits = digits * 10 + d;
        nDigits++;
        if (sawDot) fracCount++;
        sawDigit = true;
      }
    }
    if (!sawDigit || nDigits > 15) return null;
    final v = digits / _pow10[fracCount];
    return negative ? -v : v;
  }

  /// Parses the integer in `bytes[start..end)` exactly as
  /// `int.tryParse(String.fromCharCodes(bytes, start, end))` would - an
  /// optional leading `+`/`-` then digits - but without allocating a string.
  /// Returns null for malformed input or a mantissa long enough to risk
  /// 64-bit overflow (≥19 digits), so the caller can fall back to the string
  /// path with identical semantics.
  int? _parseIntRange(int start, int end) {
    var i = start;
    var negative = false;
    final first = bytes[i];
    if (first == 0x2B || first == 0x2D) {
      negative = first == 0x2D;
      i++;
    }
    if (i >= end || end - i > 18) return null; // empty mantissa, or too long
    var value = 0;
    for (; i < end; i++) {
      final d = bytes[i] - 0x30;
      if (d < 0 || d > 9) return null; // embedded sign or junk
      value = value * 10 + d;
    }
    return negative ? -value : value;
  }

  CosToken _literalString(int start, CosTokenBuffer? reuse) {
    position++; // (
    var depth = 1;
    final out = BytesBuilder();
    while (true) {
      // Fast path: bulk-append the run of ordinary bytes up to the next byte
      // that needs interpretation (escape, paren, or CR) in one copy rather
      // than one addByte per character.
      final runStart = position;
      while (position < bytes.length) {
        final c = bytes[position];
        if (c == 0x5C || c == 0x28 || c == 0x29 || c == 0x0D) break;
        position++;
      }
      if (position > runStart) {
        out.add(Uint8List.sublistView(bytes, runStart, position));
      }
      if (position >= bytes.length) {
        throw CosParseException('unterminated string', start);
      }
      final b = bytes[position++];
      if (b == 0x5C) {
        if (position >= bytes.length) {
          throw CosParseException('unterminated string', start);
        }
        final e = bytes[position++];
        switch (e) {
          case 0x6E: // \n
            out.addByte(0x0A);
          case 0x72: // \r
            out.addByte(0x0D);
          case 0x74: // \t
            out.addByte(0x09);
          case 0x62: // \b
            out.addByte(0x08);
          case 0x66: // \f
            out.addByte(0x0C);
          case 0x28 || 0x29 || 0x5C:
            out.addByte(e);
          case 0x0D: // backslash-EOL: line continuation
            if (position < bytes.length && bytes[position] == 0x0A) position++;
          case 0x0A:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              // up to three octal digits
              var code = e - 0x30;
              for (var i = 0; i < 2 && position < bytes.length; i++) {
                final d = bytes[position];
                if (d < 0x30 || d > 0x37) break;
                code = code * 8 + (d - 0x30);
                position++;
              }
              out.addByte(code & 0xFF);
            } else {
              // unknown escape: the backslash is dropped (§7.3.4.2)
              out.addByte(e);
            }
        }
      } else if (b == 0x28) {
        depth++;
        out.addByte(b);
      } else if (b == 0x29) {
        depth--;
        if (depth == 0) break;
        out.addByte(b);
      } else {
        // b == 0x0D: EOL inside a string is normalized to LF (§7.3.4.2)
        if (position < bytes.length && bytes[position] == 0x0A) position++;
        out.addByte(0x0A);
      }
    }
    return _token(reuse, CosTokenType.string, start, out.takeBytes());
  }

  CosToken _hexString(int start, CosTokenBuffer? reuse) {
    position++; // <
    final out = BytesBuilder();
    int? pending;
    while (true) {
      if (position >= bytes.length) {
        throw CosParseException('unterminated hex string', start);
      }
      final b = bytes[position++];
      if (b == 0x3E) break;
      if (isWhitespace(b)) continue;
      final d = hexDigit(b);
      if (d == null) {
        throw CosParseException('invalid hex digit in string', position - 1);
      }
      if (pending == null) {
        pending = d;
      } else {
        out.addByte((pending << 4) | d);
        pending = null;
      }
    }
    // an odd final digit is padded with zero (§7.3.4.3)
    if (pending != null) out.addByte(pending << 4);
    return _token(reuse, CosTokenType.hexString, start, out.takeBytes());
  }

  CosToken _name(int start, CosTokenBuffer? reuse) {
    position++; // /
    final nameStart = position;
    // Fast path: a name with no `#XX` escape is just the regular-byte run, so
    // build the string straight from the range (most names have no escapes).
    while (position < bytes.length && isRegular(bytes[position])) {
      if (bytes[position] == 0x23) {
        return _nameWithEscapes(start, nameStart, reuse);
      }
      position++;
    }
    return _token(reuse, CosTokenType.name, start,
        String.fromCharCodes(bytes, nameStart, position));
  }

  CosToken _nameWithEscapes(int start, int nameStart, CosTokenBuffer? reuse) {
    position = nameStart;
    final out = BytesBuilder();
    while (position < bytes.length && isRegular(bytes[position])) {
      var b = bytes[position++];
      if (b == 0x23 && position + 1 < bytes.length) {
        final h1 = hexDigit(bytes[position]);
        final h2 = hexDigit(bytes[position + 1]);
        if (h1 != null && h2 != null) {
          b = (h1 << 4) | h2;
          position += 2;
        }
      }
      out.addByte(b);
    }
    return _token(
        reuse, CosTokenType.name, start, String.fromCharCodes(out.takeBytes()));
  }

  CosToken _keyword(int start, CosTokenBuffer? reuse) {
    var p = position;
    while (p < bytes.length && isRegular(bytes[p])) {
      p++;
    }
    if (p == start) {
      throw CosParseException(
          'unexpected byte 0x${bytes[position].toRadixString(16)}', start);
    }
    position = p;
    return _token(reuse, CosTokenType.keyword, start, _internKeyword(start, p));
  }

  /// Interned strings for keywords up to 3 bytes, packed little-endian into
  /// one int. Content streams repeat a tiny operator vocabulary millions of
  /// times; handing back one shared string per spelling replaces a
  /// String.fromCharCodes allocation per operator token.
  static final Map<int, String> _keywordIntern = {};

  String _internKeyword(int start, int end) {
    final len = end - start;
    if (len > 3) return String.fromCharCodes(bytes, start, end);
    var packed = bytes[start];
    if (len > 1) packed |= bytes[start + 1] << 8;
    if (len > 2) packed |= bytes[start + 2] << 16;
    // The content interpreter consumes a fixed operator vocabulary. Return
    // those canonical literals without a hash-table probe: a vector-dense CAD
    // stream can contain hundreds of thousands of one- and two-byte operators.
    // Unknown short keywords still use the bounded interner below, preserving
    // the general lexer contract for extensions and malformed real-world PDFs.
    final known = switch (packed) {
      0x6d => 'm',
      0x6c => 'l',
      0x63 => 'c',
      0x76 => 'v',
      0x79 => 'y',
      0x6572 => 're',
      0x6d63 => 'cm',
      0x68 => 'h',
      0x53 => 'S',
      0x73 => 's',
      0x66 => 'f',
      0x46 => 'F',
      0x2a66 => 'f*',
      0x42 => 'B',
      0x2a42 => 'B*',
      0x62 => 'b',
      0x2a62 => 'b*',
      0x6e => 'n',
      0x57 => 'W',
      0x2a57 => 'W*',
      0x71 => 'q',
      0x51 => 'Q',
      0x77 => 'w',
      0x4a => 'J',
      0x6a => 'j',
      0x4d => 'M',
      0x64 => 'd',
      0x7367 => 'gs',
      0x6972 => 'ri',
      0x69 => 'i',
      0x67 => 'g',
      0x47 => 'G',
      0x6772 => 'rg',
      0x4752 => 'RG',
      0x6b => 'k',
      0x4b => 'K',
      0x7363 => 'cs',
      0x5343 => 'CS',
      0x6373 => 'sc',
      0x6e6373 => 'scn',
      0x4353 => 'SC',
      0x4e4353 => 'SCN',
      0x5442 => 'BT',
      0x5445 => 'ET',
      0x6654 => 'Tf',
      0x6454 => 'Td',
      0x4454 => 'TD',
      0x6d54 => 'Tm',
      0x2a54 => 'T*',
      0x4c54 => 'TL',
      0x6354 => 'Tc',
      0x7754 => 'Tw',
      0x7a54 => 'Tz',
      0x7354 => 'Ts',
      0x7254 => 'Tr',
      0x6a54 => 'Tj',
      0x27 => "'",
      0x22 => '"',
      0x4a54 => 'TJ',
      0x6f44 => 'Do',
      0x4942 => 'BI',
      0x4449 => 'ID',
      0x4945 => 'EI',
      0x6873 => 'sh',
      0x434442 => 'BDC',
      0x434d42 => 'BMC',
      0x434d45 => 'EMC',
      0x504d => 'MP',
      0x5044 => 'DP',
      0x5842 => 'BX',
      0x5845 => 'EX',
      0x3064 => 'd0',
      0x3164 => 'd1',
      0x52 => 'R',
      0x6a626f => 'obj',
      0x646e65 => 'end',
      _ => null,
    };
    if (known != null) return known;
    final hit = _keywordIntern[packed];
    if (hit != null) return hit;
    final s = String.fromCharCodes(bytes, start, end);
    if (_keywordIntern.length < 4096) _keywordIntern[packed] = s;
    return s;
  }
}
