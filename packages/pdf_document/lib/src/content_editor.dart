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

  /// Region erasing. Removes the part of every bounded element that falls
  /// inside [rect]. Elements fully contained by [rect] are deleted; elements
  /// that cross the rectangle are preserved under a clipping path that covers
  /// the rest of the page, so content outside the drag area remains visible.
  /// Returns how many elements were deleted or clipped.
  int eraseElementsInRect(PdfPageElements elements, PdfRect rect) {
    final page = document.page(elements.pageIndex);
    final pageBox = page.cropBox;
    final erase = rect.intersect(pageBox);
    if (erase.width <= 0 || erase.height <= 0) return 0;

    final clip = _outsideRectClip(pageBox, erase);
    final drop = <int>{};
    final replacements = <int, String>{};
    final prefixes = <int, String>{};
    final suffixes = <int, String>{};
    var changed = 0;

    for (final element in elements.elements) {
      final bounds = element.bounds;
      if (bounds == null || !_intersects(bounds, erase)) continue;
      changed++;
      if (_containsRect(erase, bounds) || clip == null) {
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
      } else {
        prefixes[element.start] = 'q\n$clip';
        suffixes[element.end - 1] = 'Q\n';
      }
    }

    if (changed == 0) return 0;
    _setContent(
        page,
        elements.serialize(
            drop: drop,
            replacements: replacements,
            prefixes: prefixes,
            suffixes: suffixes));
    return changed;
  }

  static bool _intersects(PdfRect a, PdfRect b) {
    final hit = a.intersect(b);
    return hit.width > 0 && hit.height > 0;
  }

  static bool _containsRect(PdfRect outer, PdfRect inner) =>
      outer.left <= inner.left &&
      outer.bottom <= inner.bottom &&
      outer.right >= inner.right &&
      outer.top >= inner.top;

  static String? _outsideRectClip(PdfRect page, PdfRect erase) {
    final out = StringBuffer();

    void addRect(double x, double y, double w, double h) {
      if (w <= 0 || h <= 0) return;
      out.writeln('${ContentWriter.fmt(x)} ${ContentWriter.fmt(y)} '
          '${ContentWriter.fmt(w)} ${ContentWriter.fmt(h)} re');
    }

    addRect(page.left, page.bottom, erase.left - page.left, page.height);
    addRect(erase.right, page.bottom, page.right - erase.right, page.height);
    addRect(erase.left, page.bottom, erase.width, erase.bottom - page.bottom);
    addRect(erase.left, erase.top, erase.width, page.top - erase.top);
    if (out.isEmpty) return null;
    out.write('W n\n');
    return out.toString();
  }

  /// Tier 3 — text editing. Replaces occurrences of [find] with [replace]
  /// inside individual text-showing operations on page [index] and
  /// returns how many were rewritten.
  ///
  /// Honest limitations: the match must fall entirely inside one shown
  /// string; only simple single-byte fonts qualify (composite /Type0
  /// runs are skipped — their bytes are glyph indexes, not characters);
  /// both strings must be Latin-1; and glyphs are not re-measured, so
  /// replacing with a longer string can collide with whatever follows on
  /// the line. Good for short corrections, not for reflowing paragraphs.
  int replaceText(int index, String find, String replace) {
    if (find.isEmpty) throw ArgumentError.value(find, 'find', 'is empty');
    final findBytes = latin1.encode(find);
    final replaceBytes = latin1.encode(replace);

    final page = document.page(index);
    final elements = PdfPageElements.of(document, index);
    final cos = document.cos;
    final fonts = cos.resolve(page.resources['Font']);

    // fonts whose strings are single-byte character codes
    bool replaceable(String? fontName) {
      if (fontName == null) return true; // no Tf seen — assume simple
      if (fonts is! CosDictionary) return true;
      final font = cos.resolve(fonts[fontName]);
      if (font is! CosDictionary) return true;
      final subtype = cos.resolve(font['Subtype']);
      return !(subtype is CosName && subtype.value == 'Type0');
    }

    var count = 0;
    var fontName = _firstFontOf(elements.operations);
    for (final op in elements.operations) {
      if (op.operator == 'Tf' && op.operands.isNotEmpty) {
        final name = op.operands[0];
        if (name is CosName) fontName = name.value;
        continue;
      }
      final isShow = switch (op.operator) {
        'Tj' || "'" || '"' || 'TJ' => true,
        _ => false,
      };
      if (!isShow || !replaceable(fontName)) continue;

      void patch(CosString string, void Function(CosString) write) {
        final replaced = _replaceBytes(string.bytes, findBytes, replaceBytes);
        if (replaced == null) return;
        write(CosString(replaced, isHex: string.isHex));
        count++;
      }

      if (op.operator == 'TJ' && op.operands.isNotEmpty) {
        final array = op.operands[0];
        if (array is! CosArray) continue;
        for (var i = 0; i < array.items.length; i++) {
          if (array.items[i] case final CosString s) {
            patch(s, (replacement) => array.items[i] = replacement);
          }
        }
      } else {
        final stringIndex = op.operator == '"' ? 2 : 0;
        if (op.operands.length > stringIndex &&
            op.operands[stringIndex] is CosString) {
          patch(op.operands[stringIndex] as CosString,
              (replacement) => op.operands[stringIndex] = replacement);
        }
      }
    }
    if (count > 0) _setContent(page, elements.serialize());
    return count;
  }

  static String? _firstFontOf(List<ContentOperation> operations) {
    for (final op in operations) {
      if (op.operator == 'Tf' && op.operands.isNotEmpty) {
        final name = op.operands[0];
        return name is CosName ? name.value : null;
      }
    }
    return null;
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
    contents.items.add(_updater.addObject(
        CosStream(CosDictionary({'Length': CosInteger(bytes.length)}), bytes)));
    _updater.markChanged(dict);
  }

  /// Replaces the page's entire content with one new stream.
  void _setContent(PdfPage page, Uint8List bytes) {
    page.dict['Contents'] = _updater.addObject(
        CosStream(CosDictionary({'Length': CosInteger(bytes.length)}), bytes));
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
    content.op(fillColor != null ? (strokeColor != null ? 'B' : 'f') : 'S');
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
    _xobjects[name] = _editor._updater
        .addObject(img.toXObject((smask) => _editor._updater.addObject(smask)));

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
    final copy =
        CosDictionary({if (existing is CosDictionary) ...existing.entries});
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
