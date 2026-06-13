import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart'
    show helveticaWidths, helveticaBoldWidths, timesRomanWidths;

import 'fonts/cff.dart';
import 'fonts/cjk_cmap.dart';
import 'fonts/encodings.dart';
import 'fonts/truetype.dart';
import 'fonts/type1.dart';
import 'path.dart';

/// Metrics, text decoding, and (for embedded TrueType fonts) real glyph
/// outlines for one font dictionary. Fonts without usable embedded outlines
/// fall back to device-side substitution scaled to these widths.
class PdfFontInfo {
  PdfFontInfo._({
    required this.baseFont,
    required this.isCid,
    required Map<int, double> widths,
    required double defaultWidth,
    required Map<int, String> toUnicode,
    TrueTypeFont? trueType,
    CffFont? cff,
    Type1Font? type1,
    Uint8List? cidToGid,
    bool symbolic = false,
    bool legacyGbk = false,
    ShiftJisCmap? cjkCmap,
    Map<int, String> encodingNames = const {},
    Map<int, int>? cffCodeToGid,
    Map<int, CosStream> type3Procs = const {},
    this.type3Resources,
    List<double>? type3Matrix,
    this.isVertical = false,
    List<double> dw2 = const [880, -1000],
    Map<int, List<double>> w2 = const {},
  })  : _widths = widths,
        _dw2 = dw2,
        _w2 = w2,
        _defaultWidth = defaultWidth,
        _toUnicode = toUnicode,
        _trueType = trueType,
        _cff = cff,
        _type1 = type1,
        _cidToGid = cidToGid,
        _symbolic = symbolic,
        _legacyGbk = legacyGbk,
        _cjkCmap = cjkCmap,
        _encodingNames = encodingNames,
        _cffCodeToGid = cffCodeToGid,
        _type3Procs = type3Procs,
        _type3Matrix = type3Matrix;

  final String? baseFont;

  /// True for Type0 composite fonts. Identity-H/V (the common case) uses
  /// two-byte codes here; a predefined Shift-JIS (RKSJ) CMap on a non-embedded
  /// font is decoded via [_cjkCmap]. Other predefined CMaps remain a TODO.
  final bool isCid;

  final Map<int, double> _widths;
  final double _defaultWidth;

  /// True for Type0 fonts with a vertical writing-mode CMap: Identity-V, a
  /// predefined `…-V` CMap, or an embedded CMap stream with `/WMode 1`. Glyphs
  /// advance downward and use the vertical metrics from /W2 and /DW2
  /// (§9.7.4.3); horizontal fonts ignore all of that.
  final bool isVertical;

  /// /DW2 `[v_y w1_y]` in glyph space (÷1000), default `[880 −1000]`: the
  /// default position-vector y and vertical displacement for vertical writing.
  final List<double> _dw2;

  /// /W2 vertical metrics by CID: `[w1_y, v_x, v_y]` in glyph space (÷1000).
  final Map<int, List<double>> _w2;
  final Map<int, String> _toUnicode;
  final TrueTypeFont? _trueType;
  final CffFont? _cff;
  final Type1Font? _type1;
  final Uint8List? _cidToGid;
  final bool _symbolic;
  final bool _legacyGbk;

  /// Decoder for a predefined Shift-JIS (RKSJ) CMap on a non-embedded Type0
  /// font; null for Identity-H and all embedded composites.
  final ShiftJisCmap? _cjkCmap;

  final Map<int, String> _encodingNames;

  /// PDF /Encoding (base + Differences) resolved against the CFF charset;
  /// overrides the font's built-in encoding when present.
  final Map<int, int>? _cffCodeToGid;

  /// Type3 glyph procedures by character code, with their resources and
  /// glyph-space matrix. Type3 text renders by executing these tiny content
  /// streams — never by substitution (blank procs are intentional, e.g.
  /// invisible text layers).
  final Map<int, CosStream> _type3Procs;
  final CosDictionary? type3Resources;
  final List<double>? _type3Matrix;

  bool get isType3 => _type3Matrix != null;

  /// Glyph space → text space, for Type3 fonts (§9.6.5).
  List<double> get type3Matrix =>
      _type3Matrix ?? const [0.001, 0, 0, 0.001, 0, 0];

  CosStream? type3ProcFor(int code) => _type3Procs[code];

  /// True when embedded glyph outlines are available.
  bool get hasOutlines =>
      _trueType != null || _cff != null || _type1 != null;

  static PdfFontInfo load(CosDocument cos, CosDictionary font) {
    final subtype = font['Subtype'];
    final subtypeName = subtype is CosName ? subtype.value : '';
    final baseFontObj = cos.resolve(font['BaseFont']);
    final baseFont = baseFontObj is CosName ? baseFontObj.value : null;
    final isCid = subtypeName == 'Type0';

    // Widths are in thousandths of an em — except for Type3 fonts, whose
    // glyph space is defined by /FontMatrix (§9.6.5).
    var widthScale = 0.001;
    var defaultWidth = 0.5;
    var isVertical = false;
    var dw2 = const <double>[880, -1000];
    final w2 = <int, List<double>>{};
    List<double>? type3Matrix;
    var type3Procs = const <int, CosStream>{};
    CosDictionary? type3Resources;
    if (subtypeName == 'Type3') {
      defaultWidth = 0;
      type3Matrix = const [0.001, 0, 0, 0.001, 0, 0];
      final matrix = cos.resolve(font['FontMatrix']);
      if (matrix is CosArray && matrix.length >= 6) {
        type3Matrix = [
          for (var i = 0; i < 6; i++) _toNum(cos.resolve(matrix[i])),
        ];
        if (type3Matrix[0] != 0) widthScale = type3Matrix[0].abs();
      }
      type3Procs = _loadType3Procs(cos, font);
      final resources = cos.resolve(font['Resources']);
      if (resources is CosDictionary) type3Resources = resources;
    }

    final widths = <int, double>{};
    final toUnicode = _parseToUnicode(cos, font['ToUnicode']);
    TrueTypeFont? trueType;
    CffFont? cff;
    Type1Font? type1;
    Uint8List? cidToGid;
    var symbolic = false;
    ShiftJisCmap? cjkCmap;
    var encodingNames = const <int, String>{};

    if (isCid) {
      // Writing mode: a `…-V` predefined CMap name or an embedded CMap stream
      // with /WMode 1 selects vertical writing (§9.7.4.3).
      final encoding = cos.resolve(font['Encoding']);
      if (encoding is CosName) {
        isVertical = encoding.value.endsWith('-V');
      } else if (encoding is CosStream) {
        final wmode = cos.resolve(encoding.dictionary['WMode']);
        isVertical = wmode is CosInteger && wmode.value == 1;
      }
      final descendants = cos.resolve(font['DescendantFonts']);
      final descendant = descendants is CosArray && descendants.length > 0
          ? cos.resolve(descendants[0])
          : null;
      if (descendant is CosDictionary) {
        final dw = cos.resolve(descendant['DW']);
        defaultWidth = dw is CosInteger
            ? dw.value / 1000
            : dw is CosReal
                ? dw.value / 1000
                : 1.0;
        _parseCidWidths(cos, cos.resolve(descendant['W']), widths);
        final dw2obj = cos.resolve(descendant['DW2']);
        if (dw2obj is CosArray && dw2obj.length >= 2) {
          dw2 = [
            _toNum(cos.resolve(dw2obj[0])),
            _toNum(cos.resolve(dw2obj[1])),
          ];
        }
        _parseCidW2(cos, cos.resolve(descendant['W2']), w2);
        final descriptor = cos.resolve(descendant['FontDescriptor']);
        if (descriptor is CosDictionary) {
          trueType = _loadTrueType(cos, descriptor);
          if (trueType == null) cff = _loadCff(cos, descriptor);
          symbolic = _isSymbolic(cos, descriptor);
        }
        final gidMap = cos.resolve(descendant['CIDToGIDMap']);
        if (gidMap is CosStream) {
          try {
            cidToGid = cos.decodeStreamData(gidMap);
          } on Exception {
            cidToGid = null;
          }
        }
      }
      // Predefined CJK CMaps: with no embedded outlines we decode the bytes to
      // Unicode and let the device substitute a system CJK font (the renderer
      // never had glyphs for these). Only Shift-JIS (RKSJ) is handled so far;
      // Identity-H and embedded composites keep the two-byte path below.
      if (trueType == null && cff == null && toUnicode.isEmpty) {
        if (encoding is CosName && ShiftJisCmap.handles(encoding.value)) {
          cjkCmap = const ShiftJisCmap();
        }
      }
    } else {
      encodingNames = _simpleEncoding(cos, font['Encoding'], baseFont);
      final firstCharObj = cos.resolve(font['FirstChar']);
      final firstChar = firstCharObj is CosInteger ? firstCharObj.value : 0;
      final w = cos.resolve(font['Widths']);
      if (w is CosArray) {
        for (var i = 0; i < w.length; i++) {
          final value = cos.resolve(w[i]);
          widths[firstChar + i] = _toNum(value) * widthScale;
        }
      }
      final descriptor = cos.resolve(font['FontDescriptor']);
      if (descriptor is CosDictionary) {
        final missing = cos.resolve(descriptor['MissingWidth']);
        if (missing is CosInteger) {
          defaultWidth = missing.value * widthScale;
        }
        trueType = _loadTrueType(cos, descriptor);
        if (trueType == null) cff = _loadCff(cos, descriptor);
        if (trueType == null && cff == null) {
          type1 = _loadType1(cos, descriptor);
        }
        symbolic = _isSymbolic(cos, descriptor);
      }
      // base-14 fonts may omit /Widths entirely (§9.6.2.2) — the viewer
      // must supply the built-in metrics. Without this, every glyph fell
      // back to a flat 500, so text measured ~15% wide and selection /
      // extraction bounds drifted from what was painted.
      if (widths.isEmpty && subtypeName != 'Type3') {
        _fillStandardWidths(baseFont, widths);
      }
    }

    Map<int, int>? cffCodeToGid;
    if (cff != null && !isCid) {
      cffCodeToGid = _buildCffEncoding(cos, font, cff);
    }

    return PdfFontInfo._(
      baseFont: baseFont,
      isCid: isCid,
      widths: widths,
      defaultWidth: defaultWidth,
      toUnicode: toUnicode,
      trueType: trueType,
      cff: cff,
      type1: type1,
      cidToGid: cidToGid,
      symbolic: symbolic,
      legacyGbk: !isCid && toUnicode.isEmpty && _isLegacyGbkFont(baseFont),
      cjkCmap: cjkCmap,
      encodingNames: encodingNames,
      cffCodeToGid: cffCodeToGid,
      type3Procs: type3Procs,
      type3Resources: type3Resources,
      type3Matrix: type3Matrix,
      isVertical: isVertical,
      dw2: dw2,
      w2: w2,
    );
  }

  /// Fills ASCII advance widths (codes 32–126) for the standard-14
  /// families from their AFM tables. Helvetica/Arial map to the
  /// Helvetica tables (bold variants to the bold table), Times to
  /// Times-Roman, Courier to its uniform 600. Italic/oblique reuse the
  /// upright widths — within a percent of the real AFMs and far closer
  /// than the flat fallback. Symbol/ZapfDingbats keep the default.
  static void _fillStandardWidths(String? baseFont, Map<int, double> widths) {
    if (baseFont == null) return;
    // strip any ABCDEF+ subset prefix
    final plus = baseFont.indexOf('+');
    final name =
        (plus >= 0 ? baseFont.substring(plus + 1) : baseFont).toLowerCase();
    List<int>? table;
    if (name.startsWith('helvetica') || name.startsWith('arial')) {
      table = name.contains('bold') ? helveticaBoldWidths : helveticaWidths;
    } else if (name.startsWith('times')) {
      table = timesRomanWidths;
    } else if (name.startsWith('courier')) {
      for (var code = 32; code <= 126; code++) {
        widths[code] = 0.6;
      }
      return;
    }
    if (table == null) return;
    for (var i = 0; i < table.length && i < 95; i++) {
      widths[32 + i] = table[i] / 1000;
    }
  }

  static Map<int, String> _simpleEncoding(
      CosDocument cos, CosObject? encodingObject, String? baseFont) {
    final encoding = cos.resolve(encodingObject);
    final result = <int, String>{};

    void fillWinAnsi() {
      for (var code = 0; code <= 255; code++) {
        final name = winAnsiGlyphName(code);
        if (name != null) result[code] = name;
      }
    }

    void fillStandard() {
      for (var code = 0; code <= 255; code++) {
        final name = standardGlyphName(code);
        if (name != null) result[code] = name;
      }
    }

    if (encoding is CosName) {
      if (encoding.value == 'WinAnsiEncoding') {
        fillWinAnsi();
      } else if (encoding.value == 'StandardEncoding' ||
          encoding.value == 'MacRomanEncoding') {
        fillStandard();
      }
    } else if (encoding is CosDictionary) {
      final base = cos.resolve(encoding['BaseEncoding']);
      if (base is CosName && base.value == 'WinAnsiEncoding') {
        fillWinAnsi();
      } else {
        fillStandard();
      }
    } else if (_isStandardFont(baseFont)) {
      fillStandard();
    }

    _parseDifferences(cos, encodingObject).forEach((code, name) {
      result[code] = name;
    });
    return result;
  }

  static bool _isStandardFont(String? baseFont) {
    if (baseFont == null) return false;
    final plus = baseFont.indexOf('+');
    final name =
        (plus >= 0 ? baseFont.substring(plus + 1) : baseFont).toLowerCase();
    return name.startsWith('helvetica') ||
        name.startsWith('times') ||
        name.startsWith('courier');
  }

  /// Maps character codes to /CharProcs streams via /Encoding /Differences.
  static Map<int, CosStream> _loadType3Procs(
      CosDocument cos, CosDictionary font) {
    final procsDict = cos.resolve(font['CharProcs']);
    if (procsDict is! CosDictionary) return const {};
    final result = <int, CosStream>{};
    _parseDifferences(cos, font['Encoding']).forEach((code, name) {
      final proc = cos.resolve(procsDict[name]);
      if (proc is CosStream) result[code] = proc;
    });
    return result;
  }

  /// Parses an /Encoding dictionary's /Differences into code → glyph name.
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

  /// When the PDF declares its own /Encoding, codes map by glyph name
  /// (base encoding + /Differences) through the CFF charset — the font's
  /// built-in encoding does not apply (§9.6.6.2).
  static Map<int, int>? _buildCffEncoding(
      CosDocument cos, CosDictionary font, CffFont cff) {
    final encoding = cos.resolve(font['Encoding']);
    if (encoding is! CosName && encoding is! CosDictionary) return null;

    final result = <int, int>{};
    for (var code = 0; code <= 255; code++) {
      final name = winAnsiGlyphName(code);
      if (name == null) continue;
      final gid = cff.gidForName(name);
      if (gid != 0) result[code] = gid;
    }
    _parseDifferences(cos, font['Encoding']).forEach((code, name) {
      final gid = cff.gidForName(name);
      if (gid != 0) result[code] = gid;
    });
    return result.isEmpty ? null : result;
  }

  static TrueTypeFont? _loadTrueType(
      CosDocument cos, CosDictionary descriptor) {
    // FontFile2 is TrueType; FontFile3 /Subtype /OpenType may carry glyf
    // outlines too (CFF-flavored OpenType parses to null until the CFF
    // engine lands).
    for (final key in const ['FontFile2', 'FontFile3']) {
      final file = cos.resolve(descriptor[key]);
      if (file is! CosStream) continue;
      try {
        final parsed = TrueTypeFont.parse(cos.decodeStreamData(file));
        if (parsed != null) return parsed;
      } on Exception {
        // fall through to substitution
      }
    }
    return null;
  }

  /// Type 1 outlines: the raw PostScript /FontFile (eexec-encrypted
  /// charstrings). Tried only after TrueType and CFF, since those are far
  /// more common in modern PDFs.
  static Type1Font? _loadType1(CosDocument cos, CosDictionary descriptor) {
    final file = cos.resolve(descriptor['FontFile']);
    if (file is! CosStream) return null;
    try {
      return Type1Font.parse(cos.decodeStreamData(file));
    } on Exception {
      return null;
    }
  }

  static bool _isSymbolic(CosDocument cos, CosDictionary descriptor) {
    final flags = cos.resolve(descriptor['Flags']);
    return flags is CosInteger && (flags.value & 4) != 0;
  }

  /// CFF outlines: FontFile3 (/Type1C, /CIDFontType0C, CFF-flavored
  /// /OpenType), plus FontFile2 streams that turn out to be OTTO.
  static CffFont? _loadCff(CosDocument cos, CosDictionary descriptor) {
    for (final key in const ['FontFile3', 'FontFile2']) {
      final file = cos.resolve(descriptor[key]);
      if (file is! CosStream) continue;
      try {
        final parsed = CffFont.parse(cos.decodeStreamData(file));
        if (parsed != null) return parsed;
      } on Exception {
        // fall through to substitution
      }
    }
    return null;
  }

  /// Real outline for one character code, in em units, or null.
  PdfPath? outlineFor(int code) {
    final trueType = _trueType;
    if (trueType != null) return trueType.outlineForGlyph(_gidFor(code));
    final cff = _cff;
    if (cff != null) return cff.outlineForGlyph(_cffGidFor(code));
    final type1 = _type1;
    if (type1 != null) {
      final name = _type1NameFor(code);
      return name == null ? null : type1.outlineForName(name);
    }
    return null;
  }

  /// Code → glyph name for a Type 1 font: the PDF /Encoding wins, falling
  /// back to the font's built-in /Encoding (§9.6.6.2).
  String? _type1NameFor(int code) =>
      _encodingNames[code] ?? _type1?.builtinEncoding[code];

  int _cffGidFor(int code) {
    final cff = _cff!;
    if (isCid) return cff.gidForCid(code);
    final fromPdfEncoding = _cffCodeToGid?[code];
    if (fromPdfEncoding != null) return fromPdfEncoding;
    final gid = cff.gidForCode(code);
    if (gid != 0) return gid;
    // subset fonts without an encoding index glyphs directly
    return code < cff.numGlyphs ? code : 0;
  }

  /// Code → glyph id, per §9.6.6.4 (simple fonts) and §9.7.4.2 (CID fonts).
  int _gidFor(int code) {
    final font = _trueType;
    if (font == null) return 0;
    if (isCid) {
      final map = _cidToGid;
      if (map == null) return code; // Identity
      final index = code * 2;
      if (index + 1 >= map.length) return 0;
      return (map[index] << 8) | map[index + 1];
    }
    if (_symbolic || font.hasSymbolCmap) {
      final gid = font.gidForSymbolCode(code);
      if (gid != 0) return gid;
    }
    // Glyph selection goes through the font's /Encoding, not /ToUnicode
    // (§9.6.6.4). Subset fonts (pdfkit, many producers) key their Unicode
    // cmap on the original code points reached via the encoding's glyph
    // names, while /ToUnicode remaps to semantic Unicode (e.g. code 33 →
    // "exclam" → U+0021 in the cmap, but /ToUnicode says U+0053 'S').
    final encUnicode = _encodingUnicode(code);
    if (encUnicode != null) {
      final gid = font.gidForUnicode(encUnicode);
      if (gid != 0) return gid;
    }
    // Fall back to /ToUnicode-derived Unicode for fonts whose cmap really is
    // keyed by semantic Unicode and that carry no usable encoding.
    final unicode = charFor(code);
    if (unicode.isNotEmpty) {
      final gid = font.gidForUnicode(unicode.runes.first);
      if (gid != 0) return gid;
    }
    final mac = font.gidForMacCode(code);
    if (mac != 0) return mac;
    // cmap-less fonts: select by glyph name through the `post` table — a subset
    // packs its used glyphs at arbitrary gids, so the encoding name → gid
    // mapping (e.g. "greater" → gid 33) is the only correct path (§9.6.6.4).
    if (!font.hasCmap) {
      final name = _encodingNames[code] ?? _type1?.builtinEncoding[code];
      if (name != null) {
        final gid = font.gidForName(name);
        if (gid != 0) return gid;
      }
    }
    // subset fonts without a cmap or post names index glyphs directly by code
    if (!font.hasCmap && code < font.numGlyphs) return code;
    return 0;
  }

  /// Unicode for one code via the font's /Encoding (glyph name → Unicode),
  /// independent of /ToUnicode. Used for glyph selection; returns null for
  /// CID fonts and codes with no encoding entry.
  int? _encodingUnicode(int code) {
    if (isCid) return null;
    final name = _encodingNames[code] ?? _type1?.builtinEncoding[code];
    if (name != null) {
      final mapped = glyphNameUnicode(name);
      if (mapped != null) return mapped;
    }
    // No encoding entry: Standard/WinAnsi ≈ Latin-1 over 0x20–0xFF.
    if (code >= 0x20 && code <= 0xFF) return code;
    return null;
  }

  /// Splits show-text string bytes into character codes.
  List<int> codesOf(Uint8List bytes) {
    if (_legacyGbk) return _legacyGbkCodesOf(bytes);
    if (_cjkCmap != null) return _cjkCmap.split(bytes);
    if (!isCid) return bytes;
    final codes = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      codes.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return codes;
  }

  /// Glyph advance in em units (1.0 = the font size). Falls back to the
  /// embedded font's hmtx metrics before the default width.
  double widthOf(int code) {
    if (_legacyGbk && code > 0xFF) {
      final high = _widths[code >> 8] ?? _defaultWidth;
      final low = _widths[code & 0xFF] ?? _defaultWidth;
      return high + low;
    }
    final declared = _widths[code];
    if (declared != null) return declared;
    final trueType = _trueType;
    if (trueType != null) {
      final advance = trueType.advanceForGlyph(_gidFor(code));
      if (advance != null && advance > 0) return advance;
    }
    final cff = _cff;
    if (cff != null) {
      final advance = cff.advanceForGlyph(_cffGidFor(code));
      if (advance != null && advance > 0) return advance;
    }
    final type1 = _type1;
    if (type1 != null) {
      final name = _type1NameFor(code);
      final advance = name == null ? null : type1.advanceForName(name);
      if (advance != null && advance > 0) return advance;
    }
    return _defaultWidth;
  }

  /// Vertical pen advance in em for [code] — the y-component of the vertical
  /// displacement vector w1 (§9.7.4.3), normally negative (downward). Only
  /// meaningful when [isVertical].
  double verticalAdvanceOf(int code) => (_w2[code]?[0] ?? _dw2[1]) / 1000;

  /// Position vector in em from the glyph's horizontal origin to its vertical
  /// origin (§9.7.4.3): x centres the glyph on the column (half its horizontal
  /// advance) and y comes from /W2 or /DW2. Only meaningful when [isVertical].
  ({double x, double y}) verticalOriginOf(int code) {
    final v = _w2[code];
    return (
      x: v != null ? v[1] / 1000 : widthOf(code) / 2,
      y: (v != null ? v[2] : _dw2[0]) / 1000,
    );
  }

  /// Best-effort Unicode for one character code.
  String charFor(int code) {
    final mapped = _toUnicode[code];
    if (mapped != null) return mapped;
    if (_cjkCmap != null) return _cjkCmap.unicode(code);
    if (_legacyGbk && code > 0xFF) {
      final mapped = _legacyGbkUnicode[code];
      if (mapped != null) return String.fromCharCode(mapped);
    }
    if (!isCid && _isZapfDingbats(baseFont)) {
      final mapped = zapfDingbatsUnicode(code);
      if (mapped != null) return String.fromCharCode(mapped);
    }
    if (!isCid) {
      final name = _encodingNames[code] ?? _type1?.builtinEncoding[code];
      if (name != null) {
        final mapped = glyphNameUnicode(name);
        if (mapped != null) return String.fromCharCode(mapped);
      }
    }
    if (!isCid && code >= 0x20 && code <= 0xFF) {
      return String.fromCharCode(code); // Latin-1 ≈ Standard/WinAnsi enough
    }
    return '';
  }

  static bool _isZapfDingbats(String? baseFont) {
    if (baseFont == null) return false;
    final plus = baseFont.indexOf('+');
    final name =
        (plus >= 0 ? baseFont.substring(plus + 1) : baseFont).toLowerCase();
    return name == 'zapfdingbats';
  }

  static double _toNum(CosObject? value) {
    if (value is CosInteger) return value.value.toDouble();
    if (value is CosReal) return value.value;
    return 0;
  }

  /// /W array: `c [w1 w2 ...]` lists widths from CID c; `c1 c2 w` sets a
  /// range (§9.7.4.3).
  static void _parseCidWidths(
      CosDocument cos, CosObject? w, Map<int, double> out) {
    if (w is! CosArray) return;
    var i = 0;
    while (i < w.length) {
      final first = cos.resolve(w[i]);
      if (first is! CosInteger || i + 1 >= w.length) break;
      final second = cos.resolve(w[i + 1]);
      if (second is CosArray) {
        for (var k = 0; k < second.length; k++) {
          out[first.value + k] = _toNum(cos.resolve(second[k])) / 1000;
        }
        i += 2;
      } else if (second is CosInteger && i + 2 < w.length) {
        final width = _toNum(cos.resolve(w[i + 2])) / 1000;
        for (var cid = first.value; cid <= second.value; cid++) {
          out[cid] = width;
        }
        i += 3;
      } else {
        break;
      }
    }
  }

  /// /W2 vertical metrics (§9.7.4.3): `c [w1y vx vy w1y vx vy …]` lists triples
  /// from CID c; `c1 c2 w1y vx vy` sets a range. Values are in glyph space.
  static void _parseCidW2(
      CosDocument cos, CosObject? w, Map<int, List<double>> out) {
    if (w is! CosArray) return;
    var i = 0;
    while (i < w.length) {
      final first = cos.resolve(w[i]);
      if (first is! CosInteger || i + 1 >= w.length) break;
      final second = cos.resolve(w[i + 1]);
      if (second is CosArray) {
        for (var k = 0; k + 2 < second.length; k += 3) {
          out[first.value + k ~/ 3] = [
            _toNum(cos.resolve(second[k])),
            _toNum(cos.resolve(second[k + 1])),
            _toNum(cos.resolve(second[k + 2])),
          ];
        }
        i += 2;
      } else if (second is CosInteger && i + 4 < w.length) {
        final m = [
          _toNum(cos.resolve(w[i + 2])),
          _toNum(cos.resolve(w[i + 3])),
          _toNum(cos.resolve(w[i + 4])),
        ];
        for (var cid = first.value; cid <= second.value; cid++) {
          out[cid] = m;
        }
        i += 5;
      } else {
        break;
      }
    }
  }

  static bool _isLegacyGbkFont(String? baseFont) {
    if (baseFont == null) return false;
    return baseFont.contains('ËÎÌå') || // 宋体
        baseFont.contains('ºÚÌå') || // 黑体
        baseFont.contains('¿¬Ìå') || // 楷体
        baseFont.contains('·ÂËÎ') || // 仿宋
        baseFont.contains('Ð¡±êËÎ'); // 小标宋
  }

  static List<int> _legacyGbkCodesOf(Uint8List bytes) {
    final codes = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      final high = bytes[i];
      if (high >= 0x81 &&
          high <= 0xFE &&
          i + 1 < bytes.length &&
          bytes[i + 1] >= 0x40 &&
          bytes[i + 1] <= 0xFE &&
          bytes[i + 1] != 0x7F) {
        codes.add((high << 8) | bytes[++i]);
        if (i + 1 < bytes.length && bytes[i + 1] == 0x20) i++;
      } else {
        codes.add(high);
      }
    }
    return codes;
  }

  // Targeted GBK repair table for malformed non-embedded Chinese simple
  // fonts that declare WinAnsiEncoding but store GBK byte pairs. Keep this
  // small and corpus-driven until a full charset dependency is warranted.
  static const Map<int, int> _legacyGbkUnicode = {
    0xA1A1: 0x3000, //
    0xA1AD: 0x2026, // …
    0xA3A8: 0xFF08, // （
    0xA3A9: 0xFF09, // ）
    0xA3AC: 0xFF0C, // ，
    0xA3B1: 0xFF11, // １
    0xA3B2: 0xFF12, // ２
    0xA3B3: 0xFF13, // ３
    0xA3B5: 0xFF15, // ５
    0xA3B6: 0xFF16, // ６
    0xA3B8: 0xFF18, // ８
    0xA3B9: 0xFF19, // ９
    0xB0CB: 0x516B, // 八
    0xB1AC: 0x7206, // 爆
    0xB1E0: 0x7F16, // 编
    0xB2BF: 0x90E8, // 部
    0xB2FA: 0x4EA7, // 产
    0xB3D6: 0x6301, // 持
    0xB5C4: 0x7684, // 的
    0xB5D0: 0x654C, // 敌
    0xB5D8: 0x5730, // 地
    0xB6C0: 0x72EC, // 独
    0xB6C8: 0x5EA6, // 度
    0xB6CF: 0x65AD, // 断
    0xB6D4: 0x5BF9, // 对
    0xB6FE: 0x4E8C, // 二
    0xB7A2: 0x53D1, // 发
    0xB7BD: 0x65B9, // 方
    0xB7C0: 0x9632, // 防
    0xB8C4: 0x6539, // 改
    0xB8F7: 0x5404, // 各
    0xB9D8: 0x5173, // 关
    0xB9FA: 0x56FD, // 国
    0xBACF: 0x5408, // 合
    0xBAEC: 0x7EA2, // 红
    0xBAF3: 0x540E, // 后
    0xBBF7: 0x51FB, // 击
    0xBCB0: 0x53CA, // 及
    0xBCE1: 0x575A, // 坚
    0xBCFB: 0x89C1, // 见
    0xBDD3: 0x63A5, // 接
    0xBDE2: 0x89E3, // 解
    0xBDE7: 0x754C, // 界
    0xBEC5: 0x4E5D, // 九
    0xBEFC: 0x519B, // 军
    0xBFAA: 0x5F00, // 开
    0xC0B4: 0x6765, // 来
    0xC1A2: 0x7ACB, // 立
    0xC1AA: 0x8054, // 联
    0xC2B7: 0x8DEF, // 路
    0xC2BC: 0x5F55, // 录
    0xC2D4: 0x7565, // 略
    0xC4BF: 0x76EE, // 目
    0xC4CF: 0x5357, // 南
    0xC4EA: 0x5E74, // 年
    0xC5D0: 0x5224, // 判
    0xC6DF: 0x4E03, // 七
    0xC6F0: 0x8D77, // 起
    0xC7A2: 0x6D3D, // 洽
    0xC7AB: 0x8C26, // 谦
    0xC7E9: 0x60C5, // 情
    0xC7F8: 0x533A, // 区
    0xC8AB: 0x5168, // 全
    0xC8CE: 0x4EFB, // 任
    0xC8D5: 0x65E5, // 日
    0xC8FD: 0x4E09, // 三
    0xC9BD: 0x5C71, // 山
    0xCAAE: 0x5341, // 十
    0xCAB1: 0x65F6, // 时
    0xCAB5: 0x5B9E, // 实
    0xCAC0: 0x4E16, // 世
    0xCAC6: 0x52BF, // 势
    0xCACD: 0x91CA, // 释
    0xCAF0: 0x7F72, // 署
    0xCBC4: 0x56DB, // 四
    0xCCAC: 0x6001, // 态
    0xCCB8: 0x8C08, // 谈
    0xCCE2: 0x9898, // 题
    0xCDAC: 0x540C, // 同
    0xCECA: 0x95EE, // 问
    0xCEDE: 0x65E0, // 无
    0xCEF1: 0x52A1, // 务
    0xCEF7: 0x897F, // 西
    0xD0CE: 0x5F62, // 形
    0xD0D0: 0x884C, // 行
    0xD1B7: 0x900A, // 逊
    0xD2AA: 0x8981, // 要
    0xD2BB: 0x4E00, // 一
    0xD2E2: 0x610F, // 意
    0xD3A6: 0x5E94, // 应
    0xD3CE: 0x6E38, // 游
    0xD3D0: 0x6709, // 有
    0xD3DA: 0x4E8E, // 于
    0xD3EB: 0x4E0E, // 与
    0xD4AD: 0x539F, // 原
    0xD4C2: 0x6708, // 月
    0xD4DA: 0x5728, // 在
    0xD4F2: 0x5219, // 则
    0xD5B9: 0x5C55, // 展
    0xD5BD: 0x6218, // 战
    0xD5DF: 0x8005, // 者
    0xD5EB: 0x9488, // 针
    0xD5F9: 0x4E89, // 争
    0xD6D0: 0x4E2D, // 中
    0xD6F7: 0x4E3B, // 主
    0xD7D4: 0x81EA, // 自
    0xD7F7: 0x4F5C, // 作
  };

  /// Minimal ToUnicode CMap reader: bfchar and bfrange sections only, which
  /// covers what real-world writers emit.
  static Map<int, String> _parseToUnicode(CosDocument cos, CosObject? ref) {
    final stream = cos.resolve(ref);
    if (stream is! CosStream) return const {};
    final Uint8List data;
    try {
      data = cos.decodeStreamData(stream);
    } on Exception {
      return const {};
    }
    final map = <int, String>{};
    final parser = CosParser(data);
    try {
      while (true) {
        final t = parser.nextToken();
        if (t.type == CosTokenType.eof) break;
        if (t.isKeyword('beginbfchar')) {
          _parseBfChars(parser, map);
        } else if (t.isKeyword('beginbfrange')) {
          _parseBfRanges(parser, map);
        }
      }
    } on CosParseException {
      // keep whatever was mapped before the malformed section
    }
    return map;
  }

  static void _parseBfChars(CosParser parser, Map<int, String> map) {
    while (true) {
      final src = parser.nextToken();
      if (src.isKeyword('endbfchar') || src.type == CosTokenType.eof) return;
      final dst = parser.nextToken();
      if (src.type == CosTokenType.hexString &&
          dst.type == CosTokenType.hexString) {
        map[_codeOf(src.bytesValue)] = _utf16Be(dst.bytesValue);
      }
    }
  }

  static void _parseBfRanges(CosParser parser, Map<int, String> map) {
    while (true) {
      final lo = parser.nextToken();
      if (lo.isKeyword('endbfrange') || lo.type == CosTokenType.eof) return;
      final hi = parser.nextToken();
      if (lo.type != CosTokenType.hexString ||
          hi.type != CosTokenType.hexString) {
        return;
      }
      final loCode = _codeOf(lo.bytesValue);
      final hiCode = _codeOf(hi.bytesValue);
      final dst = parser.peekToken();
      if (dst.type == CosTokenType.arrayOpen) {
        final list = parser.parseObject() as CosArray;
        for (var k = 0; k < list.length && loCode + k <= hiCode; k++) {
          final item = list[k];
          if (item is CosString) map[loCode + k] = _utf16Be(item.bytes);
        }
      } else if (dst.type == CosTokenType.hexString) {
        parser.nextToken();
        final base = dst.bytesValue;
        for (var code = loCode; code <= hiCode; code++) {
          final unit = _codeOf(base) + (code - loCode);
          map[code] = base.length <= 2
              ? String.fromCharCode(unit)
              : _utf16Be(_withIncrementedTail(base, code - loCode));
        }
      } else {
        return;
      }
    }
  }

  static int _codeOf(Uint8List bytes) {
    var value = 0;
    for (final b in bytes) {
      value = (value << 8) | b;
    }
    return value;
  }

  static Uint8List _withIncrementedTail(Uint8List base, int delta) {
    final out = Uint8List.fromList(base);
    var carry = delta;
    for (var i = out.length - 1; i >= 0 && carry > 0; i--) {
      final sum = out[i] + carry;
      out[i] = sum & 0xFF;
      carry = sum >> 8;
    }
    return out;
  }

  static String _utf16Be(Uint8List bytes) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
}
