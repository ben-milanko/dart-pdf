part of 'editor.dart';

/// Composite (/Type0) text editing for [PdfContentEditing.replaceText].
///
/// Where simple-font runs encode one byte per character, a /Type0 run draws
/// 2-byte codes. For the Identity-H + CIDFontType2 + Identity-CIDToGIDMap
/// shape — what this library emits and the dominant form real producers use
/// — a content-stream code is the glyph id directly, and:
///
///  * the existing text is recovered from the font's `/ToUnicode` CMap
///    (code -> string), so a `find` string can be matched against it;
///  * a replacement character is re-encoded by looking its glyph up in the
///    embedded font program's own `cmap` ([PdfEmbeddedFont.glyphForRune]),
///    so *any* character the embedded font carries a glyph for can be typed,
///    not just ones already drawn on the page;
///  * the new glyphs' advances and Unicode values are merged into the
///    descendant font's `/W` array and the `/ToUnicode` CMap, so the line
///    re-measures correctly and the result stays selectable/searchable in
///    every viewer.
///
/// When the document's own font has no glyph for a replacement character —
/// a *subsetted* embedded font physically lacks the outlines it dropped —
/// the run's replacement is drawn in a bundled **fallback font** instead
/// (passed in via [PdfContentEditing.replaceText]'s `fallbackFonts`): the
/// fallback is embedded as a new page /Font resource and the replacement is
/// emitted between `Tf` switches, so the edit still lands (in the fallback
/// face) rather than failing. A fallback matching the original's serif /
/// monospace style is preferred.
///
/// A run is left untouched (no corruption) when the font is anything this
/// path can't safely round-trip: a non-Identity-H encoding, a CIDFontType0
/// (CFF) descendant, a stream `/CIDToGIDMap`, a missing/garbled embedded
/// program or `/ToUnicode`, or a replacement character that neither the
/// document's font nor any fallback can draw.
class _Type0Editing {
  _Type0Editing._(
    this._editor,
    this.page,
    this.resourceName,
    this.fontDict,
    this.cidFont,
    this._embedded,
    this._codeToText,
    this._cidWidths,
    this._dw,
    this._fallbacks,
    this._serif,
    this._mono,
  );

  final PdfEditor _editor;
  final PdfPage page;

  /// The /Font resource key this font is referenced by on [page] (e.g. `F0`)
  /// — emitted in the `Tf` that restores it after a fallback segment.
  final String resourceName;
  final CosDictionary fontDict; // the /Type0 dictionary
  final CosDictionary cidFont; // the descendant CIDFont
  final PdfEmbeddedFont _embedded;

  /// code (2-byte CID == GID) -> its Unicode text, from `/ToUnicode`.
  final Map<int, String> _codeToText;

  /// code -> advance width (thousandths of an em), from `/W`.
  final Map<int, double> _cidWidths;
  final double _dw;

  /// Bundled fallback fonts to draw characters the document font lacks.
  final List<PdfEmbeddedFont> _fallbacks;
  final bool _serif;
  final bool _mono;

  /// New glyphs introduced by replacements in the *document's own* font:
  /// gid -> rune, flushed into `/W` and `/ToUnicode` by [commit].
  final Map<int, int> _newGlyphs = {};

  /// Fallback fonts actually used, mapped to the page /Font resource name
  /// allocated for each — registered by [commit].
  final Map<PdfEmbeddedFont, String> _usedFallbacks = {};
  final Set<String> _allocatedNames = {};
  CosDictionary? _fontResourcesCache;

  bool get isDirty => _newGlyphs.isNotEmpty || _usedFallbacks.isNotEmpty;

  /// Builds an editor for the font named [resourceName] ([fontDict]) on
  /// [page], or null when the font isn't an Identity-H / CIDFontType2 /
  /// Identity-CIDToGIDMap composite this path can safely rewrite.
  static _Type0Editing? tryCreate(PdfEditor editor, PdfPage page,
      String resourceName, CosDictionary fontDict,
      List<PdfEmbeddedFont> fallbacks) {
    try {
      final cos = editor.document.cos;
      final enc = cos.resolve(fontDict['Encoding']);
      if (enc is! CosName || enc.value != 'Identity-H') return null;
      final desc = cos.resolve(fontDict['DescendantFonts']);
      if (desc is! CosArray || desc.items.isEmpty) return null;
      final cidFont = cos.resolve(desc.items.first);
      if (cidFont is! CosDictionary) return null;
      final sub = cos.resolve(cidFont['Subtype']);
      if (sub is! CosName || sub.value != 'CIDFontType2') return null;
      // CIDToGIDMap must be Identity (a name, or absent → default Identity);
      // a stream means code != gid and we can't emit glyph ids directly.
      final c2g = cos.resolve(cidFont['CIDToGIDMap']);
      if (c2g is CosStream) return null;
      if (c2g is CosName && c2g.value != 'Identity') return null;
      final embedded = PdfEmbeddedFont.fromFontDict(cos, fontDict, 'F0');
      if (embedded == null) return null;
      final toUni = cos.resolve(fontDict['ToUnicode']);
      if (toUni is! CosStream) return null;
      final codeToText = parseToUnicodeCmap(cos.decodeStreamData(toUni));
      if (codeToText.isEmpty) return null;
      // /Flags drives the fallback style preference (serif bit 2, fixed-pitch
      // bit 1, per §9.8.2 Table 121).
      var flags = 0;
      final fd = cos.resolve(cidFont['FontDescriptor']);
      if (fd is CosDictionary) {
        final f = cos.resolve(fd['Flags']);
        if (f is CosInteger) flags = f.value;
      }
      return _Type0Editing._(
        editor,
        page,
        resourceName,
        fontDict,
        cidFont,
        embedded,
        codeToText,
        parseCidWidths(cos, cidFont),
        cidDefaultWidth(cos, cidFont),
        fallbacks,
        flags & 2 != 0,
        flags & 1 != 0,
      );
    } catch (_) {
      return null;
    }
  }

  double _widthOf(int code) => _cidWidths[code] ?? _dw;

  /// Encodes [text] as an Identity-H hex show string (2-byte glyph ids),
  /// recording each glyph's width and Unicode for [commit]. Returns null
  /// when the embedded font lacks a glyph for any rune — paragraph reflow
  /// has no fallback path, so the caller bails rather than draw `.notdef`.
  CosString? encodeReflowLine(String text) {
    final buffer = <int>[];
    for (final rune in text.runes) {
      if (rune == 0x20) {
        // a space need not carry an outline; emit the font's space glyph if
        // it has one, else a zero advance so wrapping math still holds.
        final gid = _embedded.glyphForRune(rune);
        buffer
          ..add(gid >> 8)
          ..add(gid & 0xFF);
        if (gid != 0) _useGlyph(gid, rune);
        continue;
      }
      final gid = _embedded.glyphForRune(rune);
      if (gid == 0) return null; // the font can't draw it
      buffer
        ..add(gid >> 8)
        ..add(gid & 0xFF);
      _useGlyph(gid, rune);
    }
    return CosString(Uint8List.fromList(buffer), isHex: true);
  }

  /// Advance of [text] in text-space points at [size], from the embedded
  /// font's own metrics — used to re-measure reflowed lines.
  double measureReflow(String text, double size) =>
      _embedded.measure(text, size);

  /// Rewrites one run of show operators (active font size [fontSize]),
  /// replacing [find] with [replace]. Returns the operations to emit and how
  /// many replacements were made (the originals, untouched, when nothing
  /// matched or the replacement can be drawn by neither the document font
  /// nor a fallback).
  (List<ContentOperation>, int) rewriteRun(
      List<ContentOperation> run, String find, String replace, double fontSize) {
    // a code split across two shown strings would misalign 2-byte reads;
    // bail rather than risk corrupting the run.
    for (final op in run) {
      if (op.operator == 'TJ' &&
          op.operands.isNotEmpty &&
          op.operands[0] is CosArray) {
        for (final item in (op.operands[0] as CosArray).items) {
          if (item is CosString && item.bytes.length.isOdd) return (run, 0);
        }
      } else if (op.operands.isNotEmpty && op.operands[0] is CosString) {
        if ((op.operands[0] as CosString).bytes.length.isOdd) return (run, 0);
      }
    }

    // pick the font that can draw the whole replacement: the document's own
    // font when it has every glyph, else a style-matched fallback. (An empty
    // replacement — deletion — needs no font.)
    final runes = replace.runes.toList();
    final origOk = runes.every((r) => _embedded.glyphForRune(r) != 0);
    PdfEmbeddedFont? fallback;
    if (!origOk && replace.isNotEmpty) {
      fallback = _pickFallback(runes);
      if (fallback == null) return (run, 0); // nobody can draw it
    }

    final cells = _type0Cells(run);

    // flatten the code cells into a decoded string, tracking where each code
    // cell starts so matches can be aligned to code boundaries.
    final codeCellOf = <int>[]; // code-cell index -> cell index
    final boundaryChar = <int>[]; // code-cell index -> start char in decoded
    final decoded = StringBuffer();
    for (var c = 0; c < cells.length; c++) {
      if (cells[c].code case final int code) {
        boundaryChar.add(decoded.length);
        codeCellOf.add(c);
        // a code with no ToUnicode entry gets a sentinel that `find` can't
        // contain, so matches never span it.
        decoded.write(_codeToText[code] ?? '￿');
      }
    }
    boundaryChar.add(decoded.length);
    final text = decoded.toString();
    final boundaryAt = <int, int>{
      for (var k = 0; k < boundaryChar.length; k++) boundaryChar[k]: k
    };

    // boundary-aligned, non-overlapping matches as code-cell ranges.
    final matches = <(int, int)>[]; // [startCodeCell, endCodeCell)
    if (find.isNotEmpty) {
      var from = 0;
      while (true) {
        final at = text.indexOf(find, from);
        if (at < 0) break;
        final start = boundaryAt[at];
        final end = boundaryAt[at + find.length];
        if (start != null && end != null && end > start) {
          matches.add((start, end));
          from = at + find.length;
        } else {
          from = at + 1; // not on code boundaries — skip
        }
      }
    }
    if (matches.isEmpty) return (run, 0);

    return fallback == null
        ? _rewriteInPlace(run, cells, matches, codeCellOf, runes)
        : _rewriteWithFallback(
            cells, matches, codeCellOf, replace, fallback, fontSize);
  }

  /// The all-in-the-document-font path: replacement codes are this font's
  /// own glyph ids, emitted as one show op.
  (List<ContentOperation>, int) _rewriteInPlace(
      List<ContentOperation> run,
      List<({int? code, double? kern})> cells,
      List<(int, int)> matches,
      List<int> codeCellOf,
      List<int> runes) {
    final numCodeCells = codeCellOf.length;
    final out = <({int? code, double? kern})>[];
    var count = 0;
    var cell = 0;
    var m = 0;
    while (cell < cells.length) {
      if (m < matches.length && cell == codeCellOf[matches[m].$1]) {
        final (_, endK) = matches[m];
        final lastCell = codeCellOf[endK - 1];
        final oldWidth = _spanWidth(cells, cell, lastCell);
        var newWidth = 0.0;
        for (final rune in runes) {
          final gid = _embedded.glyphForRune(rune);
          out.add((code: gid, kern: null));
          newWidth += _useGlyph(gid, rune);
        }
        if (endK < numCodeCells && (newWidth - oldWidth).abs() >= 0.001) {
          out.add((code: null, kern: newWidth - oldWidth));
        }
        count++;
        cell = lastCell + 1;
        m++;
      } else {
        out.add(cells[cell]);
        cell++;
      }
    }
    return (_emit(run, out), count);
  }

  /// The fallback path: the replacement is drawn in [fallback] between `Tf`
  /// switches, with the unchanged surrounding text staying in the document's
  /// own font.
  (List<ContentOperation>, int) _rewriteWithFallback(
      List<({int? code, double? kern})> cells,
      List<(int, int)> matches,
      List<int> codeCellOf,
      String replace,
      PdfEmbeddedFont fallback,
      double fontSize) {
    final numCodeCells = codeCellOf.length;
    final ops = <ContentOperation>[];
    final orig = <({int? code, double? kern})>[]; // pending original-font cells
    var inFallback = false;
    var count = 0;

    void flushOrig() {
      if (orig.isEmpty) return;
      if (inFallback) {
        ops.add(_tf(resourceName, fontSize));
        inFallback = false;
      }
      ops.addAll(_emit(const [], List.of(orig)));
      orig.clear();
    }

    final fbName = _fallbackName(fallback);
    final fbBytes = _hexToBytes(fallback.encodeHex(replace));
    var fbWidth = 0.0;
    for (final rune in replace.runes) {
      fbWidth += fallback.advanceForGlyph(fallback.glyphForRune(rune));
    }

    var cell = 0;
    var m = 0;
    while (cell < cells.length) {
      if (m < matches.length && cell == codeCellOf[matches[m].$1]) {
        final (_, endK) = matches[m];
        final lastCell = codeCellOf[endK - 1];
        final oldWidth = _spanWidth(cells, cell, lastCell);
        flushOrig();
        ops
          ..add(_tf(fbName, fontSize))
          ..add(ContentOperation('Tj', [CosString(fbBytes, isHex: true)]));
        inFallback = true;
        if (endK < numCodeCells && (fbWidth - oldWidth).abs() >= 0.001) {
          orig.add((code: null, kern: fbWidth - oldWidth));
        }
        count++;
        cell = lastCell + 1;
        m++;
      } else {
        orig.add(cells[cell]);
        cell++;
      }
    }
    flushOrig();
    // the run began in the document font and following content assumes it,
    // so restore it if the last thing drawn was a fallback segment.
    if (inFallback) ops.add(_tf(resourceName, fontSize));
    return (ops, count);
  }

  double _spanWidth(
      List<({int? code, double? kern})> cells, int first, int last) {
    var w = 0.0;
    for (var x = first; x <= last; x++) {
      w += cells[x].code != null ? _widthOf(cells[x].code!) : -cells[x].kern!;
    }
    return w;
  }

  /// Records [gid]→[rune] for the /W and /ToUnicode flush and returns the
  /// glyph's real advance (thousandths of an em).
  double _useGlyph(int gid, int rune) {
    final w = _embedded.advanceForGlyph(gid).toDouble();
    if (!_cidWidths.containsKey(gid) || _codeToText[gid] != _stringOf(rune)) {
      _newGlyphs[gid] = rune;
    }
    return _cidWidths[gid] ?? w;
  }

  /// The fallback that can draw every rune in [runes], preferring one whose
  /// family matches the document font's serif/monospace style.
  PdfEmbeddedFont? _pickFallback(List<int> runes) {
    bool draws(PdfEmbeddedFont f) =>
        runes.every((r) => f.glyphForRune(r) != 0);
    final candidates = _fallbacks.where(draws).toList();
    if (candidates.isEmpty) return null;
    bool isMono(PdfEmbeddedFont f) => f.familyName.toLowerCase().contains('mono');
    bool isSerif(PdfEmbeddedFont f) =>
        f.familyName.toLowerCase().contains('serif') && !isMono(f);
    if (_mono) {
      final m = candidates.where(isMono);
      if (m.isNotEmpty) return m.first;
    }
    if (_serif) {
      final s = candidates.where(isSerif);
      if (s.isNotEmpty) return s.first;
    }
    final sans = candidates.where((f) => !isSerif(f) && !isMono(f));
    return sans.isNotEmpty ? sans.first : candidates.first;
  }

  /// The page /Font resource name for [fallback], allocating one (and
  /// starting a fresh glyph accumulation) on first use.
  String _fallbackName(PdfEmbeddedFont fallback) {
    final existing = _usedFallbacks[fallback];
    if (existing != null) return existing;
    fallback.resetUsage();
    final fonts = _fontResources();
    var i = 0;
    while (fonts.containsKey('Fbk$i') || _allocatedNames.contains('Fbk$i')) {
      i++;
    }
    final name = 'Fbk$i';
    _allocatedNames.add(name);
    _usedFallbacks[fallback] = name;
    return name;
  }

  /// The page's own (materialized) /Font resource dictionary.
  CosDictionary _fontResources() {
    if (_fontResourcesCache != null) return _fontResourcesCache!;
    final cos = _editor.document.cos;
    final res = _editor._ownResources(page);
    final existing = cos.resolve(res['Font']);
    final fonts = CosDictionary(
        {if (existing is CosDictionary) ...existing.entries});
    res['Font'] = fonts;
    return _fontResourcesCache = fonts;
  }

  ContentOperation _tf(String name, double size) => ContentOperation(
      'Tf', [CosName(name), PdfContentEditing._numberObject(size)]);

  /// Coalesces cells into one show op (2-byte hex codes, adjacent kerns
  /// merged). When [run] is a single unchanged `Tj` it stays a `Tj`.
  List<ContentOperation> _emit(
      List<ContentOperation> run, List<({int? code, double? kern})> out) {
    final items = <CosObject>[];
    final buffer = <int>[];
    var kern = 0.0;
    void flushString() {
      if (buffer.isNotEmpty) {
        items.add(CosString(Uint8List.fromList(buffer), isHex: true));
        buffer.clear();
      }
    }

    void flushKern() {
      if (kern.abs() >= 0.001) {
        items.add(PdfContentEditing._numberObject(kern));
      }
      kern = 0;
    }

    for (final c in out) {
      if (c.code case final int code) {
        flushKern();
        buffer
          ..add(code >> 8)
          ..add(code & 0xFF);
      } else {
        flushString();
        kern += c.kern!;
      }
    }
    flushString();
    flushKern();

    if (run.length == 1 &&
        run[0].operator == 'Tj' &&
        items.length == 1 &&
        items[0] is CosString) {
      run[0].operands[0] = items[0];
      return run;
    }
    return [
      ContentOperation('TJ', [CosArray(items)])
    ];
  }

  /// Writes the document font's new glyphs into its `/W` and `/ToUnicode`,
  /// and registers every fallback font used as a page /Font resource. Call
  /// once, after all runs.
  void commit() {
    final updater = _editor._updater;
    final cos = _editor.document.cos;

    if (_newGlyphs.isNotEmpty) {
      for (final entry in _newGlyphs.entries) {
        _cidWidths[entry.key] =
            _embedded.advanceForGlyph(entry.key).toDouble();
        _codeToText[entry.key] = _stringOf(entry.value);
      }
      final wItems = <CosObject>[];
      final codes = _cidWidths.keys.toList()..sort();
      for (final code in codes) {
        final w = _cidWidths[code]!;
        if (w == _dw) continue;
        wItems
          ..add(CosInteger(code))
          ..add(CosArray([PdfContentEditing._numberObject(w)]));
      }
      cidFont['W'] = CosArray(wItems);
      fontDict['ToUnicode'] = updater.addObject(_buildToUnicode());
      // Mark indirect font dictionaries; inline ones ride along on the page
      // rewrite replaceText performs.
      if (cos.referenceTo(cidFont) != null) updater.markChanged(cidFont);
      if (cos.referenceTo(fontDict) != null) updater.markChanged(fontDict);
    }

    // embed each used fallback as a page /Font resource (the page's own
    // resources were materialized when the name was allocated, so the new
    // entries persist with the page rewrite).
    _usedFallbacks.forEach((font, name) {
      final built = font.buildResource(updater.addObject).entries.values.first;
      _fontResources()[name] = updater.addObject(built);
    });
  }

  CosStream _buildToUnicode() {
    final codes = _codeToText.keys.toList()..sort();
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
    for (var i = 0; i < codes.length; i += 100) {
      final group = codes.sublist(i, (i + 100).clamp(0, codes.length));
      buf.writeln('${group.length} beginbfchar');
      for (final code in group) {
        final src = code.toRadixString(16).padLeft(4, '0');
        buf.writeln('<$src> <${_utf16BeHexOf(_codeToText[code]!)}>');
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
        CosDictionary({'Length': CosInteger(bytes.length)}), bytes);
  }

  static String _stringOf(int rune) => String.fromCharCodes([rune]);

  /// UTF-16BE hex of every code unit in [s] (surrogate pairs preserved).
  static String _utf16BeHexOf(String s) {
    final out = StringBuffer();
    for (final unit in s.codeUnits) {
      out.write(unit.toRadixString(16).padLeft(4, '0'));
    }
    return out.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  static List<({int? code, double? kern})> _type0Cells(
      List<ContentOperation> run) {
    final cells = <({int? code, double? kern})>[];
    void addString(Uint8List bytes) {
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        cells.add((code: (bytes[i] << 8) | bytes[i + 1], kern: null));
      }
    }

    for (final op in run) {
      if (op.operator == 'TJ' &&
          op.operands.isNotEmpty &&
          op.operands[0] is CosArray) {
        for (final item in (op.operands[0] as CosArray).items) {
          switch (item) {
            case CosString(:final bytes):
              addString(bytes);
            case CosInteger(:final value):
              cells.add((code: null, kern: value.toDouble()));
            case CosReal(:final value):
              cells.add((code: null, kern: value));
            default:
              break;
          }
        }
      } else if (op.operands.isNotEmpty && op.operands[0] is CosString) {
        addString((op.operands[0] as CosString).bytes);
      }
    }
    return cells;
  }
}
