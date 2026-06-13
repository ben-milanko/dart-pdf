import 'dart:typed_data';

import '../path.dart';
import 'encodings.dart';

/// A parsed Adobe Type 1 font program (PDF `/FontFile`).
///
/// Type 1 fonts store glyphs as eexec-encrypted PostScript charstrings keyed
/// by glyph *name* (unlike TrueType/CFF, which key by glyph id). This parser
/// decrypts the eexec section, extracts the /Subrs and /CharStrings, and
/// interprets the Type 1 charstring language (a different dialect from the
/// Type 2 charstrings in CFF) into em-space outlines with the /FontMatrix
/// applied. Hints are ignored; flex and OtherSubr hint-replacement are
/// handled enough to reconstruct the path.
class Type1Font {
  Type1Font._({
    required Map<String, Uint8List> charStrings,
    required List<Uint8List?> subrs,
    required List<double> fontMatrix,
    required Map<int, String> builtinEncoding,
  })  : _charStrings = charStrings,
        _subrs = subrs,
        _fontMatrix = fontMatrix,
        _builtinEncoding = builtinEncoding;

  final Map<String, Uint8List> _charStrings;
  final List<Uint8List?> _subrs;
  final List<double> _fontMatrix;
  final Map<int, String> _builtinEncoding;

  final Map<String, PdfPath?> _outlineCache = {};
  final Map<String, double> _advanceCache = {};

  /// The font's built-in /Encoding (code → glyph name). Used only when the
  /// PDF font dictionary supplies no /Encoding of its own (§9.6.6.2).
  Map<int, String> get builtinEncoding => _builtinEncoding;

  bool hasGlyph(String name) => _charStrings.containsKey(name);

  /// Real outline for a glyph name, in em units (y-up), or null when the
  /// glyph is absent or draws nothing.
  PdfPath? outlineForName(String name) {
    return _outlineCache.putIfAbsent(name, () {
      final charString = _charStrings[name];
      if (charString == null) return null;
      try {
        final runner = _Type1Runner(
          subrs: _subrs,
          charStrings: _charStrings,
          fontMatrix: _fontMatrix,
        );
        runner.run(charString);
        _advanceCache[name] = runner.width * _fontMatrix[0].abs();
        return runner.segments.isEmpty ? null : PdfPath(runner.segments);
      } on Object {
        return null;
      }
    });
  }

  /// Advance width for a glyph name in em units (from hsbw); null if unknown.
  double? advanceForName(String name) {
    outlineForName(name);
    return _advanceCache[name];
  }

  static Type1Font? parse(Uint8List raw) {
    try {
      final bytes = _stripPfb(raw);
      final eexec = _indexOf(bytes, _eexecKeyword, 0);
      if (eexec < 0) return null;
      final clearText = String.fromCharCodes(bytes, 0, eexec);

      // Decrypt the eexec section (everything after the keyword + one space).
      var p = eexec + _eexecKeyword.length;
      while (p < bytes.length && _isWhitespace(bytes[p])) {
        p++;
      }
      final encrypted = _decodeEexecRegion(bytes, p);
      final decrypted = _decrypt(encrypted, 55665, 4);

      final fontMatrix = _parseFontMatrix(clearText);
      final builtinEncoding = _parseEncoding(clearText);

      final lenIV = _parseLenIV(decrypted);
      final subrs = _parseSubrs(decrypted, lenIV);
      final charStrings = _parseCharStrings(decrypted, lenIV);
      if (charStrings.isEmpty) return null;

      return Type1Font._(
        charStrings: charStrings,
        subrs: subrs,
        fontMatrix: fontMatrix,
        builtinEncoding: builtinEncoding,
      );
    } on Object {
      return null;
    }
  }

  // ---------- container formats ----------

  /// PFB wraps the segments in 6-byte headers (0x80, type, 4-byte length).
  /// Strip them and concatenate; raw PFA/PDF streams pass through unchanged.
  static Uint8List _stripPfb(Uint8List bytes) {
    if (bytes.isEmpty || bytes[0] != 0x80) return bytes;
    final out = BytesBuilder();
    var p = 0;
    while (p + 6 <= bytes.length && bytes[p] == 0x80) {
      final type = bytes[p + 1];
      if (type == 3) break; // EOF segment
      final len = bytes[p + 2] |
          (bytes[p + 3] << 8) |
          (bytes[p + 4] << 16) |
          (bytes[p + 5] << 24);
      p += 6;
      if (p + len > bytes.length) break;
      out.add(Uint8List.sublistView(bytes, p, p + len));
      p += len;
    }
    return out.toBytes();
  }

  /// The bytes after `eexec` are either raw binary or ASCII-hex. Hex when the
  /// first four non-blank bytes are all hex digits (§ T1 spec). Decode hex to
  /// binary; otherwise return the binary tail verbatim.
  static Uint8List _decodeEexecRegion(Uint8List bytes, int start) {
    var hexCount = 0;
    var i = start;
    while (i < bytes.length && hexCount < 4) {
      final c = bytes[i];
      if (_isWhitespace(c)) {
        i++;
        continue;
      }
      if (!_isHexDigit(c)) break;
      hexCount++;
      i++;
    }
    if (hexCount < 4) {
      return Uint8List.sublistView(bytes, start);
    }
    final out = BytesBuilder();
    int? hi;
    for (var j = start; j < bytes.length; j++) {
      final c = bytes[j];
      if (_isWhitespace(c)) continue;
      if (!_isHexDigit(c)) break;
      final v = _hexValue(c);
      if (hi == null) {
        hi = v;
      } else {
        out.addByte((hi << 4) | v);
        hi = null;
      }
    }
    return out.toBytes();
  }

  /// Adobe eexec/charstring decryption (R, c1=52845, c2=22719), discarding
  /// the first [skip] random bytes.
  static Uint8List _decrypt(Uint8List cipher, int r, int skip) {
    const c1 = 52845, c2 = 22719;
    var rr = r;
    final out = Uint8List(cipher.length);
    var n = 0;
    for (final c in cipher) {
      out[n++] = c ^ (rr >> 8);
      rr = ((c + rr) * c1 + c2) & 0xFFFF;
    }
    if (skip >= n) return Uint8List(0);
    return Uint8List.sublistView(out, skip, n);
  }

  // ---------- clear-text parsing ----------

  static List<double> _parseFontMatrix(String text) {
    final m = RegExp(r'/FontMatrix\s*\[([^\]]*)\]').firstMatch(text);
    if (m == null) return const [0.001, 0, 0, 0.001, 0, 0];
    final nums = RegExp(r'-?[0-9.eE+-]+')
        .allMatches(m.group(1)!)
        .map((x) => double.tryParse(x.group(0)!))
        .whereType<double>()
        .toList();
    if (nums.length < 6) return const [0.001, 0, 0, 0.001, 0, 0];
    return nums.sublist(0, 6);
  }

  static Map<int, String> _parseEncoding(String text) {
    final result = <int, String>{};
    final m = RegExp(r'/Encoding\s+(\w+)\s+def').firstMatch(text);
    if (m != null && m.group(1) == 'StandardEncoding') {
      for (var code = 0; code <= 255; code++) {
        final name = _standardName(code);
        if (name != null) result[code] = name;
      }
      return result;
    }
    for (final d
        in RegExp(r'dup\s+(\d+)\s*/(\S+)\s+put').allMatches(text)) {
      result[int.parse(d.group(1)!)] = d.group(2)!;
    }
    return result;
  }

  static String? _standardName(int code) =>
      code >= 32 && code <= 126 ? winAnsiGlyphName(code) : standardGlyphName(code);

  // ---------- private-dict parsing ----------

  static int _parseLenIV(Uint8List data) {
    final m = RegExp(r'/lenIV\s+(\d+)')
        .firstMatch(String.fromCharCodes(_head(data, 4096)));
    return m == null ? 4 : int.parse(m.group(1)!);
  }

  /// `/Subrs N array` followed by `dup i len RD <binary> NP` entries.
  static List<Uint8List?> _parseSubrs(Uint8List data, int lenIV) {
    final header = _indexOfString(data, '/Subrs', 0);
    if (header < 0) return const [];
    final countMatch = RegExp(r'/Subrs\s+(\d+)')
        .firstMatch(String.fromCharCodes(data, header, _min(header + 40, data.length)));
    final count = countMatch == null ? 0 : int.parse(countMatch.group(1)!);
    final subrs = List<Uint8List?>.filled(count <= 0 ? 0 : count, null);
    var p = header;
    while (true) {
      final dup = _indexOfString(data, 'dup ', p);
      if (dup < 0) break;
      // stop once we leave the Subrs section for CharStrings
      final cs = _indexOfString(data, '/CharStrings', header);
      if (cs >= 0 && dup > cs) break;
      final entry = _readBinaryEntry(data, dup + 4);
      if (entry == null) break;
      final (index, bin, next) = entry;
      if (index >= 0 && index < subrs.length) {
        subrs[index] = _decrypt(bin, 4330, lenIV);
      }
      p = next;
    }
    return subrs;
  }

  /// `/CharStrings N dict ... begin` then `/name len RD <binary> ND` entries.
  static Map<String, Uint8List> _parseCharStrings(Uint8List data, int lenIV) {
    final result = <String, Uint8List>{};
    var start = _indexOfString(data, '/CharStrings', 0);
    if (start < 0) return result;
    final begin = _indexOfString(data, 'begin', start);
    var p = begin < 0 ? start : begin + 5;
    while (p < data.length) {
      // next '/name'
      while (p < data.length && data[p] != 0x2F) {
        // an 'end' token terminates the dict
        if (_matchesAt(data, p, 'end')) return result;
        p++;
      }
      if (p >= data.length) break;
      p++; // skip '/'
      final nameStart = p;
      while (p < data.length && !_isDelimiter(data[p])) {
        p++;
      }
      final name = String.fromCharCodes(data, nameStart, p);
      // length
      while (p < data.length && _isWhitespace(data[p])) {
        p++;
      }
      final numStart = p;
      while (p < data.length && data[p] >= 0x30 && data[p] <= 0x39) {
        p++;
      }
      if (p == numStart) continue;
      final len = int.parse(String.fromCharCodes(data, numStart, p));
      // RD / -| token, then exactly one space, then `len` bytes
      while (p < data.length && _isWhitespace(data[p])) {
        p++;
      }
      while (p < data.length && !_isWhitespace(data[p])) {
        p++; // skip the RD / -| token
      }
      p++; // the single separating space
      if (p + len > data.length) break;
      final bin = Uint8List.sublistView(data, p, p + len);
      result[name] = _decrypt(bin, 4330, lenIV);
      p += len;
    }
    return result;
  }

  /// Reads `i len RD <binary>` starting at [p] (just past `dup `).
  /// Returns (index, decrypted-less binary, position after the binary).
  static (int, Uint8List, int)? _readBinaryEntry(Uint8List data, int p) {
    while (p < data.length && _isWhitespace(data[p])) {
      p++;
    }
    var s = p;
    while (p < data.length && data[p] >= 0x30 && data[p] <= 0x39) {
      p++;
    }
    if (p == s) return null;
    final index = int.parse(String.fromCharCodes(data, s, p));
    while (p < data.length && _isWhitespace(data[p])) {
      p++;
    }
    s = p;
    while (p < data.length && data[p] >= 0x30 && data[p] <= 0x39) {
      p++;
    }
    if (p == s) return null;
    final len = int.parse(String.fromCharCodes(data, s, p));
    while (p < data.length && _isWhitespace(data[p])) {
      p++;
    }
    while (p < data.length && !_isWhitespace(data[p])) {
      p++; // RD / -|
    }
    p++; // single space
    if (p + len > data.length) return null;
    return (index, Uint8List.sublistView(data, p, p + len), p + len);
  }

  // ---------- byte helpers ----------

  static final List<int> _eexecKeyword = 'eexec'.codeUnits;

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C || c == 0x00;

  static bool _isDelimiter(int c) =>
      _isWhitespace(c) ||
      c == 0x2F ||
      c == 0x28 ||
      c == 0x29 ||
      c == 0x5B ||
      c == 0x5D ||
      c == 0x7B ||
      c == 0x7D;

  static bool _isHexDigit(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x46) ||
      (c >= 0x61 && c <= 0x66);

  static int _hexValue(int c) => c <= 0x39
      ? c - 0x30
      : c <= 0x46
          ? c - 0x41 + 10
          : c - 0x61 + 10;

  static int _min(int a, int b) => a < b ? a : b;

  static Uint8List _head(Uint8List data, int n) =>
      Uint8List.sublistView(data, 0, _min(n, data.length));

  static int _indexOf(Uint8List haystack, List<int> needle, int from) {
    outer:
    for (var i = from; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static int _indexOfString(Uint8List haystack, String needle, int from) =>
      _indexOf(haystack, needle.codeUnits, from);

  static bool _matchesAt(Uint8List data, int p, String s) {
    if (p + s.length > data.length) return false;
    for (var j = 0; j < s.length; j++) {
      if (data[p + j] != s.codeUnitAt(j)) return false;
    }
    return true;
  }
}

/// Interprets one Type 1 charstring into em-space [PdfPathSegment]s.
class _Type1Runner {
  _Type1Runner({
    required this.subrs,
    required this.charStrings,
    required this.fontMatrix,
  });

  final List<Uint8List?> subrs;
  final Map<String, Uint8List> charStrings;
  final List<double> fontMatrix;

  final segments = <PdfPathSegment>[];
  final _stack = <double>[];
  final _psStack = <double>[];
  final _flexPoints = <List<double>>[];
  bool _inFlex = false;
  double _x = 0, _y = 0;
  double _sbx = 0;
  double width = 0;
  bool _open = false;
  bool _done = false;
  int _depth = 0;

  void run(Uint8List charString) {
    _exec(charString);
    _closeIfOpen();
  }

  void _exec(Uint8List cs) {
    if (_depth++ > 30 || _done) {
      _depth--;
      return;
    }
    var p = 0;
    while (p < cs.length && !_done) {
      final b = cs[p++];
      if (b >= 32) {
        if (b <= 246) {
          _stack.add((b - 139).toDouble());
        } else if (b <= 250) {
          _stack.add(((b - 247) * 256 + cs[p++] + 108).toDouble());
        } else if (b <= 254) {
          _stack.add((-(b - 251) * 256 - cs[p++] - 108).toDouble());
        } else {
          // 255: 32-bit signed integer (not 16.16 fixed — that's Type 2).
          var v = (cs[p] << 24) | (cs[p + 1] << 16) | (cs[p + 2] << 8) | cs[p + 3];
          if (v > 0x7FFFFFFF) v -= 0x100000000;
          p += 4;
          _stack.add(v.toDouble());
        }
        continue;
      }
      switch (b) {
        case 1: // hstem
        case 3: // vstem
          _stack.clear();
        case 4: // vmoveto
          _rmoveTo(0, _arg(0));
          _stack.clear();
        case 5: // rlineto
          _rlineTo(_arg(0), _arg(1));
          _stack.clear();
        case 6: // hlineto
          _rlineTo(_arg(0), 0);
          _stack.clear();
        case 7: // vlineto
          _rlineTo(0, _arg(0));
          _stack.clear();
        case 8: // rrcurveto
          _rcurveTo(_arg(0), _arg(1), _arg(2), _arg(3), _arg(4), _arg(5));
          _stack.clear();
        case 9: // closepath
          _closeIfOpen();
          _stack.clear();
        case 10: // callsubr
          final idx = _stack.isEmpty ? 0 : _stack.removeLast().toInt();
          if (idx >= 0 && idx < subrs.length) {
            final s = subrs[idx];
            if (s != null) _exec(s);
          }
        case 11: // return
          _depth--;
          return;
        case 13: // hsbw
          _sbx = _arg(0);
          width = _arg(1);
          _x = _sbx;
          _y = 0;
          _stack.clear();
        case 14: // endchar
          _done = true;
        case 21: // rmoveto
          _rmoveTo(_arg(0), _arg(1));
          _stack.clear();
        case 22: // hmoveto
          _rmoveTo(_arg(0), 0);
          _stack.clear();
        case 30: // vhcurveto
          _rcurveTo(0, _arg(0), _arg(1), _arg(2), _arg(3), 0);
          _stack.clear();
        case 31: // hvcurveto
          _rcurveTo(_arg(0), 0, _arg(1), _arg(2), 0, _arg(3));
          _stack.clear();
        case 12: // escape
          final b2 = cs[p++];
          _escape(b2);
      }
    }
    _depth--;
  }

  void _escape(int op) {
    switch (op) {
      case 0: // dotsection
      case 1: // vstem3
      case 2: // hstem3
        _stack.clear();
      case 6: // seac
        _seac(_arg(0), _arg(1), _arg(2), _arg(3).toInt(), _arg(4).toInt());
        _stack.clear();
        _done = true;
      case 7: // sbw
        _sbx = _arg(0);
        width = _arg(2);
        _x = _arg(0);
        _y = _arg(1);
        _stack.clear();
      case 12: // div
        final b = _stack.isEmpty ? 1.0 : _stack.removeLast();
        final a = _stack.isEmpty ? 0.0 : _stack.removeLast();
        _stack.add(b == 0 ? 0 : a / b);
      case 16: // callothersubr
        _callOtherSubr();
      case 17: // pop
        _stack.add(_psStack.isEmpty ? 0 : _psStack.removeLast());
      case 33: // setcurrentpoint
        _x = _arg(0);
        _y = _arg(1);
        _stack.clear();
      default:
        _stack.clear();
    }
  }

  void _callOtherSubr() {
    final othersubr = _stack.isEmpty ? 0 : _stack.removeLast().toInt();
    final n = _stack.isEmpty ? 0 : _stack.removeLast().toInt();
    final args = <double>[];
    for (var i = 0; i < n && _stack.isNotEmpty; i++) {
      args.insert(0, _stack.removeLast());
    }
    switch (othersubr) {
      case 1: // flex begin
        _inFlex = true;
        _flexPoints.clear();
      case 2: // flex add point (the rmoveto already recorded it)
        break;
      case 0: // flex end: args = [flexHeight, endX, endY]
        _inFlex = false;
        if (_flexPoints.length >= 7) {
          final f = _flexPoints;
          _absCurve(f[1][0], f[1][1], f[2][0], f[2][1], f[3][0], f[3][1]);
          _absCurve(f[4][0], f[4][1], f[5][0], f[5][1], f[6][0], f[6][1]);
        }
        // leave end x,y for the following `pop pop setcurrentpoint`
        if (args.length >= 3) {
          _psStack.add(args[2]);
          _psStack.add(args[1]);
        }
      case 3: // hint replacement: push the subr# back for `pop callsubr`
        _psStack.add(args.isNotEmpty ? args[0] : 3);
      default:
        for (final a in args.reversed) {
          _psStack.add(a);
        }
    }
  }

  void _seac(double asb, double adx, double ady, int bchar, int achar) {
    final baseName = Type1Font._standardName(bchar);
    final accentName = Type1Font._standardName(achar);
    _closeIfOpen();
    if (baseName != null) {
      final base = _lookupOutline(baseName);
      if (base != null) _appendPath(base, 0, 0);
    }
    if (accentName != null) {
      final accent = _lookupOutline(accentName);
      if (accent != null) {
        final dx = _sbx + adx - asb;
        // em-space delta through the linear part of the FontMatrix
        final edx = dx * fontMatrix[0] + ady * fontMatrix[2];
        final edy = dx * fontMatrix[1] + ady * fontMatrix[3];
        _appendPath(accent, edx, edy);
      }
    }
  }

  PdfPath? _lookupOutline(String name) {
    final cs = charStrings[name];
    if (cs == null) return null;
    final runner = _Type1Runner(
      subrs: subrs,
      charStrings: charStrings,
      fontMatrix: fontMatrix,
    );
    runner.run(cs);
    return runner.segments.isEmpty ? null : PdfPath(runner.segments);
  }

  void _appendPath(PdfPath path, double dx, double dy) {
    for (final s in path.segments) {
      segments.add(switch (s) {
        PdfMoveTo(:final x, :final y) => PdfMoveTo(x + dx, y + dy),
        PdfLineTo(:final x, :final y) => PdfLineTo(x + dx, y + dy),
        PdfCubicTo(
          :final x1,
          :final y1,
          :final x2,
          :final y2,
          :final x3,
          :final y3
        ) =>
          PdfCubicTo(x1 + dx, y1 + dy, x2 + dx, y2 + dy, x3 + dx, y3 + dy),
        PdfClosePath() => s,
      });
    }
  }

  void _rmoveTo(double dx, double dy) {
    _x += dx;
    _y += dy;
    if (_inFlex) {
      _flexPoints.add([_x, _y]);
      return;
    }
    _closeIfOpen();
    segments.add(PdfMoveTo(_tx(_x, _y), _ty(_x, _y)));
    _open = true;
  }

  void _rlineTo(double dx, double dy) {
    _x += dx;
    _y += dy;
    segments.add(PdfLineTo(_tx(_x, _y), _ty(_x, _y)));
  }

  void _rcurveTo(double dx1, double dy1, double dx2, double dy2, double dx3,
      double dy3) {
    final c1x = _x + dx1, c1y = _y + dy1;
    final c2x = c1x + dx2, c2y = c1y + dy2;
    _absCurve(c1x, c1y, c2x, c2y, c2x + dx3, c2y + dy3);
  }

  void _absCurve(
      double c1x, double c1y, double c2x, double c2y, double x, double y) {
    segments.add(PdfCubicTo(_tx(c1x, c1y), _ty(c1x, c1y), _tx(c2x, c2y),
        _ty(c2x, c2y), _tx(x, y), _ty(x, y)));
    _x = x;
    _y = y;
  }

  void _closeIfOpen() {
    if (_open) {
      segments.add(const PdfClosePath());
      _open = false;
    }
  }

  double _arg(int i) => i < _stack.length ? _stack[i] : 0;

  double _tx(double x, double y) =>
      x * fontMatrix[0] + y * fontMatrix[2] + fontMatrix[4];

  double _ty(double x, double y) =>
      x * fontMatrix[1] + y * fontMatrix[3] + fontMatrix[5];
}
