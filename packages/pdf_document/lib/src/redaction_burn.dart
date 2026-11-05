part of 'editor.dart';

// The content-stream surgery half of a redaction burn (see
// [PdfRedactionApply]): walks a page or form content stream and rewrites it
// with everything that falls inside a redaction region removed.
//
// The rule throughout is that removing too much beats leaking: where the
// geometry of something can't be known exactly (a font without metrics, a
// CMap of unknown code length, a picture-carrying pattern or shading) it is
// judged by a deliberately generous bound and removed whole when that bound
// touches a region.

/// Resource categories the burn can retire or add names in.
const _resXObject = 'XObject';
const _resExtGState = 'ExtGState';
const _resPattern = 'Pattern';
const _resShading = 'Shading';
const _resProperties = 'Properties';

/// An open marked-content sequence.
class _RedMarkedContent {
  _RedMarkedContent(this.op, {this.part = -1, this.props, this.mcid});

  final ContentOperation op;

  /// Index of the BDC operator's own piece in [_RedactionBurn._parts], or -1
  /// when its property list carries no text to strip.
  final int part;

  /// The resolved property list (inline or named), when it carries text.
  final CosDictionary? props;

  /// The sequence's /MCID, tying it to a structure element.
  final int? mcid;
  bool stripped = false;
}

/// One subpath of the path under construction, in default user space.
class _RedSubpath {
  final List<ContentOperation> ops = [];

  /// Every point the subpath names (end points and control points).
  final List<(double, double)> points = [];

  /// Points along its curves, so a curve sweeping through a region is seen
  /// even when all its control points lie outside.
  final List<(double, double)> samples = [];
  (double, double)? current;
}

class _RedactionBurn {
  _RedactionBurn(
    this._cos,
    this._resources,
    this._regions,
    this._session,
    this._addObject, {
    _RedMatrix ctm = _redIdentity,
    _RedactionBurn? parent,
    int? structParents,
  })  : _ctm = ctm,
        _parent = parent,
        _structParents = structParents,
        _depth = parent == null ? 0 : parent._depth + 1 {
    if (parent != null) {
      // a form inherits the invoking graphics state, the current font
      // *object* included - not a name to look up in its own resources
      _tfs = parent._tfs;
      _tc = parent._tc;
      _tw = parent._tw;
      _th = parent._th;
      _tl = parent._tl;
      _trise = parent._trise;
      _stateFont = parent._currentFont();
      _fontKnown = true;
      _fillPattern = parent._fillPattern;
      _strokePattern = parent._strokePattern;
      _fillPatternSpace = parent._fillPatternSpace;
      _strokePatternSpace = parent._strokePatternSpace;
    }
  }

  final CosDocument _cos;
  final CosDictionary _resources;
  final List<PdfRect> _regions;
  final _RedactionSession _session;
  final CosReference Function(CosObject) _addObject;
  final _RedactionBurn? _parent;
  final int _depth;

  /// The /StructParents key this stream's /MCIDs are numbered under.
  final int? _structParents;

  static const _maxFormDepth = 16;

  final Map<CosDictionary, _RedFont> _fontCache = Map.identity();

  /// Whether anything was removed from this stream (or what it draws).
  bool changed = false;

  // resource bookkeeping for [rebuiltResources], per category
  final Map<String, Set<String>> _used = {};
  final Map<String, Map<String, CosObject>> _retired = {};
  final Map<String, Map<String, CosObject>> _added = {};

  // output: pieces, so an operator already written can still be rewritten
  final List<Uint8List> _parts = [];
  final BytesBuilder _out = BytesBuilder();
  final List<_RedMarkedContent?> _marked = [];
  final List<(int, String)> _patternSelections = [];
  final List<_RedMarkedContent> _namedMarks = [];

  // the text removed since the last kept glyph or text positioning
  final StringBuffer _span = StringBuffer();

  // the path under construction
  final List<_RedSubpath> _path = [];
  ContentOperation? _clip;

  // graphics state
  _RedMatrix _ctm;
  final List<_RedGraphicsState> _gsStack = [];
  String? _fillPattern;
  String? _strokePattern;
  bool _fillPatternSpace = false;
  bool _strokePatternSpace = false;

  // text state (the q/Q-saved parameters live in _RedGraphicsState)
  _RedMatrix _tm = _redIdentity;
  _RedMatrix _tlm = _redIdentity;
  double _tfs = 0;
  double _tc = 0;
  double _tw = 0;
  double _th = 1;
  double _tl = 0;
  double _trise = 0;

  /// The current font; null with [_fontKnown] when the font set could not
  /// be resolved (its metrics are then unknown).
  _RedFont? _stateFont;
  bool _fontKnown = false;

  /// Text-space distance the text position may be off by, after a show
  /// whose advance couldn't be measured; 0 when exact. Reset by every
  /// operator that positions from the line matrix.
  double _slack = 0;

  Uint8List run(Uint8List content) {
    final ops = ContentStreamParser.parse(content);
    for (final op in ops) {
      _handle(op);
    }
    if (_path.isNotEmpty) _paintPath(null);
    _flushSpan();
    _parts.add(_out.takeBytes());
    for (final frame in _namedMarks) {
      if (!frame.stripped) {
        _use(_resProperties, (frame.op.operands[1] as CosName).value);
      }
    }
    // a pattern no kept paint uses is no longer selected either, so the
    // stream stops naming it and the purge can take it out of the file
    final retiredPatterns = _retired[_resPattern];
    if (retiredPatterns != null) {
      for (final (index, name) in _patternSelections) {
        if (retiredPatterns.containsKey(name) && !_isUsed(_resPattern, name)) {
          _parts[index] = Uint8List(0);
        }
      }
    }
    final all = BytesBuilder(copy: false);
    for (final part in _parts) {
      all.add(part);
    }
    return all.takeBytes();
  }

  /// The resource dictionary the rewritten stream needs, or null when the
  /// original serves unchanged: dropped/replaced resources no longer used
  /// are gone, and replacements are added under fresh names.
  CosDictionary? rebuiltResources() {
    if (_added.isEmpty && _retired.isEmpty) return null;
    final out = CosDictionary({..._resources.entries});
    for (final category in {..._retired.keys, ..._added.keys}) {
      final sub = _cos.resolve(_resources[category]);
      final copy = CosDictionary({if (sub is CosDictionary) ...sub.entries});
      for (final name in _retired[category]?.keys ?? const <String>[]) {
        if (!_isUsed(category, name)) copy.entries.remove(name);
      }
      copy.entries.addAll(_added[category] ?? const {});
      out[category] = copy;
    }
    return out;
  }

  bool _isUsed(String category, String name) =>
      _used[category]?.contains(name) ?? false;

  void _use(String category, String name) => (_used[category] ??= {}).add(name);

  void _retire(String category, String name, CosObject? entry) {
    (_retired[category] ??= {})[name] = entry ?? CosNull.instance;
    if (entry is CosReference) _session.retired.add(entry.objectNumber);
  }

  /// Adds [object] as a new resource and returns its name.
  String _addResource(String category, CosObject object) {
    final existing = _cos.resolve(_resources[category]);
    final added = _added[category] ??= {};
    var i = added.length;
    while (true) {
      final name = 'Rd${category.substring(0, 2)}${++i}';
      if ((existing is! CosDictionary || !existing.containsKey(name)) &&
          !added.containsKey(name)) {
        added[name] = _addObject(object);
        _use(category, name);
        return name;
      }
    }
  }

  /// A named resource, looked up in this stream's resources and then - as
  /// viewers do for a form that omits it - in its invoker's.
  CosObject? _lookup(String category, String name) {
    final dict = _cos.resolve(_resources[category]);
    if (dict is CosDictionary && dict.containsKey(name)) return dict[name];
    return _parent?._lookup(category, name);
  }

  double _n(CosObject o) => switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0,
      };

  static const _pathConstruction = {'m', 'l', 'c', 'v', 'y', 'h', 're'};
  static const _pathPainting = {
    'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', 'n', //
  };

  void _handle(ContentOperation op) {
    final operator = op.operator;
    if (_pathConstruction.contains(operator)) {
      _buildPath(op);
      return;
    }
    if (operator == 'W' || operator == 'W*') {
      _clip = op;
      return;
    }
    if (_pathPainting.contains(operator)) {
      _paintPath(op);
      return;
    }
    // anything else ends a malformed path without painting it
    if (_path.isNotEmpty || _clip != null) _paintPath(null);

    final operands = op.operands;
    switch (operator) {
      case 'q':
        _gsStack.add(_RedGraphicsState(
          ctm: _ctm,
          tfs: _tfs,
          tc: _tc,
          tw: _tw,
          th: _th,
          tl: _tl,
          trise: _trise,
          font: _stateFont,
          fontKnown: _fontKnown,
          fillPattern: _fillPattern,
          strokePattern: _strokePattern,
          fillPatternSpace: _fillPatternSpace,
          strokePatternSpace: _strokePatternSpace,
        ));
      case 'Q':
        if (_gsStack.isNotEmpty) {
          final s = _gsStack.removeLast();
          _ctm = s.ctm;
          _tfs = s.tfs;
          _tc = s.tc;
          _tw = s.tw;
          _th = s.th;
          _tl = s.tl;
          _trise = s.trise;
          _stateFont = s.font;
          _fontKnown = s.fontKnown;
          _fillPattern = s.fillPattern;
          _strokePattern = s.strokePattern;
          _fillPatternSpace = s.fillPatternSpace;
          _strokePatternSpace = s.strokePatternSpace;
        }
      case 'cm':
        if (operands.length >= 6) {
          _ctm = _redMul((
            _n(operands[0]),
            _n(operands[1]),
            _n(operands[2]),
            _n(operands[3]),
            _n(operands[4]),
            _n(operands[5]),
          ), _ctm);
        }
      case 'gs':
        if (_handleExtGState(op)) return;
      case 'cs' || 'CS':
        final space = operands.isNotEmpty && _isPatternSpace(operands.first);
        if (operator == 'cs') {
          _fillPatternSpace = space;
          _fillPattern = null;
        } else {
          _strokePatternSpace = space;
          _strokePattern = null;
        }
      case 'g' || 'rg' || 'k':
        _fillPatternSpace = false;
        _fillPattern = null;
      case 'G' || 'RG' || 'K':
        _strokePatternSpace = false;
        _strokePattern = null;
      case 'sc':
        _fillPattern = null;
      case 'SC':
        _strokePattern = null;
      case 'scn' || 'SCN':
        final fill = operator == 'scn';
        final last = operands.isEmpty ? null : operands.last;
        final name =
            last is CosName && (fill ? _fillPatternSpace : _strokePatternSpace)
                ? last.value
                : null;
        if (fill) {
          _fillPattern = name;
        } else {
          _strokePattern = name;
        }
        if (name != null) {
          // its own piece: blanked at the end if the pattern is retired
          _parts.add(_out.takeBytes());
          _patternSelections.add((_parts.length, name));
          final piece = BytesBuilder();
          ContentStreamSerializer.writeOperation(op, piece);
          _parts.add(piece.takeBytes());
          return;
        }
      case 'sh':
        if (_handleShading(op)) return;
      case 'BT':
        _flushSpan();
        _tm = _redIdentity;
        _tlm = _redIdentity;
        _slack = 0;
      case 'ET':
        _flushSpan();
      case 'Tf':
        if (operands.length >= 2) {
          final name =
              operands[0] is CosName ? (operands[0] as CosName).value : null;
          _stateFont = name == null ? null : _fontNamed(name);
          _fontKnown = true;
          _tfs = _n(operands[1]);
        }
      case 'Tc':
        if (operands.isNotEmpty) _tc = _n(operands[0]);
      case 'Tw':
        if (operands.isNotEmpty) _tw = _n(operands[0]);
      case 'Tz':
        if (operands.isNotEmpty) _th = _n(operands[0]) / 100;
      case 'TL':
        if (operands.isNotEmpty) _tl = _n(operands[0]);
      case 'Ts':
        if (operands.isNotEmpty) _trise = _n(operands[0]);
      case 'Td':
        _flushSpan();
        if (operands.length >= 2) {
          _tlm = _redMul((1, 0, 0, 1, _n(operands[0]), _n(operands[1])), _tlm);
          _tm = _tlm;
          _slack = 0;
        }
      case 'TD':
        _flushSpan();
        if (operands.length >= 2) {
          _tl = -_n(operands[1]);
          _tlm = _redMul((1, 0, 0, 1, _n(operands[0]), _n(operands[1])), _tlm);
          _tm = _tlm;
          _slack = 0;
        }
      case 'Tm':
        _flushSpan();
        if (operands.length >= 6) {
          _tm = (
            _n(operands[0]),
            _n(operands[1]),
            _n(operands[2]),
            _n(operands[3]),
            _n(operands[4]),
            _n(operands[5]),
          );
          _tlm = _tm;
          _slack = 0;
        }
      case 'T*':
        _flushSpan();
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
        _slack = 0;
      case 'Tj' || 'TJ':
        _showText(op);
        return;
      case "'":
        _flushSpan();
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
        _slack = 0;
        _showText(op, prefix: 'T*\n');
        return;
      case '"':
        _flushSpan();
        if (operands.length >= 3) {
          _tw = _n(operands[0]);
          _tc = _n(operands[1]);
        }
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
        _slack = 0;
        _showText(
          op,
          prefix: '${ContentWriter.fmt(_tw)} Tw '
              '${ContentWriter.fmt(_tc)} Tc T*\n',
        );
        return;
      case 'Do':
        _handleDo(op);
        return;
      case 'BI':
        // an inline image touching a region goes whole: they are small, and
        // splitting their samples would need the abbreviated-name decoding
        if (_rectIntersectsAny(_unitSquareBounds(_ctm))) {
          _removed();
          return;
        }
      case 'BMC':
        _marked.add(_RedMarkedContent(op));
      case 'BDC':
        _beginMarkedContent(op);
        return;
      case 'EMC':
        if (_marked.isNotEmpty) _marked.removeLast();
    }
    _writeOp(op);
  }

  // ---------------------------------------------------------------- marked

  static const _markedTextKeys = ['ActualText', 'Alt', 'E'];

  void _beginMarkedContent(ContentOperation op) {
    final operands = op.operands;
    final raw = operands.length >= 2 ? operands[1] : null;
    CosDictionary? props;
    if (raw is CosDictionary) {
      props = raw;
    } else if (raw is CosName) {
      final p = _cos.resolve(_lookup(_resProperties, raw.value));
      if (p is CosDictionary) props = p;
    }
    final mcidObj = props == null ? null : _cos.resolve(props['MCID']);
    final mcid = mcidObj is CosInteger ? mcidObj.value : null;
    if (props != null && _markedTextKeys.any(props.containsKey)) {
      _parts.add(_out.takeBytes());
      final frame =
          _RedMarkedContent(op, part: _parts.length, props: props, mcid: mcid);
      _marked.add(frame);
      if (raw is CosName) _namedMarks.add(frame);
      final piece = BytesBuilder();
      ContentStreamSerializer.writeOperation(op, piece);
      _parts.add(piece.takeBytes());
      return;
    }
    final frame = _RedMarkedContent(op, mcid: mcid);
    _marked.add(frame);
    if (raw is CosName) _namedMarks.add(frame);
    _writeOp(op);
  }

  /// Records that content was removed here: strips the replacement and
  /// alternate text of every enclosing marked-content sequence (inline or
  /// named), which would otherwise still spell out what was removed, and
  /// notes their /MCIDs so the structure elements they belong to lose
  /// theirs too.
  void _removed() {
    changed = true;
    for (final frame in _marked) {
      if (frame == null) continue;
      final mcid = frame.mcid;
      if (mcid != null && _structParents != null) {
        (_session.removedMcids[_structParents] ??= {}).add(mcid);
      }
      final props = frame.props;
      if (props == null || frame.stripped) continue;
      frame.stripped = true;
      final stripped = CosDictionary({...props.entries});
      for (final key in _markedTextKeys) {
        stripped.entries.remove(key);
      }
      final ContentOperation replacement;
      final raw = frame.op.operands[1];
      if (raw is CosName) {
        // a named list: the stream gets its own stripped copy
        _retire(_resProperties, raw.value, _lookup(_resProperties, raw.value));
        final fresh = _addResource(_resProperties, stripped);
        replacement =
            ContentOperation('BDC', [frame.op.operands[0], CosName(fresh)]);
      } else {
        replacement = ContentOperation('BDC', [frame.op.operands[0], stripped]);
      }
      final piece = BytesBuilder();
      ContentStreamSerializer.writeOperation(replacement, piece);
      _parts[frame.part] = piece.takeBytes();
    }
    _parent?._removedInChild();
  }

  /// A form this stream draws had content removed: its enclosing marked
  /// content here describes it too.
  void _removedInChild() => _removed();

  void _flushSpan() {
    if (_span.isEmpty) return;
    _session.texts.add(_span.toString());
    _span.clear();
  }

  // ------------------------------------------------------------------ paths

  void _buildPath(ContentOperation op) {
    final o = op.operands;
    double at(int i) => i < o.length ? _n(o[i]) : 0;
    (double, double) user(double x, double y) => _redApply(_ctm, x, y);

    _RedSubpath current() {
      if (_path.isEmpty) _path.add(_RedSubpath());
      return _path.last;
    }

    switch (op.operator) {
      case 'm':
        final s = _RedSubpath();
        final p = user(at(0), at(1));
        s
          ..points.add(p)
          ..current = p;
        _path.add(s);
        s.ops.add(op);
        return;
      case 're':
        final s = _RedSubpath();
        final x = at(0), y = at(1), w = at(2), h = at(3);
        s.points.addAll([
          user(x, y),
          user(x + w, y),
          user(x + w, y + h),
          user(x, y + h),
        ]);
        s.current = s.points.first;
        s.ops.add(op);
        _path.add(s);
        return;
      case 'l':
        final s = current();
        final p = user(at(0), at(1));
        s
          ..points.add(p)
          ..current = p
          ..ops.add(op);
        return;
      case 'c' || 'v' || 'y':
        final s = current();
        final start = s.current ?? user(at(0), at(1));
        final (double, double) p1, p2, p3;
        if (op.operator == 'c') {
          p1 = user(at(0), at(1));
          p2 = user(at(2), at(3));
          p3 = user(at(4), at(5));
        } else if (op.operator == 'v') {
          p1 = start;
          p2 = user(at(0), at(1));
          p3 = user(at(2), at(3));
        } else {
          p1 = user(at(0), at(1));
          p2 = user(at(2), at(3));
          p3 = p2;
        }
        s.points.addAll([p1, p2, p3]);
        _sampleCurve(s.samples, start, p1, p2, p3);
        s
          ..current = p3
          ..ops.add(op);
        return;
      case 'h':
        current().ops.add(op);
        return;
    }
  }

  /// Points along a cubic Bézier, at most ~2pt apart.
  static void _sampleCurve(
    List<(double, double)> out,
    (double, double) p0,
    (double, double) p1,
    (double, double) p2,
    (double, double) p3,
  ) {
    double dist((double, double) a, (double, double) b) =>
        math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
    final length = dist(p0, p1) + dist(p1, p2) + dist(p2, p3);
    final n = length.isFinite ? (length / 2).ceil().clamp(8, 1024) : 8;
    for (var i = 1; i < n; i++) {
      final t = i / n, u = 1 - t;
      final a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
      out.add((
        a * p0.$1 + b * p1.$1 + c * p2.$1 + d * p3.$1,
        a * p0.$2 + b * p1.$2 + c * p2.$2 + d * p3.$2,
      ));
    }
  }

  /// Ends the path under construction with [paint] (null for a malformed
  /// path broken off by another operator), dropping every subpath that
  /// draws inside a region.
  ///
  /// A subpath goes when any point it names, or any point along its
  /// curves, lies inside a region: outlined text, a vector signature or a
  /// barcode bar under the box. One that only crosses a region with
  /// straight edges (a table rule, a background box) stays - what it
  /// draws inside is fixed by its points outside. Painted with a pattern
  /// that can carry a picture (a tiling pattern, a sampled shading) a
  /// subpath goes as soon as its bounds touch a region, since the picture
  /// is the content. A clip is always kept, as clipping alone shows nothing.
  void _paintPath(ContentOperation? paint) {
    final subpaths = List.of(_path);
    final clip = _clip;
    _path.clear();
    _clip = null;

    final operator = paint?.operator;
    final fills =
        const {'f', 'F', 'f*', 'B', 'B*', 'b', 'b*'}.contains(operator);
    final strokes = const {'S', 's', 'B', 'B*', 'b', 'b*'}.contains(operator);
    final patterns = <String>[
      if (fills &&
          _fillPattern != null &&
          _patternCarriesPicture(_fillPattern!))
        _fillPattern!,
      if (strokes &&
          _strokePattern != null &&
          _patternCarriesPicture(_strokePattern!))
        _strokePattern!,
    ];

    final kept = <_RedSubpath>[];
    for (final s in subpaths) {
      final drop = operator != 'n' &&
          (patterns.isNotEmpty
              ? _boundsTouchAny(_hullBounds(s.points))
              : _anyInside(s.points) || _anyInside(s.samples));
      if (!drop) kept.add(s);
    }

    void emit(Iterable<_RedSubpath> parts) {
      for (final s in parts) {
        for (final op in s.ops) {
          _writeOp(op);
        }
      }
    }

    if (kept.length == subpaths.length) {
      emit(subpaths);
      if (clip != null) _writeOp(clip);
      if (paint != null) _writeOp(paint);
      _usePaintPatterns(fills, strokes, paint != null && subpaths.isNotEmpty);
      return;
    }
    _removed();
    for (final p in patterns) {
      _retire(_resPattern, p, _lookup(_resPattern, p));
    }
    if (clip != null) {
      // keep the clip exactly as it was, without painting
      emit(subpaths);
      _writeOp(clip);
      _writeOp(ContentOperation('n', const []));
    }
    if (kept.isNotEmpty && paint != null) {
      emit(kept);
      _writeOp(paint);
      _usePaintPatterns(fills, strokes, true);
    }
  }

  void _usePaintPatterns(bool fills, bool strokes, bool painted) {
    if (!painted) return;
    if (fills && _fillPattern != null) _use(_resPattern, _fillPattern!);
    if (strokes && _strokePattern != null) _use(_resPattern, _strokePattern!);
  }

  bool _anyInside(List<(double, double)> points) {
    for (final (x, y) in points) {
      for (final r in _regions) {
        if (x >= r.left && x <= r.right && y >= r.bottom && y <= r.top) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isPatternSpace(CosObject operand) {
    if (operand is! CosName) return false;
    if (operand.value == 'Pattern') return true;
    final cs = _cos.resolve(_lookup('ColorSpace', operand.value));
    if (cs is CosName) return cs.value == 'Pattern';
    if (cs is CosArray && cs.length > 0) {
      final head = _cos.resolve(cs[0]);
      return head is CosName && head.value == 'Pattern';
    }
    return false;
  }

  /// Whether the named pattern can paint a picture: a tiling pattern (its
  /// cell is arbitrary content) or a shading pattern whose shading can.
  bool _patternCarriesPicture(String name) {
    final pattern = _cos.resolve(_lookup(_resPattern, name));
    final dict = pattern is CosStream
        ? pattern.dictionary
        : pattern is CosDictionary
            ? pattern
            : null;
    if (dict == null) return true;
    final type = _cos.resolve(dict['PatternType']);
    if (type is CosInteger && type.value == 2) {
      return _shadingCarriesPicture(_cos.resolve(dict['Shading']));
    }
    return true;
  }

  /// Whether a shading can encode a picture: a function-based or mesh
  /// shading, or an axial/radial one driven by a sampled or PostScript
  /// function. Plain exponential gradients can't.
  bool _shadingCarriesPicture(CosObject shading) {
    final dict = shading is CosStream
        ? shading.dictionary
        : shading is CosDictionary
            ? shading
            : null;
    if (dict == null) return true;
    final type = _cos.resolve(dict['ShadingType']);
    if (type is! CosInteger || (type.value != 2 && type.value != 3)) {
      return true;
    }
    return _functionCarriesPicture(dict['Function'], 0);
  }

  bool _functionCarriesPicture(CosObject? function, int depth) {
    if (depth > 8) return true;
    final f = _cos.resolve(function);
    if (f is CosNull) return false;
    if (f is CosArray) {
      return f.items.any((g) => _functionCarriesPicture(g, depth + 1));
    }
    final dict = f is CosStream
        ? f.dictionary
        : f is CosDictionary
            ? f
            : null;
    if (dict == null) return true;
    final type = _cos.resolve(dict['FunctionType']);
    if (type is! CosInteger) return true;
    if (type.value == 2) return false;
    if (type.value == 3) {
      return _functionCarriesPicture(dict['Functions'], depth + 1);
    }
    return true; // sampled (0) or PostScript (4)
  }

  bool _handleShading(ContentOperation op) {
    final name = op.operands.isNotEmpty && op.operands.first is CosName
        ? (op.operands.first as CosName).value
        : null;
    if (name == null) return false;
    final entry = _lookup(_resShading, name);
    final shading = _cos.resolve(entry);
    if (_shadingCarriesPicture(shading)) {
      final dict = shading is CosStream
          ? shading.dictionary
          : shading is CosDictionary
              ? shading
              : null;
      final bbox = dict == null ? null : pdfRectFrom(_cos, dict['BBox']);
      // without a /BBox `sh` paints the whole clip: assume it reaches
      final bounds = bbox == null
          ? null
          : _hullBounds([
              _redApply(_ctm, bbox.left, bbox.bottom),
              _redApply(_ctm, bbox.right, bbox.bottom),
              _redApply(_ctm, bbox.left, bbox.top),
              _redApply(_ctm, bbox.right, bbox.top),
            ]);
      if (bounds == null || _rectIntersectsAny(bounds)) {
        _retire(_resShading, name, entry);
        _removed();
        return true;
      }
    }
    _use(_resShading, name);
    return false;
  }

  // ------------------------------------------------------------- ExtGState

  /// Applies a `gs`: its /Font sets the text font, and a soft-mask group
  /// is burned like a form - its content can be extracted like any other.
  /// Returns true when the operator was rewritten (already emitted).
  bool _handleExtGState(ContentOperation op) {
    final name = op.operands.isNotEmpty && op.operands.first is CosName
        ? (op.operands.first as CosName).value
        : null;
    if (name == null) return false;
    final entry = _lookup(_resExtGState, name);
    final state = _cos.resolve(entry);
    if (state is! CosDictionary) {
      _use(_resExtGState, name);
      return false;
    }
    final font = _cos.resolve(state['Font']);
    if (font is CosArray && font.length >= 2) {
      final dict = _cos.resolve(font[0]);
      _stateFont = dict is CosDictionary ? _fontFor(dict) : null;
      _fontKnown = true;
      _tfs = _n(_cos.resolve(font[1]));
    }
    final mask = _cos.resolve(state['SMask']);
    final group = mask is CosDictionary ? _cos.resolve(mask['G']) : null;
    if (mask is! CosDictionary || group is! CosStream) {
      _use(_resExtGState, name);
      return false;
    }
    final (groupChanged, burned) =
        _burnForm(group, _redMul(_formMatrix(group), _ctm));
    if (!groupChanged) {
      _use(_resExtGState, name);
      return false;
    }
    final newMask = CosDictionary({
      for (final key in const ['Type', 'S', 'BC', 'TR'])
        if (mask.containsKey(key)) key: mask[key]!,
    });
    if (burned != null) newMask['G'] = _addObject(burned);
    final newState = CosDictionary({
      ...state.entries,
      'SMask': burned != null ? newMask : const CosName('None'),
    });
    _retire(_resExtGState, name, entry);
    final maskRef = mask['G'];
    if (maskRef is CosReference) _session.retired.add(maskRef.objectNumber);
    _removed();
    final fresh = _addResource(_resExtGState, newState);
    _writeOp(ContentOperation('gs', [CosName(fresh)]));
    return true;
  }

  // ---------------------------------------------------------------- XObject

  void _handleDo(ContentOperation op) {
    final name = op.operands.isNotEmpty && op.operands.first is CosName
        ? (op.operands.first as CosName).value
        : null;
    final entry = name == null ? null : _lookup(_resXObject, name);
    final xobject = _cos.resolve(entry);
    if (name == null || entry == null || xobject is! CosStream) {
      _writeOp(op);
      return;
    }

    final isForm = _isForm(xobject);
    final drawCtm = isForm ? _redMul(_formMatrix(xobject), _ctm) : _ctm;
    PdfRect? bounds;
    if (isForm) {
      final bbox = pdfRectFrom(_cos, xobject.dictionary['BBox']);
      if (bbox != null) {
        bounds = _hullBounds([
          _redApply(drawCtm, bbox.left, bbox.bottom),
          _redApply(drawCtm, bbox.right, bbox.bottom),
          _redApply(drawCtm, bbox.left, bbox.top),
          _redApply(drawCtm, bbox.right, bbox.top),
        ]);
      }
    } else {
      bounds = _unitSquareBounds(_ctm);
      if (!_rectIntersectsAny(bounds)) {
        _keepDo(op, name);
        return;
      }
    }
    if (bounds != null && _boundsFullyCovered(bounds)) {
      _retire(_resXObject, name, entry);
      _removed();
      return; // drop
    }

    final CosStream? replacement;
    if (isForm) {
      // always burned: a form's /BBox clips what it shows, not what text
      // extraction reads, so text under a region can sit outside it
      final (formChanged, burned) = _burnForm(xobject, drawCtm);
      if (!formChanged) {
        _keepDo(op, name);
        return;
      }
      replacement = burned;
    } else {
      final redacted = _redactImage(xobject, _ctm);
      if (identical(redacted, xobject)) {
        _keepDo(op, name);
        return;
      }
      replacement = redacted;
    }
    _retire(_resXObject, name, entry);
    _removed();
    if (replacement == null) return; // couldn't be rewritten: dropped whole
    final fresh = _addResource(_resXObject, replacement);
    _writeOp(ContentOperation('Do', [CosName(fresh)]));
  }

  void _keepDo(ContentOperation op, String name) {
    _use(_resXObject, name);
    _writeOp(op);
  }

  bool _isForm(CosStream xobject) {
    final subtype = _cos.resolve(xobject.dictionary['Subtype']);
    return subtype is CosName && subtype.value == 'Form';
  }

  _RedMatrix _formMatrix(CosStream form) {
    final m = _cos.resolve(form.dictionary['Matrix']);
    if (m is! CosArray || m.length < 6) return _redIdentity;
    double at(int i) => _n(_cos.resolve(m[i]));
    return (at(0), at(1), at(2), at(3), at(4), at(5));
  }

  /// Form keys a burned copy keeps; everything else (alternate or private
  /// renditions, metadata, OPI, the old encoding) describes the original.
  static const _formKeys = {
    'Type',
    'Subtype',
    'FormType',
    'BBox',
    'Matrix',
    'Resources',
    'Group',
    'OC',
    'StructParent',
    'StructParents',
  };

  /// Image keys a redacted copy keeps (see [_formKeys]).
  static const _imageKeys = {
    'Type',
    'Subtype',
    'Width',
    'Height',
    'ColorSpace',
    'BitsPerComponent',
    'Intent',
    'ImageMask',
    'Mask',
    'SMask',
    'Decode',
    'Interpolate',
    'Matte',
    'OC',
    'StructParent',
  };

  /// Burns a form XObject (or soft-mask group) drawn under [drawCtm] into a
  /// fresh copy. Returns `(false, _)` when nothing in it was covered,
  /// `(true, null)` when it must be dropped whole (undecodable, or nested
  /// too deep to follow).
  (bool, CosStream?) _burnForm(CosStream form, _RedMatrix drawCtm) {
    if (_depth >= _maxFormDepth) return (true, null);
    final Uint8List content;
    try {
      content = _cos.decodeStreamData(form);
    } on Object {
      return (true, null);
    }
    final ownResources = _cos.resolve(form.dictionary['Resources']);
    final sp = _cos.resolve(form.dictionary['StructParents']);
    if (++_session.formBurns > _RedactionSession.maxFormBurns) {
      // fail closed: nothing is saved rather than a partial burn
      throw StateError('redaction: too many nested form XObjects to burn');
    }
    final nested = _RedactionBurn(
      _cos,
      // a form without /Resources uses its invoker's
      ownResources is CosDictionary ? ownResources : _resources,
      _regions,
      _session,
      _addObject,
      ctm: drawCtm,
      parent: this,
      structParents: sp is CosInteger ? sp.value : null,
    );
    final Uint8List burned;
    try {
      burned = nested.run(content);
    } on Object {
      return (true, null);
    }
    if (!nested.changed) return (false, null);
    final dict = CosDictionary({
      for (final MapEntry(:key, :value) in form.dictionary.entries.entries)
        if (_formKeys.contains(key)) key: value,
    });
    final resources = nested.rebuiltResources();
    if (resources != null) dict['Resources'] = resources;
    dict['Length'] = CosInteger(burned.length);
    return (true, CosStream(dict, burned));
  }

  // ----------------------------------------------------------------- images

  /// [image] drawn under [ctm] with the pixels under any region cleared,
  /// re-encoded with Flate. Returns [image] itself when no pixel is under a
  /// region, and null when the samples can't be decoded or rewritten -
  /// the caller then drops the image whole (removing too much beats
  /// leaking).
  CosStream? _redactImage(CosStream image, _RedMatrix ctm) {
    try {
      return _redactImageSamples(image, ctm);
    } on Object {
      return null;
    }
  }

  CosStream? _redactImageSamples(CosStream image, _RedMatrix ctm) {
    final dict = image.dictionary;
    final width = _int(dict['Width']);
    final height = _int(dict['Height']);
    if (width <= 0 || height <= 0 || width * height > 200000000) return null;

    // the pixel box each region covers (rows from the top)
    final inverse = _redInvert(ctm);
    if (inverse == null) return null;
    final boxes = <(int, int, int, int)>[];
    for (final region in _regions) {
      final hull = _hullBounds([
        _redApply(inverse, region.left, region.bottom),
        _redApply(inverse, region.right, region.bottom),
        _redApply(inverse, region.left, region.top),
        _redApply(inverse, region.right, region.top),
      ])!;
      final x0 = (hull.left * width).floor().clamp(0, width);
      final x1 = (hull.right * width).ceil().clamp(0, width);
      final y0 = ((1 - hull.top) * height).floor().clamp(0, height);
      final y1 = ((1 - hull.bottom) * height).ceil().clamp(0, height);
      if (x0 < x1 && y0 < y1) boxes.add((x0, y0, x1, y1));
    }
    if (boxes.isEmpty) return image;

    final imageMask = _cos.resolve(dict['ImageMask']);
    final isMask = imageMask is CosBoolean && imageMask.value;
    final components = isMask ? 1 : _componentCount(dict['ColorSpace']);
    if (components == null) return null;
    var bits = isMask ? 1 : _int(dict['BitsPerComponent'], fallback: 8);
    if (!const {1, 2, 4, 8, 16}.contains(bits)) return null;

    final filters = _filterNames(dict['Filter']);
    final Uint8List samples;
    if (filters.contains('JPXDecode')) {
      return null;
    } else if (filters.isNotEmpty && filters.last == 'DCTDecode') {
      final decoded = _decodeJpegSamples(image, width, height, components);
      if (decoded == null) return null;
      samples = decoded;
      bits = 8;
    } else if (filters.contains('JBIG2Decode')) {
      if (filters.last != 'JBIG2Decode') return null;
      final params = _filterParams(dict, filters.length - 1);
      final globalsStream =
          params == null ? null : _cos.resolve(params['JBIG2Globals']);
      final decoded = Jbig2Decoder.decode(
        data: _cos.decodeStreamData(image, stopBeforeFilter: 'JBIG2Decode'),
        globals: globalsStream is CosStream
            ? _cos.decodeStreamData(globalsStream)
            : null,
        width: width,
        height: height,
      );
      if (decoded == null) return null;
      samples = decoded;
    } else {
      samples = _cos.decodeStreamData(image);
    }

    final rowBytes = (width * components * bits + 7) >> 3;
    if (samples.length < rowBytes * height) return null;
    // a copy: decoded bytes may be the document's cached decode
    final data = Uint8List.fromList(
        Uint8List.sublistView(samples, 0, rowBytes * height));
    final bitsPerPixel = components * bits;
    for (final (x0, y0, x1, y1) in boxes) {
      for (var y = y0; y < y1; y++) {
        _clearBits(data, y * rowBytes, x0 * bitsPerPixel, x1 * bitsPerPixel);
      }
    }

    final out = CosDictionary({
      for (final MapEntry(:key, :value) in dict.entries.entries)
        if (_imageKeys.contains(key)) key: value,
    });
    if (!isMask) out['BitsPerComponent'] = CosInteger(bits);
    // the soft mask and stencil mask carry the same picture's shape
    for (final key in const ['SMask', 'Mask']) {
      final mask = _cos.resolve(dict[key]);
      if (mask is! CosStream) continue;
      final redacted = _redactImageSamples(mask, ctm);
      if (redacted == null) return null;
      if (!identical(redacted, mask)) out[key] = _addObject(redacted);
    }
    final payload =
        Uint8List.fromList(const ZLibEncoder().encodeBytes(data, level: 6));
    out['Filter'] = const CosName('FlateDecode');
    out['Length'] = CosInteger(payload.length);
    return CosStream(out, payload);
  }

  /// The 8-bit samples of a DCT-encoded [image], or null when the JPEG's
  /// shape disagrees with the dictionary or can't be reproduced as plain
  /// samples (CMYK/YCCK, EXIF rotation, explicit /ColorTransform).
  Uint8List? _decodeJpegSamples(
      CosStream image, int width, int height, int components) {
    if (components != 1 && components != 3) return null;
    final filters = _filterNames(image.dictionary['Filter']);
    if (_filterParams(image.dictionary, filters.length - 1) != null) {
      return null;
    }
    final bytes = _cos.decodeStreamData(image, stopBeforeFilter: 'DCTDecode');
    final decoder = imaging.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width != width ||
        info.height != height ||
        decoder.info!.numComponents != components) {
      return null;
    }
    final orientation = imaging.decodeJpgExif(bytes)?.imageIfd.orientation;
    if (orientation != null && orientation != 1) return null;
    final pixels = decoder.decodeFrame(0);
    if (pixels == null) return null;
    return pixels.getBytes(
        order: components == 1
            ? imaging.ChannelOrder.red
            : imaging.ChannelOrder.rgb);
  }

  /// Clears bits [startBit, endBit) of the row starting at [rowStart].
  static void _clearBits(
      Uint8List data, int rowStart, int startBit, int endBit) {
    var b = startBit;
    while (b < endBit) {
      if (b & 7 == 0 && b + 8 <= endBit) {
        data[rowStart + (b >> 3)] = 0;
        b += 8;
      } else {
        data[rowStart + (b >> 3)] &= ~(0x80 >> (b & 7)) & 0xFF;
        b++;
      }
    }
  }

  int? _componentCount(CosObject? colorSpace) {
    final cs = _cos.resolve(colorSpace);
    String? family;
    if (cs is CosName) family = cs.value;
    if (cs is CosArray && cs.length > 0) {
      final head = _cos.resolve(cs[0]);
      if (head is CosName) family = head.value;
    }
    switch (family) {
      case 'DeviceGray' || 'G' || 'CalGray' || 'Indexed' || 'I' || 'Separation':
        return 1;
      case 'DeviceRGB' || 'RGB' || 'CalRGB' || 'Lab':
        return 3;
      case 'DeviceCMYK' || 'CMYK':
        return 4;
      case 'ICCBased':
        final stream =
            cs is CosArray && cs.length > 1 ? _cos.resolve(cs[1]) : null;
        if (stream is! CosStream) return null;
        final n = _int(stream.dictionary['N']);
        return n > 0 ? n : null;
      case 'DeviceN':
        final names =
            cs is CosArray && cs.length > 1 ? _cos.resolve(cs[1]) : null;
        return names is CosArray && names.length > 0 ? names.length : null;
    }
    return null;
  }

  List<String> _filterNames(CosObject? filter) {
    final f = _cos.resolve(filter);
    if (f is CosName) return [f.value];
    if (f is CosArray) {
      return [
        for (final item in f.items)
          if (_cos.resolve(item) case CosName(:final value)) value,
      ];
    }
    return const [];
  }

  CosDictionary? _filterParams(CosDictionary dict, int index) {
    final p = _cos.resolve(dict['DecodeParms'] ?? dict['DP']);
    if (p is CosDictionary) return index == 0 ? p : null;
    if (p is CosArray && index < p.length) {
      final r = _cos.resolve(p[index]);
      return r is CosDictionary ? r : null;
    }
    return null;
  }

  int _int(CosObject? value, {int fallback = 0}) {
    final v = _cos.resolve(value);
    if (v is CosInteger) return v.value;
    if (v is CosReal) return v.value.round();
    return fallback;
  }

  // ------------------------------------------------------------------- text

  _RedFont? _currentFont() => _fontKnown ? _stateFont : null;

  _RedFont? _fontNamed(String name) {
    final font = _cos.resolve(_lookup('Font', name));
    return font is CosDictionary ? _fontFor(font) : null;
  }

  _RedFont? _fontFor(CosDictionary dict) {
    final cached = _fontCache[dict];
    if (cached != null) return cached;
    try {
      return _fontCache[dict] = _RedFont.from(_cos, dict);
    } on Object {
      return null; // unreadable: metrics unknown
    }
  }

  void _showText(ContentOperation op, {String prefix = ''}) {
    // Pull the (string | adjustment) elements out of the operator.
    final elements = <Object>[]; // CosString or double (TJ adjustment)
    if (op.operator == 'TJ' && op.operands.isNotEmpty) {
      final array = op.operands.first;
      if (array is CosArray) {
        for (final item in array.items) {
          if (item is CosString) {
            elements.add(item);
          } else if (item is CosInteger || item is CosReal) {
            elements.add(_n(item));
          }
        }
      }
    } else if (op.operator == '"' && op.operands.length >= 3) {
      if (op.operands[2] is CosString) elements.add(op.operands[2]);
    } else if (op.operands.isNotEmpty && op.operands.first is CosString) {
      elements.add(op.operands.first);
    }

    final font = _currentFont();
    final exact = font != null && font.metricsKnown && _slack == 0;
    if (!exact) {
      _showConservatively(op, elements, font, prefix);
      return;
    }
    final codeLength = font.codeLength!;
    final degenerate = _tfs * _th == 0;

    // Walk glyph by glyph, building a TJ array with covered glyphs removed
    // and replaced by a numeric gap so survivors keep their position.
    final rebuilt = <Object>[]; // CosString | double
    final current = BytesBuilder();
    var currentHex = false;
    var redactedAny = false;
    double pendingGap = 0; // accumulated removed advance (text-space points)
    final removedText = StringBuffer();

    void flushString() {
      if (current.length > 0) {
        rebuilt.add(CosString(current.takeBytes(), isHex: currentHex));
      }
    }

    void flushGap() {
      if (pendingGap != 0) {
        // displacement = -num/1000 * tfs * th  ⇒  num = -gap*1000/(tfs*th)
        rebuilt.add(-pendingGap * 1000 / (_tfs * _th));
        pendingGap = 0;
      }
    }

    for (final element in elements) {
      if (element is double) {
        // existing TJ adjustment: advances the cursor, carry it through
        final disp = -element / 1000 * _tfs * _th;
        if (current.length > 0) {
          flushString();
        }
        // fold into the gap stream so spacing survives either way; both are
        // forward advances, so a kern keeps its direction when re-emitted
        pendingGap += disp;
        _tm = _redMul((1, 0, 0, 1, disp, 0), _tm);
        continue;
      }
      final string = element as CosString;
      final bytes = string.bytes;
      for (var i = 0; i + codeLength <= bytes.length; i += codeLength) {
        final code =
            codeLength == 2 ? (bytes[i] << 8) | bytes[i + 1] : bytes[i];
        final w0 = font.widthOf(code); // thousandths of text space
        final glyphWidth = w0 / 1000 * _tfs * _th;
        // word spacing applies to the single-byte code 32 only (§9.3.3)
        final wordSpace = codeLength == 1 && code == 32 ? _tw : 0;
        final advance = (w0 / 1000 * _tfs + _tc + wordSpace) * _th;

        if (_glyphCovered(font, glyphWidth)) {
          redactedAny = true;
          flushString();
          pendingGap += advance;
          _span.write(font.textOf(code));
          removedText.write(font.textOf(code));
        } else {
          _flushSpan();
          flushGap();
          if (current.length > 0 && currentHex != string.isHex) {
            flushString();
          }
          currentHex = string.isHex;
          current.add(Uint8List.sublistView(bytes, i, i + codeLength));
        }
        _tm = _redMul((1, 0, 0, 1, advance, 0), _tm);
      }
    }

    if (!redactedAny) {
      // nothing covered: re-emit the original operator unchanged (it moves
      // to the next line itself, so no prefix).
      _writeOp(op);
      _useTextPatterns();
      return;
    }
    _removed();
    if (prefix.isNotEmpty) _out.add(latin1.encode(prefix));
    if (degenerate) {
      // a zero size or scale can't carry a TJ gap: the whole run goes (it
      // advances nothing a gap could stand in for, bar Tc/Tw)
      _flushSpan();
      return;
    }
    flushString();
    flushGap();

    if (rebuilt.isEmpty) {
      // everything was removed: emit nothing (but Tm already advanced).
      return;
    }
    _out.add(latin1.encode('['));
    for (final piece in rebuilt) {
      if (piece is CosString) {
        _out.add(CosSerializer.serialize(piece));
      } else {
        _out.add(latin1.encode(ContentWriter.fmt(piece as double)));
      }
      _out.addByte(0x20);
    }
    _out.add(latin1.encode('] TJ\n'));
    _useTextPatterns();
  }

  void _useTextPatterns() {
    if (_fillPattern != null) _use(_resPattern, _fillPattern!);
    if (_strokePattern != null) _use(_resPattern, _strokePattern!);
  }

  /// A show whose glyph positions can't be measured exactly - no usable
  /// font, a composite font whose code lengths or widths are unknown, a
  /// vertical CMap, or a text position already uncertain: judged by a
  /// generous bound (every code at least an em plus the spacings, in any
  /// direction) and removed whole when that touches a region.
  void _showConservatively(ContentOperation op, List<Object> elements,
      _RedFont? font, String prefix) {
    final codeLength = font?.codeLength ?? 1; // unknown: a glyph per byte
    final em = _tfs.abs();
    final th = _th.abs();
    final maxWidth = math.max(font?.maxWidth ?? 1000, 1000);
    final perCode = (maxWidth / 1000 * em + _tc.abs() + _tw.abs()) * th;
    var length = _slack;
    for (final element in elements) {
      if (element is double) {
        length += element.abs() / 1000 * em * th;
      } else {
        length += (element as CosString).bytes.length / codeLength * perCode;
      }
    }
    final pad = math.max(em, em * th);
    final m = _redMul(_tm, _ctm);
    final vertical = font?.isVertical ?? true;
    final bounds = _hullBounds([
      _redApply(m, -length - pad, _trise - length - pad),
      _redApply(m, length + pad, _trise - length - pad),
      _redApply(m, -length - pad, _trise + (vertical ? pad : length + 2 * pad)),
      _redApply(m, length + pad, _trise + (vertical ? pad : length + 2 * pad)),
    ])!;
    // whatever happens, the position after this run is uncertain
    _slack = length;
    if (!_boundsTouchAny(bounds)) {
      _writeOp(op);
      _useTextPatterns();
      return;
    }
    _removed();
    for (final element in elements) {
      if (element is! CosString) continue;
      final bytes = element.bytes;
      for (var i = 0; i + codeLength <= bytes.length; i += codeLength) {
        final code =
            codeLength == 2 ? (bytes[i] << 8) | bytes[i + 1] : bytes[i];
        _span.write(font?.textOf(code) ?? '');
      }
    }
    _flushSpan();
    if (prefix.isNotEmpty) _out.add(latin1.encode(prefix));
  }

  /// True when the glyph occupying [glyphWidth] text-space points from the
  /// current text position lies under a redaction region.
  ///
  /// The test runs along lines through the glyph's body - at [_bodyLines]
  /// of the font size above the baseline (#1162: not the full em box, which
  /// overhangs the visible glyph and reached into the line below) - and
  /// takes the glyph when a region covers more than [_minCoveredFraction]
  /// of any one, so a neighbour that only grazes a box edge stays. Along
  /// each line the glyph spans its advance clamped to a quarter..one em:
  /// the outline lives near the origin whatever /Widths claims. A Type 3
  /// glyph is tested over its procedures' real bounding box instead.
  bool _glyphCovered(_RedFont font, double glyphWidth) {
    final m = _redMul(_tm, _ctm);
    final double x0, x1;
    final List<double> ys;
    final box = font.glyphBox;
    if (box != null) {
      x0 = box.left * _tfs * _th;
      x1 = box.right * _tfs * _th;
      ys = [
        for (var i = 0; i < 4; i++)
          _trise + (box.bottom + box.height * (i + 0.5) / 4) * _tfs,
      ];
    } else {
      final em = (_tfs * _th).abs();
      final length = glyphWidth.abs().clamp(0.25 * em, em);
      final sign = glyphWidth != 0
          ? glyphWidth.sign
          : (_tfs * _th).sign == 0
              ? 1.0
              : (_tfs * _th).sign;
      x0 = 0;
      x1 = length * sign;
      ys = [for (final h in _bodyLines) _trise + h * _tfs];
    }
    for (final y in ys) {
      final (ax, ay) = _redApply(m, x0, y);
      final (bx, by) = _redApply(m, x1, y);
      for (final region in _regions) {
        // a zero-length test line is a point: 1 when inside, 0 when not
        if (_coveredFraction(ax, ay, bx, by, region) > _minCoveredFraction) {
          return true;
        }
      }
    }
    return false;
  }

  /// Heights (fractions of the font size above the baseline) of the lines a
  /// glyph is tested along: low x-height to near cap-height.
  static const _bodyLines = [0.1, 0.3, 0.5, 0.7];

  /// How much of a test line a region must cover to remove the glyph.
  static const double _minCoveredFraction = 0.1;

  /// The fraction (0..1) of the segment (x0,y0)-(x1,y1) inside [r]
  /// (Liang-Barsky clipping).
  static double _coveredFraction(
      double x0, double y0, double x1, double y1, PdfRect r) {
    final dx = x1 - x0, dy = y1 - y0;
    var t0 = 0.0, t1 = 1.0;
    for (final (p, q) in [
      (-dx, x0 - r.left),
      (dx, r.right - x0),
      (-dy, y0 - r.bottom),
      (dy, r.top - y0),
    ]) {
      if (p == 0) {
        if (q < 0) return 0; // parallel to this edge and outside it
        continue;
      }
      final t = q / p;
      if (p < 0) {
        if (t > t1) return 0;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return 0;
        if (t < t1) t1 = t;
      }
    }
    return t1 - t0;
  }

  // --------------------------------------------------------------- geometry

  bool _rectIntersectsAny(PdfRect rect) {
    for (final region in _regions) {
      if (rect.left < region.right &&
          rect.right > region.left &&
          rect.bottom < region.top &&
          rect.top > region.bottom) {
        return true;
      }
    }
    return false;
  }

  /// Like [_rectIntersectsAny], but a degenerate (zero-width or -height)
  /// rect counts when it lies inside a region.
  bool _boundsTouchAny(PdfRect? rect) {
    if (rect == null) return false;
    for (final region in _regions) {
      if (rect.left <= region.right &&
          rect.right >= region.left &&
          rect.bottom <= region.top &&
          rect.top >= region.bottom) {
        final overlapW = math.min(rect.right, region.right) -
            math.max(rect.left, region.left);
        final overlapH = math.min(rect.top, region.top) -
            math.max(rect.bottom, region.bottom);
        if ((overlapW > 0 || rect.width == 0) &&
            (overlapH > 0 || rect.height == 0)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _boundsFullyCovered(PdfRect rect) {
    for (final region in _regions) {
      if (rect.left >= region.left &&
          rect.right <= region.right &&
          rect.bottom >= region.bottom &&
          rect.top <= region.top) {
        return true;
      }
    }
    return false;
  }

  PdfRect _unitSquareBounds(_RedMatrix ctm) => _hullBounds([
        _redApply(ctm, 0, 0),
        _redApply(ctm, 1, 0),
        _redApply(ctm, 0, 1),
        _redApply(ctm, 1, 1),
      ])!;

  /// Re-serializes [op] verbatim (mirrors [PdfPageElements.serialize]).
  void _writeOp(ContentOperation op) {
    ContentStreamSerializer.writeOperation(op, _out);
  }
}

/// The glyph metrics (and text) a redaction burn needs from one font.
class _RedFont {
  _RedFont._({
    required this.isComposite,
    required this.codeLength,
    required this.metricsKnown,
    required double Function(int code) widthOf,
    required String Function(int code) textOf,
    required this.maxWidth,
    this.isVertical = false,
    this.glyphBox,
  })  : _widthOf = widthOf,
        _textOf = textOf;

  final bool isComposite;

  /// Bytes per character code; null when it can't be known without the
  /// CMap.
  final int? codeLength;

  /// Whether glyph advances (and so positions) are known exactly: /Widths
  /// or base-14 metrics for a simple font, /W for an Identity-H composite.
  final bool metricsKnown;

  /// A composite font with a vertical (`-V`) CMap.
  final bool isVertical;

  /// The widest advance the font declares (thousandths of text space).
  final double maxWidth;

  /// For a Type 3 font, the union of its glyphs' bounding boxes in text
  /// space per unit font size (FontMatrix applied); null otherwise.
  final PdfRect? glyphBox;

  final double Function(int code) _widthOf;
  final String Function(int code) _textOf;

  /// Advance of [code] in thousandths of text space.
  double widthOf(int code) => _widthOf(code);

  /// The Unicode text [code] stands for, best effort ('' when unknown).
  String textOf(int code) {
    try {
      return _textOf(code);
    } on Object {
      return '';
    }
  }

  static double _num(CosDocument cos, CosObject? o) => switch (cos.resolve(o)) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0,
      };

  static _RedFont from(CosDocument cos, CosDictionary font) {
    final subtype = cos.resolve(font['Subtype']);
    final sub = subtype is CosName ? subtype.value : '';
    if (sub == 'Type0') return _composite(cos, font);

    String Function(int) text;
    try {
      text = SimpleFont.decode(cos, font).textFor;
    } on Object {
      text =
          (code) => code >= 32 && code < 127 ? String.fromCharCode(code) : '';
    }

    var scale = 1.0;
    PdfRect? glyphBox;
    if (sub == 'Type3') {
      final matrix = _fontMatrix(cos, font);
      scale = matrix.$1 * 1000;
      glyphBox = _type3GlyphBox(cos, font, matrix);
    }

    final widthsObj = cos.resolve(font['Widths']);
    if (widthsObj is CosArray) {
      final firstChar = _num(cos, font['FirstChar']).round();
      final descriptor = cos.resolve(font['FontDescriptor']);
      final missing = descriptor is CosDictionary
          ? _num(cos, descriptor['MissingWidth'])
          : 0.0;
      final table = [for (final w in widthsObj.items) _num(cos, w)];
      final maxWidth =
          [missing, ...table].map((w) => (w * scale).abs()).fold(0.0, math.max);
      return _RedFont._(
        isComposite: false,
        codeLength: 1,
        metricsKnown: true,
        widthOf: (code) {
          final i = code - firstChar;
          return (i >= 0 && i < table.length ? table[i] : missing) * scale;
        },
        textOf: text,
        maxWidth: maxWidth,
        glyphBox: glyphBox,
      );
    }

    // no /Widths: only a base-14 face has metrics a viewer will agree on
    final baseFont = cos.resolve(font['BaseFont']);
    final standard = sub == 'Type3' || baseFont is! CosName
        ? null
        : _standardFont(baseFont.value);
    return _RedFont._(
      isComposite: false,
      codeLength: 1,
      metricsKnown: standard != null,
      widthOf: (code) =>
          (standard ?? PdfStandardFont.helvetica).widthOf(code).toDouble(),
      textOf: text,
      maxWidth: 1000,
      glyphBox: glyphBox,
    );
  }

  /// The base-14 face [baseFont] names exactly (subset tag and common
  /// metric-compatible aliases allowed), or null.
  static PdfStandardFont? _standardFont(String baseFont) {
    var n = baseFont;
    final plus = n.indexOf('+');
    if (plus == 6) n = n.substring(7);
    n = n.toLowerCase().replaceAll(RegExp(r'[-, ]|mt$|ps$'), '');
    const names = {
      'helvetica', 'helveticabold', 'helveticaoblique',
      'helveticaboldoblique', 'arial', 'arialbold', 'arialitalic',
      'arialbolditalic', 'timesroman', 'timesbold', 'timesitalic',
      'timesbolditalic', 'timesnewroman', 'timesnewromanbold',
      'timesnewromanitalic', 'timesnewromanbolditalic', 'courier',
      'courierbold', 'courieroblique', 'courierboldoblique', 'couriernew',
      'couriernewbold', 'couriernewitalic', 'couriernewbolditalic', //
    };
    if (!names.contains(n)) return null;
    return PdfStandardFont.tryFromName(n);
  }

  static _RedFont _composite(CosDocument cos, CosDictionary font) {
    var dw = 1000.0;
    var widths = <int, double>{};
    final descendants = cos.resolve(font['DescendantFonts']);
    if (descendants is CosArray && descendants.length > 0) {
      final d = cos.resolve(descendants.items.first);
      if (d is CosDictionary) {
        dw = cidDefaultWidth(cos, d);
        widths = parseCidWidths(cos, d);
      }
    }
    final encoding = cos.resolve(font['Encoding']);
    final name = encoding is CosName ? encoding.value : '';
    Map<int, String> toUnicode;
    try {
      toUnicode = Type0Font.decode(cos, font).codeToText;
    } on Object {
      toUnicode = const {};
    }
    final identityH = name == 'Identity-H';
    final vertical = encoding is! CosName || name.endsWith('-V');
    final maxWidth = [dw, ...widths.values].map((w) => w.abs()).fold(
          0.0,
          math.max,
        );
    return _RedFont._(
      isComposite: true,
      codeLength: identityH || name == 'Identity-V' ? 2 : null,
      metricsKnown: identityH,
      widthOf: (code) => widths[code] ?? dw,
      textOf: (code) => toUnicode[code] ?? '',
      maxWidth: maxWidth,
      // an embedded CMap may be vertical (/WMode 1); treat it so
      isVertical: vertical,
    );
  }

  static _RedMatrix _fontMatrix(CosDocument cos, CosDictionary font) {
    final m = cos.resolve(font['FontMatrix']);
    if (m is! CosArray || m.length < 6) return (0.001, 0, 0, 0.001, 0, 0);
    double at(int i) => _num(cos, m[i]);
    return (at(0), at(1), at(2), at(3), at(4), at(5));
  }

  /// The union of a Type 3 font's glyph boxes (from each procedure's `d1`,
  /// else /FontBBox), mapped through [matrix]; generous when unknown.
  static PdfRect _type3GlyphBox(
      CosDocument cos, CosDictionary font, _RedMatrix matrix) {
    double? x0, y0, x1, y1;
    var unknown = false;
    void include(double a, double b, double c, double d) {
      x0 = math.min(x0 ?? a, math.min(a, c));
      y0 = math.min(y0 ?? b, math.min(b, d));
      x1 = math.max(x1 ?? c, math.max(a, c));
      y1 = math.max(y1 ?? d, math.max(b, d));
    }

    final procs = cos.resolve(font['CharProcs']);
    if (procs is CosDictionary) {
      for (final p in procs.entries.values) {
        final proc = cos.resolve(p);
        if (proc is! CosStream) continue;
        try {
          final ops = ContentStreamParser.parse(cos.decodeStreamData(proc));
          final first = ops.isEmpty ? null : ops.first;
          if (first != null &&
              first.operator == 'd1' &&
              first.operands.length >= 6) {
            final o = [for (final v in first.operands) _num(cos, v)];
            include(o[2], o[3], o[4], o[5]);
          } else {
            unknown = true; // d0: draws wherever it likes
          }
        } on Object {
          unknown = true;
        }
      }
    }
    final bbox = pdfRectFrom(cos, font['FontBBox']);
    if (bbox != null && bbox.width > 0 && bbox.height > 0) {
      include(bbox.left, bbox.bottom, bbox.right, bbox.top);
    } else if (unknown || x0 == null) {
      // nothing says where the ink is: a generous few ems around the origin
      final inverse = _redInvert(matrix);
      if (inverse != null) {
        final a = _redApply(inverse, -1, -1), b = _redApply(inverse, 2, 2);
        include(a.$1, a.$2, b.$1, b.$2);
      }
    }
    if (x0 == null) return const PdfRect(-1, -1, 2, 2);
    return _hullBounds([
      _redApply(matrix, x0!, y0!),
      _redApply(matrix, x1!, y0!),
      _redApply(matrix, x0!, y1!),
      _redApply(matrix, x1!, y1!),
    ])!;
  }
}

class _RedGraphicsState {
  _RedGraphicsState({
    required this.ctm,
    required this.tfs,
    required this.tc,
    required this.tw,
    required this.th,
    required this.tl,
    required this.trise,
    required this.font,
    required this.fontKnown,
    required this.fillPattern,
    required this.strokePattern,
    required this.fillPatternSpace,
    required this.strokePatternSpace,
  });

  final _RedMatrix ctm;
  final double tfs;
  final double tc;
  final double tw;
  final double th;
  final double tl;
  final double trise;
  final _RedFont? font;
  final bool fontKnown;
  final String? fillPattern;
  final String? strokePattern;
  final bool fillPatternSpace;
  final bool strokePatternSpace;
}

typedef _RedMatrix = (double, double, double, double, double, double);

const _RedMatrix _redIdentity = (1, 0, 0, 1, 0, 0);

_RedMatrix _redMul(_RedMatrix m, _RedMatrix n) => (
      m.$1 * n.$1 + m.$2 * n.$3,
      m.$1 * n.$2 + m.$2 * n.$4,
      m.$3 * n.$1 + m.$4 * n.$3,
      m.$3 * n.$2 + m.$4 * n.$4,
      m.$5 * n.$1 + m.$6 * n.$3 + n.$5,
      m.$5 * n.$2 + m.$6 * n.$4 + n.$6,
    );

(double, double) _redApply(_RedMatrix m, double x, double y) =>
    (m.$1 * x + m.$3 * y + m.$5, m.$2 * x + m.$4 * y + m.$6);

_RedMatrix? _redInvert(_RedMatrix m) {
  final det = m.$1 * m.$4 - m.$2 * m.$3;
  if (det == 0 || !det.isFinite) return null;
  final a = m.$4 / det, b = -m.$2 / det, c = -m.$3 / det, d = m.$1 / det;
  return (a, b, c, d, -(m.$5 * a + m.$6 * c), -(m.$5 * b + m.$6 * d));
}

PdfRect? _hullBounds(List<(double, double)> points) {
  if (points.isEmpty) return null;
  var minX = points.first.$1, maxX = points.first.$1;
  var minY = points.first.$2, maxY = points.first.$2;
  for (final (x, y) in points) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return PdfRect(minX, minY, maxX, maxY);
}
