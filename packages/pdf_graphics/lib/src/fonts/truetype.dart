import 'dart:math' as math;
import 'dart:typed_data';

import '../path.dart';

/// A parsed TrueType/OpenType font (sfnt container with a `glyf` table),
/// providing glyph outlines in em units (1.0 = the font size, y-up).
///
/// CFF-flavored OpenType ('OTTO') parses to null here; the CFF charstring
/// engine is separate. Returns null rather than throwing on anything
/// malformed — callers fall back to font substitution.
class TrueTypeFont {
  TrueTypeFont._({
    required Uint8List bytes,
    required Map<String, (int, int)> tables,
    required this.unitsPerEm,
    required this.numGlyphs,
    required bool longLoca,
    required int numberOfHMetrics,
  })  : _bytes = bytes,
        _tables = tables,
        _longLoca = longLoca,
        _numberOfHMetrics = numberOfHMetrics;

  final Uint8List _bytes;
  final Map<String, (int offset, int length)> _tables;
  final int unitsPerEm;
  final int numGlyphs;
  final bool _longLoca;
  final int _numberOfHMetrics;

  final Map<int, PdfPath?> _outlineCache = {};
  List<_CmapSubtable>? _cmaps;
  Map<String, int>? _postNames;

  static TrueTypeFont? parse(Uint8List bytes) {
    try {
      return _parse(bytes);
    } on Object {
      return null;
    }
  }

  static TrueTypeFont? _parse(Uint8List bytes) {
    final r = _Reader(bytes);
    var scaler = r.u32();
    if (scaler == 0x74746366 /* 'ttcf' collection */) {
      r.u32(); // version
      final count = r.u32();
      if (count == 0) return null;
      final first = r.u32();
      r.seek(first);
      scaler = r.u32();
    }
    if (scaler == 0x4F54544F /* 'OTTO' */) return null; // CFF outlines
    if (scaler != 0x00010000 && scaler != 0x74727565 /* 'true' */) {
      return null;
    }
    final numTables = r.u16();
    r.skip(6);
    final tables = <String, (int, int)>{};
    for (var i = 0; i < numTables; i++) {
      final tag = String.fromCharCodes(
          [r.u8(), r.u8(), r.u8(), r.u8()]);
      r.u32(); // checksum
      final offset = r.u32();
      final length = r.u32();
      tables[tag] = (offset, length);
    }
    final head = tables['head'];
    final maxp = tables['maxp'];
    if (head == null || maxp == null || !tables.containsKey('glyf')) {
      return null;
    }

    r.seek(head.$1 + 18);
    final unitsPerEm = r.u16();
    r.seek(head.$1 + 50);
    final longLoca = r.s16() == 1;

    r.seek(maxp.$1 + 4);
    final numGlyphs = r.u16();

    var numberOfHMetrics = 0;
    final hhea = tables['hhea'];
    if (hhea != null) {
      r.seek(hhea.$1 + 34);
      numberOfHMetrics = r.u16();
    }

    if (unitsPerEm == 0) return null;
    return TrueTypeFont._(
      bytes: bytes,
      tables: tables,
      unitsPerEm: unitsPerEm,
      numGlyphs: numGlyphs,
      longLoca: longLoca,
      numberOfHMetrics: numberOfHMetrics,
    );
  }

  /// Glyph outline in em units, or null for empty/broken glyphs.
  PdfPath? outlineForGlyph(int glyphId) {
    return _outlineCache.putIfAbsent(glyphId, () {
      try {
        final contours = _glyphContours(glyphId, 0);
        if (contours == null || contours.isEmpty) return null;
        final scale = 1 / unitsPerEm;
        final segments = <PdfPathSegment>[];
        for (final contour in contours) {
          _contourToSegments(contour, scale, segments);
        }
        return segments.isEmpty ? null : PdfPath(segments);
      } on Object {
        return null;
      }
    });
  }

  /// Advance width in em units, or null when the font has no metrics.
  double? advanceForGlyph(int glyphId) {
    final hmtx = _tables['hmtx'];
    if (hmtx == null || _numberOfHMetrics == 0) return null;
    final index = math.min(glyphId, _numberOfHMetrics - 1);
    final r = _Reader(_bytes)..seek(hmtx.$1 + index * 4);
    return r.u16() / unitsPerEm;
  }

  /// Maps a Unicode code point through the font's Unicode cmaps.
  int gidForUnicode(int codePoint) {
    for (final cmap in _cmapSubtables()) {
      final unicode = (cmap.platform == 3 &&
              (cmap.encoding == 1 || cmap.encoding == 10)) ||
          cmap.platform == 0;
      if (!unicode) continue;
      final gid = cmap.lookup(codePoint);
      if (gid != 0) return gid;
    }
    return 0;
  }

  /// Maps a raw byte code through a (3,0) symbol cmap.
  int gidForSymbolCode(int code) {
    for (final cmap in _cmapSubtables()) {
      if (cmap.platform != 3 || cmap.encoding != 0) continue;
      final gid = cmap.lookup(0xF000 | (code & 0xFF));
      if (gid != 0) return gid;
      return cmap.lookup(code);
    }
    return 0;
  }

  /// Maps a raw byte code through a (1,0) Mac Roman cmap.
  int gidForMacCode(int code) {
    for (final cmap in _cmapSubtables()) {
      if (cmap.platform == 1 && cmap.encoding == 0) {
        return cmap.lookup(code);
      }
    }
    return 0;
  }

  bool get hasCmap => _cmapSubtables().isNotEmpty;

  bool get hasSymbolCmap =>
      _cmapSubtables().any((c) => c.platform == 3 && c.encoding == 0);

  /// Maps a PostScript glyph name to a glyph id through the `post` (format
  /// 2.0) table, or 0 when absent. Lets a cmap-less embedded subset font —
  /// whose codes reach glyphs by name through the PDF /Encoding — select the
  /// right glyph instead of indexing by raw code (§9.6.6.4).
  int gidForName(String name) => (_postNames ??= _parsePostNames())[name] ?? 0;

  Map<String, int> _parsePostNames() {
    final post = _tables['post'];
    if (post == null) return const {};
    try {
      final r = _Reader(_bytes)..seek(post.$1);
      // Only format 2.0 carries a per-glyph name table; 1.0/3.0 don't.
      if (r.u32() != 0x00020000) return const {};
      r.seek(post.$1 + 32);
      final count = r.u16();
      if (count == 0 || count > numGlyphs + 1) return const {};
      final indices = [for (var i = 0; i < count; i++) r.u16()];
      // Variable-length Pascal strings for names not in the standard set.
      final extra = <String>[];
      final end = post.$1 + post.$2;
      while (r.position < end) {
        final len = r.u8();
        if (r.position + len > end) break;
        extra.add(String.fromCharCodes(
            [for (var i = 0; i < len; i++) r.u8()]));
      }
      final map = <String, int>{};
      for (var gid = 0; gid < count; gid++) {
        final index = indices[gid];
        final String? name;
        if (index < _macGlyphNames.length) {
          name = _macGlyphNames[index];
        } else {
          final j = index - 258;
          name = j >= 0 && j < extra.length ? extra[j] : null;
        }
        // first (lowest) gid wins for a duplicated name
        if (name != null) map.putIfAbsent(name, () => gid);
      }
      return map;
    } on Object {
      return const {};
    }
  }

  // ---------- glyf ----------

  (int, int)? _glyphRange(int glyphId) {
    final loca = _tables['loca'];
    final glyf = _tables['glyf'];
    if (loca == null || glyf == null) return null;
    if (glyphId < 0 || glyphId >= numGlyphs) return null;
    final r = _Reader(_bytes);
    final int start;
    final int end;
    if (_longLoca) {
      r.seek(loca.$1 + glyphId * 4);
      start = r.u32();
      end = r.u32();
    } else {
      r.seek(loca.$1 + glyphId * 2);
      start = r.u16() * 2;
      end = r.u16() * 2;
    }
    if (end <= start) return null; // empty glyph (e.g. space)
    return (glyf.$1 + start, glyf.$1 + end);
  }

  /// Contours in font units. Composite glyphs recurse with transforms.
  List<List<_Point>>? _glyphContours(int glyphId, int depth) {
    if (depth > 5) return null;
    final range = _glyphRange(glyphId);
    if (range == null) return null;
    final r = _Reader(_bytes)..seek(range.$1);
    final numberOfContours = r.s16();
    r.skip(8); // bbox
    if (numberOfContours >= 0) {
      return _simpleGlyph(r, numberOfContours);
    }
    return _compositeGlyph(r, depth);
  }

  List<List<_Point>> _simpleGlyph(_Reader r, int contourCount) {
    final endPoints = [for (var i = 0; i < contourCount; i++) r.u16()];
    final pointCount = contourCount == 0 ? 0 : endPoints.last + 1;
    r.skip(r.u16()); // instructions

    final flags = <int>[];
    while (flags.length < pointCount) {
      final flag = r.u8();
      flags.add(flag);
      if (flag & 0x08 != 0) {
        final repeat = r.u8();
        for (var i = 0; i < repeat; i++) {
          flags.add(flag);
        }
      }
    }

    final xs = <int>[];
    var x = 0;
    for (final flag in flags) {
      if (flag & 0x02 != 0) {
        final dx = r.u8();
        x += (flag & 0x10 != 0) ? dx : -dx;
      } else if (flag & 0x10 == 0) {
        x += r.s16();
      }
      xs.add(x);
    }
    final ys = <int>[];
    var y = 0;
    for (final flag in flags) {
      if (flag & 0x04 != 0) {
        final dy = r.u8();
        y += (flag & 0x20 != 0) ? dy : -dy;
      } else if (flag & 0x20 == 0) {
        y += r.s16();
      }
      ys.add(y);
    }

    final contours = <List<_Point>>[];
    var start = 0;
    for (final end in endPoints) {
      final contour = <_Point>[];
      for (var i = start; i <= end && i < pointCount; i++) {
        contour.add(_Point(
            xs[i].toDouble(), ys[i].toDouble(), flags[i] & 0x01 != 0));
      }
      if (contour.isNotEmpty) contours.add(contour);
      start = end + 1;
    }
    return contours;
  }

  List<List<_Point>> _compositeGlyph(_Reader r, int depth) {
    final contours = <List<_Point>>[];
    while (true) {
      final flags = r.u16();
      final glyphIndex = r.u16();
      final double dx;
      final double dy;
      if (flags & 0x0001 != 0) {
        // ARG_1_AND_2_ARE_WORDS
        dx = r.s16().toDouble();
        dy = r.s16().toDouble();
      } else {
        dx = r.s8().toDouble();
        dy = r.s8().toDouble();
      }
      var a = 1.0, b = 0.0, c = 0.0, d = 1.0;
      if (flags & 0x0008 != 0) {
        // WE_HAVE_A_SCALE
        a = d = r.f2dot14();
      } else if (flags & 0x0040 != 0) {
        // X_AND_Y_SCALE
        a = r.f2dot14();
        d = r.f2dot14();
      } else if (flags & 0x0080 != 0) {
        // TWO_BY_TWO
        a = r.f2dot14();
        b = r.f2dot14();
        c = r.f2dot14();
        d = r.f2dot14();
      }
      // ARGS_ARE_XY_VALUES (0x0002) is the supported placement mode;
      // point-matching placement is rare and treated as offsets here.
      final component = _glyphContours(glyphIndex, depth + 1);
      if (component != null) {
        for (final contour in component) {
          contours.add([
            for (final p in contour)
              _Point(
                a * p.x + c * p.y + dx,
                b * p.x + d * p.y + dy,
                p.onCurve,
              ),
          ]);
        }
      }
      if (flags & 0x0020 == 0) break; // MORE_COMPONENTS
    }
    return contours;
  }

  /// TrueType contours are quadratic B-splines: consecutive off-curve
  /// points imply an on-curve midpoint. Quadratics convert to cubics.
  void _contourToSegments(
      List<_Point> contour, double scale, List<PdfPathSegment> out) {
    if (contour.isEmpty) return;

    _Point at(int i) => contour[i % contour.length];

    // start from an on-curve point, synthesizing one if necessary
    _Point start;
    var offset = 0;
    if (contour[0].onCurve) {
      start = contour[0];
      offset = 1;
    } else if (contour.last.onCurve) {
      start = contour.last;
    } else {
      start = _Point.midpoint(contour[0], contour.last);
    }
    out.add(PdfMoveTo(start.x * scale, start.y * scale));

    var current = start;
    _Point? pendingControl;
    for (var i = 0; i < contour.length; i++) {
      final point = at(i + offset);
      if (pendingControl == null) {
        if (point.onCurve) {
          if (point == start && i == contour.length - 1) break;
          out.add(PdfLineTo(point.x * scale, point.y * scale));
          current = point;
        } else {
          pendingControl = point;
        }
      } else {
        final end =
            point.onCurve ? point : _Point.midpoint(pendingControl, point);
        _quadratic(out, current, pendingControl, end, scale);
        current = end;
        pendingControl = point.onCurve ? null : point;
      }
    }
    if (pendingControl != null) {
      _quadratic(out, current, pendingControl, start, scale);
    }
    out.add(const PdfClosePath());
  }

  static void _quadratic(List<PdfPathSegment> out, _Point from, _Point control,
      _Point to, double scale) {
    // exact quadratic → cubic elevation
    final c1x = from.x + 2 / 3 * (control.x - from.x);
    final c1y = from.y + 2 / 3 * (control.y - from.y);
    final c2x = to.x + 2 / 3 * (control.x - to.x);
    final c2y = to.y + 2 / 3 * (control.y - to.y);
    out.add(PdfCubicTo(c1x * scale, c1y * scale, c2x * scale, c2y * scale,
        to.x * scale, to.y * scale));
  }

  // ---------- cmap ----------

  List<_CmapSubtable> _cmapSubtables() {
    final cached = _cmaps;
    if (cached != null) return cached;
    final result = <_CmapSubtable>[];
    final cmap = _tables['cmap'];
    if (cmap != null) {
      try {
        final r = _Reader(_bytes)..seek(cmap.$1 + 2);
        final count = r.u16();
        for (var i = 0; i < count; i++) {
          final platform = r.u16();
          final encoding = r.u16();
          final offset = r.u32();
          result.add(
              _CmapSubtable(_bytes, cmap.$1 + offset, platform, encoding));
        }
      } on Object {
        // broken cmap: act as if absent
      }
    }
    return _cmaps = result;
  }
}

class _Point {
  const _Point(this.x, this.y, this.onCurve);

  factory _Point.midpoint(_Point a, _Point b) =>
      _Point((a.x + b.x) / 2, (a.y + b.y) / 2, true);

  final double x;
  final double y;
  final bool onCurve;
}

class _CmapSubtable {
  _CmapSubtable(this._bytes, this._offset, this.platform, this.encoding);

  final Uint8List _bytes;
  final int _offset;
  final int platform;
  final int encoding;

  int lookup(int code) {
    try {
      final r = _Reader(_bytes)..seek(_offset);
      final format = r.u16();
      switch (format) {
        case 0:
          if (code < 0 || code > 255) return 0;
          r.skip(4);
          r.skip(code);
          return r.u8();
        case 4:
          return _format4(r, code);
        case 6:
          r.skip(4);
          final first = r.u16();
          final count = r.u16();
          if (code < first || code >= first + count) return 0;
          r.skip((code - first) * 2);
          return r.u16();
        case 12:
          r.skip(10);
          final groups = r.u32();
          for (var i = 0; i < groups; i++) {
            final startChar = r.u32();
            final endChar = r.u32();
            final startGlyph = r.u32();
            if (code >= startChar && code <= endChar) {
              return startGlyph + (code - startChar);
            }
          }
          return 0;
        default:
          return 0;
      }
    } on Object {
      return 0;
    }
  }

  int _format4(_Reader r, int code) {
    if (code < 0 || code > 0xFFFF) return 0;
    r.skip(4); // length, language
    final segCount = r.u16() ~/ 2;
    r.skip(6);
    final endCodesAt = r.position;
    var segment = -1;
    for (var i = 0; i < segCount; i++) {
      if (r.u16() >= code) {
        segment = i;
        break;
      }
    }
    if (segment < 0) return 0;
    final startCodesAt = endCodesAt + segCount * 2 + 2;
    r.seek(startCodesAt + segment * 2);
    final startCode = r.u16();
    if (code < startCode) return 0;
    final idDeltaAt = startCodesAt + segCount * 2;
    r.seek(idDeltaAt + segment * 2);
    final idDelta = r.s16();
    final idRangeOffsetEntry = idDeltaAt + segCount * 2 + segment * 2;
    r.seek(idRangeOffsetEntry);
    final idRangeOffset = r.u16();
    if (idRangeOffset == 0) {
      return (code + idDelta) & 0xFFFF;
    }
    r.seek(idRangeOffsetEntry + idRangeOffset + (code - startCode) * 2);
    final gid = r.u16();
    return gid == 0 ? 0 : (gid + idDelta) & 0xFFFF;
  }
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int position = 0;

  void seek(int p) => position = p;

  void skip(int n) => position += n;

  int u8() => bytes[position++];

  int s8() {
    final v = bytes[position++];
    return v > 127 ? v - 256 : v;
  }

  int u16() {
    final v = (bytes[position] << 8) | bytes[position + 1];
    position += 2;
    return v;
  }

  int s16() {
    final v = u16();
    return v > 0x7FFF ? v - 0x10000 : v;
  }

  int u32() {
    final v = (bytes[position] << 24) |
        (bytes[position + 1] << 16) |
        (bytes[position + 2] << 8) |
        bytes[position + 3];
    position += 4;
    return v;
  }

  double f2dot14() => s16() / 16384;
}

/// The 258 standard Macintosh glyph names, in order — the `post` format 2.0
/// name index points into this list for indices < 258 (Apple TrueType
/// Reference, the `post` table). Custom names follow as Pascal strings.
const List<String> _macGlyphNames = [
  '.notdef', '.null', 'nonmarkingreturn', 'space', 'exclam', 'quotedbl',
  'numbersign', 'dollar', 'percent', 'ampersand', 'quotesingle', 'parenleft',
  'parenright', 'asterisk', 'plus', 'comma', 'hyphen', 'period', 'slash',
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'colon', 'semicolon', 'less', 'equal', 'greater', 'question', 'at',
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
  'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'bracketleft',
  'backslash', 'bracketright', 'asciicircum', 'underscore', 'grave', 'a', 'b',
  'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q',
  'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'braceleft', 'bar',
  'braceright', 'asciitilde', 'Adieresis', 'Aring', 'Ccedilla', 'Eacute',
  'Ntilde', 'Odieresis', 'Udieresis', 'aacute', 'agrave', 'acircumflex',
  'adieresis', 'atilde', 'aring', 'ccedilla', 'eacute', 'egrave',
  'ecircumflex', 'edieresis', 'iacute', 'igrave', 'icircumflex', 'idieresis',
  'ntilde', 'oacute', 'ograve', 'ocircumflex', 'odieresis', 'otilde', 'uacute',
  'ugrave', 'ucircumflex', 'udieresis', 'dagger', 'degree', 'cent', 'sterling',
  'section', 'bullet', 'paragraph', 'germandbls', 'registered', 'copyright',
  'trademark', 'acute', 'dieresis', 'notequal', 'AE', 'Oslash', 'infinity',
  'plusminus', 'lessequal', 'greaterequal', 'yen', 'mu', 'partialdiff',
  'summation', 'product', 'pi', 'integral', 'ordfeminine', 'ordmasculine',
  'Omega', 'ae', 'oslash', 'questiondown', 'exclamdown', 'logicalnot',
  'radical', 'florin', 'approxequal', 'Delta', 'guillemotleft',
  'guillemotright', 'ellipsis', 'nonbreakingspace', 'Agrave', 'Atilde',
  'Otilde', 'OE', 'oe', 'endash', 'emdash', 'quotedblleft', 'quotedblright',
  'quoteleft', 'quoteright', 'divide', 'lozenge', 'ydieresis', 'Ydieresis',
  'fraction', 'currency', 'guilsinglleft', 'guilsinglright', 'fi', 'fl',
  'daggerdbl', 'periodcentered', 'quotesinglbase', 'quotedblbase',
  'perthousand', 'Acircumflex', 'Ecircumflex', 'Aacute', 'Edieresis', 'Egrave',
  'Iacute', 'Icircumflex', 'Idieresis', 'Igrave', 'Oacute', 'Ocircumflex',
  'apple', 'Ograve', 'Uacute', 'Ucircumflex', 'Ugrave', 'dotlessi',
  'circumflex', 'tilde', 'macron', 'breve', 'dotaccent', 'ring', 'cedilla',
  'hungarumlaut', 'ogonek', 'caron', 'Lslash', 'lslash', 'Scaron', 'scaron',
  'Zcaron', 'zcaron', 'brokenbar', 'Eth', 'eth', 'Yacute', 'yacute', 'Thorn',
  'thorn', 'minus', 'multiply', 'onesuperior', 'twosuperior', 'threesuperior',
  'onehalf', 'onequarter', 'threequarters', 'franc', 'Gbreve', 'gbreve',
  'Idotaccent', 'Scedilla', 'scedilla', 'Cacute', 'cacute', 'Ccaron', 'ccaron',
  'dcroat',
];
