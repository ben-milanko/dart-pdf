import 'dart:typed_data';

import '../path.dart';
import 'encodings.dart';

/// A parsed CFF (Compact Font Format) font: FontFile3 /Type1C and
/// /CIDFontType0C streams, and the 'CFF ' table of OpenType ('OTTO') fonts.
///
/// Outlines come from a Type 2 charstring interpreter (§The Type 2
/// Charstring Format); hints are parsed and discarded. Returns null rather
/// than throwing on malformed input — callers fall back to substitution.
class CffFont {
  CffFont._({
    required Uint8List bytes,
    required List<(int, int)> charStrings,
    required List<(int, int)> globalSubrs,
    required List<_PrivateDict> privates,
    required Uint8List? fdSelect,
    required Map<int, int>? cidToGid,
    required Map<int, int> codeToGid,
    required List<double> fontMatrix,
    required List<List<double>?> fdMatrices,
    required bool topMatrixExplicit,
    required Map<int, int> gidToSid,
    required List<(int, int)> strings,
  })  : _bytes = bytes,
        _charStrings = charStrings,
        _globalSubrs = globalSubrs,
        _privates = privates,
        _fdSelect = fdSelect,
        _cidToGid = cidToGid,
        _codeToGid = codeToGid,
        _fontMatrix = fontMatrix,
        _fdMatrices = fdMatrices,
        _topMatrixExplicit = topMatrixExplicit,
        _gidToSid = gidToSid,
        _strings = strings;

  final Uint8List _bytes;
  final List<(int, int)> _charStrings;
  final List<(int, int)> _globalSubrs;
  final List<_PrivateDict> _privates;
  final Uint8List? _fdSelect; // per-glyph font dict index (CID fonts)
  final Map<int, int>? _cidToGid;
  final Map<int, int> _codeToGid;
  final List<double> _fontMatrix;

  /// Per-FD FontMatrices for CID-keyed fonts (null entry = the FD declared
  /// none). Combined with the top matrix per the CFF spec (§ FontMatrix).
  final List<List<double>?> _fdMatrices;

  /// Whether the top dict carried an explicit FontMatrix. When it didn't but
  /// an FD did, the FD matrix stands alone (top is treated as identity, not
  /// the 0.001 default — that default only applies when *no* matrix exists).
  final bool _topMatrixExplicit;
  final Map<int, int> _gidToSid;
  final List<(int, int)> _strings;

  final Map<int, PdfPath?> _outlineCache = {};
  final Map<int, double> _advanceCache = {};
  Map<String, int>? _nameToGid;

  int get numGlyphs => _charStrings.length;

  /// True for CID-keyed CFF fonts (/CIDFontType0C).
  bool get isCidKeyed => _cidToGid != null;

  static CffFont? parse(Uint8List bytes) {
    try {
      return _parse(_unwrapOpenType(bytes) ?? bytes);
    } on Object {
      return null;
    }
  }

  /// Extracts the 'CFF ' table when [bytes] is an OpenType (OTTO) font.
  static Uint8List? _unwrapOpenType(Uint8List bytes) {
    if (bytes.length < 12) return null;
    final scaler =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    if (scaler != 0x4F54544F) return null;
    final numTables = (bytes[4] << 8) | bytes[5];
    for (var i = 0; i < numTables; i++) {
      final p = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(p, p + 4));
      if (tag == 'CFF ') {
        final offset = (bytes[p + 8] << 24) |
            (bytes[p + 9] << 16) |
            (bytes[p + 10] << 8) |
            bytes[p + 11];
        final length = (bytes[p + 12] << 24) |
            (bytes[p + 13] << 16) |
            (bytes[p + 14] << 8) |
            bytes[p + 15];
        return Uint8List.sublistView(bytes, offset, offset + length);
      }
    }
    return null;
  }

  static CffFont? _parse(Uint8List bytes) {
    final r = _Reader(bytes);
    r.seek(2);
    final hdrSize = r.u8();
    r.seek(hdrSize);

    _readIndex(r); // Name INDEX
    final topDicts = _readIndex(r);
    final strings = _readIndex(r);
    final globalSubrs = _readIndex(r);
    if (topDicts.isEmpty) return null;

    final top = _parseDict(bytes, topDicts[0]);
    final charStringsOffset = _firstInt(top[17]);
    if (charStringsOffset == null) return null;
    final charStrings = _readIndex(_Reader(bytes)..seek(charStringsOffset));
    if (charStrings.isEmpty) return null;

    final topMatrixExplicit = top.containsKey(0x0C07);
    final fontMatrix = [
      for (final v in top[0x0C07] ?? const <num>[0.001, 0, 0, 0.001, 0, 0])
        v.toDouble(),
    ];

    // private dict(s): one for plain fonts, one per FD for CID-keyed fonts.
    // Each FD may also carry its own FontMatrix (§ CFF FontMatrix), which the
    // glyph runner combines with the top matrix.
    final privates = <_PrivateDict>[];
    final fdMatrices = <List<double>?>[];
    Uint8List? fdSelect;
    final isCid = top.containsKey(0x0C1E); // ROS
    if (isCid) {
      final fdArrayOffset = _firstInt(top[0x0C24]);
      if (fdArrayOffset != null) {
        for (final range in _readIndex(_Reader(bytes)..seek(fdArrayOffset))) {
          final fdDict = _parseDict(bytes, range);
          privates.add(_PrivateDict.parse(bytes, fdDict[18]));
          final m = fdDict[0x0C07];
          fdMatrices.add(m == null || m.length < 6
              ? null
              : [for (final v in m) v.toDouble()]);
        }
      }
      final fdSelectOffset = _firstInt(top[0x0C25]);
      if (fdSelectOffset != null) {
        fdSelect = _parseFdSelect(bytes, fdSelectOffset, charStrings.length);
      }
    }
    if (privates.isEmpty) {
      privates.add(_PrivateDict.parse(bytes, top[18]));
    }

    // charset: gid → SID (simple fonts) or gid → CID (CID-keyed)
    final gidToSid =
        _parseCharset(bytes, _firstInt(top[15]), charStrings.length);
    Map<int, int>? cidToGid;
    if (isCid) {
      cidToGid = {};
      gidToSid.forEach((gid, cid) => cidToGid![cid] = gid);
    }

    // encoding: code → gid for simple fonts
    final codeToGid = <int, int>{};
    if (!isCid) {
      final sidToGid = <int, int>{};
      gidToSid.forEach((gid, sid) => sidToGid[sid] = gid);
      final encodingOffset = _firstInt(top[16]) ?? 0;
      if (encodingOffset > 1) {
        _parseEncoding(bytes, encodingOffset, codeToGid, sidToGid);
      } else {
        // standard encoding: codes 32..126 carry SIDs 1..95 in order
        for (var code = 32; code <= 126; code++) {
          final gid = sidToGid[code - 31];
          if (gid != null) codeToGid[code] = gid;
        }
      }
    }

    return CffFont._(
      bytes: bytes,
      charStrings: charStrings,
      globalSubrs: globalSubrs,
      privates: privates,
      fdSelect: fdSelect,
      cidToGid: cidToGid,
      codeToGid: codeToGid,
      fontMatrix: fontMatrix,
      fdMatrices: fdMatrices,
      topMatrixExplicit: topMatrixExplicit,
      gidToSid: gidToSid,
      strings: strings,
    );
  }

  /// Effective glyph-space → text-space matrix for [fd], combining the top
  /// dict and FD FontMatrices per the CFF spec.
  List<double> _effectiveMatrix(int fd) {
    final fdM = fd >= 0 && fd < _fdMatrices.length ? _fdMatrices[fd] : null;
    if (fdM == null) return _fontMatrix;
    if (!_topMatrixExplicit) return fdM; // FD matrix stands alone
    return _multiplyMatrix(_fontMatrix, fdM); // top ∘ FD
  }

  /// 3×2 affine product `a ∘ b` (apply b first, then a).
  static List<double> _multiplyMatrix(List<double> a, List<double> b) => [
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5],
      ];

  int gidForCid(int cid) => _cidToGid == null ? cid : (_cidToGid[cid] ?? 0);

  int gidForCode(int code) => _codeToGid[code] ?? 0;

  /// Glyph lookup by name through the charset — what PDF /Differences and
  /// base encodings need.
  int gidForName(String name) {
    final map = _nameToGid ??= _buildNameToGid();
    return map[name] ?? 0;
  }

  Map<String, int> _buildNameToGid() {
    final result = <String, int>{};
    _gidToSid.forEach((gid, sid) {
      final String? name;
      if (sid < cffStandardStrings.length) {
        name = cffStandardStrings[sid];
      } else if (sid - 391 >= 0 && sid - 391 < _strings.length) {
        final range = _strings[sid - 391];
        name = String.fromCharCodes(
            Uint8List.sublistView(_bytes, range.$1, range.$2));
      } else {
        name = null;
      }
      if (name != null) result.putIfAbsent(name, () => gid);
    });
    return result;
  }

  PdfPath? outlineForGlyph(int gid) {
    return _outlineCache.putIfAbsent(gid, () {
      try {
        final builder = _run(gid);
        if (builder == null) return null;
        _advanceCache[gid] =
            builder.width * _effectiveMatrix(_fdFor(gid))[0].abs();
        return builder.segments.isEmpty ? null : PdfPath(builder.segments);
      } on Object {
        return null;
      }
    });
  }

  int _fdFor(int gid) {
    final select = _fdSelect;
    if (select != null && gid >= 0 && gid < select.length) return select[gid];
    return 0;
  }

  /// Advance width in em units, known after the charstring runs.
  double? advanceForGlyph(int gid) {
    outlineForGlyph(gid);
    return _advanceCache[gid];
  }

  _CharstringRunner? _run(int gid) {
    if (gid < 0 || gid >= _charStrings.length) return null;
    final fd = _fdFor(gid);
    final private = _privates[fd < _privates.length ? fd : 0];
    final matrix = _effectiveMatrix(fd);
    late final _CharstringRunner runner;
    runner = _CharstringRunner(
      bytes: _bytes,
      globalSubrs: _globalSubrs,
      localSubrs: private.subrs,
      defaultWidthX: private.defaultWidthX,
      nominalWidthX: private.nominalWidthX,
      scaleX: matrix[0],
      skewX: matrix.length > 2 ? matrix[2] : 0,
      skewY: matrix.length > 1 ? matrix[1] : 0,
      scaleY: matrix.length > 3 ? matrix[3] : 0.001,
      seac: (adx, ady, bchar, achar) {
        final base = _outlineForStandardCode(bchar);
        final accent = _outlineForStandardCode(achar);
        if (base != null) runner.appendPath(base);
        if (accent != null) runner.appendPath(accent, dx: adx, dy: ady);
      },
    );
    runner.execute(_charStrings[gid]);
    return runner;
  }

  PdfPath? _outlineForStandardCode(int code) {
    final name = _standardEncodingName(code);
    return name == null ? null : outlineForGlyph(gidForName(name));
  }

  static String? _standardEncodingName(int code) => code >= 32 && code <= 126
      ? winAnsiGlyphName(code)
      : standardGlyphName(code);

  // ---------- low-level structures ----------

  /// Reads an INDEX, returning (start, end) data ranges.
  static List<(int, int)> _readIndex(_Reader r) {
    final count = r.u16();
    if (count == 0) return const [];
    final offSize = r.u8();
    int readOffset() {
      var v = 0;
      for (var i = 0; i < offSize; i++) {
        v = (v << 8) | r.u8();
      }
      return v;
    }

    final offsets = [for (var i = 0; i <= count; i++) readOffset()];
    final base = r.position - 1;
    final ranges = [
      for (var i = 0; i < count; i++)
        (base + offsets[i], base + offsets[i + 1]),
    ];
    r.seek(base + offsets[count]);
    return ranges;
  }

  static Map<int, List<num>> _parseDict(Uint8List bytes, (int, int) range) {
    final result = <int, List<num>>{};
    final operands = <num>[];
    var p = range.$1;
    while (p < range.$2) {
      final b = bytes[p];
      if (b <= 21) {
        var op = b;
        p++;
        if (b == 12) {
          op = 0x0C00 | bytes[p];
          p++;
        }
        result[op] = List.of(operands);
        operands.clear();
      } else if (b == 28) {
        final v = (bytes[p + 1] << 8) | bytes[p + 2];
        operands.add(v > 0x7FFF ? v - 0x10000 : v);
        p += 3;
      } else if (b == 29) {
        var v = (bytes[p + 1] << 24) |
            (bytes[p + 2] << 16) |
            (bytes[p + 3] << 8) |
            bytes[p + 4];
        if (v > 0x7FFFFFFF) v -= 0x100000000;
        operands.add(v);
        p += 5;
      } else if (b == 30) {
        // packed BCD real
        final sb = StringBuffer();
        p++;
        var done = false;
        while (!done && p < range.$2) {
          final byte = bytes[p++];
          for (final nibble in [byte >> 4, byte & 0xF]) {
            switch (nibble) {
              case 0xF:
                done = true;
              case 0xA:
                sb.write('.');
              case 0xB:
                sb.write('E');
              case 0xC:
                sb.write('E-');
              case 0xE:
                sb.write('-');
              case 0xD:
                break;
              default:
                sb.write(nibble);
            }
            if (done) break;
          }
        }
        operands.add(double.tryParse(sb.toString()) ?? 0);
      } else if (b >= 32 && b <= 246) {
        operands.add(b - 139);
        p++;
      } else if (b >= 247 && b <= 250) {
        operands.add((b - 247) * 256 + bytes[p + 1] + 108);
        p += 2;
      } else if (b >= 251 && b <= 254) {
        operands.add(-(b - 251) * 256 - bytes[p + 1] - 108);
        p += 2;
      } else {
        p++;
      }
    }
    return result;
  }

  static int? _firstInt(List<num>? operands) =>
      operands == null || operands.isEmpty ? null : operands.first.toInt();

  static Map<int, int> _parseCharset(
      Uint8List bytes, int? offset, int glyphCount) {
    final result = <int, int>{0: 0};
    if (offset == null || offset == 0) {
      // ISOAdobe default: SIDs follow gids directly
      for (var gid = 0; gid < glyphCount; gid++) {
        result[gid] = gid;
      }
      return result;
    }
    final r = _Reader(bytes)..seek(offset);
    final format = r.u8();
    var gid = 1;
    switch (format) {
      case 0:
        while (gid < glyphCount) {
          result[gid++] = r.u16();
        }
      case 1 || 2:
        while (gid < glyphCount) {
          final first = r.u16();
          final left = format == 1 ? r.u8() : r.u16();
          for (var i = 0; i <= left && gid < glyphCount; i++) {
            result[gid++] = first + i;
          }
        }
    }
    return result;
  }

  static void _parseEncoding(Uint8List bytes, int offset,
      Map<int, int> codeToGid, Map<int, int> sidToGid) {
    final r = _Reader(bytes)..seek(offset);
    final raw = r.u8();
    final format = raw & 0x7F;
    if (format == 0) {
      final count = r.u8();
      for (var gid = 1; gid <= count; gid++) {
        codeToGid[r.u8()] = gid;
      }
    } else if (format == 1) {
      final ranges = r.u8();
      var gid = 1;
      for (var i = 0; i < ranges; i++) {
        final first = r.u8();
        final left = r.u8();
        for (var k = 0; k <= left; k++) {
          codeToGid[first + k] = gid++;
        }
      }
    }
    // Supplements (high bit of the format byte): extra code → SID mappings,
    // commonly used for ligatures/accented glyphs that fall outside the base
    // encoding (e.g. an ff ligature at code 0xAE). Resolve the SID to a gid
    // through the charset (CFF spec / Adobe TN #5176 §12).
    if (raw & 0x80 != 0) {
      final nSups = r.u8();
      for (var i = 0; i < nSups; i++) {
        final code = r.u8();
        final sid = r.u16();
        final gid = sidToGid[sid];
        if (gid != null) codeToGid[code] = gid;
      }
    }
  }

  static Uint8List _parseFdSelect(Uint8List bytes, int offset, int glyphCount) {
    final r = _Reader(bytes)..seek(offset);
    final result = Uint8List(glyphCount);
    final format = r.u8();
    if (format == 0) {
      for (var gid = 0; gid < glyphCount; gid++) {
        result[gid] = r.u8();
      }
    } else if (format == 3) {
      final ranges = r.u16();
      var first = r.u16();
      for (var i = 0; i < ranges; i++) {
        final fd = r.u8();
        final next = r.u16();
        for (var gid = first; gid < next && gid < glyphCount; gid++) {
          result[gid] = fd;
        }
        first = next;
      }
    }
    return result;
  }
}

class _PrivateDict {
  const _PrivateDict(this.subrs, this.defaultWidthX, this.nominalWidthX);

  final List<(int, int)> subrs;
  final double defaultWidthX;
  final double nominalWidthX;

  static _PrivateDict parse(Uint8List bytes, List<num>? sizeAndOffset) {
    if (sizeAndOffset == null || sizeAndOffset.length < 2) {
      return const _PrivateDict([], 0, 0);
    }
    final size = sizeAndOffset[0].toInt();
    final offset = sizeAndOffset[1].toInt();
    final dict = CffFont._parseDict(bytes, (offset, offset + size));
    var subrs = const <(int, int)>[];
    final subrsOffset = CffFont._firstInt(dict[19]);
    if (subrsOffset != null) {
      subrs = CffFont._readIndex(_Reader(bytes)..seek(offset + subrsOffset));
    }
    return _PrivateDict(
      subrs,
      (dict[20]?.firstOrNull ?? 0).toDouble(),
      (dict[21]?.firstOrNull ?? 0).toDouble(),
    );
  }
}

/// Executes one Type 2 charstring into path segments (em units).
class _CharstringRunner {
  _CharstringRunner({
    required this.bytes,
    required this.globalSubrs,
    required this.localSubrs,
    required this.defaultWidthX,
    required this.nominalWidthX,
    required this.scaleX,
    required this.skewX,
    required this.skewY,
    required this.scaleY,
    required this.seac,
  }) : width = defaultWidthX;

  final Uint8List bytes;
  final List<(int, int)> globalSubrs;
  final List<(int, int)> localSubrs;
  final double defaultWidthX;
  final double nominalWidthX;
  final double scaleX, skewX, skewY, scaleY;
  final void Function(double adx, double ady, int bchar, int achar) seac;

  final segments = <PdfPathSegment>[];
  final _stack = <double>[];
  double _x = 0, _y = 0;
  int _stemCount = 0;
  bool _widthParsed = false;
  bool _open = false;
  double width;
  int _depth = 0;

  static int _bias(int count) =>
      count < 1240 ? 107 : (count < 33900 ? 1131 : 32768);

  void execute((int, int) range) {
    if (_depth++ > 10) return;
    var p = range.$1;
    while (p < range.$2) {
      final b = bytes[p];
      if (b >= 32 || b == 28) {
        if (b == 28) {
          final v = (bytes[p + 1] << 8) | bytes[p + 2];
          _stack.add((v > 0x7FFF ? v - 0x10000 : v).toDouble());
          p += 3;
        } else if (b <= 246) {
          _stack.add((b - 139).toDouble());
          p++;
        } else if (b <= 250) {
          _stack.add(((b - 247) * 256 + bytes[p + 1] + 108).toDouble());
          p += 2;
        } else if (b <= 254) {
          _stack.add((-(b - 251) * 256 - bytes[p + 1] - 108).toDouble());
          p += 2;
        } else {
          // 16.16 fixed
          var v = (bytes[p + 1] << 24) |
              (bytes[p + 2] << 16) |
              (bytes[p + 3] << 8) |
              bytes[p + 4];
          if (v > 0x7FFFFFFF) v -= 0x100000000;
          _stack.add(v / 65536);
          p += 5;
        }
        continue;
      }
      p++;
      switch (b) {
        case 1 || 3 || 18 || 23: // h/vstem(hm)
          _takeWidth(even: true);
          _stemCount += _stack.length ~/ 2;
          _stack.clear();
        case 19 || 20: // hintmask, cntrmask
          _takeWidth(even: true);
          _stemCount += _stack.length ~/ 2;
          _stack.clear();
          p += (_stemCount + 7) ~/ 8;
        case 21: // rmoveto
          _takeWidth(expected: 2);
          _moveTo(_x + _arg(0), _y + _arg(1));
          _stack.clear();
        case 22: // hmoveto
          _takeWidth(expected: 1);
          _moveTo(_x + _arg(0), _y);
          _stack.clear();
        case 4: // vmoveto
          _takeWidth(expected: 1);
          _moveTo(_x, _y + _arg(0));
          _stack.clear();
        case 5: // rlineto
          for (var i = 0; i + 1 < _stack.length; i += 2) {
            _lineTo(_x + _stack[i], _y + _stack[i + 1]);
          }
          _stack.clear();
        case 6 || 7: // hlineto / vlineto (alternating)
          var horizontal = b == 6;
          for (var i = 0; i < _stack.length; i++) {
            if (horizontal) {
              _lineTo(_x + _stack[i], _y);
            } else {
              _lineTo(_x, _y + _stack[i]);
            }
            horizontal = !horizontal;
          }
          _stack.clear();
        case 8: // rrcurveto
          for (var i = 0; i + 5 < _stack.length; i += 6) {
            _relCurve(_stack[i], _stack[i + 1], _stack[i + 2], _stack[i + 3],
                _stack[i + 4], _stack[i + 5]);
          }
          _stack.clear();
        case 24: // rcurveline
          var i = 0;
          for (; i + 5 < _stack.length - 2; i += 6) {
            _relCurve(_stack[i], _stack[i + 1], _stack[i + 2], _stack[i + 3],
                _stack[i + 4], _stack[i + 5]);
          }
          if (i + 1 < _stack.length) {
            _lineTo(_x + _stack[i], _y + _stack[i + 1]);
          }
          _stack.clear();
        case 25: // rlinecurve
          var i = 0;
          for (; i + 1 < _stack.length - 6; i += 2) {
            _lineTo(_x + _stack[i], _y + _stack[i + 1]);
          }
          if (i + 5 < _stack.length) {
            _relCurve(_stack[i], _stack[i + 1], _stack[i + 2], _stack[i + 3],
                _stack[i + 4], _stack[i + 5]);
          }
          _stack.clear();
        case 26: // vvcurveto
          var i = 0;
          var dx1 = 0.0;
          if (_stack.length.isOdd) {
            dx1 = _stack[0];
            i = 1;
          }
          for (; i + 3 < _stack.length; i += 4) {
            _relCurve(
                dx1, _stack[i], _stack[i + 1], _stack[i + 2], 0, _stack[i + 3]);
            dx1 = 0;
          }
          _stack.clear();
        case 27: // hhcurveto
          var i = 0;
          var dy1 = 0.0;
          if (_stack.length.isOdd) {
            dy1 = _stack[0];
            i = 1;
          }
          for (; i + 3 < _stack.length; i += 4) {
            _relCurve(
                _stack[i], dy1, _stack[i + 1], _stack[i + 2], _stack[i + 3], 0);
            dy1 = 0;
          }
          _stack.clear();
        case 30 || 31: // vhcurveto / hvcurveto (alternating)
          var horizontal = b == 31;
          var i = 0;
          while (i + 3 < _stack.length) {
            final last = i + 8 > _stack.length;
            final extra = last && i + 4 < _stack.length ? _stack[i + 4] : 0.0;
            if (horizontal) {
              _relCurve(_stack[i], 0, _stack[i + 1], _stack[i + 2],
                  last ? extra : 0, _stack[i + 3]);
            } else {
              _relCurve(0, _stack[i], _stack[i + 1], _stack[i + 2],
                  _stack[i + 3], last ? extra : 0);
            }
            horizontal = !horizontal;
            i += 4;
          }
          _stack.clear();
        case 10: // callsubr
          if (_stack.isNotEmpty && localSubrs.isNotEmpty) {
            final index =
                _stack.removeLast().toInt() + _bias(localSubrs.length);
            if (index >= 0 && index < localSubrs.length) {
              execute(localSubrs[index]);
              _depth--;
            }
          }
        case 29: // callgsubr
          if (_stack.isNotEmpty && globalSubrs.isNotEmpty) {
            final index =
                _stack.removeLast().toInt() + _bias(globalSubrs.length);
            if (index >= 0 && index < globalSubrs.length) {
              execute(globalSubrs[index]);
              _depth--;
            }
          }
        case 11: // return
          return;
        case 14: // endchar
          _takeWidth(even: true);
          if (_stack.length == 4) {
            seac(_stack[0], _stack[1], _stack[2].round(), _stack[3].round());
            _stack.clear();
          }
          _closeIfOpen();
          return;
        case 12:
          final escape = bytes[p];
          p++;
          _escape(escape);
        default:
          _stack.clear();
      }
    }
  }

  void _escape(int op) {
    switch (op) {
      case 35: // flex
        if (_stack.length >= 13) {
          _relCurve(
              _stack[0], _stack[1], _stack[2], _stack[3], _stack[4], _stack[5]);
          _relCurve(_stack[6], _stack[7], _stack[8], _stack[9], _stack[10],
              _stack[11]);
        }
        _stack.clear();
      case 34: // hflex
        if (_stack.length >= 7) {
          final dy2 = _stack[2];
          _relCurve(_stack[0], 0, _stack[1], dy2, _stack[3], 0);
          _relCurve(_stack[4], 0, _stack[5], -dy2, _stack[6], 0);
        }
        _stack.clear();
      case 36: // hflex1
        if (_stack.length >= 9) {
          final dy1 = _stack[1], dy2 = _stack[3], dy5 = _stack[7];
          _relCurve(_stack[0], dy1, _stack[2], dy2, _stack[4], 0);
          _relCurve(
              _stack[5], 0, _stack[6], dy5, _stack[8], -(dy1 + dy2 + dy5));
        }
        _stack.clear();
      case 37: // flex1
        if (_stack.length >= 11) {
          final startX = _x, startY = _y;
          var dx = 0.0, dy = 0.0;
          for (var i = 0; i < 10; i += 2) {
            dx += _stack[i];
            dy += _stack[i + 1];
          }
          _relCurve(
              _stack[0], _stack[1], _stack[2], _stack[3], _stack[4], _stack[5]);
          final c1x = _x + _stack[6], c1y = _y + _stack[7];
          final c2x = c1x + _stack[8], c2y = c1y + _stack[9];
          final double endX, endY;
          if (dx.abs() > dy.abs()) {
            endX = c2x + _stack[10];
            endY = startY;
          } else {
            endX = startX;
            endY = c2y + _stack[10];
          }
          _absCurve(c1x, c1y, c2x, c2y, endX, endY);
        }
        _stack.clear();
      default:
        _stack.clear();
    }
  }

  double _arg(int i) => i < _stack.length ? _stack[i] : 0;

  /// The first stack-clearing operator may carry the glyph width as one
  /// extra leading operand.
  void _takeWidth({int? expected, bool even = false}) {
    if (_widthParsed) return;
    _widthParsed = true;
    final extra =
        expected != null ? _stack.length > expected : _stack.length.isOdd;
    if (extra && _stack.isNotEmpty) {
      width = nominalWidthX + _stack.removeAt(0);
    }
  }

  void _moveTo(double x, double y) {
    _closeIfOpen();
    _x = x;
    _y = y;
    segments.add(PdfMoveTo(_tx(x, y), _ty(x, y)));
    _open = true;
  }

  void _lineTo(double x, double y) {
    _x = x;
    _y = y;
    segments.add(PdfLineTo(_tx(x, y), _ty(x, y)));
  }

  void _relCurve(
      double dx1, double dy1, double dx2, double dy2, double dx3, double dy3) {
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

  void appendPath(PdfPath path, {double dx = 0, double dy = 0}) {
    final tx = _tx(dx, dy);
    final ty = _ty(dx, dy);
    for (final segment in path.segments) {
      segments.add(_translate(segment, tx, ty));
    }
  }

  PdfPathSegment _translate(PdfPathSegment segment, double dx, double dy) {
    return switch (segment) {
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
      PdfClosePath() => segment,
    };
  }

  double _tx(double x, double y) => x * scaleX + y * skewX;

  double _ty(double x, double y) => x * skewY + y * scaleY;
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int position = 0;

  void seek(int p) => position = p;

  int u8() => bytes[position++];

  int u16() {
    final v = (bytes[position] << 8) | bytes[position + 1];
    position += 2;
    return v;
  }
}

extension on List<num> {
  num? get firstOrNull => isEmpty ? null : first;
}
