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
        _baseCtm = ctm,
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
  double _lineWidth = 1;
  double _miterLimit = 10;
  bool _dashed = false;
  int? _dashPart;
  final List<int> _dashParts = [];
  final Set<int> _usedDashParts = {};

  /// Bounds (default user space) of the current clip; null when unbounded.
  PdfRect? _clipBounds;

  /// The matrix pattern space is relative to: this stream's starting CTM.
  final _RedMatrix _baseCtm;
  bool _inText = false;

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
    // marked content left open at the end of a stream (a form that opens a
    // sequence its invoker closes) spans content this burn can't see: its
    // replacement text goes
    if (_marked.any((f) => f != null && f.props != null && !f.stripped)) {
      final open = List.of(_marked);
      _marked
        ..clear()
        ..addAll(open.where((f) => f != null && f.props != null));
      final before = changed;
      _removed();
      changed = before || _parent != null;
      _marked
        ..clear()
        ..addAll(open);
    }
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
    for (final index in _dashParts) {
      if (!_usedDashParts.contains(index)) {
        _parts[index] = latin1.encode('[] 0 d\n');
      }
    }
    final all = BytesBuilder(copy: false);
    for (final part in _parts) {
      all.add(part);
    }
    final bytes = all.takeBytes();
    // what's left of a redacted stream shouldn't trace what was there
    return changed
        ? _tidyRedactedContent(bytes, leadingKnown: _parent == null)
        : bytes;
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
      for (final MapEntry(key: name, value: entry)
          in (_retired[category] ?? const <String, CosObject>{}).entries) {
        if (!_isUsed(category, name)) {
          copy.entries.remove(name);
        } else if (entry is! CosReference) {
          // still used here, but a direct original can't be substituted at
          // save time: point the name at its one redacted copy, or drop it
          final owner = _ownerOf(category, name);
          final copies =
              owner == null ? null : _session.directRetired[owner]?[name];
          if (copies != null && copies.length == 1) {
            copy[name] = copies.single;
          } else {
            copy.entries.remove(name);
          }
        }
      }
      copy.entries.addAll(_added[category] ?? const {});
      if (sub is CosDictionary) {
        (_session.resourceCopies[sub] ??= []).add(copy);
      }
      out[category] = copy;
    }
    return out;
  }

  bool _isUsed(String category, String name) =>
      _used[category]?.contains(name) ?? false;

  void _use(String category, String name) => (_used[category] ??= {}).add(name);

  void _retire(String category, String name, CosObject? entry) {
    (_retired[category] ??= {})[name] = entry ?? CosNull.instance;
    if (entry is CosReference) {
      _session.retired.addAll(_chain(entry));
    } else if (entry != null) {
      // a direct entry lives inside a resource dictionary other pages (or
      // the page tree) may share: that dictionary is fixed at save time
      final owner = _ownerOf(category, name);
      if (owner != null) {
        (_session.directRetired[owner] ??= {})[name] ??= [];
      }
    }
    // an XObject that is its own structure item loses its alternate text
    final resolved = _cos.resolve(entry);
    final dict = resolved is CosStream
        ? resolved.dictionary
        : resolved is CosDictionary
            ? resolved
            : null;
    final sp = dict == null ? null : _cos.resolve(dict['StructParent']);
    if (sp is CosInteger) _session.removedStructParents.add(sp.value);
  }

  /// Adds [replacement] for the retired resource [entry] under a fresh
  /// name, recording it so other uses of the original can be pointed at it.
  String _replace(String category, String original, CosObject? entry,
      CosObject replacement) {
    final name = _addResource(category, replacement);
    final ref = _added[category]![name] as CosReference;
    if (entry is CosReference) {
      for (final number in _chain(entry)) {
        (_session.replacements[number] ??= []).add(ref);
      }
    } else {
      final owner = _ownerOf(category, original);
      if (owner != null) {
        ((_session.directRetired[owner] ??= {})[original] ??= []).add(ref);
      }
    }
    return name;
  }

  /// Every object number along a reference chain (an object may hold
  /// nothing but another reference): each must give way to the copy.
  List<int> _chain(CosReference ref) {
    final out = <int>[];
    CosObject current = ref;
    while (current is CosReference && out.length < 64) {
      if (out.contains(current.objectNumber)) break;
      out.add(current.objectNumber);
      current = _cos.getObject(current.objectNumber, current.generation);
    }
    return out;
  }

  /// The resource dictionary (of this stream, or of an invoker) that
  /// defines [name] in [category].
  CosDictionary? _ownerOf(String category, String name) {
    final dict = _cos.resolve(_resources[category]);
    if (dict is CosDictionary && dict.containsKey(name)) return dict;
    return _parent?._ownerOf(category, name);
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

  /// Operand shapes of the operators the burn interprets: `n` a number,
  /// `s` a string, `a` an array, `N` a name, `p` a property list (a name or
  /// a dictionary).
  static const _arity = {
    'cm': 'nnnnnn', 'Tm': 'nnnnnn', 'Td': 'nn', 'TD': 'nn', 'Tc': 'n',
    'Tw': 'n', 'Tz': 'n', 'TL': 'n', 'Ts': 'n', 'Tr': 'n', 'Tf': 'Nn',
    'Tj': 's', "'": 's', '"': 'nns', 'TJ': 'a', 'Do': 'N', 'sh': 'N',
    'gs': 'N', 'BMC': 'N', 'MP': 'N', 'BDC': 'Np', 'DP': 'Np', 'cs': 'N',
    'CS': 'N', 'm': 'nn', 'l': 'nn', 'c': 'nnnnnn', 'v': 'nnnn',
    'y': 'nnnn', 're': 'nnnn', 'w': 'n', 'M': 'n', 'J': 'n', 'j': 'n',
    'd': 'an', 'g': 'n', 'G': 'n', 'rg': 'nnn', 'RG': 'nnn', 'k': 'nnnn',
    'K': 'nnnn', 'd0': 'nn', 'd1': 'nnnnnn', 'q': '', 'Q': '', 'BT': '',
    'ET': '', 'T*': '', 'h': '', 'S': '', 's': '', 'f': '', 'F': '',
    'f*': '', 'B': '', 'B*': '', 'b': '', 'b*': '', 'n': '', 'W': '',
    'W*': '', 'EMC': '', //
  };

  static bool _isNumber(CosObject o) =>
      (o is CosInteger) || (o is CosReal && o.value.isFinite);

  /// [op] in the one form every viewer reads the same way, or null to drop
  /// it. Viewers disagree with a naive reading of a malformed operator -
  /// poppler and pdf.js keep the *last* operands of an over-long list and
  /// skip an operator whose operands have the wrong type - so the burn
  /// interprets exactly what it then writes: the last operands, of the
  /// right types, and nothing else. Too few or mistyped operands drop the
  /// operator, as a viewer does.
  ContentOperation? _canonical(ContentOperation op) {
    final operator = op.operator;
    final operands = op.operands;
    if (operator == 'sc' ||
        operator == 'SC' ||
        operator == 'scn' ||
        operator == 'SCN') {
      for (var i = 0; i < operands.length; i++) {
        final o = operands[i];
        final trailingName = i == operands.length - 1 &&
            o is CosName &&
            (operator == 'scn' || operator == 'SCN');
        if (!_isNumber(o) && !trailingName) return null;
      }
      return op;
    }
    final shape = _arity[operator];
    if (shape == null) return op; // not interpreted: passes through
    if (operands.length < shape.length) return null;
    final args = operands.sublist(operands.length - shape.length);
    for (var i = 0; i < shape.length; i++) {
      final a = args[i];
      final ok = switch (shape[i]) {
        'n' => _isNumber(a),
        's' => a is CosString,
        'a' => a is CosArray,
        'N' => a is CosName,
        _ => a is CosName || a is CosDictionary,
      };
      if (!ok) return null;
    }
    if (operator == 'TJ') {
      // only strings and numbers draw; anything else is dropped
      final items = (args.first as CosArray).items;
      final clean = [
        for (final item in items)
          if (item is CosString || _isNumber(item)) item,
      ];
      if (clean.length != items.length) {
        return ContentOperation('TJ', [CosArray(clean)]);
      }
    }
    if (args.length == operands.length) return op;
    return ContentOperation(operator, args);
  }

  void _handle(ContentOperation raw) {
    final op = _canonical(raw);
    if (op == null) return; // a viewer skips it too
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
          lineWidth: _lineWidth,
          miterLimit: _miterLimit,
          dashed: _dashed,
          dashPart: _dashPart,
          clipBounds: _clipBounds,
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
          _lineWidth = s.lineWidth;
          _miterLimit = s.miterLimit;
          _dashed = s.dashed;
          _dashPart = s.dashPart;
          _clipBounds = s.clipBounds;
        }
      case 'w':
        _lineWidth = _n(operands[0]);
      case 'M':
        _miterLimit = _n(operands[0]);
      case 'd':
        _dashed = (operands[0] as CosArray).length > 0;
        if (_dashed) {
          // its own piece: blanked at the end unless a kept stroke uses it
          // (a dash array can itself encode marks)
          _parts.add(_out.takeBytes());
          _dashPart = _parts.length;
          final piece = BytesBuilder();
          _serializeOp(op, piece);
          _parts.add(piece.takeBytes());
          _dashParts.add(_dashPart!);
          return;
        }
        _dashPart = null;
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
          _serializeOp(op, piece);
          _parts.add(piece.takeBytes());
          return;
        }
      case 'sh':
        if (_handleShading(op)) return;
      case 'BT':
        _inText = true;
        _flushSpan();
        _tm = _redIdentity;
        _tlm = _redIdentity;
        _slack = 0;
      case 'ET':
        _inText = false;
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
        final image = _canonicalInlineImage(op);
        if (image == null) {
          changed = true; // ambiguous data: dropped
          return;
        }
        _writeOp(image);
        return;
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

  /// An inline image whose data every viewer delimits the same way, or
  /// null. Viewers find the end of the data differently - by its computed
  /// length, or by scanning for `EI` - so data that could end early can
  /// smuggle operators (#1255 review). Unfiltered data is cut to its exact
  /// length; any data still holding an `EI` is refused.
  ContentOperation? _canonicalInlineImage(ContentOperation op) {
    if (op.operands.length < 2) return null;
    final dict = op.operands[0];
    final data = op.operands[1];
    if (dict is! CosDictionary || data is! CosString) return null;
    CosObject? get(String short, String long) => dict[short] ?? dict[long];
    var bytes = data.bytes;
    final filter = get('F', 'Filter');
    final unfiltered =
        filter == null || (filter is CosArray && filter.length == 0);
    if (unfiltered) {
      final width = _int(get('W', 'Width'));
      final height = _int(get('H', 'Height'));
      final mask = get('IM', 'ImageMask');
      final isMask = mask is CosBoolean && mask.value;
      final bits = isMask ? 1 : _int(get('BPC', 'BitsPerComponent'));
      final components =
          isMask ? 1 : _inlineComponents(get('CS', 'ColorSpace'));
      if (width <= 0 || height <= 0 || bits <= 0 || components == null) {
        return null;
      }
      final length = ((width * components * bits + 7) >> 3) * height;
      if (bytes.length < length) return null;
      bytes = Uint8List.sublistView(bytes, 0, length);
    }
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] == 0x45 && bytes[i + 1] == 0x49) return null; // "EI"
    }
    return ContentOperation('BI', [dict, CosString(bytes)]);
  }

  int? _inlineComponents(CosObject? colorSpace) {
    final cs = _cos.resolve(colorSpace);
    if (cs is CosName) {
      switch (cs.value) {
        case 'G' || 'DeviceGray' || 'I' || 'Indexed':
          return 1;
        case 'RGB' || 'DeviceRGB':
          return 3;
        case 'CMYK' || 'DeviceCMYK':
          return 4;
      }
      final named = _lookup('ColorSpace', cs.value);
      return named == null ? null : _componentCount(named);
    }
    return _componentCount(cs);
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
      _serializeOp(op, piece);
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
        final entry = _lookup(_resProperties, raw.value);
        _retire(_resProperties, raw.value, entry);
        final fresh = _replace(_resProperties, raw.value, entry, stripped);
        replacement =
            ContentOperation('BDC', [frame.op.operands[0], CosName(fresh)]);
      } else {
        replacement = ContentOperation('BDC', [frame.op.operands[0], stripped]);
      }
      final piece = BytesBuilder();
      _serializeOp(replacement, piece);
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
  /// barcode bar under the box. For a stroke the regions are first grown
  /// by the ink a vertex can throw (half the line width, times the miter
  /// limit), and a dashed stroke goes as soon as its inked hull touches a
  /// region - a dash pattern can place marks anywhere along an edge whose
  /// ends are outside. A straight edge merely crossing a region (a table
  /// rule, a background box) stays - what it draws inside is fixed by its
  /// points outside. Painted with a pattern or shading that can carry a
  /// picture a subpath goes as soon as its bounds touch a region.
  ///
  /// A clip is judged like a fill: a clip outline under a box (a glyph, a
  /// signature) would print its shape through whatever is painted next. A
  /// clip left with no subpath clips everything away.
  void _paintPath(ContentOperation? paint) {
    final subpaths = List.of(_path);
    final clip = _clip;
    _path.clear();
    _clip = null;
    if (paint == null) {
      // a path broken off by another operator: some viewers drop it, some
      // keep it for the next painting operator - so it goes
      if (subpaths.isNotEmpty || clip != null) changed = true;
      return;
    }

    final operator = paint.operator;
    final fills =
        const {'f', 'F', 'f*', 'B', 'B*', 'b', 'b*'}.contains(operator);
    final strokes = const {'S', 's', 'B', 'B*', 'b', 'b*'}.contains(operator);
    final patterns = <String>[
      if (fills && _fillPattern != null && _patternIsStrict(_fillPattern!))
        _fillPattern!,
      if (strokes &&
          _strokePattern != null &&
          _patternIsStrict(_strokePattern!))
        _strokePattern!,
    ];
    final inflate = strokes ? _strokeReach() : 0.0;

    bool dropForPaint(_RedSubpath s) {
      if (operator == 'n') return false;
      final hull = _hullBounds([...s.points, ...s.samples]);
      if (patterns.isNotEmpty && _boundsTouchAny(_inflate(hull, inflate))) {
        return true;
      }
      if (strokes && _dashed && _boundsTouchAny(_inflate(hull, inflate))) {
        return true;
      }
      return _anyInside(s.points, inflate) || _anyInside(s.samples, inflate);
    }

    bool dropForClip(_RedSubpath s) =>
        _anyInside(s.points, 0) || _anyInside(s.samples, 0);

    final kept = [
      for (final s in subpaths)
        if (!dropForPaint(s)) s,
    ];
    final clipKept = clip == null
        ? subpaths
        : [
            for (final s in subpaths)
              if (!dropForClip(s)) s,
          ];

    void emit(Iterable<_RedSubpath> parts) {
      for (final s in parts) {
        for (final op in s.ops) {
          _writeOp(op);
        }
      }
    }

    if (kept.length == subpaths.length && clipKept.length == subpaths.length) {
      emit(subpaths);
      if (clip != null) {
        _writeOp(clip);
        _narrowClip(subpaths);
      }
      _writeOp(paint);
      _usePaintPatterns(fills, strokes, subpaths.isNotEmpty);
      return;
    }
    _removed();
    if (kept.length != subpaths.length) {
      for (final p in patterns) {
        _retire(_resPattern, p, _lookup(_resPattern, p));
      }
    }
    if (clip != null) {
      if (clipKept.isEmpty) {
        _writeOp(ContentOperation('re', [
          CosInteger(0),
          CosInteger(0),
          CosInteger(0),
          CosInteger(0),
        ]));
      } else {
        emit(clipKept);
      }
      _writeOp(clip);
      _writeOp(ContentOperation('n', const []));
      _narrowClip(clipKept);
    }
    if (kept.isNotEmpty && operator != 'n') {
      emit(kept);
      _writeOp(paint);
      _usePaintPatterns(fills, strokes, true);
    }
  }

  /// Intersects the tracked clip bounds with [subpaths]' hull.
  void _narrowClip(List<_RedSubpath> subpaths) {
    final hull = _hullBounds([
      for (final s in subpaths) ...[...s.points, ...s.samples],
    ]);
    final bounds = hull ?? const PdfRect(0, 0, 0, 0);
    final current = _clipBounds;
    if (current == null) {
      _clipBounds = bounds;
      return;
    }
    final left = math.max(current.left, bounds.left);
    final bottom = math.max(current.bottom, bounds.bottom);
    final right = math.max(left, math.min(current.right, bounds.right));
    final top = math.max(bottom, math.min(current.top, bounds.top));
    _clipBounds = PdfRect(left, bottom, right, top);
  }

  /// How far (default user space) stroke ink can reach from a vertex: half
  /// the line width (a zero width is a one-pixel hairline), scaled by the
  /// CTM, times the miter limit for joins and at least sqrt 2 for caps.
  double _strokeReach() {
    final (a, b, c, d, _, _) = _ctm;
    final scale = math.max(math.sqrt(a * a + b * b), math.sqrt(c * c + d * d));
    final width = math.max(_lineWidth.abs() * scale, 1.0);
    final miter = _miterLimit.isFinite ? _miterLimit.abs() : 10.0;
    return width / 2 * math.max(math.sqrt2, math.min(miter, 100));
  }

  static PdfRect? _inflate(PdfRect? r, double by) => r == null
      ? null
      : PdfRect(r.left - by, r.bottom - by, r.right + by, r.top + by);

  void _usePaintPatterns(bool fills, bool strokes, bool painted) {
    if (!painted) return;
    if (strokes && _dashPart != null) _usedDashParts.add(_dashPart!);
    if (fills && _fillPattern != null) _use(_resPattern, _fillPattern!);
    if (strokes && _strokePattern != null) _use(_resPattern, _strokePattern!);
  }

  bool _anyInside(List<(double, double)> points, double inflate) {
    for (final (x, y) in points) {
      // overflowed geometry can't be placed: assume the worst
      if (!x.isFinite || !y.isFinite) return true;
      for (final r in _regions) {
        if (x >= r.left - inflate &&
            x <= r.right + inflate &&
            y >= r.bottom - inflate &&
            y <= r.top + inflate) {
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

  /// Whether painting with the named pattern must drop any subpath whose
  /// bounds touch a region: a tiling pattern (its cell is arbitrary
  /// content), or a shading pattern whose shading can carry a picture or
  /// puts its gradient's geometry under a box.
  bool _patternIsStrict(String name) {
    final pattern = _cos.resolve(_lookup(_resPattern, name));
    final dict = pattern is CosStream
        ? pattern.dictionary
        : pattern is CosDictionary
            ? pattern
            : null;
    if (dict == null) return true;
    final type = _cos.resolve(dict['PatternType']);
    if (type is CosInteger && type.value == 2) {
      final shading = _cos.resolve(dict['Shading']);
      if (_shadingCarriesPicture(shading)) return true;
      // pattern space is this stream's own starting space (§8.7.2)
      final matrix = _matrixOf(dict['Matrix']);
      return _gradientUnderBox(shading, _redMul(matrix, _baseCtm));
    }
    return true;
  }

  _RedMatrix _matrixOf(CosObject? value) {
    final m = _cos.resolve(value);
    if (m is! CosArray || m.length < 6) return _redIdentity;
    double at(int i) => _n(_cos.resolve(m[i]));
    return (at(0), at(1), at(2), at(3), at(4), at(5));
  }

  /// Whether a shading can encode a picture: anything but an axial or
  /// radial shading driven by plain exponential (type 2) functions. A
  /// stitching function's bounds are a 1-D raster, so it counts too.
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
    final f = _cos.resolve(dict['Function']);
    if (f is CosArray) {
      return f.items.isEmpty || f.items.any((g) => !_isExponential(g));
    }
    return !_isExponential(f);
  }

  bool _isExponential(CosObject? function) {
    final f = _cos.resolve(function);
    final dict = f is CosDictionary ? f : null; // a stream is sampled/PS
    if (dict == null) return false;
    final type = _cos.resolve(dict['FunctionType']);
    return type is CosInteger && type.value == 2;
  }

  /// Whether a plain gradient's defining geometry - an axial shading's end
  /// points, a radial shading's circles - lies under a region: a step
  /// placed there would encode a position the box hides.
  bool _gradientUnderBox(CosObject shading, _RedMatrix matrix) {
    final dict = shading is CosStream
        ? shading.dictionary
        : shading is CosDictionary
            ? shading
            : null;
    if (dict == null) return true;
    final coords = _cos.resolve(dict['Coords']);
    if (coords is! CosArray) return true;
    final c = [for (final v in coords.items) _n(_cos.resolve(v))];
    final points = <(double, double)>[];
    if (c.length == 4) {
      points
        ..add(_redApply(matrix, c[0], c[1]))
        ..add(_redApply(matrix, c[2], c[3]));
    } else if (c.length == 6) {
      for (final (x, y, r) in [(c[0], c[1], c[2]), (c[3], c[4], c[5])]) {
        final rr = r.abs();
        points.addAll([
          _redApply(matrix, x - rr, y - rr),
          _redApply(matrix, x + rr, y - rr),
          _redApply(matrix, x - rr, y + rr),
          _redApply(matrix, x + rr, y + rr),
        ]);
      }
      return _boundsTouchAny(_hullBounds(points.sublist(0, 4))) ||
          _boundsTouchAny(_hullBounds(points.sublist(4)));
    } else {
      return true;
    }
    return _anyInside(points, 0);
  }

  bool _handleShading(ContentOperation op) {
    final name = (op.operands.first as CosName).value;
    final entry = _lookup(_resShading, name);
    final shading = _cos.resolve(entry);
    final dict = shading is CosStream
        ? shading.dictionary
        : shading is CosDictionary
            ? shading
            : null;
    final bbox = dict == null ? null : pdfRectFrom(_cos, dict['BBox']);
    // `sh` paints the whole clip (cut to its /BBox when it has one)
    PdfRect? area = bbox == null
        ? null
        : _hullBounds([
            _redApply(_ctm, bbox.left, bbox.bottom),
            _redApply(_ctm, bbox.right, bbox.bottom),
            _redApply(_ctm, bbox.left, bbox.top),
            _redApply(_ctm, bbox.right, bbox.top),
          ]);
    final clip = _clipBounds;
    if (clip != null) {
      area = area == null
          ? clip
          : PdfRect(
              math.max(area.left, clip.left),
              math.max(area.bottom, clip.bottom),
              math.max(math.max(area.left, clip.left),
                  math.min(area.right, clip.right)),
              math.max(math.max(area.bottom, clip.bottom),
                  math.min(area.top, clip.top)));
    }
    // a shading clipped to nothing draws nothing: it goes, data and all
    if (area != null && (area.width <= 0 || area.height <= 0)) {
      _retire(_resShading, name, entry);
      changed = true;
      return true;
    }
    final reaches = area == null || _boundsTouchAny(area);
    if (reaches &&
        (_shadingCarriesPicture(shading) || _gradientUnderBox(shading, _ctm))) {
      _retire(_resShading, name, entry);
      _removed();
      return true;
    }
    _use(_resShading, name);
    return false;
  }

  // ------------------------------------------------------------- ExtGState

  /// Applies a `gs`: its /Font sets the text font, and a soft-mask group
  /// is burned like a form - its content can be extracted like any other.
  /// Returns true when the operator was rewritten (already emitted).
  bool _handleExtGState(ContentOperation op) {
    final name = (op.operands.first as CosName).value;
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
    final width = _cos.resolve(state['LW']);
    if (_isNumber(width)) _lineWidth = _n(width);
    final miter = _cos.resolve(state['ML']);
    if (_isNumber(miter)) _miterLimit = _n(miter);

    final changes = <String, CosObject?>{};
    final dash = _cos.resolve(state['D']);
    if (dash is CosArray) {
      // a dash pattern held in a resource can't be blanked per use: the
      // stream gets a solid copy (a dash array can itself encode marks)
      final pattern = dash.length > 0 ? _cos.resolve(dash[0]) : null;
      if (pattern is CosArray && pattern.length > 0) changes['D'] = null;
      _dashed = false;
      _dashPart = null;
    }
    final mask = _cos.resolve(state['SMask']);
    final group = mask is CosDictionary ? _cos.resolve(mask['G']) : null;
    if (mask is CosDictionary && group is CosStream) {
      final (groupChanged, burned) =
          _burnForm(group, _redMul(_formMatrix(group), _ctm));
      if (groupChanged) {
        final newMask = CosDictionary({
          for (final key in const ['Type', 'S', 'BC', 'TR'])
            if (mask.containsKey(key)) key: mask[key]!,
        });
        if (burned != null) newMask['G'] = _addObject(burned);
        changes['SMask'] = burned != null ? newMask : const CosName('None');
        final maskRef = mask['G'];
        if (maskRef is CosReference) {
          _session.retired.add(maskRef.objectNumber);
        }
      }
    }
    if (changes.isEmpty) {
      _use(_resExtGState, name);
      return false;
    }
    final newState = CosDictionary({...state.entries});
    changes.forEach((key, value) {
      if (value == null) {
        newState.entries.remove(key);
      } else {
        newState[key] = value;
      }
    });
    _retire(_resExtGState, name, entry);
    _removed();
    final fresh = _replace(_resExtGState, name, entry, newState);
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
    final fresh = _replace(_resXObject, name, entry, replacement);
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
      // a form without its own key numbers its MCIDs as its invoker does
      structParents: sp is CosInteger ? sp.value : _structParents,
    );
    if (_inText) {
      // a form drawn inside BT: viewers differ on the text matrix it
      // starts with, so its text is judged generously until it positions
      nested._slack = 1e6;
    }
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
    // a composite string with a stray byte, or word spacing (which viewers
    // apply differently to two-byte codes), can't be placed exactly
    final exact = font != null &&
        font.metricsKnown &&
        _slack == 0 &&
        (font.codeLength == 1 ||
            (_tw == 0 &&
                elements.every((e) =>
                    e is! CosString ||
                    e.bytes.length % font.codeLength! == 0))) &&
        elements.every((e) =>
            e is! CosString ||
            font.codeLength != 1 ||
            e.bytes.every(font.knowsCode));
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

    // First pass: place every glyph and decide which are covered.
    final glyphs = <_RedGlyph>[];
    final kerns = <int, double>{}; // glyph index -> kern displacement before it
    var word = 0;
    final em = (_tfs * _th).abs();
    for (final element in elements) {
      if (element is double) {
        final disp = -element / 1000 * _tfs * _th;
        kerns[glyphs.length] = (kerns[glyphs.length] ?? 0) + disp;
        // a kern of a fifth of an em or more separates words
        if (disp.abs() >= 0.2 * em) word++;
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
        final text = font.textOf(code);
        // a glyph with no Unicode is a letter as far as words go: treating
        // it as a space would leave its neighbours standing
        final space = (codeLength == 1 && code == 32) ||
            (text.isNotEmpty && text.trim().isEmpty);
        if (space) word++;
        glyphs.add(_RedGlyph(
          Uint8List.sublistView(bytes, i, i + codeLength),
          string.isHex,
          text,
          advance,
          glyphWidth,
          _redMul(_tm, _ctm),
          covered: _glyphCovered(font, code, glyphWidth),
          word: space ? -1 : word,
        ));
        if (space) word++;
        _tm = _redMul((1, 0, 0, 1, advance, 0), _tm);
      }
    }

    // A word that loses any letter loses them all: a fragment left standing
    // ("rives") gives away what stood next to it. The fill grows over the
    // letters taken this way.
    if (_session.wholeWords) {
      final hit = {
        for (final g in glyphs)
          if (g.covered && g.word >= 0) g.word,
      };
      // one fill per word, over the whole word: a box per letter would
      // record each letter's width
      final corners = <int, List<(double, double)>>{};
      final grown = <int>{};
      final lo = _trise - 0.25 * _tfs, hi = _trise + 0.95 * _tfs;
      for (final g in glyphs) {
        if (g.word < 0 || !hit.contains(g.word)) continue;
        if (!g.covered) grown.add(g.word);
        g.covered = true;
        final points = corners.putIfAbsent(g.word, () => []);
        points.addAll([
          _redApply(g.matrix, 0, lo),
          _redApply(g.matrix, g.width, lo),
          _redApply(g.matrix, 0, hi),
          _redApply(g.matrix, g.width, hi),
        ]);
      }
      for (final word in grown) {
        final box = _hullBounds(corners[word]!)!;
        if (_finite(box)) _session.extraFills.add(box);
      }
    }

    // Second pass: rebuild the show with the covered glyphs replaced by
    // gaps.
    for (var index = 0; index <= glyphs.length; index++) {
      final kern = kerns[index];
      if (kern != null) {
        if (current.length > 0) flushString();
        // fold into the gap stream so spacing survives either way; both are
        // forward advances, so a kern keeps its direction when re-emitted
        pendingGap += kern;
      }
      if (index == glyphs.length) break;
      final g = glyphs[index];
      if (g.covered) {
        redactedAny = true;
        flushString();
        pendingGap += g.advance;
        _span.write(g.text);
        removedText.write(g.text);
      } else {
        _flushSpan();
        flushGap();
        if (current.length > 0 && currentHex != g.isHex) flushString();
        currentHex = g.isHex;
        current.add(g.bytes);
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
  bool _glyphCovered(_RedFont font, int code, double glyphWidth) {
    final m = _redMul(_tm, _ctm);
    final double x0, x1;
    final List<double> ys;
    final box = font.glyphBoxOf(code);
    if (box != null) {
      x0 = box.left * _tfs * _th;
      x1 = box.right * _tfs * _th;
      // lines at most a fifth of an em apart, however tall the box
      final lines = (box.height / 0.2).ceil().clamp(4, 64);
      ys = [
        for (var i = 0; i < lines; i++)
          _trise + (box.bottom + box.height * (i + 0.5) / lines) * _tfs,
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
      if (!ax.isFinite || !ay.isFinite || !bx.isFinite || !by.isFinite) {
        return true; // overflowed geometry can't be placed
      }
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
    if (!_finite(rect)) return true;
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
    if (!_finite(rect)) return true;
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

  static bool _finite(PdfRect r) =>
      r.left.isFinite &&
      r.right.isFinite &&
      r.bottom.isFinite &&
      r.top.isFinite;

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
    _serializeOp(op, _out);
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
    PdfRect? Function(int code)? glyphBox,
    bool Function(int code)? knowsCode,
  })  : _knowsCode = knowsCode,
        _widthOf = widthOf,
        _textOf = textOf,
        _glyphBox = glyphBox;

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

  final PdfRect? Function(int code)? _glyphBox;
  final bool Function(int code)? _knowsCode;

  /// Whether [code]'s advance is known the way every viewer knows it.
  bool knowsCode(int code) => _knowsCode?.call(code) ?? true;

  /// For a Type 3 font, where [code]'s glyph draws, in text space per unit
  /// font size (FontMatrix applied); null for other fonts.
  PdfRect? glyphBoxOf(int code) => _glyphBox?.call(code);

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
    PdfRect? Function(int)? glyphBox;
    var skewed = false;
    if (sub == 'Type3') {
      final matrix = _fontMatrix(cos, font);
      scale = matrix.$1 * 1000;
      // advances along anything but the x axis aren't modelled
      skewed = matrix.$2 != 0 || matrix.$3 != 0 || matrix.$1 == 0;
      glyphBox = _type3GlyphBoxes(cos, font, matrix);
    }

    final widthsObj = cos.resolve(font['Widths']);
    if (widthsObj is CosArray) {
      // poppler takes only an integer /FirstChar (else 0): a real one is
      // read two ways
      final firstObj = cos.resolve(font['FirstChar']);
      final firstChar = _num(cos, firstObj).round();
      final descriptor = cos.resolve(font['FontDescriptor']);
      final missing = descriptor is CosDictionary
          ? _num(cos, descriptor['MissingWidth'])
          : 0.0;
      final table = [for (final w in widthsObj.items) _num(cos, w)];
      final maxWidth =
          [missing, ...table].map((w) => (w * scale).abs()).fold(0.0, math.max);
      // a non-numeric entry or a /LastChar disagreeing with the table is
      // read differently by different viewers (MissingWidth, 0, the font
      // program): codes it touches are placed generously
      final wellFormed = widthsObj.items.every((w) {
        final v = cos.resolve(w);
        return v is CosInteger || (v is CosReal && v.value.isFinite);
      });
      final lastObj = cos.resolve(font['LastChar']);
      final last =
          lastObj is CosInteger ? lastObj.value : firstChar + table.length - 1;
      final knownEnd = math.min(last, firstChar + table.length - 1);
      return _RedFont._(
        isComposite: false,
        codeLength: 1,
        metricsKnown: !skewed && wellFormed && firstObj is CosInteger,
        knowsCode: (code) => code >= firstChar && code <= knownEnd,
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
    // The base-14 tables are indexed by WinAnsi code, while viewers measure
    // by glyph name through the font's own encoding. Only codes that name
    // the same glyph either way are exact: all of WinAnsi for an explicit
    // /WinAnsiEncoding, else printable ASCII bar the two quote codes
    // (StandardEncoding's quoteright/quoteleft), and never a /Differences
    // code.
    final encoding = cos.resolve(font['Encoding']);
    final baseEncoding = encoding is CosName
        ? encoding.value
        : encoding is CosDictionary
            ? switch (cos.resolve(encoding['BaseEncoding'])) {
                CosName(:final value) => value,
                _ => 'StandardEncoding',
              }
            : 'StandardEncoding';
    final winAnsi = baseEncoding == 'WinAnsiEncoding';
    // MacRoman names the same glyphs as WinAnsi across printable ASCII;
    // StandardEncoding differs at the two quotes; anything else (MacExpert,
    // an unknown name) can't be trusted at all
    final ascii =
        const {'StandardEncoding', 'MacRomanEncoding'}.contains(baseEncoding);
    final quotesDiffer = baseEncoding == 'StandardEncoding';
    final differed = <int>{};
    if (encoding is CosDictionary) {
      final diffs = cos.resolve(encoding['Differences']);
      if (diffs is CosArray) {
        var code = 0;
        for (final item in diffs.items) {
          final v = cos.resolve(item);
          if (v is CosInteger) {
            code = v.value;
          } else if (v is CosName) {
            differed.add(code++);
          }
        }
      }
    }
    return _RedFont._(
      isComposite: false,
      codeLength: 1,
      metricsKnown: standard != null,
      knowsCode: (code) => winAnsi
          ? code >= 32 && code <= 255 && !differed.contains(code)
          : ascii &&
              code >= 32 &&
              code <= 126 &&
              !(quotesDiffer && (code == 0x27 || code == 0x60)) &&
              !differed.contains(code),
      widthOf: (code) =>
          (standard ?? PdfStandardFont.helvetica).widthOf(code).toDouble(),
      textOf: text,
      maxWidth: 1000,
      glyphBox: glyphBox,
    );
  }

  /// The base-14 face [baseFont] names exactly - case and all, no subset
  /// tag, no alias - or null. Viewers match these names differently
  /// (poppler exactly, pdf.js through an alias table); only the canonical
  /// names mean the same metrics to all of them.
  static PdfStandardFont? _standardFont(String baseFont) {
    const names = {
      'Helvetica': PdfStandardFont.helvetica,
      'Helvetica-Bold': PdfStandardFont.helveticaBold,
      'Helvetica-Oblique': PdfStandardFont.helveticaOblique,
      'Helvetica-BoldOblique': PdfStandardFont.helveticaBoldOblique,
      'Times-Roman': PdfStandardFont.times,
      'Times-Bold': PdfStandardFont.timesBold,
      'Times-Italic': PdfStandardFont.timesItalic,
      'Times-BoldItalic': PdfStandardFont.timesBoldItalic,
      'Courier': PdfStandardFont.courier,
      'Courier-Bold': PdfStandardFont.courierBold,
      'Courier-Oblique': PdfStandardFont.courierOblique,
      'Courier-BoldOblique': PdfStandardFont.courierBoldOblique,
    };
    return names[baseFont];
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
    final identityH = name == 'Identity-H' && !_overlappingWidths(cos, font);
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

  /// Whether a composite font's /W names a CID twice (viewers resolve
  /// overlaps differently), or holds anything but numbers and arrays.
  static bool _overlappingWidths(CosDocument cos, CosDictionary font) {
    final descendants = cos.resolve(font['DescendantFonts']);
    if (descendants is! CosArray || descendants.length == 0) return false;
    final cid = cos.resolve(descendants[0]);
    if (cid is! CosDictionary) return false;
    // poppler ignores a non-integer /DW (using 1000): read two ways
    final dw = cos.resolve(cid['DW']);
    if (dw is! CosNull && dw is! CosInteger) return true;
    final w = cos.resolve(cid['W']);
    if (w is! CosArray) return false;
    bool isNumber(CosObject o) =>
        o is CosInteger || (o is CosReal && o.value.isFinite);
    final ranges = <(int, int)>[];
    final items = [for (final i in w.items) cos.resolve(i)];
    var i = 0;
    while (i < items.length) {
      final first = items[i];
      if (first is! CosInteger) return true;
      if (i + 1 >= items.length) return true;
      final next = items[i + 1];
      if (next is CosArray) {
        // a null or name among the widths is skipped by some viewers and
        // read as 0 by others
        if (!next.items.every((v) => isNumber(cos.resolve(v)))) return true;
        ranges.add((first.value, first.value + next.length - 1));
        i += 2;
      } else if (next is CosInteger &&
          i + 2 < items.length &&
          isNumber(items[i + 2])) {
        ranges.add((first.value, next.value));
        i += 3;
      } else {
        return true;
      }
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    for (var k = 1; k < ranges.length; k++) {
      if (ranges[k].$1 <= ranges[k - 1].$2) return true;
    }
    return false;
  }

  static _RedMatrix _fontMatrix(CosDocument cos, CosDictionary font) {
    final m = cos.resolve(font['FontMatrix']);
    if (m is! CosArray || m.length < 6) return (0.001, 0, 0, 0.001, 0, 0);
    double at(int i) => _num(cos, m[i]);
    return (at(0), at(1), at(2), at(3), at(4), at(5));
  }

  /// Where each of a Type 3 font's glyphs draws, by code: the union of its
  /// procedure's `d1` box and the ink it actually lays down (paths, images
  /// - a `d1` box can lie), mapped through [matrix]. A glyph whose
  /// procedure can't be bounded (d0 colour glyphs drawing text, shadings,
  /// unparsable procedures) or whose name is unknown gets a generous box.
  static PdfRect? Function(int) _type3GlyphBoxes(
      CosDocument cos, CosDictionary font, _RedMatrix matrix) {
    final names = <int, String>{};
    final encoding = cos.resolve(font['Encoding']);
    final diffs =
        encoding is CosDictionary ? cos.resolve(encoding['Differences']) : null;
    if (diffs is CosArray) {
      var code = 0;
      for (final item in diffs.items) {
        final v = cos.resolve(item);
        if (v is CosInteger) {
          code = v.value;
        } else if (v is CosName) {
          names[code++] = v.value;
        }
      }
    }
    final procs = cos.resolve(font['CharProcs']);
    final boxes = <String, PdfRect?>{};
    PdfRect toText(PdfRect glyph) => _hullBounds([
          _redApply(matrix, glyph.left, glyph.bottom),
          _redApply(matrix, glyph.right, glyph.bottom),
          _redApply(matrix, glyph.left, glyph.top),
          _redApply(matrix, glyph.right, glyph.top),
        ])!;
    // nothing known: a generous few ems around the origin
    const generous = PdfRect(-1, -1, 2, 2);
    PdfRect boxOf(String? name) {
      if (name == null || procs is! CosDictionary) return generous;
      final glyph = boxes.putIfAbsent(name, () {
        final proc = cos.resolve(procs[name]);
        if (proc is! CosStream) return null;
        try {
          return _inkBounds(cos, proc);
        } on Object {
          return null;
        }
      });
      if (glyph == null) return generous;
      final text = toText(glyph);
      return PdfRect(
        math.min(text.left, 0),
        math.min(text.bottom, 0),
        math.max(text.right, 0),
        math.max(text.top, 0),
      );
    }

    return (code) => boxOf(names[code]);
  }

  /// The bounds (glyph space) of what a Type 3 procedure draws, with its
  /// `d1` box; null when it can't be bounded.
  static PdfRect? _inkBounds(CosDocument cos, CosStream proc) {
    final ops = ContentStreamParser.parse(cos.decodeStreamData(proc));
    var ctm = _redIdentity;
    final stack = <_RedMatrix>[];
    final points = <(double, double)>[];
    double num(CosObject o) => _num(cos, o);
    var width = 1.0; // stroke ink reaches half the line width past a point
    for (final op in ops) {
      final o = op.operands;
      List<double> nums() => [for (final v in o) num(v)];
      switch (op.operator) {
        case 'd1':
          if (o.length < 6) return null;
          final v = nums();
          points.addAll([(v[2], v[3]), (v[4], v[5])]);
        case 'q':
          stack.add(ctm);
        case 'Q':
          if (stack.isNotEmpty) ctm = stack.removeLast();
        case 'cm':
          if (o.length != 6) return null;
          final v = nums();
          ctm = _redMul((v[0], v[1], v[2], v[3], v[4], v[5]), ctm);
        case 'm' || 'l' || 'c' || 'v' || 'y':
          final v = nums();
          for (var i = 0; i + 1 < v.length; i += 2) {
            points.add(_redApply(ctm, v[i], v[i + 1]));
          }
        case 're':
          if (o.length != 4) return null;
          final v = nums();
          points.addAll([
            _redApply(ctm, v[0], v[1]),
            _redApply(ctm, v[0] + v[2], v[1] + v[3]),
            _redApply(ctm, v[0], v[1] + v[3]),
            _redApply(ctm, v[0] + v[2], v[1]),
          ]);
        case 'BI':
          points.addAll([
            _redApply(ctm, 0, 0),
            _redApply(ctm, 1, 1),
            _redApply(ctm, 0, 1),
            _redApply(ctm, 1, 0),
          ]);
        case 'w':
          if (o.isNotEmpty) width = math.max(width, num(o.first).abs());
        case 'Do' || 'sh' || 'Tj' || 'TJ' || "'" || '"' || 'd0' || 'gs':
          // a form, shading, text, colour glyph or graphics state (which
          // can set a line width): unbounded here
          return null;
      }
    }
    final hull = _hullBounds(points);
    if (hull == null) return null;
    final reach = width / 2 * 10; // miter joins at the default limit
    return PdfRect(hull.left - reach, hull.bottom - reach, hull.right + reach,
        hull.top + reach);
  }
}

/// One glyph of a show, placed: what [_RedactionBurn._showText] needs to
/// decide its fate and rebuild the run.
class _RedGlyph {
  _RedGlyph(
      this.bytes, this.isHex, this.text, this.advance, this.width, this.matrix,
      {required this.covered, required this.word});

  final Uint8List bytes;
  final bool isHex;
  final String text;
  final double advance;
  final double width;

  /// Text space to default user space at the glyph's origin.
  final _RedMatrix matrix;
  bool covered;

  /// Index of the word the glyph belongs to, or -1 for a space.
  final int word;
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
    required this.lineWidth,
    required this.miterLimit,
    required this.dashed,
    required this.dashPart,
    required this.clipBounds,
  });

  final int? dashPart;

  final double lineWidth;
  final double miterLimit;
  final bool dashed;
  final PdfRect? clipBounds;

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

/// Writes [op] as a burn writes everything: reals with every digit they
/// carry (rounding to six decimals collapses content drawn at tiny scales).
void _serializeOp(ContentOperation op, BytesBuilder out) =>
    ContentStreamSerializer.writeOperation(op, out,
        preserveRealPrecision: true);

/// Operators that put something on the page. Marked content is not among
/// them: a group or text object holding only that changes nothing drawn.
const _paintOperators = {
  'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', //
  'Do', 'sh', 'BI', 'd0', 'd1', //
};

const _showOperators = {'Tj', 'TJ', "'", '"'};
const _positionOperators = {'Td', 'TD', 'Tm', 'T*'};
const _markedOpen = {'BMC', 'BDC'};
const _markedPoint = {'MP', 'DP'};

/// Rewrites a burned content stream so what's left doesn't trace what was
/// removed, without changing what it draws:
///  * text objects that show nothing keep only the state that outlives
///    them (font, spacing, colour, graphics state), not the positions of
///    the text they held;
///  * in the others, a run of positioning operators collapses into one
///    `Tm` in front of the next show, so the stops along the way (where
///    removed lines stood) don't survive; positioning nothing uses goes,
///    and so does a kern nothing after it relies on - a kern-only show, or
///    the tail of a `TJ` - since it would only record a removed width;
///  * `q`...`Q` groups that draw nothing (the colour and line state of a
///    removed shape) go, and so does marked content left empty.
///
/// [leadingKnown] says the leading (`TL`) is known at the start - true for
/// a page; a form inherits it, so a `T*` there folds only after a `TL`.
Uint8List _tidyRedactedContent(Uint8List content,
    {required bool leadingKnown}) {
  final List<ContentOperation> ops;
  try {
    ops = ContentStreamParser.parse(content);
  } on Object {
    return content; // our own output; never expected, and safe as it is
  }
  var out = _tidyTextObjects(ops, leadingKnown: leadingKnown);
  // dropping a group can empty marked content around it, and the other way
  // round
  for (var pass = 0; pass < 8; pass++) {
    final next = _dropEmptyMarkedContent(_dropEmptyGroups(out));
    if (next.length == out.length) break;
    out = next;
  }
  return ContentStreamSerializer.serialize(out, preserveRealPrecision: true);
}

/// The text-object half of [_tidyRedactedContent].
List<ContentOperation> _tidyTextObjects(List<ContentOperation> ops,
    {required bool leadingKnown}) {
  final out = <ContentOperation>[];
  // the leading is graphics state: `q` saves it and `Q` brings it back
  double? leading = leadingKnown ? 0 : null;
  final saved = <double?>[];
  var i = 0;
  while (i < ops.length) {
    final op = ops[i];
    if (op.operator != 'BT') {
      switch (op.operator) {
        case 'q':
          saved.add(leading);
        case 'Q':
          if (saved.isNotEmpty) leading = saved.removeLast();
        case 'TL':
          leading = op.operands.isEmpty ? null : _tidyNumber(op.operands.last);
      }
      out.add(op);
      i++;
      continue;
    }
    var end = i + 1;
    while (end < ops.length && ops[end].operator != 'ET') {
      end++;
    }
    if (end >= ops.length) {
      out.addAll(ops.sublist(i)); // unterminated: left alone
      break;
    }
    final body = ops.sublist(i + 1, end);
    final shows = body.any((o) =>
        (_showOperators.contains(o.operator) && !_isEmptyShow(o)) ||
        _paintOperators.contains(o.operator) ||
        o.operator == 'q' ||
        o.operator == 'Q' ||
        o.operator == 'BT');
    if (!shows) {
      // Nothing shown: keep what outlives the object - text state, colour,
      // graphics state, and marked content that isn't closed in here.
      final unmatched = _unmatchedMarkedContent(body);
      for (var k = 0; k < body.length; k++) {
        final o = body[k];
        final name = o.operator;
        if (_positionOperators.contains(name) && name != 'TD') continue;
        if (_showOperators.contains(name)) continue; // all show nothing
        if (_markedPoint.contains(name)) continue;
        if ((_markedOpen.contains(name) || name == 'EMC') &&
            !unmatched.contains(k)) {
          continue;
        }
        if (name == 'TD') {
          // what a TD leaves behind is its leading
          final ty = o.operands.length == 2 ? _tidyNumber(o.operands[1]) : null;
          leading = ty == null ? null : -ty;
          if (ty != null) out.add(ContentOperation('TL', [_tidyOperand(-ty)]));
          continue;
        }
        if (name == 'TL') {
          leading = o.operands.isEmpty ? null : _tidyNumber(o.operands.last);
        }
        out.add(o);
      }
      i = end + 1;
      continue;
    }
    out.add(op);
    var tlm = _redIdentity;
    // once a position can't be followed, no later run in this object folds
    var tlmKnown = true;
    var run = <ContentOperation>[];
    var runFoldable = true;
    var runSetsLeading = false;
    void flushRun({required bool beforeShow}) {
      if (run.isEmpty) return;
      if (!runFoldable || !tlmKnown) {
        tlmKnown = false;
        out.addAll(run);
      } else {
        if (runSetsLeading) {
          out.add(ContentOperation('TL', [_tidyOperand(leading!)]));
        }
        if (beforeShow) {
          final (a, b, c, d, e, f) = tlm;
          out.add(ContentOperation('Tm', [
            for (final v in [a, b, c, d, e, f]) _tidyOperand(v),
          ]));
        }
      }
      run = [];
      runFoldable = true;
      runSetsLeading = false;
    }

    // Whether the pen position after the operator at [k] is never used:
    // the next thing that cares about it is a new position (or the end of
    // the object). State, marked content and shows of nothing in between
    // don't use it.
    final penUnused = List.filled(body.length, true);
    var unused = true;
    for (var j = body.length - 1; j >= 0; j--) {
      penUnused[j] = unused;
      final o = body[j];
      final name = o.operator;
      if (_positionOperators.contains(name) ||
          name == "'" ||
          name == '"' ||
          name == 'BT' ||
          name == 'ET') {
        unused = true;
      } else if ((name == 'Tj' || name == 'TJ') && !_isEmptyShow(o)) {
        unused = false;
      }
    }

    for (var k = 0; k < body.length; k++) {
      final o = body[k];
      final name = o.operator;
      // a show that draws nothing - the kern a burn leaves for a removed
      // run - only moves the pen; when nothing uses that, it would only
      // record the removed run's width
      if (_isEmptyShow(o) && penUnused[k]) continue;
      if (_positionOperators.contains(name)) {
        final v = [for (final x in o.operands) _tidyNumber(x)];
        switch (name) {
          case 'Td' || 'TD':
            if (v.length == 2 && v[0] != null && v[1] != null) {
              tlm = _redMul((1, 0, 0, 1, v[0]!, v[1]!), tlm);
              if (name == 'TD') {
                leading = -v[1]!;
                runSetsLeading = true;
              }
            } else {
              runFoldable = false;
              if (name == 'TD') leading = null;
            }
          case 'Tm':
            if (v.length == 6 && v.every((x) => x != null)) {
              tlm = (v[0]!, v[1]!, v[2]!, v[3]!, v[4]!, v[5]!);
            } else {
              runFoldable = false;
            }
          case 'T*':
            if (leading == null) {
              runFoldable = false;
            } else {
              tlm = _redMul((1, 0, 0, 1, 0, -leading), tlm);
            }
        }
        run.add(o);
        continue;
      }
      if (_showOperators.contains(name)) {
        flushRun(beforeShow: true);
        if (name == "'" || name == '"') {
          final l = leading;
          if (l == null) {
            tlmKnown = false;
          } else {
            tlm = _redMul((1, 0, 0, 1, 0, -l), tlm);
          }
        }
        out.add(name == 'TJ' && penUnused[k] ? _withoutTrailingKern(o) : o);
        continue;
      }
      if (name == 'TL') {
        leading = o.operands.isEmpty ? null : _tidyNumber(o.operands.last);
      }
      if (name == 'BT' || name == 'ET') tlmKnown = false;
      // State and marked content keep their place; a run in front of them
      // carries on past them, since none of them moves the text. One that
      // can't be followed is written out as it was, before them, so a TD's
      // leading stays ahead of a later TL.
      if (run.isNotEmpty && (!runFoldable || !tlmKnown)) {
        flushRun(beforeShow: false);
      }
      out.add(o);
    }
    // positioning nothing follows is dropped (bar the leading it sets)
    flushRun(beforeShow: false);
    out.add(ops[end]);
    i = end + 1;
  }
  return out;
}

/// The indices in [body] of marked-content operators whose partner is
/// outside it.
Set<int> _unmatchedMarkedContent(List<ContentOperation> body) {
  final open = <int>[];
  final unmatched = <int>{};
  for (var k = 0; k < body.length; k++) {
    final name = body[k].operator;
    if (_markedOpen.contains(name)) {
      open.add(k);
    } else if (name == 'EMC') {
      if (open.isEmpty) {
        unmatched.add(k);
      } else {
        open.removeLast();
      }
    }
  }
  return unmatched..addAll(open);
}

/// Drops `q`...`Q` groups that draw nothing, unless they hold half of some
/// marked content (dropping them would unbalance it).
List<ContentOperation> _dropEmptyGroups(List<ContentOperation> ops) {
  final stack = <List<ContentOperation>>[[]];
  final keep = <bool>[true];
  final marked = <int>[0]; // open marked content per group
  for (final op in ops) {
    final name = op.operator;
    if (name == 'q') {
      stack.add([op]);
      keep.add(false);
      marked.add(0);
    } else if (name == 'Q' && stack.length > 1) {
      final group = stack.removeLast()..add(op);
      final drew = keep.removeLast() || marked.removeLast() != 0;
      if (drew) {
        stack.last.addAll(group);
        keep[keep.length - 1] = true;
      }
    } else {
      stack.last.add(op);
      if (_paintOperators.contains(name) ||
          (_showOperators.contains(name) && !_isEmptyShow(op)) ||
          name == 'BT' ||
          name == 'ET') {
        keep[keep.length - 1] = true;
      } else if (_markedOpen.contains(name)) {
        marked[marked.length - 1]++;
      } else if (name == 'EMC') {
        // closing marked content opened outside the group pins it
        if (--marked[marked.length - 1] < 0) keep[keep.length - 1] = true;
      }
    }
  }
  while (stack.length > 1) {
    // unbalanced: what's left open stays
    final group = stack.removeLast();
    keep.removeLast();
    marked.removeLast();
    stack.last.addAll(group);
  }
  return stack.single;
}

/// Drops marked content that holds nothing (`BMC`/`BDC` straight before
/// its `EMC`).
List<ContentOperation> _dropEmptyMarkedContent(List<ContentOperation> ops) {
  final out = <ContentOperation>[];
  for (final op in ops) {
    if (op.operator == 'EMC' &&
        out.isNotEmpty &&
        _markedOpen.contains(out.last.operator)) {
      out.removeLast();
      continue;
    }
    out.add(op);
  }
  return out;
}

/// [o] (a `TJ`) without the kerns after its last string: nothing uses the
/// pen they move.
ContentOperation _withoutTrailingKern(ContentOperation o) {
  final a = o.operands.isEmpty ? null : o.operands.last;
  if (a is! CosArray) return o;
  var end = a.items.length;
  while (end > 0 && a.items[end - 1] is! CosString) {
    end--;
  }
  if (end == a.items.length) return o;
  if (end == 1) return ContentOperation('Tj', [a.items.first]);
  return ContentOperation('TJ', [CosArray(a.items.sublist(0, end))]);
}

/// A `Tj`/`TJ` that shows no glyph: only kerns, or empty strings.
bool _isEmptyShow(ContentOperation o) {
  if (o.operator == 'Tj') {
    final s = o.operands.isEmpty ? null : o.operands.last;
    return s is CosString && s.bytes.isEmpty;
  }
  if (o.operator != 'TJ') return false;
  final a = o.operands.isEmpty ? null : o.operands.last;
  return a is CosArray &&
      a.items.every((i) => i is! CosString || i.bytes.isEmpty);
}

/// [v] as an operand: an integer when it is one.
CosObject _tidyOperand(double v) => v == v.roundToDouble() && v.abs() < 1e15
    ? CosInteger(v.toInt())
    : CosReal(v);

double? _tidyNumber(CosObject o) => switch (o) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value.isFinite ? value : null,
      _ => null,
    };
