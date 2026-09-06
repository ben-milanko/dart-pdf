part of 'editor.dart';

/// Composite (/Type0) text editing for [PdfContentEditing.replaceText].
///
/// The Type0 *font model* - decoding codes to text, measuring, re-encoding
/// replacements through the embedded program's own cmap, and merging new
/// glyphs into `/W` + `/ToUnicode` - lives in [Type0Font]. This class is the
/// thin editor-side wiring around it: it resolves the eligible font on a
/// page, drives the shared [TextRunRewriter] with a Type0 codec, and does
/// the document plumbing a font model can't (allocating a fallback-font page
/// resource, marking objects changed on the updater).
///
/// Where a simple-font run encodes one byte per character, a /Type0 run draws
/// 2-byte codes. For the Identity-H + CIDFontType2 + Identity-CIDToGIDMap
/// shape [Type0Font.forEditing] accepts, a content-stream code is the glyph
/// id directly, so:
///
///  * existing text is recovered from `/ToUnicode` (matched against `find`);
///  * a replacement character is re-encoded through the embedded program's
///    own `cmap`, so *any* glyph the program carries can be typed;
///  * new glyphs' advances and Unicode values are merged back into `/W` and
///    `/ToUnicode`, so the line re-measures and stays selectable/searchable.
///
/// When the document's own font has no glyph for a replacement character - a
/// *subsetted* embedded font physically lacks the outlines it dropped - the
/// replacement is drawn in a bundled **fallback font** ([fallbackFonts]):
/// embedded as a new page /Font resource and emitted between `Tf` switches,
/// so the edit still lands (in the fallback face) rather than failing.
///
/// A run is left untouched when the font is anything [Type0Font.forEditing]
/// rejects, or when a replacement character neither the document's font nor
/// any fallback can draw.
class _Type0RunEditor {
  _Type0RunEditor._(
    this._editor,
    this.page,
    this.resourceName,
    this._font,
    this._fallbacks,
  );

  final PdfEditor _editor;
  final PdfPage page;

  /// The /Font resource key this font is referenced by on [page] (e.g. `F0`)
  /// - emitted in the `Tf` that restores it after a fallback segment.
  final String resourceName;

  /// The parsed, editable composite font.
  final Type0Font _font;

  /// Bundled fallback fonts to draw characters the document font lacks.
  final List<PdfEmbeddedFont> _fallbacks;

  /// Fallback fonts actually used, mapped to the page /Font resource name
  /// allocated for each - registered by [commit].
  final Map<PdfEmbeddedFont, String> _usedFallbacks = {};
  final Set<String> _allocatedNames = {};
  CosDictionary? _fontResourcesCache;

  bool get isDirty => _font.isDirty || _usedFallbacks.isNotEmpty;

  /// Builds an editor for the font named [resourceName] ([fontDict]) on
  /// [page], or null when the font isn't an Identity-H / CIDFontType2 /
  /// Identity-CIDToGIDMap composite this path can safely rewrite.
  static _Type0RunEditor? tryCreate(PdfEditor editor, PdfPage page,
      String resourceName, CosDictionary fontDict,
      List<PdfEmbeddedFont> fallbacks) {
    final font = Type0Font.forEditing(editor.document.cos, fontDict);
    return font == null
        ? null
        : _Type0RunEditor._(editor, page, resourceName, font, fallbacks);
  }

  /// Rewrites one run of show operators (active font size [fontSize]),
  /// replacing [find] with [replace]. Returns the operations to emit and how
  /// many replacements were made (the originals, untouched, when nothing
  /// matched or the replacement can be drawn by neither the document font
  /// nor a fallback).
  (List<ContentOperation>, int) rewriteRun(List<ContentOperation> run,
      String find, String replace, double fontSize) {
    // pick the font that can draw the whole replacement: the document's own
    // font when it has every glyph, else a style-matched fallback. (An empty
    // replacement - deletion - needs no font.)
    final runes = replace.runes.toList();
    final origOk = runes.every((r) => _font.glyphForRune(r) != 0);
    if (origOk || replace.isEmpty) {
      return TextRunRewriter(_Type0RunCodec(_font)).rewrite(run, find, replace);
    }
    final fallback = _font.pickFallback(runes, _fallbacks);
    if (fallback == null) return (run, 0); // nobody can draw it

    // Allocate the fallback page /Font resource and encode the replacement
    // lazily, on the first match: a run where [find] does not occur (or which
    // is skipped for an odd-length string) must reserve no resource, record no
    // glyphs, and leave the page unchanged.
    _FallbackDraw resolve() {
      final fbName = _fallbackName(fallback);
      final fbBytes = _hexToBytes(fallback.encodeHex(replace));
      var fbWidth = 0.0;
      for (final rune in replace.runes) {
        fbWidth += fallback.advanceForGlyph(fallback.glyphForRune(rune));
      }
      return _FallbackDraw(fbName, fbBytes, fbWidth);
    }

    final codec =
        _Type0FallbackCodec(_font, resourceName, fontSize, resolve);
    return TextRunRewriter(codec).rewrite(run, find, replace);
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

  /// Writes the document font's new glyphs into its `/W` and `/ToUnicode`,
  /// and registers every fallback font used as a page /Font resource. Call
  /// once, after all runs.
  void commit() {
    final updater = _editor._updater;
    _font.commitFontDict(updater);
    // embed each used fallback as a page /Font resource (the page's own
    // resources were materialized when the name was allocated, so the new
    // entries persist with the page rewrite).
    _usedFallbacks.forEach((font, name) {
      final built = font.buildResource(updater.addObject).entries.values.first;
      _fontResources()[name] = updater.addObject(built);
      PdfPerf.add(PdfPerfCount.fallbackFontEmbedded);
    });
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }
}

/// The in-the-document-font Type0 codec: replacement codes are the font's own
/// glyph ids, drawn as 2-byte Identity-H show strings.
class _Type0RunCodec extends RunCodec {
  _Type0RunCodec(this._font);
  final Type0Font _font;

  @override
  bool shouldSkip(List<ContentOperation> run) => type0RunHasOddString(run);

  @override
  List<RunCell> flatten(List<ContentOperation> run) => type0RunCells(run);

  // a code with no /ToUnicode entry gets a sentinel `find` can't contain, so
  // matches never span it.
  @override
  String glyphText(int glyph) => _font.codeToText[glyph] ?? '￿';

  @override
  double glyphWidth(int glyph) => _font.widthOf(glyph);

  @override
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing) {
    var newWidth = 0.0;
    for (final rune in replace.runes) {
      final gid = _font.glyphForRune(rune);
      out.add(CellEmit((glyph: gid, kern: null)));
      newWidth += _font.recordGlyph(gid, rune);
    }
    if (hasTrailing && (newWidth - oldWidth).abs() >= 0.001) {
      out.add(CellEmit((glyph: null, kern: newWidth - oldWidth)));
    }
  }

  @override
  List<ContentOperation> assemble(
          List<ContentOperation> run, List<Emit> out) =>
      RunCodec.coalesce(run, out,
          putGlyph: _putType0Glyph, makeString: _hexShowString);
}

/// The fallback-font Type0 codec: the replacement is drawn in a bundled
/// fallback face between `Tf` switches, with the unchanged surrounding text
/// staying in the document's own font.
class _Type0FallbackCodec extends RunCodec {
  _Type0FallbackCodec(
      this._font, this._resourceName, this._fontSize, this._resolve);

  final Type0Font _font;
  final String _resourceName; // base font, restored after a fallback segment
  final double _fontSize;

  /// Allocates the fallback resource + encodes the replacement, run once on
  /// the first match so a non-matching run reserves nothing.
  final _FallbackDraw Function() _resolve;
  _FallbackDraw? _draw;

  bool _inFallback = false;
  double? _pendingKern;

  @override
  bool shouldSkip(List<ContentOperation> run) => type0RunHasOddString(run);

  @override
  List<RunCell> flatten(List<ContentOperation> run) => type0RunCells(run);

  @override
  String glyphText(int glyph) => _font.codeToText[glyph] ?? '￿';

  @override
  double glyphWidth(int glyph) => _font.widthOf(glyph);

  /// Restores the base font (if a fallback segment is open) and flushes the
  /// pending compensation kern into the base-font context.
  void _restoreBase(List<Emit> out) {
    if (_inFallback) {
      out.add(OpEmit(PdfContentEditing._tfOp(_resourceName, _fontSize)));
      _inFallback = false;
    }
    if (_pendingKern != null) {
      out.add(CellEmit((glyph: null, kern: _pendingKern)));
      _pendingKern = null;
    }
  }

  @override
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing) {
    final draw = _draw ??= _resolve();
    _restoreBase(out);
    out
      ..add(OpEmit(PdfContentEditing._tfOp(draw.name, _fontSize)))
      ..add(OpEmit(
          ContentOperation('Tj', [CosString(draw.bytes, isHex: true)])));
    _inFallback = true;
    if (hasTrailing && (draw.width - oldWidth).abs() >= 0.001) {
      _pendingKern = draw.width - oldWidth;
    }
  }

  @override
  void beforePassthrough(List<Emit> out) => _restoreBase(out);

  @override
  void finish(List<Emit> out) => _restoreBase(out);

  @override
  List<ContentOperation> assemble(
          List<ContentOperation> run, List<Emit> out) =>
      RunCodec.coalesce(run, out,
          putGlyph: _putType0Glyph, makeString: _hexShowString);
}

/// The resolved fallback draw for a [_Type0FallbackCodec]: the page /Font
/// resource name to draw the replacement in, the pre-encoded (hex) show bytes,
/// and the replacement's advance (thousandths of an em).
class _FallbackDraw {
  _FallbackDraw(this.name, this.bytes, this.width);
  final String name;
  final Uint8List bytes;
  final double width;
}

void _putType0Glyph(int glyph, List<int> buffer) => buffer
  ..add(glyph >> 8)
  ..add(glyph & 0xFF);

CosString _hexShowString(List<int> buffer) =>
    CosString(Uint8List.fromList(buffer), isHex: true);
