part of 'editor.dart';

/// Tier 4 - paragraph reflow. Where [PdfContentEditing.replaceText] corrects
/// text *within* a line (holding everything after it put), this re-wraps a
/// whole paragraph: the replacement may make the paragraph grow or shrink by
/// lines, the paragraph's lines are re-broken at its right margin, and the
/// lines that follow it cascade up or down so nothing overlaps.
///
/// The paragraph is found by the same kind of geometric inference the reading
/// (reflow) view uses - visual lines grouped into a left-aligned, single
/// column, single font/size block with a regular leading - but ported to run
/// directly over the content stream (this layer cannot import the renderer).
///
/// ## Supported shape (others leave the page untouched, returning false)
///
///  * Single column, left-aligned, horizontal unrotated text (the text and
///    line matrices are pure translation: `a == d == 1`, `b == c == 0`).
///  * Lines reached by a regular *relative* downward break - `T*`, or
///    `0 -leading Td`/`TD` - so changing the paragraph's line count cascades
///    into the following lines through the same relative breaks. The first
///    line keeps whatever positioned it (an absolute `Tm`/`Td` is fine).
///  * One show operator (`Tj`/`TJ`) per line, with nothing but the breaks
///    between them - no mid-paragraph font, colour, or spacing changes.
///  * Simple Latin-1 fonts, or Identity-H / CIDFontType2 / Identity-
///    CIDToGIDMap composite (/Type0) fonts whose embedded program carries a
///    glyph for every character of the reflowed text (no fallback-font path).
///
/// ## Out of scope (documented limitations)
///
///  * Multi-column and justified layouts (column detection here is a single
///    left-aligned run; inter-word spacing is not redistributed to a right
///    margin), first-line indents, the `'`/`"` show-and-break operators,
///    vertical writing modes, and font/size changes inside a paragraph.
///  * Non-text content (paths, images) and text in *other* text objects do
///    not move; only the lines that follow the paragraph in its own text
///    object cascade. Reflow bails when the paragraph's line count changes
///    but its following content is positioned absolutely (it would overlap).
extension PdfParagraphReflow on PdfEditor {
  /// Replaces [find] with [replace] inside a detected paragraph on page
  /// [index] and re-flows the paragraph and the lines after it. Returns true
  /// when a paragraph was reflowed, false (page untouched) when no safe
  /// reflow shape contained [find].
  ///
  /// See the [PdfParagraphReflow] doc comment for the supported shape and
  /// limitations. For corrections that must stay on one line, use
  /// [PdfContentEditing.replaceText].
  bool reflowText(int index, String find, String replace) {
    if (find.isEmpty) throw ArgumentError.value(find, 'find', 'is empty');

    final page = document.page(index);
    final elements = PdfPageElements.of(document, index);
    final ops = elements.operations;
    final cos = document.cos;
    final fonts = cos.resolve(page.resources['Font']);

    CosDictionary? fontFor(String? name) {
      if (name == null || fonts is! CosDictionary) return null;
      final font = cos.resolve(fonts[name]);
      return font is CosDictionary ? font : null;
    }

    // decoded text per show operator, taken from the element extractor so
    // /Type0 runs read as real Unicode (not Latin-1 byte pairs).
    final textByOp = <int, String>{
      for (final e in elements.elements)
        if (e.kind == PdfElementKind.text && e.text != null) e.start: e.text!,
    };

    final lines = _reflowLines(ops, textByOp);
    final groups = _reflowGroups(lines);

    for (final group in groups) {
      final joined = _joinParagraph(group);
      if (!joined.contains(find)) continue;

      final font = fontFor(group.first.fontName);
      final reflowFont = _reflowFontFor(
        page,
        group.first.fontName,
        font,
        group.first.fontSize,
      );
      if (reflowFont == null) continue; // unsupported font for this group

      // available width: the widest line the author used (the column they
      // wrapped against), with a hair of slack so re-measuring rounding
      // doesn't drop a word that already fit.
      var width = 0.0;
      for (final line in group) {
        width = math.max(width, reflowFont.measure(line.text.trim()));
      }
      width += 0.5;

      final newText = joined.replaceAll(find, replace);
      final newLines = _wrap(newText, width, reflowFont);

      // pick the relative break style that joins the paragraph's lines (and,
      // for a single-line paragraph, the break that connects it to whatever
      // follows in the same text object).
      final breakStyle = _breakStyleFor(group, lines);
      if (newLines.length != group.length) {
        if (breakStyle == null) continue; // no relative break to cascade
        // a line-count change must cascade through the following content; if
        // that content is positioned absolutely it can't move and would
        // overlap, so leave the page untouched.
        final following = _followingLine(group, lines);
        if (following != null && !_isRelativeDown(following)) continue;
      }

      // every show op between the first and last line of the paragraph must
      // be a plain show or a recognized relative break - anything else
      // (a font switch, colour, spacing) would be dropped by the rewrite.
      final firstShow = group.first.opIndex;
      final lastShow = group.last.opIndex;
      if (!_spanIsClean(ops, firstShow, lastShow)) continue;

      // build the replacement operations: the first line reuses the original
      // line's positioning (preserved before [firstShow]); each subsequent
      // line is preceded by the chosen relative break.
      final breakOp = _breakOp(breakStyle, group);
      final generated = <ContentOperation>[];
      for (var k = 0; k < newLines.length; k++) {
        if (k > 0) generated.add(breakOp);
        final show = reflowFont.showOp(newLines[k]);
        if (show == null) {
          generated.clear();
          break;
        }
        generated.add(show);
      }
      if (generated.isEmpty) continue; // a line couldn't be encoded - bail

      ops.replaceRange(firstShow, lastShow + 1, generated);
      reflowFont.commit();
      _setContent(index, page, elements.serialize());
      return true;
    }
    return false;
  }

  /// A measuring/encoding strategy for [font] at [size], or null when the
  /// font isn't one paragraph reflow can rewrite.
  _ReflowFont? _reflowFontFor(
    PdfPage page,
    String? name,
    CosDictionary? font,
    double size,
  ) {
    if (font == null) return null;
    if (PdfContentEditing._isType0(document.cos, font) && name != null) {
      final editing = _Type0Editing.tryCreate(this, page, name, font, const []);
      return editing == null ? null : _Type0ReflowFont(editing, size);
    }
    return _SimpleReflowFont(_widthsFor(font), size);
  }

  /// The paragraph lines flattened from [ops], decoding each show with
  /// [textByOp], tracking the text/line matrices so each line carries its
  /// origin, leading, font, and how it was reached.
  static List<_ReflowLine> _reflowLines(
    List<ContentOperation> ops,
    Map<int, String> textByOp,
  ) {
    final lines = <_ReflowLine>[];
    var objId = -1;
    String? fontName;
    var fontSize = 0.0;
    var leading = 0.0;
    var charSpace = 0.0;
    var wordSpace = 0.0;
    // text line matrix (a, b, c, d, e, f)
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0;
    _ReflowBreak? pending;

    void translate(double tx, double ty) {
      e = tx * a + ty * c + e;
      f = tx * b + ty * d + f;
    }

    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final operands = op.operands;
      switch (op.operator) {
        case 'BT':
          objId++;
          a = 1;
          b = 0;
          c = 0;
          d = 1;
          e = 0;
          f = 0;
          pending = const _ReflowBreak('first', 0, 0);
        case 'Tf':
          if (operands.isNotEmpty && operands[0] is CosName) {
            fontName = (operands[0] as CosName).value;
          }
          if (operands.length >= 2) {
            fontSize = PdfContentEditing._num(operands[1]);
          }
        case 'TL':
          if (operands.isNotEmpty) {
            leading = PdfContentEditing._num(operands[0]);
          }
        case 'Tc':
          if (operands.isNotEmpty) {
            charSpace = PdfContentEditing._num(operands[0]);
          }
        case 'Tw':
          if (operands.isNotEmpty) {
            wordSpace = PdfContentEditing._num(operands[0]);
          }
        case 'Td':
          if (operands.length >= 2) {
            final tx = PdfContentEditing._num(operands[0]),
                ty = PdfContentEditing._num(operands[1]);
            translate(tx, ty);
            pending = _ReflowBreak('Td', tx, ty);
          }
        case 'TD':
          if (operands.length >= 2) {
            final tx = PdfContentEditing._num(operands[0]),
                ty = PdfContentEditing._num(operands[1]);
            leading = -ty;
            translate(tx, ty);
            pending = _ReflowBreak('TD', tx, ty);
          }
        case 'Tm':
          if (operands.length >= 6) {
            a = PdfContentEditing._num(operands[0]);
            b = PdfContentEditing._num(operands[1]);
            c = PdfContentEditing._num(operands[2]);
            d = PdfContentEditing._num(operands[3]);
            e = PdfContentEditing._num(operands[4]);
            f = PdfContentEditing._num(operands[5]);
            pending = const _ReflowBreak('Tm', 0, 0);
          }
        case 'T*':
          translate(0, -leading);
          pending = _ReflowBreak('T*', 0, -leading);
        case "'":
          translate(0, -leading);
          _addLine(
            lines,
            op,
            i,
            objId,
            fontName,
            fontSize,
            leading,
            charSpace,
            wordSpace,
            a,
            b,
            c,
            d,
            e,
            f,
            const _ReflowBreak("'", 0, 0),
            textByOp,
          );
          pending = null;
        case '"':
          if (operands.length >= 2) {
            wordSpace = PdfContentEditing._num(operands[0]);
            charSpace = PdfContentEditing._num(operands[1]);
          }
          translate(0, -leading);
          _addLine(
            lines,
            op,
            i,
            objId,
            fontName,
            fontSize,
            leading,
            charSpace,
            wordSpace,
            a,
            b,
            c,
            d,
            e,
            f,
            const _ReflowBreak('"', 0, 0),
            textByOp,
          );
          pending = null;
        case 'Tj':
        case 'TJ':
          _addLine(
            lines,
            op,
            i,
            objId,
            fontName,
            fontSize,
            leading,
            charSpace,
            wordSpace,
            a,
            b,
            c,
            d,
            e,
            f,
            pending ?? const _ReflowBreak('cont', 0, 0),
            textByOp,
          );
          pending = null;
      }
    }
    return lines;
  }

  static void _addLine(
    List<_ReflowLine> lines,
    ContentOperation op,
    int opIndex,
    int objId,
    String? fontName,
    double fontSize,
    double leading,
    double charSpace,
    double wordSpace,
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
    _ReflowBreak brk,
    Map<int, String> textByOp,
  ) {
    lines.add(
      _ReflowLine(
        opIndex: opIndex,
        objId: objId,
        operator: op.operator,
        fontName: fontName,
        fontSize: fontSize,
        leading: leading,
        charSpace: charSpace,
        wordSpace: wordSpace,
        a: a,
        b: b,
        c: c,
        d: d,
        originX: e,
        baselineY: f,
        brk: brk,
        text: textByOp[opIndex] ?? '',
      ),
    );
  }

  /// Groups the eligible lines into paragraph candidates: consecutive,
  /// same text object, same font and size, left-aligned at a constant x,
  /// reached by a regular relative downward break of a constant leading.
  static List<List<_ReflowLine>> _reflowGroups(List<_ReflowLine> lines) {
    final groups = <List<_ReflowLine>>[];
    List<_ReflowLine>? current;
    double? groupX;
    double? groupLeading;

    void close() {
      if (current != null && current!.isNotEmpty) groups.add(current!);
      current = null;
      groupX = null;
      groupLeading = null;
    }

    for (final line in lines) {
      if (!_eligible(line)) {
        close();
        continue;
      }
      if (current == null) {
        current = [line];
        groupX = line.originX;
        continue;
      }
      final previous = current!.last;
      final pitch = previous.baselineY - line.baselineY;
      final xtol = math.max(1.0, line.fontSize * 0.1);
      final sameColumn = (line.originX - groupX!).abs() <= xtol;
      final sameFont = line.fontName == previous.fontName &&
          (line.fontSize - previous.fontSize).abs() < 0.01;
      final relative = _isRelativeDown(line) && pitch > 0;
      var consistentLeading = relative;
      if (relative && groupLeading != null) {
        final ltol = math.max(0.5, groupLeading! * 0.08);
        consistentLeading = (pitch - groupLeading!).abs() <= ltol;
      }
      if (line.objId == previous.objId &&
          sameColumn &&
          sameFont &&
          relative &&
          consistentLeading) {
        groupLeading ??= pitch;
        current!.add(line);
      } else {
        close();
        current = [line];
        groupX = line.originX;
      }
    }
    close();
    return groups;
  }

  /// Whether [line] can take part in a paragraph at all: horizontal,
  /// unrotated, unscaled text drawn by a single show with a real font.
  static bool _eligible(_ReflowLine line) =>
      line.fontName != null &&
      line.fontSize > 0 &&
      (line.operator == 'Tj' || line.operator == 'TJ') &&
      line.brk.kind != 'cont' &&
      (line.a - 1).abs() < 1e-6 &&
      line.b.abs() < 1e-6 &&
      line.c.abs() < 1e-6 &&
      (line.d - 1).abs() < 1e-6;

  /// Whether [line] was reached by a relative downward break (`T*`, or a
  /// `Td`/`TD` that only moves down) - the breaks a line-count change can
  /// cascade through.
  static bool _isRelativeDown(_ReflowLine line) {
    switch (line.brk.kind) {
      case 'T*':
        return true;
      case 'Td':
      case 'TD':
        return line.brk.tx.abs() < 1e-6 && line.brk.ty < 0;
      default:
        return false;
    }
  }

  /// The line immediately following [group] in the same text object, or null
  /// when the paragraph is the last text in its object.
  static _ReflowLine? _followingLine(
    List<_ReflowLine> group,
    List<_ReflowLine> lines,
  ) {
    final last = group.last;
    for (final line in lines) {
      if (line.objId == last.objId && line.opIndex > last.opIndex) return line;
    }
    return null;
  }

  /// The relative break style (`T*` or `Td`) to emit between reflowed lines:
  /// the paragraph's own inter-line break when it has one, else the break
  /// that connects a single-line paragraph to its following content.
  static String? _breakStyleFor(
    List<_ReflowLine> group,
    List<_ReflowLine> lines,
  ) {
    if (group.length >= 2) {
      final kind = group[1].brk.kind;
      return kind == 'T*' ? 'T*' : 'Td';
    }
    final following = _followingLine(group, lines);
    if (following != null && _isRelativeDown(following)) {
      return following.brk.kind == 'T*' ? 'T*' : 'Td';
    }
    return null;
  }

  /// The break operator to place before each reflowed line after the first.
  static ContentOperation _breakOp(String? style, List<_ReflowLine> group) {
    if (style == 'Td') {
      final leading = group.length >= 2
          ? group.first.baselineY - group[1].baselineY
          : group.first.leading;
      return ContentOperation('Td', [
        PdfContentEditing._numberObject(0),
        PdfContentEditing._numberObject(-leading),
      ]);
    }
    return ContentOperation('T*', const []);
  }

  /// Whether `ops[first..last]` holds only show operators and the recognized
  /// relative breaks - so replacing the span drops nothing meaningful.
  static bool _spanIsClean(List<ContentOperation> ops, int first, int last) {
    for (var i = first; i <= last; i++) {
      switch (ops[i].operator) {
        case 'Tj':
        case 'TJ':
        case 'T*':
        case 'Td':
        case 'TD':
          break;
        default:
          return false;
      }
    }
    return true;
  }

  /// Joins a paragraph's lines into one logical string: soft hyphens at line
  /// ends are repaired, other line breaks become a single space.
  static String _joinParagraph(List<_ReflowLine> group) {
    final buffer = StringBuffer();
    for (final line in group) {
      final piece = line.text.trim();
      if (buffer.isEmpty) {
        buffer.write(piece);
        continue;
      }
      final soFar = buffer.toString();
      if (soFar.endsWith('-') && piece.isNotEmpty) {
        buffer
          ..clear()
          ..write(soFar.substring(0, soFar.length - 1))
          ..write(piece);
      } else {
        buffer
          ..write(' ')
          ..write(piece);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Greedy word wrap of [text] at [width] text-space points, measuring with
  /// [font]. A single word wider than [width] still occupies its own line.
  static List<String> _wrap(String text, double width, _ReflowFont font) {
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [''];
    final out = <String>[];
    var line = '';
    for (final word in words) {
      final candidate = line.isEmpty ? word : '$line $word';
      if (line.isEmpty || font.measure(candidate) <= width) {
        line = candidate;
      } else {
        out.add(line);
        line = word;
      }
    }
    if (line.isNotEmpty) out.add(line);
    return out;
  }
}

/// One show operator flattened with the text state that placed it.
class _ReflowLine {
  _ReflowLine({
    required this.opIndex,
    required this.objId,
    required this.operator,
    required this.fontName,
    required this.fontSize,
    required this.leading,
    required this.charSpace,
    required this.wordSpace,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.originX,
    required this.baselineY,
    required this.brk,
    required this.text,
  });

  final int opIndex;
  final int objId;
  final String operator;
  final String? fontName;
  final double fontSize;
  final double leading;
  final double charSpace;
  final double wordSpace;
  final double a, b, c, d;
  final double originX;
  final double baselineY;
  final _ReflowBreak brk;
  final String text;
}

/// How a line was reached from the previous one.
class _ReflowBreak {
  const _ReflowBreak(this.kind, this.tx, this.ty);

  /// One of `first`, `Tm`, `Td`, `TD`, `T*`, `'`, `"`, `cont`.
  final String kind;
  final double tx;
  final double ty;
}

/// Measures and re-encodes reflowed lines for one font.
abstract class _ReflowFont {
  /// Advance of [text] in text-space points at the line's size.
  double measure(String text);

  /// The show operator that draws [text], or null when the font can't encode
  /// some character (composite fonts missing a glyph).
  ContentOperation? showOp(String text);

  /// Flushes any font-table changes (composite `/W` + `/ToUnicode`).
  void commit();
}

class _SimpleReflowFont extends _ReflowFont {
  _SimpleReflowFont(this._widthOf, this._size);

  final double Function(int code) _widthOf;
  final double _size;

  @override
  double measure(String text) {
    var total = 0.0;
    for (final unit in text.codeUnits) {
      total += _widthOf(unit);
    }
    return total / 1000 * _size;
  }

  @override
  ContentOperation? showOp(String text) {
    for (final unit in text.codeUnits) {
      if (unit > 0xFF) return null; // not representable in a simple font
    }
    return ContentOperation('Tj', [
      CosString(Uint8List.fromList(text.codeUnits)),
    ]);
  }

  @override
  void commit() {}
}

class _Type0ReflowFont extends _ReflowFont {
  _Type0ReflowFont(this._editing, this._size);

  final _Type0Editing _editing;
  final double _size;

  @override
  double measure(String text) => _editing.measureReflow(text, _size);

  @override
  ContentOperation? showOp(String text) {
    final string = _editing.encodeReflowLine(text);
    return string == null ? null : ContentOperation('Tj', [string]);
  }

  @override
  void commit() {
    if (_editing.isDirty) _editing.commit();
  }
}
