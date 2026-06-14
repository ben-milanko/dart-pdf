import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'content_writer.dart';

/// A TrueType/OpenType font program, parsed and ready to embed in a PDF as
/// a full-Unicode composite (Type0) font.
///
/// Where [PdfStandardFont] writes one of the base-14 faces every viewer
/// already has, this embeds an *arbitrary* font so authored text renders
/// and prints identically everywhere — the price is the font bytes riding
/// along in the file.
///
/// Encoding is Identity-H over a CIDFontType2 (TrueType outlines) or
/// CIDFontType0 (CFF/OpenType outlines) descendant, so character codes in
/// the content stream are 2-byte glyph ids. A /ToUnicode CMap maps them
/// back to text, keeping the result selectable, searchable, and
/// copy-able. The whole font program is embedded (no subsetting yet), with
/// a /W array and the ToUnicode CMap covering only the glyphs actually
/// shown.
///
/// Use [PdfEmbeddedFont.parse] to sniff and load font bytes. The instance
/// is reusable across annotations; [resetUsage] starts a fresh glyph
/// accumulation for the next appearance stream.
class PdfEmbeddedFont implements PdfTextFont {
  PdfEmbeddedFont._(
    this._bytes,
    this.resourceName,
    this.postScriptName,
    this.familyName,
    this._unitsPerEm,
    this._numHMetrics,
    this._advances,
    this._cmap,
    this._isCff,
    this._bbox,
    this._italicAngle,
    this._ascent,
    this._descent,
    this._capHeight,
    this._stemV,
    this._flags,
  );

  /// The /Font resource key this font is referenced by in /DA and the
  /// appearance resources. Embedded fonts use a generated name (`F0`)
  /// distinct from the base-14 short names so a reparser can tell them
  /// apart.
  @override
  final String resourceName;

  /// The font's PostScript name, used for /BaseFont and /FontName.
  final String postScriptName;

  /// A human-friendly family name (name table id 1), for font menus.
  final String familyName;

  final Uint8List _bytes;
  final int _unitsPerEm;
  final int _numHMetrics;
  final Uint16List _advances; // font units, length == _numHMetrics
  final _Cmap _cmap;
  final bool _isCff;

  // FontDescriptor metrics, already scaled to thousandths of an em.
  final List<int> _bbox; // [xMin, yMin, xMax, yMax]
  final int _italicAngle;
  final int _ascent;
  final int _descent;
  final int _capHeight;
  final int _stemV;
  final int _flags;

  // Glyphs shown since the last [resetUsage] — drives /W and /ToUnicode.
  final Map<int, int> _gidToRune = {};

  /// Ascender height in thousandths of an em (where the first baseline
  /// sits below the top of a text box).
  @override
  int get ascent => _ascent;

  /// Parses [bytes] as a TrueType (`glyf`) or OpenType/CFF (`OTTO`) font.
  ///
  /// Throws [ArgumentError] for unrecognized data (e.g. WOFF, TrueType
  /// collections, or a font without a usable Unicode `cmap`).
  factory PdfEmbeddedFont.parse(Uint8List bytes, {String resourceName = 'F0'}) {
    if (bytes.length < 12) {
      throw ArgumentError('not a font (too short)');
    }
    final data = ByteData.sublistView(bytes);
    final sfnt = data.getUint32(0);
    final isCff = sfnt == 0x4F54544F; // 'OTTO'
    final isTrueType = sfnt == 0x00010000 || sfnt == 0x74727565; // 1.0 / 'true'
    if (!isCff && !isTrueType) {
      if (sfnt == 0x774F4646 || sfnt == 0x774F4632) {
        throw ArgumentError('WOFF fonts are not supported; supply a '
            'TrueType (.ttf) or OpenType (.otf) file');
      }
      if (sfnt == 0x74746366) {
        throw ArgumentError('TrueType collections (.ttc) are not supported');
      }
      throw ArgumentError('unrecognized font format');
    }

    final numTables = data.getUint16(4);
    final tables = <String, ({int offset, int length})>{};
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + i * 16;
      final tag = String.fromCharCodes(bytes, rec, rec + 4);
      tables[tag] = (offset: data.getUint32(rec + 8), length: data.getUint32(rec + 12));
    }

    final head = tables['head'];
    final hhea = tables['hhea'];
    final maxp = tables['maxp'];
    final hmtx = tables['hmtx'];
    final cmapT = tables['cmap'];
    if (head == null || hhea == null || maxp == null || hmtx == null) {
      throw ArgumentError('font is missing required tables');
    }
    if (cmapT == null) {
      throw ArgumentError('font has no cmap (cannot map text to glyphs)');
    }

    final unitsPerEm = data.getUint16(head.offset + 18);
    final xMin = data.getInt16(head.offset + 36);
    final yMin = data.getInt16(head.offset + 38);
    final xMax = data.getInt16(head.offset + 40);
    final yMax = data.getInt16(head.offset + 42);

    final hheaAscent = data.getInt16(hhea.offset + 4);
    final hheaDescent = data.getInt16(hhea.offset + 6);
    final numHMetrics = data.getUint16(hhea.offset + 34);

    final advances = Uint16List(numHMetrics);
    for (var i = 0; i < numHMetrics; i++) {
      advances[i] = data.getUint16(hmtx.offset + i * 4);
    }

    // OS/2 carries the typographic ascent/descent, cap height and weight.
    int? capHeight, typoAscent, typoDescent, weightClass, fsSelection;
    final os2 = tables['OS/2'];
    if (os2 != null && os2.length >= 78) {
      weightClass = data.getUint16(os2.offset + 4);
      fsSelection = data.getUint16(os2.offset + 62);
      typoAscent = data.getInt16(os2.offset + 68);
      typoDescent = data.getInt16(os2.offset + 70);
      final version = data.getUint16(os2.offset + 0);
      if (version >= 2 && os2.length >= 96) {
        capHeight = data.getInt16(os2.offset + 88);
      }
    }

    var italicAngle = 0; // 16.16 fixed, integer part is enough
    var fixedPitch = false;
    final post = tables['post'];
    if (post != null && post.length >= 20) {
      italicAngle = data.getInt32(post.offset + 4) >> 16;
      fixedPitch = data.getUint32(post.offset + 16) != 0;
    }

    final cmap = _Cmap.parse(data, cmapT.offset);

    final scale = unitsPerEm == 0 ? 1.0 : 1000.0 / unitsPerEm;
    int s(num v) => (v * scale).round();

    final ascent = s(typoAscent ?? hheaAscent);
    final descent = s(typoDescent ?? hheaDescent);
    final cap = capHeight != null ? s(capHeight) : (ascent * 0.7).round();

    final italic = (fsSelection != null && (fsSelection & 0x01) != 0) ||
        italicAngle != 0;
    final bold = fsSelection != null && (fsSelection & 0x20) != 0;
    // Nonsymbolic (32) for fonts with a Unicode cmap; add Italic (64),
    // ForceBold (1<<18) and FixedPitch (1) as detected.
    var flags = 32;
    if (italic) flags |= 64;
    if (fixedPitch) flags |= 1;
    if (bold) flags |= 1 << 18;

    // StemV has no reliable source; estimate from the weight class.
    final stemV = (weightClass ?? 400) >= 600 ? 120 : 80;

    final names = _readNames(data, tables['name']);

    return PdfEmbeddedFont._(
      bytes,
      resourceName,
      names.postScript ?? 'EmbeddedFont',
      names.family ?? names.postScript ?? 'Embedded Font',
      unitsPerEm == 0 ? 1000 : unitsPerEm,
      numHMetrics,
      advances,
      cmap,
      isCff,
      [s(xMin), s(yMin), s(xMax), s(yMax)],
      italicAngle,
      ascent,
      descent,
      cap,
      stemV,
      flags,
    );
  }

  /// Recovers the embedded font from a free-text [annotation]'s appearance,
  /// or null when it was written with a base-14 face (or the appearance
  /// can't be read). Lets editors round-trip the text of an embedded-font
  /// box — re-wrap, resize, restyle — without reverting it to a standard
  /// font.
  static PdfEmbeddedFont? fromFreeText(PdfAnnotation annotation) {
    try {
      final cos = annotation.document.cos;
      final form = annotation.normalAppearance;
      if (form == null) return null;
      final res = cos.resolve(form.dictionary['Resources']);
      if (res is! CosDictionary) return null;
      final fonts = cos.resolve(res['Font']);
      if (fonts is! CosDictionary) return null;
      final name = RegExp(r'/(\S+)\s+[\d.]+\s+Tf')
          .firstMatch(annotation.defaultAppearance ?? '')
          ?.group(1);
      final dict = name != null ? cos.resolve(fonts[name]) : null;
      if (dict is! CosDictionary) return null;
      final sub = cos.resolve(dict['Subtype']);
      if (sub is! CosName || sub.value != 'Type0') return null;
      final desc = cos.resolve(dict['DescendantFonts']);
      if (desc is! CosArray || desc.items.isEmpty) return null;
      final cid = cos.resolve(desc.items.first);
      if (cid is! CosDictionary) return null;
      final fd = cos.resolve(cid['FontDescriptor']);
      if (fd is! CosDictionary) return null;
      var file = cos.resolve(fd['FontFile2']);
      if (file is! CosStream) file = cos.resolve(fd['FontFile3']);
      if (file is! CosStream) return null;
      final bytes = cos.decodeStreamData(file);
      return PdfEmbeddedFont.parse(Uint8List.fromList(bytes),
          resourceName: name ?? 'F0');
    } catch (_) {
      return null;
    }
  }

  /// The glyph id for [rune], or 0 (.notdef) when the font lacks it.
  int glyphForRune(int rune) => _cmap.gidFor(rune);

  /// Advance width of [gid] in thousandths of an em.
  int advanceForGlyph(int gid) {
    if (_numHMetrics == 0) return 0;
    final units = gid < _numHMetrics ? _advances[gid] : _advances[_numHMetrics - 1];
    return (units * 1000 / _unitsPerEm).round();
  }

  /// Measures [text] in points at [fontSize].
  @override
  double measure(String text, double fontSize) {
    var total = 0;
    for (final rune in text.runes) {
      total += advanceForGlyph(glyphForRune(rune));
    }
    return total * fontSize / 1000;
  }

  /// Forgets the glyphs accumulated for the previous appearance stream, so
  /// the next /W and /ToUnicode cover only the new text.
  void resetUsage() => _gidToRune.clear();

  /// Encodes [text] as a hex string of big-endian 2-byte glyph ids — the
  /// operand of an Identity-H `Tj`/`TJ` show — recording each glyph so
  /// [buildResource] can emit its width and ToUnicode mapping.
  String encodeHex(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      final gid = glyphForRune(rune);
      _gidToRune[gid] = rune;
      out.write((gid >> 8).toRadixString(16).padLeft(2, '0'));
      out.write((gid & 0xFF).toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  /// Builds the /Font resource dictionary `{ resourceName: <Type0 dict> }`,
  /// registering the descendant CIDFont, FontDescriptor, embedded font
  /// program, and ToUnicode CMap as indirect objects through [addObject].
  ///
  /// Covers the glyphs shown since the last [resetUsage] (always including
  /// .notdef). Call this *after* the content stream is built.
  CosDictionary buildResource(CosReference Function(CosObject) addObject) {
    final compressed = Uint8List.fromList(const ZLibEncoder().encode(_bytes));

    final fontFileDict = CosDictionary({
      'Length': CosInteger(compressed.length),
      'Length1': CosInteger(_bytes.length),
      'Filter': const CosName('FlateDecode'),
    });
    if (_isCff) fontFileDict['Subtype'] = const CosName('OpenType');
    final fontFileRef = addObject(CosStream(fontFileDict, compressed));

    final descriptor = CosDictionary({
      'Type': const CosName('FontDescriptor'),
      'FontName': CosName(postScriptName),
      'Flags': CosInteger(_flags),
      'FontBBox': CosArray([for (final v in _bbox) CosInteger(v)]),
      'ItalicAngle': CosInteger(_italicAngle),
      'Ascent': CosInteger(_ascent),
      'Descent': CosInteger(_descent),
      'CapHeight': CosInteger(_capHeight),
      'StemV': CosInteger(_stemV),
      _isCff ? 'FontFile3' : 'FontFile2': fontFileRef,
    });
    final descriptorRef = addObject(descriptor);

    final cidFont = CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': CosName(_isCff ? 'CIDFontType0' : 'CIDFontType2'),
      'BaseFont': CosName(postScriptName),
      'CIDSystemInfo': CosDictionary({
        'Registry': CosString.fromText('Adobe'),
        'Ordering': CosString.fromText('Identity'),
        'Supplement': const CosInteger(0),
      }),
      'FontDescriptor': descriptorRef,
      'DW': const CosInteger(1000),
      'W': _widthsArray(),
    });
    if (!_isCff) cidFont['CIDToGIDMap'] = const CosName('Identity');
    final cidFontRef = addObject(cidFont);

    final toUnicodeRef = addObject(_toUnicodeStream());

    final type0 = CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type0'),
      'BaseFont': CosName(postScriptName),
      'Encoding': const CosName('Identity-H'),
      'DescendantFonts': CosArray([cidFontRef]),
      'ToUnicode': toUnicodeRef,
    });

    return CosDictionary({resourceName: type0});
  }

  /// A /W array with one entry per used glyph: `gid [ width ]`.
  CosArray _widthsArray() {
    final gids = _gidToRune.keys.toList()..sort();
    final items = <CosObject>[];
    for (final gid in gids) {
      final w = advanceForGlyph(gid);
      if (w == 1000) continue; // covered by /DW
      items
        ..add(CosInteger(gid))
        ..add(CosArray([CosInteger(w)]));
    }
    return CosArray(items);
  }

  CosStream _toUnicodeStream() {
    final entries = _gidToRune.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final buf = StringBuffer()
      ..writeln('/CIDInit /ProcSet findresource begin')
      ..writeln('12 dict begin')
      ..writeln('begincmap')
      ..writeln('/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) '
          '/Supplement 0 >> def')
      ..writeln('/CMapName /Adobe-Identity-UCS def')
      ..writeln('/CMapType 2 def')
      ..writeln('1 begincodespacerange')
      ..writeln('<0000> <FFFF>')
      ..writeln('endcodespacerange');
    // bfchar groups are capped at 100 entries each.
    for (var i = 0; i < entries.length; i += 100) {
      final group = entries.sublist(i, (i + 100).clamp(0, entries.length));
      buf.writeln('${group.length} beginbfchar');
      for (final e in group) {
        final gid = e.key.toRadixString(16).padLeft(4, '0');
        buf.writeln('<$gid> <${_utf16BeHex(e.value)}>');
      }
      buf.writeln('endbfchar');
    }
    buf
      ..writeln('endcmap')
      ..writeln('CMapName currentdict /CMap defineresource pop')
      ..writeln('end')
      ..writeln('end');
    final bytes = Uint8List.fromList(latin1.encode(buf.toString()));
    return CosStream(
      CosDictionary({'Length': CosInteger(bytes.length)}),
      bytes,
    );
  }

  static String _utf16BeHex(int rune) {
    final out = StringBuffer();
    if (rune <= 0xFFFF) {
      out.write(rune.toRadixString(16).padLeft(4, '0'));
    } else {
      final v = rune - 0x10000;
      final hi = 0xD800 + (v >> 10);
      final lo = 0xDC00 + (v & 0x3FF);
      out.write(hi.toRadixString(16).padLeft(4, '0'));
      out.write(lo.toRadixString(16).padLeft(4, '0'));
    }
    return out.toString();
  }

  static ({String? postScript, String? family}) _readNames(
      ByteData data, ({int offset, int length})? name) {
    if (name == null) return (postScript: null, family: null);
    final base = name.offset;
    final count = data.getUint16(base + 2);
    final storage = base + data.getUint16(base + 4);
    String? family, postScript;
    String? best(String? current, String value, int platform) =>
        // Prefer Windows (3) names, but take anything if nothing yet.
        current == null || platform == 3 ? value : current;
    for (var i = 0; i < count; i++) {
      final rec = base + 6 + i * 12;
      final platform = data.getUint16(rec);
      final nameId = data.getUint16(rec + 6);
      if (nameId != 1 && nameId != 6) continue;
      final len = data.getUint16(rec + 8);
      final off = storage + data.getUint16(rec + 10);
      if (off + len > data.lengthInBytes) continue;
      final value = platform == 1
          ? String.fromCharCodes(
              Uint8List.sublistView(data, off, off + len))
          : _decodeUtf16Be(data, off, len);
      if (nameId == 1) family = best(family, value, platform);
      if (nameId == 6) postScript = best(postScript, value, platform);
    }
    return (postScript: postScript, family: family);
  }

  static String _decodeUtf16Be(ByteData data, int off, int len) {
    final units = <int>[];
    for (var i = 0; i + 1 < len; i += 2) {
      units.add(data.getUint16(off + i));
    }
    return String.fromCharCodes(units);
  }
}

/// A parsed Unicode `cmap` subtable answering rune → glyph-id lookups.
///
/// Supports segment-mapped format 4 (BMP) and segmented-coverage format 12
/// (full Unicode), chosen in that preference order. Lookups binary-search
/// the segment arrays, so even huge CJK fonts stay cheap.
class _Cmap {
  _Cmap._format4(this._end4, this._start4, this._delta4, this._range4,
      this._rangeBase4, this._data)
      : _format = 4,
        _groups12 = const [];
  _Cmap._format12(this._groups12, this._data)
      : _format = 12,
        _end4 = const [],
        _start4 = const [],
        _delta4 = const [],
        _range4 = const [],
        _rangeBase4 = 0;

  final int _format;
  final ByteData _data;

  // Format 4 arrays (sorted by endCode).
  final List<int> _end4;
  final List<int> _start4;
  final List<int> _delta4;
  final List<int> _range4;
  final int _rangeBase4; // byte offset of the idRangeOffset array

  // Format 12 groups: each [startChar, endChar, startGid], sorted by start.
  final List<List<int>> _groups12;

  factory _Cmap.parse(ByteData data, int base) {
    final numTables = data.getUint16(base + 2);
    int? best4, best12;
    var bestScore = -1;
    for (var i = 0; i < numTables; i++) {
      final rec = base + 4 + i * 8;
      final platform = data.getUint16(rec);
      final encoding = data.getUint16(rec + 2);
      final off = base + data.getUint32(rec + 4);
      final format = data.getUint16(off);
      // Score Unicode subtables; prefer full-repertoire format 12.
      var score = -1;
      if ((platform == 3 && encoding == 10) || (platform == 0 && encoding >= 4)) {
        score = format == 12 ? 5 : 3;
      } else if ((platform == 3 && encoding == 1) || platform == 0) {
        score = format == 12 ? 4 : 2;
      } else if (platform == 3 && encoding == 0) {
        score = 1; // symbol
      }
      if (score <= bestScore) continue;
      if (format == 12) {
        best12 = off;
        best4 = null;
        bestScore = score;
      } else if (format == 4) {
        best4 = off;
        best12 = null;
        bestScore = score;
      }
    }
    if (best12 != null) return _parse12(data, best12);
    if (best4 != null) return _parse4(data, best4);
    throw ArgumentError('font has no supported cmap subtable (need format '
        '4 or 12)');
  }

  static _Cmap _parse4(ByteData data, int off) {
    final segX2 = data.getUint16(off + 6);
    final segCount = segX2 ~/ 2;
    final endBase = off + 14;
    final startBase = endBase + segX2 + 2; // + reservedPad
    final deltaBase = startBase + segX2;
    final rangeBase = deltaBase + segX2;
    final end = <int>[], start = <int>[], delta = <int>[], range = <int>[];
    for (var i = 0; i < segCount; i++) {
      end.add(data.getUint16(endBase + i * 2));
      start.add(data.getUint16(startBase + i * 2));
      delta.add(data.getInt16(deltaBase + i * 2));
      range.add(data.getUint16(rangeBase + i * 2));
    }
    return _Cmap._format4(end, start, delta, range, rangeBase, data);
  }

  static _Cmap _parse12(ByteData data, int off) {
    final nGroups = data.getUint32(off + 12);
    final groups = <List<int>>[];
    for (var i = 0; i < nGroups; i++) {
      final g = off + 16 + i * 12;
      groups.add([
        data.getUint32(g),
        data.getUint32(g + 4),
        data.getUint32(g + 8),
      ]);
    }
    return _Cmap._format12(groups, data);
  }

  /// The glyph id for [rune], or 0 (.notdef) when unmapped.
  int gidFor(int rune) => _format == 12 ? _gid12(rune) : _gid4(rune);

  int _gid4(int c) {
    if (c > 0xFFFF) return 0;
    // Binary search for the first segment whose endCode >= c.
    var lo = 0, hi = _end4.length - 1, seg = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_end4[mid] >= c) {
        seg = mid;
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    if (seg < 0 || c < _start4[seg]) return 0;
    final ro = _range4[seg];
    if (ro == 0) return (c + _delta4[seg]) & 0xFFFF;
    // glyphIdArray index, per the format-4 idRangeOffset addressing.
    final addr = _rangeBase4 + seg * 2 + ro + (c - _start4[seg]) * 2;
    if (addr + 1 >= _data.lengthInBytes) return 0;
    final gid = _data.getUint16(addr);
    return gid == 0 ? 0 : (gid + _delta4[seg]) & 0xFFFF;
  }

  int _gid12(int c) {
    var lo = 0, hi = _groups12.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final g = _groups12[mid];
      if (c < g[0]) {
        hi = mid - 1;
      } else if (c > g[1]) {
        lo = mid + 1;
      } else {
        return g[2] + (c - g[0]);
      }
    }
    return 0;
  }
}
