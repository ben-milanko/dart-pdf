part of 'editor.dart';

/// Content editing tiers: stamping new content, deleting elements, and
/// replacing text runs.
extension PdfContentEditing on PdfEditor {
  /// Tier 1 — stamping. Draws new content on top of page [index] via
  /// [draw]. The existing content is wrapped in q/Q once so its dangling
  /// graphics state cannot leak into the stamp, and each stamp runs in
  /// its own saved state.
  void stampPage(int index, void Function(PdfStamp stamp) draw) {
    final page = document.page(index);
    final stamp = PdfStamp._(this, page, _ownResources(page));
    draw(stamp);
    final wrapped = BytesBuilder(copy: false)
      ..add(latin1.encode('q\n'))
      ..add(stamp.content.takeBytes())
      ..add(latin1.encode('Q\n'));
    _appendContent(page, wrapped.takeBytes());
  }

  /// Tier 2 — element deletion. Removes the [ids] listed in [elements]
  /// (a snapshot from [PdfPageElements.of]) and rewrites the page's
  /// content stream. The `'` and `"` text operators keep their line-feed
  /// and spacing side effects so surrounding text stays put.
  void deleteElements(PdfPageElements elements, Iterable<int> ids) {
    final page = document.page(elements.pageIndex);
    final drop = <int>{};
    final replacements = <int, String>{};
    for (final id in ids) {
      if (id < 0 || id >= elements.elements.length) {
        throw RangeError.range(id, 0, elements.elements.length - 1, 'ids');
      }
      final element = elements.elements[id];
      for (var i = element.start; i < element.end; i++) {
        drop.add(i);
      }
      final op = elements.operations[element.start];
      if (op.operator == "'") {
        replacements[element.start] = 'T*';
      } else if (op.operator == '"' && op.operands.length >= 3) {
        final aw = _num(op.operands[0]);
        final ac = _num(op.operands[1]);
        replacements[element.start] =
            '${ContentWriter.fmt(aw)} Tw ${ContentWriter.fmt(ac)} Tc T*';
      }
    }
    if (drop.isEmpty) return;
    _setContent(
        page, elements.serialize(drop: drop, replacements: replacements));
  }

  /// Tier 3 — text editing. Replaces occurrences of [find] with [replace]
  /// in the text-showing operations on page [index] and returns how many
  /// were rewritten.
  ///
  /// A match may span the multiple shown strings of one `TJ` array and any
  /// run of consecutive `Tj`/`TJ` operators on the same line, so kerned
  /// text (`[(spli) -20 (t run)]`) is matched as the single word it reads
  /// as. Replacements are re-measured against the font's real advance
  /// widths (its `/Widths`, or base-14 metrics by `/BaseFont`) and a
  /// compensating `TJ` adjustment is inserted so whatever follows on the
  /// line keeps its position regardless of how the width changed.
  ///
  /// Composite (/Type0) runs are handled too, for the common Identity-H /
  /// CIDFontType2 / Identity-CIDToGIDMap shape: the existing text is read
  /// from `/ToUnicode`, replacements are re-encoded through the embedded
  /// font's own `cmap` (so any character the embedded program carries a
  /// glyph for can be typed), and the new glyphs' widths and Unicode values
  /// are merged into the descendant `/W` and `/ToUnicode` (see
  /// [_Type0Editing]). A Type0 run is left untouched when it can't be safely
  /// round-tripped (CFF descendant, stream /CIDToGIDMap, non-Identity-H
  /// encoding, missing program/ToUnicode, or a character the font lacks).
  ///
  /// Remaining limitations: for simple fonts both strings must be Latin-1;
  /// and matches do not cross a line break (`Td`/`T*`/`'`/`"`) — this
  /// corrects and re-flows within a line, it does not re-flow paragraphs.
  /// [fallbackFonts] (composite editing only) supply glyph outlines for
  /// characters the document's own /Type0 font can't draw — a subsetted
  /// embedded font physically lacks the glyphs it dropped, and this library
  /// bundles none. When given, such a replacement is drawn in the first
  /// fallback that can render it (style-matched to the document font); when
  /// omitted, an undrawable replacement leaves the run untouched.
  int replaceText(int index, String find, String replace,
      {List<PdfEmbeddedFont> fallbackFonts = const []}) {
    if (find.isEmpty) throw ArgumentError.value(find, 'find', 'is empty');
    // the simple-font path is byte-encoded; non-Latin-1 strings can only be
    // matched/drawn by the composite path, so leave these null there.
    final findBytes = _tryLatin1(find);
    final replaceBytes = _tryLatin1(replace);

    final page = document.page(index);
    final elements = PdfPageElements.of(document, index);
    final cos = document.cos;
    final fonts = cos.resolve(page.resources['Font']);

    CosDictionary? fontFor(String? name) {
      if (name == null || fonts is! CosDictionary) return null;
      final font = cos.resolve(fonts[name]);
      return font is CosDictionary ? font : null;
    }

    // composite (/Type0) fonts are rewritten by a separate path that decodes
    // 2-byte glyph codes — built lazily and cached per font resource name.
    final type0Cache = <String, _Type0Editing?>{};
    _Type0Editing? type0For(String name, CosDictionary f) =>
        type0Cache.putIfAbsent(
            name, () => _Type0Editing.tryCreate(this, page, name, f, fallbackFonts));

    final ops = elements.operations;
    final rewritten = <ContentOperation>[];
    var count = 0;
    CosDictionary? font; // the font active at the current operation
    String? fontName; // its /Font resource key
    var fontSize = 0.0; // its size, for fallback Tf switches

    var i = 0;
    while (i < ops.length) {
      final op = ops[i];
      if (op.operator == 'Tf' && op.operands.isNotEmpty) {
        fontName = op.operands[0] is CosName
            ? (op.operands[0] as CosName).value
            : null;
        font = fontFor(fontName);
        if (op.operands.length >= 2) fontSize = _num(op.operands[1]);
        rewritten.add(op);
        i++;
        continue;
      }
      if (op.operator == 'Tj' || op.operator == 'TJ') {
        // a run is a maximal stretch of adjacent show operators: text
        // state (font, position) is constant across it, so the strings
        // read as one line and may be merged into a single TJ.
        final run = <ContentOperation>[];
        while (i < ops.length &&
            (ops[i].operator == 'Tj' || ops[i].operator == 'TJ')) {
          run.add(ops[i]);
          i++;
        }
        final (ops_, n) = _isType0(cos, font) && fontName != null
            ? (type0For(fontName, font!)
                    ?.rewriteRun(run, find, replace, fontSize) ??
                (run, 0))
            : (findBytes != null && replaceBytes != null
                ? _rewriteTextRun(run, font, findBytes, replaceBytes)
                : (run, 0));
        rewritten.addAll(ops_);
        count += n;
        continue;
      }
      // ' and " carry a line break, so they stand alone; a single string
      // with nothing after it on its line needs no width compensation.
      if ((op.operator == "'" || op.operator == '"') &&
          !_isType0(cos, font) &&
          findBytes != null &&
          replaceBytes != null) {
        final si = op.operator == '"' ? 2 : 0;
        if (op.operands.length > si && op.operands[si] is CosString) {
          final s = op.operands[si] as CosString;
          final replaced = _replaceBytes(s.bytes, findBytes, replaceBytes);
          if (replaced != null) {
            op.operands[si] = CosString(replaced, isHex: s.isHex);
            count += _findAll(s.bytes, findBytes).length;
          }
        }
      }
      rewritten.add(op);
      i++;
    }

    if (count > 0) {
      // write the new glyphs' widths and Unicode values into the composite
      // fonts they were added to before re-serializing the page.
      for (final ctx in type0Cache.values) {
        if (ctx != null && ctx.isDirty) ctx.commit();
      }
      ops
        ..clear()
        ..addAll(rewritten);
      _setContent(page, elements.serialize());
    }
    return count;
  }

  /// [s] as Latin-1 bytes, or null when it has a code unit past 0xFF (the
  /// simple-font path can't represent it; the composite path uses the string
  /// directly).
  static Uint8List? _tryLatin1(String s) {
    for (final unit in s.codeUnits) {
      if (unit > 0xFF) return null;
    }
    return Uint8List.fromList(s.codeUnits);
  }

  static bool _isType0(CosDocument cos, CosDictionary? font) {
    if (font == null) return false;
    final subtype = cos.resolve(font['Subtype']);
    return subtype is CosName && subtype.value == 'Type0';
  }

  /// One position in a flattened run: a shown byte, or a `TJ` kern number
  /// (advance of `-kern/1000` em). Exactly one field is set.
  static List<({int? byte, double? kern})> _runCells(
      List<ContentOperation> run) {
    final cells = <({int? byte, double? kern})>[];
    for (final op in run) {
      if (op.operator == 'TJ' &&
          op.operands.isNotEmpty &&
          op.operands[0] is CosArray) {
        for (final item in (op.operands[0] as CosArray).items) {
          switch (item) {
            case CosString(:final bytes):
              for (final b in bytes) {
                cells.add((byte: b, kern: null));
              }
            case CosInteger(:final value):
              cells.add((byte: null, kern: value.toDouble()));
            case CosReal(:final value):
              cells.add((byte: null, kern: value));
            default:
              break; // names, dicts, etc. carry no advance in a TJ array
          }
        }
      } else if (op.operands.isNotEmpty && op.operands[0] is CosString) {
        for (final b in (op.operands[0] as CosString).bytes) {
          cells.add((byte: b, kern: null));
        }
      }
    }
    return cells;
  }

  /// Rewrites one run of show operators, replacing [findBytes] with
  /// [replaceBytes] across its strings. Returns the operations to emit in
  /// the run's place (the originals untouched when nothing matched) and the
  /// number of replacements.
  (List<ContentOperation>, int) _rewriteTextRun(List<ContentOperation> run,
      CosDictionary? font, List<int> findBytes, List<int> replaceBytes) {
    if (_isType0(document.cos, font)) return (run, 0);

    final cells = _runCells(run);
    final charCell = <int>[]; // logical char index -> cell index
    final logical = <int>[];
    for (var c = 0; c < cells.length; c++) {
      if (cells[c].byte case final int b) {
        charCell.add(c);
        logical.add(b);
      }
    }
    final matches = _findAll(logical, findBytes);
    if (matches.isEmpty) return (run, 0);

    final widthOf = _widthsFor(font);
    final totalChars = logical.length;
    final out = <({int? byte, double? kern})>[];
    var count = 0;
    var cell = 0;
    var m = 0;
    while (cell < cells.length) {
      if (m < matches.length && cell == charCell[matches[m].$1]) {
        final (start, end) = matches[m];
        final last = charCell[end - 1];
        // advance the matched span covers, kern numbers inside it included
        var oldWidth = 0.0;
        for (var k = cell; k <= last; k++) {
          oldWidth +=
              cells[k].byte != null ? widthOf(cells[k].byte!) : -cells[k].kern!;
        }
        var newWidth = 0.0;
        for (final b in replaceBytes) {
          out.add((byte: b, kern: null));
          newWidth += widthOf(b);
        }
        // keep the rest of the line put when text still follows the match
        if (end < totalChars && (newWidth - oldWidth).abs() >= 0.001) {
          out.add((byte: null, kern: newWidth - oldWidth));
        }
        count++;
        cell = last + 1;
        m++;
      } else {
        out.add(cells[cell]);
        cell++;
      }
    }

    // coalesce cells back into TJ array items, merging adjacent kerns
    final items = <CosObject>[];
    final buffer = <int>[];
    var kern = 0.0;
    void flushString() {
      if (buffer.isNotEmpty) {
        items.add(CosString(Uint8List.fromList(buffer)));
        buffer.clear();
      }
    }

    void flushKern() {
      if (kern.abs() >= 0.001) items.add(_numberObject(kern));
      kern = 0;
    }

    for (final c in out) {
      if (c.byte case final int b) {
        flushKern();
        buffer.add(b);
      } else {
        flushString();
        kern += c.kern!;
      }
    }
    flushString();
    flushKern();

    // a single Tj whose result is one plain string stays a Tj, so simple
    // corrections still serialize as `(text) Tj`
    if (run.length == 1 &&
        run[0].operator == 'Tj' &&
        items.length == 1 &&
        items[0] is CosString) {
      final original = run[0].operands[0];
      run[0].operands[0] = CosString((items[0] as CosString).bytes,
          isHex: original is CosString && original.isHex);
      return (run, count);
    }
    return ([
      ContentOperation('TJ', [CosArray(items)])
    ], count);
  }

  /// An advance-width lookup (thousandths of an em) for [font]: its own
  /// /Widths when present, else base-14 metrics keyed off /BaseFont,
  /// falling back to Helvetica.
  double Function(int code) _widthsFor(CosDictionary? font) {
    final cos = document.cos;
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
        if (standard != null) return (code) => standard.widthOf(code).toDouble();
      }
    }
    return (code) => PdfStandardFont.helvetica.widthOf(code).toDouble();
  }

  static CosObject _numberObject(double value) {
    final rounded = double.parse(value.toStringAsFixed(3));
    return rounded == rounded.roundToDouble()
        ? CosInteger(rounded.toInt())
        : CosReal(rounded);
  }

  /// Non-overlapping byte matches of [needle] in [haystack] as `(start,
  /// end)` index ranges, scanning left to right.
  static List<(int, int)> _findAll(List<int> haystack, List<int> needle) {
    final out = <(int, int)>[];
    var i = 0;
    outer:
    while (i + needle.length <= haystack.length) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          i++;
          continue outer;
        }
      }
      out.add((i, i + needle.length));
      i += needle.length;
    }
    return out;
  }

  static Uint8List? _replaceBytes(
      Uint8List source, List<int> find, List<int> replace) {
    final out = BytesBuilder();
    var copied = 0;
    var found = false;
    outer:
    for (var i = 0; i + find.length <= source.length; i++) {
      for (var j = 0; j < find.length; j++) {
        if (source[i + j] != find[j]) continue outer;
      }
      out
        ..add(Uint8List.sublistView(source, copied, i))
        ..add(replace);
      copied = i + find.length;
      i = copied - 1;
      found = true;
    }
    if (!found) return null;
    out.add(Uint8List.sublistView(source, copied));
    return out.takeBytes();
  }

  static double _num(CosObject o) => switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0,
      };

  /// The page's own /Resources dictionary, materializing a private copy
  /// when the current one is inherited (mutating a shared ancestor's
  /// resources would bleed into sibling pages).
  CosDictionary _ownResources(PdfPage page) {
    final cos = document.cos;
    final direct = page.dict['Resources'];
    if (direct != null) {
      final resolved = cos.resolve(direct);
      if (resolved is CosDictionary) {
        if (direct is CosReference) {
          // shared via reference: replace with a private copy
          final copy = CosDictionary({...resolved.entries});
          page.dict['Resources'] = copy;
          _updater.markChanged(page.dict);
          return copy;
        }
        return resolved;
      }
    }
    final copy = CosDictionary({...page.resources.entries});
    page.dict['Resources'] = copy;
    _updater.markChanged(page.dict);
    return copy;
  }

  /// Wraps the existing content in q/Q (once per editor session) and
  /// appends [bytes] as a fresh stream in the /Contents array.
  void _appendContent(PdfPage page, Uint8List bytes) {
    final cos = document.cos;
    final dict = page.dict;
    if (!_wrappedPages.contains(dict)) {
      _wrappedPages.add(dict);
      final existing = dict['Contents'];
      final items = switch (cos.resolve(existing)) {
        CosArray(:final items) => List<CosObject>.of(items),
        CosStream() => <CosObject>[existing!],
        _ => <CosObject>[],
      };
      dict['Contents'] = CosArray([
        _updater.addObject(_stream('q\n')),
        ...items,
        _updater.addObject(_stream('Q\n')),
      ]);
    }
    final contents = cos.resolve(dict['Contents']) as CosArray;
    contents.items.add(_updater.addObject(CosStream(
        CosDictionary({'Length': CosInteger(bytes.length)}), bytes)));
    _updater.markChanged(dict);
  }

  /// Replaces the page's entire content with one new stream.
  void _setContent(PdfPage page, Uint8List bytes) {
    page.dict['Contents'] = _updater.addObject(CosStream(
        CosDictionary({'Length': CosInteger(bytes.length)}), bytes));
    _updater.markChanged(page.dict);
    _wrappedPages.remove(page.dict);
  }

  static CosStream _stream(String text) {
    final bytes = Uint8List.fromList(latin1.encode(text));
    return CosStream(
        CosDictionary({'Length': CosInteger(bytes.length)}), bytes);
  }
}

/// Drawing surface handed to [PdfContentEditing.stampPage]: high-level
/// helpers plus the raw [content] writer for anything else. Coordinates
/// are PDF user space (origin bottom-left).
class PdfStamp {
  PdfStamp._(this._editor, this.page, this._resources);

  final PdfEditor _editor;

  /// The page being stamped, for measuring against its boxes.
  final PdfPage page;

  final CosDictionary _resources;

  /// The underlying operator writer, for drawing beyond the helpers.
  final ContentWriter content = ContentWriter();

  /// Draws [text] at ([x], [y]) (baseline origin) in Helvetica.
  /// [color] is 0xRRGGBB. [angleDegrees] rotates around the origin.
  void text(
    String text, {
    required double x,
    required double y,
    double size = 12,
    int color = 0x000000,
    bool bold = false,
    double angleDegrees = 0,
  }) {
    final font = _helveticaResource(bold: bold);
    content.save();
    if (angleDegrees != 0) {
      final r = angleDegrees * math.pi / 180;
      content.concatMatrix(
          math.cos(r), math.sin(r), -math.sin(r), math.cos(r), x, y);
      content.beginText();
      content.font(font, size);
      content.fillColor(color);
      content.textAt(0, 0);
    } else {
      content.beginText();
      content.font(font, size);
      content.fillColor(color);
      content.textAt(x, y);
    }
    content.showText(text);
    content.endText();
    content.restore();
  }

  /// Measures [text] as [PdfStamp.text] would draw it.
  double measureText(String text, {double size = 12, bool bold = false}) =>
      measureHelvetica(text, size, bold: bold);

  /// Draws a rectangle. Provide [fillColor] and/or [strokeColor]
  /// (0xRRGGBB); omitting both draws nothing.
  void rect(
    double x,
    double y,
    double width,
    double height, {
    int? fillColor,
    int? strokeColor,
    double lineWidth = 1,
  }) {
    if (fillColor == null && strokeColor == null) return;
    content.save();
    if (fillColor != null) content.fillColor(fillColor);
    if (strokeColor != null) {
      content.strokeColor(strokeColor);
      content.lineWidth(lineWidth);
    }
    content.rect(x, y, width, height);
    content.op(fillColor != null
        ? (strokeColor != null ? 'B' : 'f')
        : 'S');
    content.restore();
  }

  /// Places a JPEG (baseline or progressive; gray or RGB) with its
  /// bottom-left corner at ([x], [y]). When only one of [width]/[height]
  /// is given the other follows the image's aspect ratio; with neither,
  /// one pixel maps to one point.
  void jpegImage(
    Uint8List jpeg, {
    required double x,
    required double y,
    double? width,
    double? height,
  }) =>
      image(PdfEmbeddableImage.jpeg(jpeg),
          x: x, y: y, width: width, height: height);

  /// Places a decoded [PdfEmbeddableImage] (JPEG or PNG — including PNG
  /// transparency) with its bottom-left corner at ([x], [y]). Sizing
  /// follows the [jpegImage] rules.
  void image(
    PdfEmbeddableImage img, {
    required double x,
    required double y,
    double? width,
    double? height,
  }) {
    final w = width ??
        (height == null
            ? img.width.toDouble()
            : height * img.width / img.height);
    final h = height ?? w * img.height / img.width;

    final name = _freeName(_xobjects, 'Im');
    _xobjects[name] = _editor._updater.addObject(
        img.toXObject((smask) => _editor._updater.addObject(smask)));

    content.save();
    content.concatMatrix(w, 0, 0, h, x, y);
    content.drawXObject(name);
    content.restore();
  }

  CosDictionary get _xobjects => _subDictionary('XObject');

  CosDictionary _subDictionary(String key) {
    final cos = _editor.document.cos;
    final existing = cos.resolve(_resources[key]);
    if (existing is CosDictionary && _resources[key] is! CosReference) {
      return existing;
    }
    final copy = CosDictionary(
        {if (existing is CosDictionary) ...existing.entries});
    _resources[key] = copy;
    return copy;
  }

  String _helveticaResource({required bool bold}) {
    final fonts = _subDictionary('Font');
    final base = bold ? 'Helvetica-Bold' : 'Helvetica';
    // reuse a matching font this stamp already added
    for (final entry in fonts.entries.entries) {
      final font = _editor.document.cos.resolve(entry.value);
      if (font is CosDictionary &&
          font['BaseFont'] == CosName(base) &&
          font['Encoding'] == const CosName('WinAnsiEncoding')) {
        return entry.key;
      }
    }
    final name = _freeName(fonts, 'StF');
    fonts[name] = _editor._updater.addObject(CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type1'),
      'BaseFont': CosName(base),
      'Encoding': const CosName('WinAnsiEncoding'),
    }));
    return name;
  }

  static String _freeName(CosDictionary dict, String prefix) {
    var i = 1;
    while (dict.containsKey('$prefix$i')) {
      i++;
    }
    return '$prefix$i';
  }
}

