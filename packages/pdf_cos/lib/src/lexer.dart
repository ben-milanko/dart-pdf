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
      byte == 0x28 || byte == 0x29 || // ( )
      byte == 0x3C || byte == 0x3E || // < >
      byte == 0x5B || byte == 0x5D || // [ ]
      byte == 0x7B || byte == 0x7D || // { }
      byte == 0x2F || byte == 0x25; // / %

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

  CosToken nextToken() {
    skipWhitespaceAndComments();
    final start = position;
    if (position >= bytes.length) return CosToken(CosTokenType.eof, start);
    final b = bytes[position];
    switch (b) {
      case 0x5B:
        position++;
        return CosToken(CosTokenType.arrayOpen, start);
      case 0x5D:
        position++;
        return CosToken(CosTokenType.arrayClose, start);
      case 0x3C:
        if (position + 1 < bytes.length && bytes[position + 1] == 0x3C) {
          position += 2;
          return CosToken(CosTokenType.dictOpen, start);
        }
        return _hexString(start);
      case 0x3E:
        if (position + 1 < bytes.length && bytes[position + 1] == 0x3E) {
          position += 2;
          return CosToken(CosTokenType.dictClose, start);
        }
        throw CosParseException('unexpected ">"', start);
      case 0x28:
        return _literalString(start);
      case 0x29:
        throw CosParseException('unexpected ")"', start);
      case 0x2F:
        return _name(start);
      // { and } only occur inside PostScript calculator functions; surface
      // them as keywords so a function parser can handle them.
      case 0x7B:
        position++;
        return CosToken(CosTokenType.keyword, start, '{');
      case 0x7D:
        position++;
        return CosToken(CosTokenType.keyword, start, '}');
      default:
        if (b == 0x2B || b == 0x2D || b == 0x2E || _isDigit(b)) {
          return _number(start);
        }
        return _keyword(start);
    }
  }

  CosToken _number(int start) {
    // Content streams are number-dense (every coordinate, colour, index), so
    // this is the tokenizer's hottest path. Scan the digit/sign/dot run once
    // and parse straight from the bytes — no per-char StringBuffer.
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
      if (v != null) return CosToken(CosTokenType.integer, start, v);
      // Overflowing or malformed: fall back to the exact string semantics.
      final raw = String.fromCharCodes(bytes, start, p);
      final iv = int.tryParse(raw);
      if (iv == null) throw CosParseException('malformed number "$raw"', start);
      return CosToken(CosTokenType.integer, start, iv);
    }

    final raw = String.fromCharCodes(bytes, start, p);
    var s = raw;
    if (s.startsWith('.')) s = '0$s';
    if (s.startsWith('-.')) s = '-0${s.substring(1)}';
    if (s.endsWith('.')) s = '${s}0';
    final v = double.tryParse(s);
    if (v == null) throw CosParseException('malformed number "$raw"', start);
    return CosToken(CosTokenType.real, start, v);
  }

  /// Parses the integer in `bytes[start..end)` exactly as
  /// `int.tryParse(String.fromCharCodes(bytes, start, end))` would — an
  /// optional leading `+`/`-` then digits — but without allocating a string.
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

  CosToken _literalString(int start) {
    position++; // (
    var depth = 1;
    final out = BytesBuilder();
    while (true) {
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
      } else if (b == 0x0D) {
        // EOL inside a string is normalized to LF (§7.3.4.2)
        if (position < bytes.length && bytes[position] == 0x0A) position++;
        out.addByte(0x0A);
      } else {
        out.addByte(b);
      }
    }
    return CosToken(CosTokenType.string, start, out.takeBytes());
  }

  CosToken _hexString(int start) {
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
    return CosToken(CosTokenType.hexString, start, out.takeBytes());
  }

  CosToken _name(int start) {
    position++; // /
    final nameStart = position;
    // Fast path: a name with no `#XX` escape is just the regular-byte run, so
    // build the string straight from the range (most names have no escapes).
    while (position < bytes.length && isRegular(bytes[position])) {
      if (bytes[position] == 0x23) {
        return _nameWithEscapes(start, nameStart);
      }
      position++;
    }
    return CosToken(
        CosTokenType.name, start, String.fromCharCodes(bytes, nameStart, position));
  }

  CosToken _nameWithEscapes(int start, int nameStart) {
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
    return CosToken(
        CosTokenType.name, start, String.fromCharCodes(out.takeBytes()));
  }

  CosToken _keyword(int start) {
    var p = position;
    while (p < bytes.length && isRegular(bytes[p])) {
      p++;
    }
    if (p == start) {
      throw CosParseException(
          'unexpected byte 0x${bytes[position].toRadixString(16)}', start);
    }
    position = p;
    return CosToken(
        CosTokenType.keyword, start, String.fromCharCodes(bytes, start, p));
  }
}
