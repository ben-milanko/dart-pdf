part of 'editor.dart';

/// A uniform style override applied to the replacement text of
/// [PdfContentEditing.replaceText] / [PdfContentEditing.replaceStyledText].
///
/// Each field left null keeps the matched run's existing value for that
/// attribute, so `PdfTextStyle(color: 0xFF0000)` recolours a replacement
/// while leaving its font and size untouched. Styling is applied to
/// simple-font (non-/Type0) text runs; composite runs are still replaced
/// but keep their original colour, size, and face.
class PdfTextStyle {
  const PdfTextStyle({
    this.color,
    this.fontSize,
    this.family,
    this.embeddedFont,
    this.bold,
    this.italic,
  });

  /// Nonstroking fill colour as `0xRRGGBB`, or null to keep the run's colour.
  final int? color;

  /// Font size in points, or null to keep the run's size.
  final double? fontSize;

  /// Switch the replacement to a base-14 family (sans/serif/mono), or null to
  /// keep the run's family. Like [bold]/[italic] this substitutes a base-14
  /// face (Helvetica/Times/Courier), so it lands even when the original is an
  /// embedded font. Ignored when [embeddedFont] is set.
  final PdfStandardFontFamily? family;

  /// Draw the replacement in this embedded font, embedding it into the page
  /// (as an Identity-H composite) so any of its glyphs render everywhere.
  /// Takes precedence over [family]/[bold]/[italic]. Null keeps the run's own
  /// face (subject to [family]/[bold]/[italic]). Falls back to the base-14
  /// path when the font can't draw the whole replacement.
  final PdfEmbeddedFont? embeddedFont;

  /// Force bold on (`true`) or off (`false`), or null to keep the run's
  /// weight. A weight/slant/[family] change substitutes a base-14 variant
  /// chosen to match the run's family (unless [family] overrides it), so it
  /// lands even when the original face is embedded and has no bold cut.
  final bool? bold;

  /// Force italic/oblique on (`true`) or off (`false`), or null to keep the
  /// run's slant.
  final bool? italic;

  /// True when no attribute is set - a plain replacement, styled like the
  /// text it replaces.
  bool get isEmpty =>
      color == null &&
      fontSize == null &&
      family == null &&
      embeddedFont == null &&
      bold == null &&
      italic == null;

  @override
  bool operator ==(Object other) =>
      other is PdfTextStyle &&
      other.color == color &&
      other.fontSize == fontSize &&
      other.family == family &&
      identical(other.embeddedFont, embeddedFont) &&
      other.bold == bold &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(
        color,
        fontSize,
        family,
        identityHashCode(embeddedFont),
        bold,
        italic,
      );
}

/// Tracks an embedded font used by a styled replacement across the runs of
/// one [PdfContentEditing.replaceText] call: its page /Font resource name
/// (allocated lazily on first use) so [PdfEmbeddedFont.buildResource] can be
/// flushed once at the end.
class _StyledEmbed {
  _StyledEmbed(this.font);
  final PdfEmbeddedFont font;
  String? name;
}

/// Content editing tiers: stamping new content, deleting elements, and
/// replacing text runs.
extension PdfContentEditing on PdfEditor {
  /// Tier 1 - stamping. Draws new content on top of page [index] via
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
    _appendContent(index, page, wrapped.takeBytes());
  }

  /// Tier 2 - element deletion. Removes the [ids] listed in [elements]
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
      elements.pageIndex,
      page,
      elements.serialize(drop: drop, replacements: replacements),
    );
  }

  /// Tier 2b - element repositioning. Shifts the [ids] listed in [elements]
  /// (a snapshot from [PdfPageElements.of]) by [dx], [dy] **page points**
  /// and rewrites the page's content stream. Returns how many elements
  /// actually moved.
  ///
  /// The drawing is left exactly as it was - same operators, same operands,
  /// same resources - and only the space it draws in is shifted, so a
  /// rotated logo stays rotated and a scaled image keeps its scale. Paths,
  /// images, forms, inline images and shadings are bracketed with
  /// `q`/`cm`…`Q`; a text run gets a `Tm` in front of it and a `Tm`
  /// behind, putting the text object's own state back so the rest of the
  /// line - and every `Td`/`T*` after it - lands where it did before. Where
  /// a following run shares the line, the moved run's advance is replayed
  /// as a kern-only `TJ` so its neighbours do not slide.
  ///
  /// An element is skipped (and not counted) when it cannot be shifted
  /// safely: a degenerate transform with no inverse, a path that also
  /// establishes a clip (`W`/`W*` - bracketing it would confine the clip to
  /// the moved drawing), or a text run at font size 0.
  ///
  /// Element ids survive the rewrite: the splices are `q`/`cm`/`Q`/`Tm` and
  /// kern-only `TJ` operators, none of which is a drawing, so re-reading the
  /// page with [PdfPageElements.of] yields the same elements in the same
  /// order. Note that this repositions the *drawing*, not the text flow: a
  /// moved run does not re-wrap, and moving it out from under a clip or a
  /// tiling pattern's phase can change what it looks like.
  int moveElements(
    PdfPageElements elements,
    Iterable<int> ids, {
    required double dx,
    required double dy,
  }) {
    final page = document.page(elements.pageIndex);
    final before = <int, String>{};
    final after = <int, String>{};
    var moved = 0;
    for (final id in ids) {
      if (id < 0 || id >= elements.elements.length) {
        throw RangeError.range(id, 0, elements.elements.length - 1, 'ids');
      }
      final element = elements.elements[id];
      if (before.containsKey(element.start)) continue; // a repeated id
      if (dx == 0 && dy == 0) continue;
      final delta = translationUnder(element.ctm, dx, dy);
      if (delta == null) continue;
      if (element.kind == PdfElementKind.text) {
        final placement = element.textPlacement;
        if (placement == null || placement.fontSize <= 0) continue;
        // `'` and `"` perform their own `T*` after this `Tm`, so they are
        // seeded with the matrix the operator *enters* on and left to do the
        // line move; everything else is seeded with the run's own matrix, so
        // a run that starts partway along its line stays there.
        final operator = elements.operations[element.start].operator;
        final seed = operator == "'" || operator == '"'
            ? placement.entryLineMatrix
            : placement.matrix;
        before[element.start] = '${_matrixOperands(seed.concat(delta))} Tm';
        // Put the text state back: the line matrix exactly (so a following
        // `Td`/`T*` still measures from the real line), then the run's own
        // advance as a kern-only `TJ` so a neighbour sharing the line starts
        // where it did. `Tm` is the only operator that sets the text matrix,
        // and it always resets the line matrix with it - hence the two steps.
        final restore =
            StringBuffer('${_matrixOperands(placement.lineMatrix)} Tm');
        final advance = placement.advance + _lineAdvance(placement);
        if (advance.abs() > 1e-9) {
          final kern = -1000 * advance / placement.fontSize;
          restore.write(' [ ${ContentWriter.fmt(kern)} ] TJ');
        }
        after[element.start] = restore.toString();
      } else {
        if (_establishesClip(elements, element)) continue;
        before[element.start] = 'q ${_matrixOperands(delta)} cm';
        after[element.end - 1] = 'Q';
      }
      moved++;
    }
    if (moved == 0) return 0;
    _setContent(
      elements.pageIndex,
      page,
      elements.serialize(before: before, after: after),
    );
    return moved;
  }

  /// Moves the [ids] from [elements]' source page into [targetPage], mapping
  /// their source-page coordinates through [transform]. Returns how many
  /// elements moved.
  ///
  /// Unlike wrapping the drawing in a Form XObject, this appends the original
  /// operators to the destination page. A text run therefore remains a text
  /// run, an image remains an image, and the content tool can keep editing the
  /// dropped element. Graphics-state operators needed by the drawing travel
  /// with it; the source page is rewritten with the same stand-ins
  /// [PdfPageElements.operationsRetaining] uses for a drag preview, so text
  /// following a moved run holds its position.
  ///
  /// Page resource names are local to a page. Referenced fonts, XObjects,
  /// colour spaces, patterns, shadings, graphics states, and marked-content
  /// properties are imported into the target under non-conflicting names and
  /// the appended operators are remapped to those names. The resource objects
  /// themselves stay shared within this document; only the page dictionaries
  /// and content streams are rewritten.
  ///
  /// [transform] maps source page user space onto target page user space. A
  /// simple same-orientation move is a [PdfMatrix.translation]. A viewer
  /// moving between differently rotated pages can supply the corresponding
  /// rotation-and-translation so the drawing keeps its displayed orientation.
  int moveElementsToPage(
    PdfPageElements elements,
    Iterable<int> ids,
    int targetPage, {
    required PdfMatrix transform,
  }) {
    if (targetPage < 0 || targetPage >= document.pageCount) {
      throw RangeError.range(
          targetPage, 0, document.pageCount - 1, 'targetPage');
    }
    if (targetPage == elements.pageIndex) {
      final origin = transform.apply(0, 0);
      final xAxis = transform.apply(1, 0);
      final yAxis = transform.apply(0, 1);
      final translationOnly = (xAxis.$1 - origin.$1 - 1).abs() < 1e-9 &&
          (xAxis.$2 - origin.$2).abs() < 1e-9 &&
          (yAxis.$1 - origin.$1).abs() < 1e-9 &&
          (yAxis.$2 - origin.$2 - 1).abs() < 1e-9;
      if (!translationOnly) {
        throw ArgumentError.value(
            transform, 'transform', 'a same-page move must be a translation');
      }
      return moveElements(
        elements,
        ids,
        dx: origin.$1,
        dy: origin.$2,
      );
    }

    final moving = <int>{};
    for (final id in ids) {
      if (id < 0 || id >= elements.elements.length) {
        throw RangeError.range(id, 0, elements.elements.length - 1, 'ids');
      }
      final element = elements.elements[id];
      if (!_canMoveElement(elements, element)) continue;
      moving.add(id);
    }
    if (moving.isEmpty) return 0;

    final source = document.page(elements.pageIndex);
    final target = document.page(targetPage);
    final sourceOps = elements.operationsRetaining(
      (element) => moving.contains(element.id),
    );
    final resourceNames = _importContentResources(source, target, sourceOps);
    final movedOps = [
      for (final op in sourceOps) _remapContentResources(op, resourceNames),
    ];
    final movedBytes = BytesBuilder(copy: false)
      ..add(latin1.encode('q ${_matrixOperands(transform)} cm\n'))
      ..add(ContentStreamSerializer.serialize(movedOps))
      ..add(latin1.encode('Q\n'));

    _setContent(
      elements.pageIndex,
      source,
      ContentStreamSerializer.serialize(
        elements.operationsRetaining((element) => !moving.contains(element.id)),
      ),
    );
    _appendContent(targetPage, target, movedBytes.takeBytes());
    return moving.length;
  }

  static bool _canMoveElement(
      PdfPageElements elements, PdfContentElement element) {
    if (element.ctm.inverted() == null) return false;
    if (element.kind == PdfElementKind.text) {
      final placement = element.textPlacement;
      return placement != null && placement.fontSize > 0;
    }
    return !_establishesClip(elements, element);
  }

  /// Imports the page resources referenced by [operations] and returns their
  /// source-name -> target-name maps, keyed by resource category.
  Map<String, Map<String, String>> _importContentResources(
    PdfPage source,
    PdfPage target,
    List<ContentOperation> operations,
  ) {
    final references = _contentResourceReferences(operations);
    if (references.isEmpty) return const {};
    final cos = document.cos;
    final sourceResources = source.resources;
    final targetResources = _ownResources(target);
    final out = <String, Map<String, String>>{};
    const prefixes = {
      'Font': 'MvF',
      'XObject': 'MvX',
      'ExtGState': 'MvG',
      'ColorSpace': 'MvC',
      'Pattern': 'MvP',
      'Shading': 'MvS',
      'Properties': 'MvR',
    };

    bool sameResource(CosObject a, CosObject b) {
      if (a == b) return true;
      try {
        return identical(cos.resolve(a), cos.resolve(b));
      } catch (_) {
        return false;
      }
    }

    for (final category in references.entries) {
      final sourceCategory = cos.resolve(sourceResources[category.key]);
      final targetCategory = cos.resolve(targetResources[category.key]);
      final targetEntries = targetCategory is CosDictionary
          ? CosDictionary({...targetCategory.entries})
          : CosDictionary();
      final names = <String, String>{};
      final reserved = <String>{...targetEntries.entries.keys};
      var changed = false;

      String freshName() {
        final prefix = prefixes[category.key] ?? 'MvR';
        var i = 1;
        while (!reserved.add('$prefix$i')) {
          i++;
        }
        return '$prefix$i';
      }

      for (final sourceName in category.value) {
        final sourceValue =
            sourceCategory is CosDictionary ? sourceCategory[sourceName] : null;
        String? targetName;
        if (sourceValue != null) {
          for (final entry in targetEntries.entries.entries) {
            if (sameResource(sourceValue, entry.value)) {
              targetName = entry.key;
              break;
            }
          }
        }
        if (targetName == null && sourceValue != null) {
          targetName =
              targetEntries.containsKey(sourceName) ? freshName() : sourceName;
          reserved.add(targetName);
          targetEntries[targetName] = sourceValue;
          changed = true;
        } else {
          // Preserve a missing source resource as missing. If the target has
          // a resource under that name, remap to an unused name rather than
          // accidentally changing the drawing's meaning.
          targetName ??=
              targetEntries.containsKey(sourceName) ? freshName() : sourceName;
        }
        names[sourceName] = targetName;
      }
      if (changed) targetResources[category.key] = targetEntries;
      out[category.key] = names;
    }
    return out;
  }

  static Map<String, Set<String>> _contentResourceReferences(
      List<ContentOperation> operations) {
    final out = <String, Set<String>>{};
    void add(String category, CosObject? value) {
      if (value case CosName(:final value)) {
        (out[category] ??= <String>{}).add(value);
      }
    }

    for (final op in operations) {
      final operands = op.operands;
      switch (op.operator) {
        case 'Tf':
          if (operands.isNotEmpty) add('Font', operands.first);
        case 'Do':
          if (operands.isNotEmpty) add('XObject', operands.first);
        case 'gs':
          if (operands.isNotEmpty) add('ExtGState', operands.first);
        case 'CS' || 'cs':
          if (operands.isNotEmpty && operands.first is CosName) {
            final name = (operands.first as CosName).value;
            if (!const {'DeviceGray', 'DeviceRGB', 'DeviceCMYK', 'Pattern'}
                .contains(name)) {
              add('ColorSpace', operands.first);
            }
          }
        case 'SCN' || 'scn':
          if (operands.isNotEmpty) add('Pattern', operands.last);
        case 'sh':
          if (operands.isNotEmpty) add('Shading', operands.first);
        case 'BDC' || 'DP':
          if (operands.length >= 2) add('Properties', operands[1]);
        case 'BI':
          if (operands.isNotEmpty && operands.first is CosDictionary) {
            final dict = operands.first as CosDictionary;
            final colorSpace = dict['CS'] ?? dict['ColorSpace'];
            if (colorSpace is! CosName ||
                !const {'G', 'RGB', 'CMYK', 'I'}.contains(colorSpace.value)) {
              add('ColorSpace', colorSpace);
            }
          }
      }
    }
    return out;
  }

  static ContentOperation _remapContentResources(
    ContentOperation op,
    Map<String, Map<String, String>> names,
  ) {
    CosObject rename(String category, CosObject value) {
      if (value is! CosName) return value;
      final renamed = names[category]?[value.value];
      return renamed == null || renamed == value.value
          ? value
          : CosName(renamed);
    }

    final operands = List<CosObject>.of(op.operands);
    switch (op.operator) {
      case 'Tf':
        if (operands.isNotEmpty) operands[0] = rename('Font', operands[0]);
      case 'Do':
        if (operands.isNotEmpty) operands[0] = rename('XObject', operands[0]);
      case 'gs':
        if (operands.isNotEmpty) {
          operands[0] = rename('ExtGState', operands[0]);
        }
      case 'CS' || 'cs':
        if (operands.isNotEmpty) {
          operands[0] = rename('ColorSpace', operands[0]);
        }
      case 'SCN' || 'scn':
        if (operands.isNotEmpty) {
          operands[operands.length - 1] = rename('Pattern', operands.last);
        }
      case 'sh':
        if (operands.isNotEmpty) operands[0] = rename('Shading', operands[0]);
      case 'BDC' || 'DP':
        if (operands.length >= 2) {
          operands[1] = rename('Properties', operands[1]);
        }
      case 'BI':
        if (operands.isNotEmpty && operands.first is CosDictionary) {
          final original = operands.first as CosDictionary;
          final dict = CosDictionary({...original.entries});
          if (dict['CS'] case final value?) {
            if (value is! CosName ||
                !const {'G', 'RGB', 'CMYK', 'I'}.contains(value.value)) {
              dict['CS'] = rename('ColorSpace', value);
            }
          }
          if (dict['ColorSpace'] case final value?) {
            if (value is! CosName ||
                !const {'G', 'RGB', 'CMYK', 'I'}.contains(value.value)) {
              dict['ColorSpace'] = rename('ColorSpace', value);
            }
          }
          operands[0] = dict;
        }
    }
    return ContentOperation(op.operator, operands);
  }

  /// How far into its line the run already sits: the text matrix differs
  /// from the line matrix only by the advances of the runs before it, so
  /// `matrix × lineMatrix⁻¹` is that pure translation.
  static double _lineAdvance(PdfTextPlacement placement) {
    final inverse = placement.lineMatrix.inverted();
    if (inverse == null) return 0;
    return placement.matrix.concat(inverse).e;
  }

  /// Whether [element]'s operations also make a clipping path. Bracketing
  /// such a run in `q`…`Q` would drop the clip the rest of the page expects.
  static bool _establishesClip(
      PdfPageElements elements, PdfContentElement element) {
    for (var i = element.start; i < element.end; i++) {
      final operator = elements.operations[i].operator;
      if (operator == 'W' || operator == 'W*') return true;
    }
    return false;
  }

  static String _matrixOperands(PdfMatrix m) => [
        for (final value in m.toList()) ContentWriter.fmt(value),
      ].join(' ');

  /// Tier 3 - text editing. Replaces occurrences of [find] with [replace]
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
  /// [_Type0RunEditor]). A Type0 run is left untouched when it can't be safely
  /// round-tripped (CFF descendant, stream /CIDToGIDMap, non-Identity-H
  /// encoding, missing program/ToUnicode, or a character the font lacks).
  ///
  /// Simple (byte-coded) fonts are read and written through their own
  /// encoding too ([SimpleFont]): `/ToUnicode` and `/Encoding`
  /// `/Differences` decide what a code reads as, so [find] and [replace] are
  /// the text on the page rather than the raw bytes drawing it, and a subset
  /// that renumbered its codes round-trips correctly. A simple-font run is
  /// left untouched when the font declares no code for one of [replace]'s
  /// characters - a subsetted face physically lacks the glyph, and writing
  /// the character's ASCII byte anyway would draw a different one.
  ///
  /// Remaining limitation: matches do not cross a line break
  /// (`Td`/`T*`/`'`/`"`) - this corrects and re-flows within a line, it does
  /// not re-flow paragraphs.
  /// [fallbackFonts] (composite editing only) supply glyph outlines for
  /// characters the document's own /Type0 font can't draw - a subsetted
  /// embedded font physically lacks the glyphs it dropped, and this library
  /// bundles none. When given, such a replacement is drawn in the first
  /// fallback that can render it (style-matched to the document font); when
  /// omitted, an undrawable replacement leaves the run untouched.
  ///
  /// [style] applies a uniform rich-text override (fill colour, size, bold,
  /// italic) to the replacement - see [replaceStyledText], which this
  /// forwards to. Styling only affects simple-font runs; a composite
  /// (/Type0) run is still corrected but keeps its original appearance.
  int replaceText(
    int index,
    String find,
    String replace, {
    List<PdfEmbeddedFont> fallbackFonts = const [],
    PdfTextStyle? style,
  }) =>
      _replaceText(
        index,
        find,
        replace,
        fallbackFonts: fallbackFonts,
        style: style,
      );

  /// Replaces [find] only inside one text [element], leaving identical text
  /// in every other page-content operation untouched.
  ///
  /// [elements] and [element] must come from the same [PdfPageElements]
  /// snapshot. Element handles die with every edit revision. This targeted
  /// form backs selection-driven editing, where changing the occurrence the
  /// user selected must not rewrite the same word elsewhere on the page.
  int replaceElementText(
    PdfPageElements elements,
    PdfContentElement element,
    String find,
    String replace, {
    List<PdfEmbeddedFont> fallbackFonts = const [],
    PdfTextStyle? style,
  }) {
    if (element.kind != PdfElementKind.text ||
        element.id < 0 ||
        element.id >= elements.elements.length ||
        !identical(elements.elements[element.id], element)) {
      throw ArgumentError.value(
          element, 'element', 'is not a text element in this snapshot');
    }
    return _replaceText(
      elements.pageIndex,
      find,
      replace,
      fallbackFonts: fallbackFonts,
      style: style,
      operationRange: (element.start, element.end),
      // The caller already parsed the page to obtain [element]; reusing that
      // snapshot saves a second decode + full tokenization of the content
      // stream, which on a dense CAD page is the dominant cost of a
      // single-word correction (#402).
      snapshot: elements,
    );
  }

  int _replaceText(
    int index,
    String find,
    String replace, {
    required List<PdfEmbeddedFont> fallbackFonts,
    required PdfTextStyle? style,
    (int start, int end)? operationRange,
    PdfPageElements? snapshot,
  }) {
    if (find.isEmpty) throw ArgumentError.value(find, 'find', 'is empty');

    final page = document.page(index);
    // Reuse the caller's snapshot only while this session has not already
    // rewritten this page's content. A second targeted edit against a
    // pre-first-edit snapshot would serialize stale operations and silently
    // drop the earlier one - the identity check in replaceElementText proves
    // the element belongs to the snapshot, not that the snapshot is current.
    // A null contentPages means "every page" (a structural edit), so it
    // invalidates too.
    final contentPages = _impact.contentPages;
    final stale = contentPages == null || contentPages.contains(index);
    final elements =
        (stale ? null : snapshot) ?? PdfPageElements.of(document, index);
    final cos = document.cos;
    final fonts = cos.resolve(page.resources['Font']);

    CosDictionary? fontFor(String? name) {
      if (name == null || fonts is! CosDictionary) return null;
      final font = cos.resolve(fonts[name]);
      return font is CosDictionary ? font : null;
    }

    // A simple font's byte codes are only the characters by convention:
    // /Encoding /Differences and subset renumbering remap them freely, so
    // both the match and the replacement go through the font's own tables
    // ([SimpleFont]). Cached per font resource name like the composite ones.
    final simpleCache = <String?, SimpleFont>{};
    SimpleFont simpleFor(String? name, CosDictionary? f) =>
        simpleCache.putIfAbsent(name, () => SimpleFont.decode(cos, f));

    // composite (/Type0) fonts are rewritten by a separate path that decodes
    // 2-byte glyph codes - built lazily and cached per font resource name.
    final type0Cache = <String, _Type0RunEditor?>{};
    _Type0RunEditor? type0For(String name, CosDictionary f) =>
        type0Cache.putIfAbsent(
          name,
          () => _Type0RunEditor.tryCreate(this, page, name, f, fallbackFonts),
        );

    final styled = style != null && !style.isEmpty;
    // an embedded-font restyle embeds the chosen face once, after the runs
    final styledEmbed =
        style?.embeddedFont == null ? null : _StyledEmbed(style!.embeddedFont!);
    final ops = elements.operations;
    final rewritten = <ContentOperation>[];
    var count = 0;
    CosDictionary? font; // the font active at the current operation
    String? fontName; // its /Font resource key
    var fontSize = 0.0; // its size, for fallback Tf switches
    // the nonstroking colour operators active at the current operation, so a
    // styled replacement can restore them for whatever text follows it.
    var restoreColorOps = <ContentOperation>[_colorOp(0x000000)];
    ContentOperation? pendingCs; // last /cs, re-emitted before an sc/scn

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
      if (styled) {
        // track the active fill colour so styled replacements can restore it
        switch (op.operator) {
          case 'rg' || 'g' || 'k' || 'sc' || 'scn':
            restoreColorOps = op.operator == 'sc' || op.operator == 'scn'
                ? [if (pendingCs != null) pendingCs, op]
                : [op];
          case 'cs':
            pendingCs = op;
        }
      }
      if (op.operator == 'Tj' || op.operator == 'TJ') {
        // Targeted selection edits leave every show operation outside the
        // selected element byte-for-byte alone. In particular, do not merge
        // an adjacent unselected Tj/TJ into the selected run.
        if (operationRange != null &&
            (i < operationRange.$1 || i >= operationRange.$2)) {
          rewritten.add(op);
          i++;
          continue;
        }
        // a run is a maximal stretch of adjacent show operators: text
        // state (font, position) is constant across it, so the strings
        // read as one line and may be merged into a single TJ.
        final run = <ContentOperation>[];
        while (i < ops.length &&
            (ops[i].operator == 'Tj' || ops[i].operator == 'TJ') &&
            (operationRange == null || i < operationRange.$2)) {
          run.add(ops[i]);
          i++;
        }
        final simpleRewrite = styled
            ? _rewriteStyledTextRun(
                page,
                run,
                font,
                fontName,
                fontSize,
                find,
                replace,
                style,
                restoreColorOps,
                styledEmbed,
                simpleFor(fontName, font),
              )
            : _rewriteTextRun(
                run, font, find, replace, simpleFor(fontName, font));
        final (ops_, n) = _isType0(cos, font) && fontName != null
            ? (type0For(
                  fontName,
                  font!,
                )?.rewriteRun(run, find, replace, fontSize) ??
                (run, 0))
            : simpleRewrite;
        rewritten.addAll(ops_);
        count += n;
        continue;
      }
      // ' and " carry a line break, so they stand alone; a single string
      // with nothing after it on its line needs no width compensation.
      if ((op.operator == "'" || op.operator == '"') &&
          (operationRange == null ||
              (i >= operationRange.$1 && i < operationRange.$2)) &&
          !_isType0(cos, font)) {
        final si = op.operator == '"' ? 2 : 0;
        if (op.operands.length > si && op.operands[si] is CosString) {
          final simple = simpleFor(fontName, font);
          // both ends run through the font's own encoding: the codes that
          // draw `find` on this page, and the codes that will draw `replace`.
          // A font that can draw neither leaves the operator alone.
          final findBytes = simple.encode(find);
          final replaceBytes = simple.encode(replace);
          if (findBytes != null && replaceBytes != null) {
            final s = op.operands[si] as CosString;
            final replaced = _replaceBytes(s.bytes, findBytes, replaceBytes);
            if (replaced != null) {
              op.operands[si] = CosString(replaced, isHex: s.isHex);
              count += _findAll(s.bytes, findBytes).length;
            }
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
      // embed the styled replacement's font as a page /Font resource once all
      // its glyphs have been recorded.
      if (styledEmbed != null && styledEmbed.name != null) {
        final built = styledEmbed.font
            .buildResource(_updater.addObject)
            .entries
            .values
            .first;
        _ownFontResources(page)[styledEmbed.name!] = _updater.addObject(built);
      }
      ops
        ..clear()
        ..addAll(rewritten);
      _setContent(index, page, elements.serialize());
    }
    return count;
  }

  /// Replaces [find] with [replace] on page [index] and restyles the
  /// replacement per [style] (fill colour, size, bold, italic). A convenience
  /// wrapper over [replaceText] - see it for match/re-flow semantics.
  ///
  /// Styling brackets each replaced span with its own colour/`Tf` operators
  /// and restores the surrounding state afterward, so text following a
  /// styled correction on the same line keeps its own appearance and stays
  /// put (the replacement is re-measured against the styled font/size). A
  /// family/bold/italic change substitutes a base-14 face (Helvetica/Times/
  /// Courier), so it works even against embedded fonts. Styling is applied to
  /// simple-font runs only; composite (/Type0) runs are corrected without
  /// restyling.
  int replaceStyledText(
    int index,
    String find,
    String replace,
    PdfTextStyle style, {
    List<PdfEmbeddedFont> fallbackFonts = const [],
  }) =>
      replaceText(
        index,
        find,
        replace,
        fallbackFonts: fallbackFonts,
        style: style,
      );

  /// Rewrites one run of show operators like [_rewriteTextRun] but applies
  /// [style] to each replacement: the replaced bytes are drawn in their own
  /// show op bracketed by colour / `Tf` operators, then the run's prior
  /// colour ([restoreColorOps]) and font ([fontName]/[fontSize]) are put back
  /// so following text is unaffected. The replacement is re-measured against
  /// the styled font and size and a compensating `TJ` adjustment keeps the
  /// rest of the line in place.
  (List<ContentOperation>, int) _rewriteStyledTextRun(
    PdfPage page,
    List<ContentOperation> run,
    CosDictionary? font,
    String? fontName,
    double fontSize,
    String find,
    String replace,
    PdfTextStyle style,
    List<ContentOperation> restoreColorOps,
    _StyledEmbed? embed,
    SimpleFont simple,
  ) {
    if (_isType0(document.cos, font)) return (run, 0);

    final origWidthOf = simple.widthOf;

    // The styled face is resolved lazily, on the first match, by [resolve]:
    // the given embedded font (as Identity-H glyph ids) when it can render the
    // whole replacement, else a base-14 variant for a family/weight/slant
    // change, else the run's own font (only colour/size may change). Deferring
    // it means a non-matching run allocates no page /Font resource and records
    // no embedded glyphs. Drawability, which needs no side effects, is decided
    // now so an undrawable replacement leaves the run untouched.
    final runes = replace.runes.toList();
    final useEmbed =
        embed != null && runes.every((r) => embed.font.glyphForRune(r) != 0);
    // The bytes to write depend on which face ends up drawing them: a
    // substituted base-14 face is WinAnsi, so the replacement is Latin-1
    // there, while the run's own face needs its own codes ([simple]).
    final variant = _styledVariant(font, style);
    final replaceBytes =
        variant != null ? _tryLatin1(replace) : simple.encode(replace);
    if (!useEmbed && replaceBytes == null) {
      // a replacement the chosen face cannot draw has nothing safe to emit.
      return (run, 0);
    }

    _StyledFace resolve() {
      if (useEmbed) {
        // allocate the resource name (which resets the font's glyph usage)
        // before encoding, so the replacement's glyphs are the ones recorded.
        final name = _embeddedFontResource(page, embed);
        final replShow =
            CosString(_hexBytes(embed.font.encodeHex(replace)), isHex: true);
        var w = 0.0;
        for (final r in runes) {
          w += embed.font.advanceForGlyph(embed.font.glyphForRune(r));
        }
        return _StyledFace(name, replShow, w);
      }
      final String? name;
      final double Function(int) styledWidthOf;
      if (variant != null) {
        final own = _fontStandard(font);
        name = own == variant && fontName != null
            ? fontName // the run is already this exact face
            : _standardFontResource(page, variant);
        styledWidthOf = (code) => variant.widthOf(code).toDouble();
      } else {
        name = fontName;
        styledWidthOf = origWidthOf;
      }
      var w = 0.0;
      for (final b in replaceBytes!) {
        w += styledWidthOf(b);
      }
      return _StyledFace(name, CosString(Uint8List.fromList(replaceBytes)), w);
    }

    final codec = _StyledRunCodec(
      simple: simple,
      origWidthOf: origWidthOf,
      resolveFace: resolve,
      styledSize: style.fontSize ?? fontSize,
      fontSize: fontSize,
      fontName: fontName,
      colorOp: style.color == null ? null : _colorOp(style.color!),
      restoreColorOps: restoreColorOps,
    );
    return TextRunRewriter(codec).rewrite(run, find, replace);
  }

  /// The base-14 [PdfStandardFont] the /BaseFont of [font] maps to, or null
  /// when it isn't clearly one of the three standard families.
  PdfStandardFont? _fontStandard(CosDictionary? font) {
    if (font == null) return null;
    final base = document.cos.resolve(font['BaseFont']);
    return base is CosName ? PdfStandardFont.tryFromName(base.value) : null;
  }

  /// The base-14 variant a family/weight/slant change asks for: [style]'s
  /// family (or the run's own, defaulting to sans) with its bold/italic
  /// applied. Null when [style] changes none of those (colour/size only).
  PdfStandardFont? _styledVariant(CosDictionary? font, PdfTextStyle style) {
    if (style.family == null && style.bold == null && style.italic == null) {
      return null;
    }
    final base = _fontStandard(font);
    return PdfStandardFont.styled(
      style.family ?? base?.family ?? PdfStandardFontFamily.sans,
      bold: style.bold ?? base?.isBold ?? false,
      italic: style.italic ?? base?.isItalic ?? false,
    );
  }

  /// The page's own (materialized) /Font resource dictionary.
  CosDictionary _ownFontResources(PdfPage page) {
    final cos = document.cos;
    final res = _ownResources(page);
    final existing = cos.resolve(res['Font']);
    if (existing is CosDictionary && res['Font'] is! CosReference) {
      return existing;
    }
    final fonts = CosDictionary({
      if (existing is CosDictionary) ...existing.entries,
    });
    res['Font'] = fonts;
    return fonts;
  }

  /// A page /Font resource name for base-14 [font], reusing a matching entry
  /// or allocating a fresh `StFn` one.
  String _standardFontResource(PdfPage page, PdfStandardFont font) {
    final cos = document.cos;
    final fonts = _ownFontResources(page);
    for (final entry in fonts.entries.entries) {
      final f = cos.resolve(entry.value);
      if (f is CosDictionary &&
          f['BaseFont'] == CosName(font.baseFont) &&
          f['Encoding'] == const CosName('WinAnsiEncoding') &&
          cos.resolve(f['Subtype']) == const CosName('Type1')) {
        return entry.key;
      }
    }
    var i = 1;
    while (fonts.containsKey('StF$i')) {
      i++;
    }
    final name = 'StF$i';
    fonts[name] = _updater.addObject(
      CosDictionary({
        'Type': const CosName('Font'),
        'Subtype': const CosName('Type1'),
        'BaseFont': CosName(font.baseFont),
        'Encoding': const CosName('WinAnsiEncoding'),
      }),
    );
    return name;
  }

  /// The page /Font resource name reserved for [embed]'s font, allocating an
  /// `Emb…` slot (and starting fresh glyph accumulation) on first use. The
  /// entry itself is written by [replaceText]'s commit, once every replacement
  /// glyph is recorded.
  String _embeddedFontResource(PdfPage page, _StyledEmbed embed) {
    final existing = embed.name;
    if (existing != null) return existing;
    embed.font.resetUsage();
    final fonts = _ownFontResources(page);
    var i = 0;
    while (fonts.containsKey('Emb$i')) {
      i++;
    }
    return embed.name = 'Emb$i';
  }

  static Uint8List _hexBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  static ContentOperation _colorOp(int rgb) => ContentOperation('rg', [
        for (final v in ContentWriter.rgbComponents(rgb)) _numberObject(v),
      ]);

  static ContentOperation _tfOp(String name, double size) =>
      ContentOperation('Tf', [CosName(name), _numberObject(size)]);

  static ContentOperation _cloneOp(ContentOperation op) =>
      ContentOperation(op.operator, List<CosObject>.of(op.operands));

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

  /// Rewrites one run of show operators, replacing [find] with [replace]
  /// across its strings. Both are matched and written as *text*: [simple]
  /// turns the run's bytes into what they read as, and turns [replace] back
  /// into the codes this font draws it with. Returns the operations to emit
  /// in the run's place (the originals untouched when nothing matched) and
  /// the number of replacements.
  (List<ContentOperation>, int) _rewriteTextRun(
    List<ContentOperation> run,
    CosDictionary? font,
    String find,
    String replace,
    SimpleFont simple,
  ) {
    if (_isType0(document.cos, font)) return (run, 0);
    // Decided before the rewrite, like the composite path's glyph check: a
    // font with no code for one of the replacement's characters cannot draw
    // it, and emitting the Latin-1 byte regardless would silently draw a
    // different glyph. Leaving the run untouched is the honest outcome.
    final replaceBytes = simple.encode(replace);
    if (replaceBytes == null) return (run, 0);
    return TextRunRewriter(_SimpleRunCodec(simple, replaceBytes))
        .rewrite(run, find, replace);
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
    Uint8List source,
    List<int> find,
    List<int> replace,
  ) {
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
  void _appendContent(int pageIndex, PdfPage page, Uint8List bytes) {
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
    contents.items.add(
      _updater.addObject(
        CosStream(CosDictionary({'Length': CosInteger(bytes.length)}), bytes),
      ),
    );
    _updater.markChanged(dict);
    _markContent([pageIndex]);
  }

  /// Replaces the page's entire content with one new stream.
  void _setContent(int pageIndex, PdfPage page, Uint8List bytes) {
    page.dict['Contents'] = _updater.addObject(
      CosStream(CosDictionary({'Length': CosInteger(bytes.length)}), bytes),
    );
    _updater.markChanged(page.dict);
    _wrappedPages.remove(page.dict);
    _markContent([pageIndex]);
  }

  static CosStream _stream(String text) {
    final bytes = Uint8List.fromList(latin1.encode(text));
    return CosStream(
      CosDictionary({'Length': CosInteger(bytes.length)}),
      bytes,
    );
  }
}

/// The simple (one-byte-per-character) font codec for [TextRunRewriter]:
/// each shown byte is a glyph, replacements are drawn as Latin-1 bytes in the
/// run's own font, and cells serialize back into plain (non-hex) show strings.
class _SimpleRunCodec extends RunCodec {
  _SimpleRunCodec(this._simple, this._replaceBytes);

  /// The run's font, which owns both directions of the code <-> text map.
  final SimpleFont _simple;

  /// [replace] already encoded in this font's codes - resolved up front so an
  /// undrawable replacement never reaches the rewriter.
  final Uint8List _replaceBytes;

  @override
  List<RunCell> flatten(List<ContentOperation> run) => simpleRunCells(run);

  @override
  String glyphText(int glyph) => _simple.textFor(glyph);

  @override
  double glyphWidth(int glyph) => _simple.widthOf(glyph);

  @override
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing) {
    var newWidth = 0.0;
    for (final code in _replaceBytes) {
      out.add(CellEmit((glyph: code, kern: null)));
      newWidth += _simple.widthOf(code);
    }
    if (hasTrailing && (newWidth - oldWidth).abs() >= 0.001) {
      out.add(CellEmit((glyph: null, kern: newWidth - oldWidth)));
    }
  }

  @override
  List<ContentOperation> assemble(
          List<ContentOperation> run, List<Emit> out) =>
      RunCodec.coalesce(run, out,
          putGlyph: (g, buffer) => buffer.add(g),
          makeString: (buffer) => CosString(Uint8List.fromList(buffer)));
}

/// The styled-simple codec: the simple codec plus a decorator that brackets
/// each replacement with its own colour / `Tf` operators and restores the
/// run's prior colour and font afterwards, so text following a styled
/// correction keeps its appearance and stays put. The replacement is
/// re-measured against the styled font/size, and a compensating kern (in the
/// restored, original-size context) holds the rest of the line in place.
class _StyledRunCodec extends RunCodec {
  _StyledRunCodec({
    required this.simple,
    required double Function(int code) origWidthOf,
    required _StyledFace Function() resolveFace,
    required this.styledSize,
    required this.fontSize,
    required this.fontName,
    required this.colorOp,
    required this.restoreColorOps,
  })  : _origWidthOf = origWidthOf,
        _resolveFace = resolveFace;

  /// The run's own font, for reading its codes back as text when matching.
  final SimpleFont simple;

  final double Function(int) _origWidthOf;
  final _StyledFace Function() _resolveFace;
  final double styledSize;
  final double fontSize;
  final String? fontName;

  /// The nonstroking-colour operator for the replacement, or null to keep the
  /// run's colour.
  final ContentOperation? colorOp;

  /// The operators that restore the run's colour after a styled replacement.
  final List<ContentOperation> restoreColorOps;

  _StyledFace? _face; // resolved once, on the first match

  @override
  List<RunCell> flatten(List<ContentOperation> run) => simpleRunCells(run);

  @override
  String glyphText(int glyph) => simple.textFor(glyph);

  @override
  double glyphWidth(int glyph) => _origWidthOf(glyph);

  @override
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing) {
    // face resolution (which may allocate a page /Font and record embedded
    // glyphs) happens on the first match only, so a non-matching run reserves
    // nothing.
    final face = _face ??= _resolveFace();
    final fontChanged = face.fontName != fontName || styledSize != fontSize;
    // open the style
    if (colorOp != null) out.add(OpEmit(colorOp!));
    if (fontChanged && face.fontName != null) {
      out.add(OpEmit(PdfContentEditing._tfOp(face.fontName!, styledSize)));
    }
    out.add(OpEmit(ContentOperation('Tj', [face.replShow])));
    // close it: restore font, then colour, for whatever follows
    if (fontChanged && fontName != null) {
      out.add(OpEmit(PdfContentEditing._tfOp(fontName!, fontSize)));
    }
    if (colorOp != null) {
      for (final op in restoreColorOps) {
        out.add(OpEmit(PdfContentEditing._cloneOp(op)));
      }
    }
    // keep the rest of the line put; the compensation is applied in the
    // restored (original size) context, so convert the new width back.
    if (hasTrailing && fontSize != 0) {
      final kern = face.newWidthEm * styledSize / fontSize - oldWidth;
      if (kern.abs() >= 0.001) {
        out.add(CellEmit((glyph: null, kern: kern)));
      }
    }
  }

  @override
  List<ContentOperation> assemble(
          List<ContentOperation> run, List<Emit> out) =>
      RunCodec.coalesce(run, out,
          putGlyph: (g, buffer) => buffer.add(g),
          makeString: (buffer) => CosString(Uint8List.fromList(buffer)));
}

/// The resolved styled face for a [_StyledRunCodec]: the page /Font resource
/// name to draw the replacement in (null keeps the run's font), the show
/// string for the replacement, and its advance (thousandths of an em).
class _StyledFace {
  _StyledFace(this.fontName, this.replShow, this.newWidthEm);
  final String? fontName;
  final CosString replShow;
  final double newWidthEm;
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
        math.cos(r),
        math.sin(r),
        -math.sin(r),
        math.cos(r),
        x,
        y,
      );
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
      image(
        PdfEmbeddableImage.jpeg(jpeg),
        x: x,
        y: y,
        width: width,
        height: height,
      );

  /// Places a decoded [PdfEmbeddableImage] (JPEG or PNG - including PNG
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
      img.toXObject((smask) => _editor._updater.addObject(smask)),
    );

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
    final copy = CosDictionary({
      if (existing is CosDictionary) ...existing.entries,
    });
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
    fonts[name] = _editor._updater.addObject(
      CosDictionary({
        'Type': const CosName('Font'),
        'Subtype': const CosName('Type1'),
        'BaseFont': CosName(base),
        'Encoding': const CosName('WinAnsiEncoding'),
      }),
    );
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
