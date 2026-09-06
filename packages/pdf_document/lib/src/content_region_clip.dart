part of 'editor.dart';

/// Clips individual graphics draws to the complement of an erase region.
/// Coordinates are captured when each path command is constructed, then
/// mapped back through the paint-time CTM. This preserves curves, dashes,
/// stroke widths and paths constructed across cm/q/Q changes.
class _RegionGraphicsClipper {
  _RegionGraphicsClipper(this.page, this.elements, this.region, this.hitsBounds,
      this.containsBounds, this.replacements);

  final PdfPage page;
  final PdfPageElements elements;
  final List<(double, double)> region;
  final bool Function(PdfRect) hitsBounds;
  final bool Function(PdfRect) containsBounds;
  final Map<int, String> replacements;
  final _path = <ContentOperation>[];
  final _clipIndexes = <int>[];
  bool _clipDeferred = false;
  bool _validPath = true;

  static double _number(CosObject o) => PdfContentEditing._num(o);

  void _deferClip() {
    // W/W* take effect after the path is painted, not before it. Defer
    // them while a temporary erase clip consumes/replays the current path.
    _clipDeferred = true;
    for (final i in _clipIndexes) {
      replacements[i] = '';
    }
  }

  String get _pendingClip => _clipIndexes.isEmpty
      ? ''
      : elements.operations[_clipIndexes.last].operator;

  static String _serialize(Iterable<ContentOperation> ops) =>
      latin1.decode(ContentStreamSerializer.serialize(ops.toList()));

  void _command(String op, List<(double, double)> points) {
    if (points.any((p) => !p.$1.isFinite || !p.$2.isFinite)) {
      _validPath = false;
    }
    _path.add(ContentOperation(op, [
      for (final (x, y) in points) ...[CosReal(x), CosReal(y)],
    ]));
  }

  List<(double, double)> get _points => [
        for (final op in _path)
          for (var i = 0; i + 1 < op.operands.length; i += 2)
            (_number(op.operands[i]), _number(op.operands[i + 1])),
      ];

  String _replayPath(PdfMatrix inverse) => _serialize([
        for (final op in _path)
          ContentOperation(op.operator, [
            for (var i = 0; i + 1 < op.operands.length; i += 2)
              ..._mapped(inverse, _number(op.operands[i]),
                  _number(op.operands[i + 1])),
          ]),
      ]);

  static List<CosObject> _mapped(PdfMatrix matrix, double x, double y) {
    final p = matrix.apply(x, y);
    return [CosReal(p.$1), CosReal(p.$2)];
  }

  String _outsideClip(PdfMatrix inverse, PdfRect bounds) {
    // The outer contour must surround both the drawing and the whole lasso.
    // Extending beyond the MediaBox also preserves off-page artwork.
    final outer = boundsOfPoints([
      ...region,
      (page.mediaBox.left, page.mediaBox.bottom),
      (page.mediaBox.right, page.mediaBox.top),
      (bounds.left, bounds.bottom),
      (bounds.right, bounds.top),
    ])!;
    final contours = [
      <(double, double)>[
        (outer.left - 1, outer.bottom - 1),
        (outer.right + 1, outer.bottom - 1),
        (outer.right + 1, outer.top + 1),
        (outer.left - 1, outer.top + 1),
      ],
      region,
    ];
    return _serialize([
      for (final contour in contours) ...[
        ContentOperation(
            'm', _mapped(inverse, contour.first.$1, contour.first.$2)),
        for (final (x, y) in contour.skip(1))
          ContentOperation('l', _mapped(inverse, x, y)),
        ContentOperation('h', const []),
      ],
      ContentOperation('W*', const []),
      ContentOperation('n', const []),
    ]);
  }

  int rewrite() {
    final draws = {
      for (final e in elements.elements)
        if (e.kind != PdfElementKind.text) e.end - 1: e,
    };
    if (draws.isEmpty) return 0;
    var state = _RegionGraphicsState();
    final stack = <_RegionGraphicsState>[];
    var changed = 0;
    for (var i = 0; i < elements.operations.length; i++) {
      final op = elements.operations[i];
      final args = op.operands;
      switch (op.operator) {
        case 'q':
          stack.add(state.copy());
        case 'Q':
          if (stack.isNotEmpty) state = stack.removeLast();
        case 'cm':
          if (args.length >= 6) {
            state.ctm = PdfMatrix.row(args.take(6).map(_number).toList())
                .concat(state.ctm);
          }
        case 'w':
          if (args.isNotEmpty) state.width = _number(args[0]).abs();
        case 'M':
          if (args.isNotEmpty) state.miter = _number(args[0]).abs();
        case 'j':
          if (args.isNotEmpty) state.join = _number(args[0]).toInt();
        case 'gs':
          final cos = elements.document.cos;
          final resources = cos.resolve(page.resources['ExtGState']);
          if (args.isNotEmpty &&
              args.first is CosName &&
              resources is CosDictionary) {
            final gs = cos.resolve(resources[(args.first as CosName).value]);
            if (gs is CosDictionary) {
              final width = cos.resolve(gs['LW']);
              final miter = cos.resolve(gs['ML']);
              final join = cos.resolve(gs['LJ']);
              if (width is CosInteger || width is CosReal) {
                state.width = _number(width).abs();
              }
              if (miter is CosInteger || miter is CosReal) {
                state.miter = _number(miter).abs();
              }
              if (join is CosInteger) state.join = join.value;
            }
          }
        case 'm' || 'l' || 'c' || 'v' || 'y':
          final needed = op.operator == 'c'
              ? 6
              : op.operator == 'v' || op.operator == 'y'
                  ? 4
                  : 2;
          if (args.length < needed) {
            _validPath = false;
          } else {
            _command(op.operator, [
              for (var j = 0; j < needed; j += 2)
                state.ctm.apply(_number(args[j]), _number(args[j + 1])),
            ]);
          }
        case 're':
          if (args.length < 4) {
            _validPath = false;
          } else {
            final x = _number(args[0]), y = _number(args[1]);
            final w = _number(args[2]), h = _number(args[3]);
            _command('m', [state.ctm.apply(x, y)]);
            _command('l', [state.ctm.apply(x + w, y)]);
            _command('l', [state.ctm.apply(x + w, y + h)]);
            _command('l', [state.ctm.apply(x, y + h)]);
            _command('h', const []);
          }
        case 'h':
          _command('h', const []);
        case 'W' || 'W*':
          _clipIndexes.add(i);
          if (_clipDeferred) replacements[i] = '';
      }
      final pathEnd = const {
        'S',
        's',
        'f',
        'F',
        'f*',
        'B',
        'B*',
        'b',
        'b*',
        'n'
      }.contains(op.operator);
      final draw = draws[i];
      final inverse = draw == null ? null : state.ctm.inverted();
      var bounds = draw?.bounds;
      if (draw?.kind == PdfElementKind.path && _validPath) {
        bounds = boundsOfPoints(_points);
        if (bounds != null &&
            const {'S', 's', 'B', 'B*', 'b', 'b*'}.contains(op.operator)) {
          final m = state.ctm;
          final scale =
              math.sqrt(m.a * m.a + m.b * m.b + m.c * m.c + m.d * m.d);
          final pad = math.max(
              1.0,
              state.width /
                  2 *
                  scale *
                  math.max(math.sqrt2, state.join == 0 ? state.miter : 1));
          bounds = PdfRect(bounds.left - pad, bounds.bottom - pad,
              bounds.right + pad, bounds.top + pad);
        }
      }
      if (draw != null &&
          bounds != null &&
          inverse != null &&
          _validPath &&
          hitsBounds(bounds)) {
        if (draw.kind == PdfElementKind.path) {
          _deferClip();
          if (containsBounds(bounds)) {
            replacements[i] = '$_pendingClip\nn';
          } else {
            final path = _replayPath(inverse);
            replacements[i] = 'n\nq\n${_outsideClip(inverse, bounds)}'
                '$path${op.operator}\nQ\n'
                '${_pendingClip.isEmpty ? '' : '$path$_pendingClip\nn\n'}';
          }
        } else {
          // q/Q do not save the current path. Preserve a path under
          // construction across an interleaved image/form invocation.
          _deferClip();
          final path = _replayPath(inverse);
          replacements[i] = containsBounds(bounds)
              ? ''
              : 'q\nn\n${_outsideClip(inverse, bounds)}'
                  '${_serialize([op])}Q\n$path';
        }
        changed++;
      } else if (pathEnd && _clipDeferred && _pendingClip.isNotEmpty) {
        replacements[i] = '$_pendingClip\n${_serialize([op])}';
      }
      if (pathEnd) {
        _path.clear();
        _clipIndexes.clear();
        _clipDeferred = false;
        _validPath = true;
      }
    }
    return changed;
  }
}

class _RegionGraphicsState {
  PdfMatrix ctm = PdfMatrix.identity;
  double width = 1;
  double miter = 10;
  int join = 0;

  _RegionGraphicsState copy() => _RegionGraphicsState()
    ..ctm = ctm
    ..width = width
    ..miter = miter
    ..join = join;
}
