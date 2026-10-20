part of 'editor.dart';

/// A device color found in page-content color operators.
class PdfContentColor {
  const PdfContentColor({
    required this.rgb,
    required this.fillUses,
    required this.strokeUses,
  });

  /// The color as `0xRRGGBB`.
  final int rgb;

  /// Number of non-stroking color operators using this color.
  final int fillUses;

  /// Number of stroking color operators using this color.
  final int strokeUses;

  /// Total number of color operators using this color.
  int get uses => fillUses + strokeUses;
}

class _ContentColorAccumulator {
  var fillUses = 0;
  var strokeUses = 0;
}

/// Page-content color processing: find a device color and replace it with
/// another across content streams.
extension PdfColorProcessing on PdfEditor {
  /// Device colours in an annotation's normal appearance (including nested
  /// forms and implicit default-black painting) and editable style dictionaries. Raster pixels, patterns
  /// and shading functions are not scanned.
  List<PdfContentColor> annotationColors(
    int index,
    PdfAnnotation annotation, {
    bool fill = true,
    bool stroke = true,
  }) {
    final collector = _ColorCollector(
      editor: this,
      page: document.page(index),
      fill: fill,
      stroke: stroke,
    );
    final visiting = <CosStream>{};
    void scan(
        CosStream form, CosDictionary inherited, _ColorGraphicsState state) {
      if (!visiting.add(form)) return;
      final resources = document.cos.resolve(form.dictionary['Resources']);
      final effective = resources is CosDictionary ? resources : inherited;
      final operations =
          ContentStreamParser.parse(document.cos.decodeStreamData(form));
      final nested = _ColorCollector(
        editor: this,
        page: document.page(index),
        fill: fill,
        stroke: stroke,
        resources: effective,
        initialState: state,
        includeImplicit: true,
      );
      final xObjects = document.cos.resolve(effective['XObject']);
      for (final op in operations) {
        nested.scan([op]);
        if (op.operator != 'Do' || xObjects is! CosDictionary) continue;
        final name = op.operands.firstOrNull;
        if (name is! CosName) continue;
        final child = document.cos.resolve(xObjects[name.value]);
        if (child is CosStream &&
            document.cos.resolve(child.dictionary['Subtype']) ==
                const CosName('Form')) {
          scan(child, effective, nested._state);
        }
      }
      collector.merge(nested.colors());
      visiting.remove(form);
    }

    final appearance = annotation.normalAppearance;
    if (appearance != null) {
      scan(appearance, document.page(index).resources,
          const _ColorGraphicsState());
    }
    collector.scan(_annotationStyleColors(annotation));
    return collector.colors();
  }

  /// Replaces only matching colours in one annotation, cloning appearance
  /// forms before changing them so other annotations sharing artwork survive.
  /// Returns changed colour operators/style entries (paint sides in transparent
  /// mode). Geometry, identity and unrelated colours are retained.
  int replaceAnnotationColors(
    int index,
    PdfAnnotation annotation, {
    int? find,
    Iterable<int>? finds,
    int replace = 0,
    int tolerance = 0,
    bool fill = true,
    bool stroke = true,
    bool transparent = false,
  }) {
    final colors = _findColors(find, finds);
    if (colors.isEmpty || (!fill && !stroke)) return 0;
    _ColorProcessor processor(
            [CosDictionary? resources, _ColorGraphicsState? state]) =>
        _ColorProcessor(
          editor: this,
          page: document.page(index),
          resources: resources,
          finds: colors,
          replace: replace & 0xFFFFFF,
          tolerance: tolerance.clamp(0, 255),
          fill: fill,
          stroke: stroke,
          transparent: transparent,
          initialState: state,
          includeImplicit: state != null,
        );
    var count = 0;
    final visiting = <CosStream>{};
    final done = <(CosStream, _ColorGraphicsState), CosObject>{};
    CosObject rewrite(
        CosStream form, CosDictionary inherited, _ColorGraphicsState state) {
      final key = (form, state);
      if (done[key] case final cached?) return cached;
      if (!visiting.add(form)) return form;
      final resources = document.cos.resolve(form.dictionary['Resources']);
      final effective = resources is CosDictionary ? resources : inherited;
      final operations =
          ContentStreamParser.parse(document.cos.decodeStreamData(form));
      final p = processor(effective, state);
      final rewritten = <ContentOperation>[];
      final xObjects = document.cos.resolve(effective['XObject']);
      CosDictionary? changedObjects;
      final formUses = <String, int>{};
      for (final op in operations) {
        if (op.operator == 'Do') {
          if (op.operands.firstOrNull case final CosName name) {
            formUses.update(name.value, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      }
      for (final op in operations) {
        if (op.operator != 'Do' || xObjects is! CosDictionary) {
          rewritten.addAll(p._rewriteWithImplicit(op));
          continue;
        }
        final name = op.operands.firstOrNull;
        final child =
            name is CosName ? document.cos.resolve(xObjects[name.value]) : null;
        if (child is! CosStream ||
            document.cos.resolve(child.dictionary['Subtype']) !=
                const CosName('Form')) {
          rewritten.add(op);
          continue;
        }
        final result = rewrite(child, effective, p._state);
        if (identical(result, child)) {
          rewritten.add(op);
          continue;
        }
        changedObjects ??= CosDictionary({...xObjects.entries});
        var childName = (formUses[(name as CosName).value] == 1)
            ? name.value
            : 'ColorForm${changedObjects.entries.length}';
        if (childName != name.value) {
          while (changedObjects.containsKey(childName)) {
            childName = '${childName}_';
          }
        }
        changedObjects[childName] = result;
        rewritten.add(ContentOperation('Do', [CosName(childName)]));
      }
      count += p.count;
      visiting.remove(form);
      if (p.count == 0 && changedObjects == null) return done[key] = form;
      final bytes = ContentStreamSerializer.serialize(rewritten);
      final dict = CosDictionary({...form.dictionary.entries})
        ..entries.remove('Filter')
        ..entries.remove('DecodeParms')
        ..entries.remove('DP')
        ..['Length'] = CosInteger(bytes.length);
      if (changedObjects != null) {
        dict['Resources'] = CosDictionary({...effective.entries})
          ..['XObject'] = changedObjects;
      }
      return done[key] = _updater.addObject(CosStream(dict, bytes));
    }

    final appearance = annotation.normalAppearance;
    if (appearance != null) {
      final result = rewrite(appearance, document.page(index).resources,
          const _ColorGraphicsState());
      if (!identical(result, appearance)) {
        final ap = document.cos.resolve(annotation.dict['AP']);
        // Non-widget normal appearances may still be state dictionaries.
        final normal =
            ap is CosDictionary ? document.cos.resolve(ap['N']) : null;
        CosObject newNormal = result;
        if (normal is CosDictionary) {
          final state = document.cos.resolve(annotation.dict['AS']);
          final name =
              state is CosName ? state.value : normal.entries.keys.single;
          newNormal = CosDictionary({...normal.entries})..[name] = result;
        }
        annotation.dict['AP'] = CosDictionary({
          if (ap is CosDictionary) ...ap.entries,
          'N': newNormal,
        });
      }
    }
    // Keep style metadata in step with the appearance, so subsequent edits
    // and other PDF viewers use the new colours too.
    for (final entry in _annotationColorEntries(annotation).entries) {
      final p = processor();
      final op = entry.value;
      final out = p.rewrite([
        op,
        ContentOperation(
          op.operator == 'RG' ? 'S' : 'f',
          const [],
        )
      ]);
      if (p.count == 0) continue;
      count += p.count;
      annotation.dict[entry.key] =
          transparent ? CosArray([]) : CosArray(out.first.operands);
    }
    final da = annotation.defaultAppearance;
    if (da != null) {
      final p = processor();
      final out = p.rewrite(
          ContentStreamParser.parse(Uint8List.fromList(latin1.encode(da))));
      if (p.count > 0) {
        annotation.dict['DA'] = CosString.fromText(
            latin1.decode(ContentStreamSerializer.serialize(out)));
        count += p.count;
      }
    }
    if (fill && !transparent) {
      // CSS declarations only: never replace a matching hex string in text.
      final cssColor = RegExp(
          r'((?:^|;)\s*color\s*:\s*)#([0-9a-f]{6}|[0-9a-f]{3})(?![0-9a-f])',
          caseSensitive: false);
      final p = processor();
      String replaceCss(String css) => css.replaceAllMapped(cssColor, (m) {
            var hex = m[2]!;
            if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
            if (!p._matches(int.parse(hex, radix: 16))) return m[0]!;
            count++;
            return '${m[1]}#${(replace & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
          });
      final styleAttribute = RegExp(r'''(\bstyle\s*=\s*["'])([^"']*)(["'])''',
          caseSensitive: false);
      for (final key in const ['RC', 'DS']) {
        final value = document.cos.resolve(annotation.dict[key]);
        if (value is! CosString) continue;
        final text = key == 'DS'
            ? replaceCss(value.text)
            : value.text.replaceAllMapped(
                styleAttribute, (m) => '${m[1]}${replaceCss(m[2]!)}${m[3]}');
        if (text != value.text) annotation.dict[key] = CosString.fromText(text);
      }
    }
    if (count > 0) _markAnnotationChanged(index, annotation.dict);
    return count;
  }

  Map<String, ContentOperation> _annotationColorEntries(PdfAnnotation a) => {
        if (!isVectorSnapshotStamp(a))
          if (a.color case final rgb?)
            'C': ContentOperation(
              const ['Ink', 'Line', 'PolyLine', 'Polygon', 'Square', 'Circle']
                      .contains(a.subtype)
                  ? 'RG'
                  : 'rg',
              _rgbColorOperands(rgb),
            ),
        if (a.interiorColor case final rgb?)
          'IC': ContentOperation('rg', _rgbColorOperands(rgb)),
      };

  List<ContentOperation> _annotationStyleColors(PdfAnnotation annotation) => [
        ..._annotationColorEntries(annotation).values,
        if (annotation.defaultAppearance case final da?)
          ...ContentStreamParser.parse(Uint8List.fromList(latin1.encode(da))),
      ];

  List<CosObject> _rgbColorOperands(int rgb) => [
        for (final shift in const [16, 8, 0])
          CosReal(((rgb >> shift) & 255) / 255),
      ];

  /// Returns the device colors explicitly set on page [index], sorted by
  /// frequency descending and then by RGB value.
  ///
  /// This scans page-content color operators in DeviceGray, DeviceRGB and
  /// DeviceCMYK, plus `sc`/`SC` variants while the current color space is one
  /// of those device spaces. Image pixels, shadings, patterns, form XObjects,
  /// annotation appearances, and implicit default black are outside this pass.
  List<PdfContentColor> contentColors(
    int index, {
    bool fill = true,
    bool stroke = true,
  }) {
    if (!fill && !stroke) return const [];
    if (index < 0 || index >= document.pageCount) {
      throw RangeError.range(index, 0, document.pageCount - 1, 'index');
    }
    final page = document.page(index);
    final operations = ContentStreamParser.parse(page.contentBytes());
    final collector = _ColorCollector(
      editor: this,
      page: page,
      fill: fill,
      stroke: stroke,
    )..scan(operations);
    return collector.colors();
  }

  /// Returns the explicit device colors set on [indices] as one merged list.
  List<PdfContentColor> contentColorsOnPages(
    Iterable<int> indices, {
    bool fill = true,
    bool stroke = true,
  }) {
    if (!fill && !stroke) return const [];
    final uses = <int, _ContentColorAccumulator>{};
    final seen = <int>{};
    for (final index in indices) {
      if (!seen.add(index)) continue;
      for (final color in contentColors(index, fill: fill, stroke: stroke)) {
        final acc = uses.putIfAbsent(color.rgb, _ContentColorAccumulator.new);
        acc.fillUses += color.fillUses;
        acc.strokeUses += color.strokeUses;
      }
    }
    final colors = [
      for (final entry in uses.entries)
        PdfContentColor(
          rgb: entry.key,
          fillUses: entry.value.fillUses,
          strokeUses: entry.value.strokeUses,
        ),
    ];
    colors.sort((a, b) {
      final byUses = b.uses.compareTo(a.uses);
      return byUses != 0 ? byUses : a.rgb.compareTo(b.rgb);
    });
    return colors;
  }

  /// Replaces matching vector/text drawing colors on page [index].
  ///
  /// [find] and [finds] are `0xRRGGBB`; pass [finds] to match several source
  /// colors in one pass. [replace] is ignored when [transparent] is true.
  /// [tolerance] is an 8-bit channel tolerance (`0` means exact; `255`
  /// matches every channel). Set [fill] or [stroke] false to leave that paint
  /// side untouched. Returns the number of color-setting operators rewritten,
  /// or the number of paint sides suppressed in transparent mode.
  ///
  /// This edits page content streams: text fill, path fill/stroke, and other
  /// operators that set the current non-stroking/stroking color. It handles
  /// DeviceGray, DeviceRGB and DeviceCMYK operators plus `sc`/`SC` variants
  /// while the current color space is one of those device spaces. Image
  /// pixels, shading functions, patterns, form XObjects, and annotation
  /// appearance streams are intentionally left unchanged.
  int replaceColors(
    int index, {
    int? find,
    Iterable<int>? finds,
    int replace = 0x000000,
    int tolerance = 0,
    bool fill = true,
    bool stroke = true,
    bool transparent = false,
  }) {
    if (!fill && !stroke) return 0;
    final findColors = _findColors(find, finds);
    if (findColors.isEmpty) return 0;
    if (index < 0 || index >= document.pageCount) {
      throw RangeError.range(index, 0, document.pageCount - 1, 'index');
    }
    final page = document.page(index);
    final operations = ContentStreamParser.parse(page.contentBytes());
    final processor = _ColorProcessor(
      editor: this,
      page: page,
      finds: findColors,
      replace: replace & 0xFFFFFF,
      tolerance: tolerance.clamp(0, 255).toInt(),
      fill: fill,
      stroke: stroke,
      transparent: transparent,
    );
    final rewritten = processor.rewrite(operations);
    if (processor.count == 0) return 0;
    _setContent(index, page, ContentStreamSerializer.serialize(rewritten));
    return processor.count;
  }

  /// Runs [replaceColors] over [indices] as one editor operation and returns
  /// the total number of color-setting operators rewritten.
  int replaceColorsOnPages(
    Iterable<int> indices, {
    int? find,
    Iterable<int>? finds,
    int replace = 0x000000,
    int tolerance = 0,
    bool fill = true,
    bool stroke = true,
    bool transparent = false,
  }) {
    final findColors = _findColors(find, finds);
    if (findColors.isEmpty) return 0;
    var count = 0;
    final seen = <int>{};
    for (final index in indices) {
      if (!seen.add(index)) continue;
      count += replaceColors(
        index,
        finds: findColors,
        replace: replace,
        tolerance: tolerance,
        fill: fill,
        stroke: stroke,
        transparent: transparent,
      );
    }
    return count;
  }

  List<int> _findColors(int? find, Iterable<int>? finds) {
    final colors = {
      if (find != null) find & 0xFFFFFF,
      if (finds != null)
        for (final color in finds) color & 0xFFFFFF,
    }.toList()
      ..sort();
    return colors;
  }
}

enum _DeviceColorSpace { gray, rgb, cmyk, other }

enum _PaintSide { fill, stroke }

class _ColorGraphicsState {
  const _ColorGraphicsState({
    this.fillSpace = _DeviceColorSpace.gray,
    this.strokeSpace = _DeviceColorSpace.gray,
    this.transparentFill = false,
    this.transparentStroke = false,
    this.textRenderingMode = 0,
    this.fillDefined = false,
    this.strokeDefined = false,
  });

  final _DeviceColorSpace fillSpace;
  final _DeviceColorSpace strokeSpace;
  final bool transparentFill;
  final bool transparentStroke;
  final int textRenderingMode;
  final bool fillDefined;
  final bool strokeDefined;

  _ColorGraphicsState copyWith({
    _DeviceColorSpace? fillSpace,
    _DeviceColorSpace? strokeSpace,
    bool? transparentFill,
    bool? transparentStroke,
    int? textRenderingMode,
    bool? fillDefined,
    bool? strokeDefined,
  }) =>
      _ColorGraphicsState(
        fillSpace: fillSpace ?? this.fillSpace,
        strokeSpace: strokeSpace ?? this.strokeSpace,
        transparentFill: transparentFill ?? this.transparentFill,
        transparentStroke: transparentStroke ?? this.transparentStroke,
        textRenderingMode: textRenderingMode ?? this.textRenderingMode,
        fillDefined: fillDefined ?? this.fillDefined,
        strokeDefined: strokeDefined ?? this.strokeDefined,
      );
}

abstract class _ColorScannerBase {
  _ColorScannerBase({
    required this.editor,
    required this.page,
    required this.fill,
    required this.stroke,
    this.resources,
    this.includeImplicit = false,
    _ColorGraphicsState? initialState,
  }) : _state = initialState ?? const _ColorGraphicsState();

  final PdfEditor editor;
  final PdfPage page;
  final bool fill;
  final bool stroke;
  final CosDictionary? resources;

  final bool includeImplicit;
  _ColorGraphicsState _state;
  final List<_ColorGraphicsState> _stack = [];

  Iterable<ContentOperation> _implicitColors(ContentOperation op) sync* {
    if (!includeImplicit) return;
    final text = const ['Tj', 'TJ', "'", '"'].contains(op.operator);
    final usesFill =
        const ['f', 'F', 'f*', 'B', 'B*', 'b', 'b*'].contains(op.operator) ||
            (text && const [0, 2, 4, 6].contains(_state.textRenderingMode));
    final usesStroke =
        const ['S', 's', 'B', 'B*', 'b', 'b*'].contains(op.operator) ||
            (text && const [1, 2, 5, 6].contains(_state.textRenderingMode));
    if (fill && usesFill && !_state.fillDefined) {
      yield ContentOperation('g', [CosInteger(0)]);
    }
    if (stroke && usesStroke && !_state.strokeDefined) {
      yield ContentOperation('G', [CosInteger(0)]);
    }
  }

  void _trackOperation(ContentOperation op) {
    switch (op.operator) {
      case 'q':
        _stack.add(_state);
        return;
      case 'Q':
        if (_stack.isNotEmpty) _state = _stack.removeLast();
        return;
      case 'cs':
        _state = _state.copyWith(
          fillSpace: _spaceFromOperands(op.operands),
          fillDefined: true,
          transparentFill: false,
        );
        return;
      case 'CS':
        _state = _state.copyWith(
          strokeSpace: _spaceFromOperands(op.operands),
          strokeDefined: true,
          transparentStroke: false,
        );
        return;
      case 'g':
        _setColor(op, _PaintSide.fill, _DeviceColorSpace.gray);
        return;
      case 'G':
        _setColor(op, _PaintSide.stroke, _DeviceColorSpace.gray);
        return;
      case 'rg':
        _setColor(op, _PaintSide.fill, _DeviceColorSpace.rgb);
        return;
      case 'RG':
        _setColor(op, _PaintSide.stroke, _DeviceColorSpace.rgb);
        return;
      case 'k':
        _setColor(op, _PaintSide.fill, _DeviceColorSpace.cmyk);
        return;
      case 'K':
        _setColor(op, _PaintSide.stroke, _DeviceColorSpace.cmyk);
        return;
      case 'sc' || 'scn':
        _currentSpaceColor(op, _PaintSide.fill);
        return;
      case 'SC' || 'SCN':
        _currentSpaceColor(op, _PaintSide.stroke);
        return;
      case 'Tr':
        final value = _intOperand(op.operands.firstOrNull);
        if (value != null) {
          _state = _state.copyWith(textRenderingMode: value.clamp(0, 7));
        }
        return;
    }
  }

  void _setColor(
    ContentOperation op,
    _PaintSide side,
    _DeviceColorSpace space,
  ) {
    _setSpace(side, space);
    _onColor(op, side, space);
  }

  void _currentSpaceColor(ContentOperation op, _PaintSide side) {
    if (op.operands.any((operand) => operand is CosName)) {
      return; // pattern names and separations are outside this pass
    }
    final space =
        side == _PaintSide.fill ? _state.fillSpace : _state.strokeSpace;
    _onColor(op, side, space);
  }

  void _onColor(ContentOperation op, _PaintSide side, _DeviceColorSpace space);

  void _setSpace(_PaintSide side, _DeviceColorSpace space) {
    _state = side == _PaintSide.fill
        ? _state.copyWith(fillSpace: space, fillDefined: true)
        : _state.copyWith(strokeSpace: space, strokeDefined: true);
  }

  _DeviceColorSpace _spaceFromOperands(List<CosObject> operands) {
    if (operands.isEmpty) return _DeviceColorSpace.other;
    final first = operands.first;
    if (first is! CosName) return _DeviceColorSpace.other;
    return _spaceFromName(first.value);
  }

  _DeviceColorSpace _spaceFromName(String name) {
    switch (name) {
      case 'DeviceGray' || 'G':
        return _DeviceColorSpace.gray;
      case 'DeviceRGB' || 'RGB':
        return _DeviceColorSpace.rgb;
      case 'DeviceCMYK' || 'CMYK':
        return _DeviceColorSpace.cmyk;
    }

    final colorSpaces = editor.document.cos.resolve(
      (resources ?? page.resources)['ColorSpace'],
    );
    if (colorSpaces is! CosDictionary) return _DeviceColorSpace.other;
    return _spaceFromObject(editor.document.cos.resolve(colorSpaces[name]));
  }

  _DeviceColorSpace _spaceFromObject(CosObject? object) {
    final resolved = editor.document.cos.resolve(object);
    if (resolved is CosName) return _spaceFromName(resolved.value);
    if (resolved is CosArray && resolved.items.isNotEmpty) {
      final first = editor.document.cos.resolve(resolved.items.first);
      if (first is CosName) return _spaceFromName(first.value);
    }
    if (resolved is CosStream) {
      final n = editor.document.cos.resolve(resolved.dictionary['N']);
      if (n is CosInteger) {
        return switch (n.value) {
          1 => _DeviceColorSpace.gray,
          3 => _DeviceColorSpace.rgb,
          4 => _DeviceColorSpace.cmyk,
          _ => _DeviceColorSpace.other,
        };
      }
    }
    return _DeviceColorSpace.other;
  }

  int? _rgbFrom(List<CosObject> operands, _DeviceColorSpace space) {
    double clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

    double? component(int index) {
      if (index >= operands.length) return null;
      return switch (operands[index]) {
        CosInteger(:final value) => clamp01(value.toDouble()),
        CosReal(:final value) => clamp01(value),
        _ => null,
      };
    }

    int byte(double value) => (clamp01(value) * 255).round();

    switch (space) {
      case _DeviceColorSpace.gray:
        final g = component(0);
        if (g == null) return null;
        final b = byte(g);
        return (b << 16) | (b << 8) | b;
      case _DeviceColorSpace.rgb:
        final r = component(0), g = component(1), b = component(2);
        if (r == null || g == null || b == null) return null;
        return (byte(r) << 16) | (byte(g) << 8) | byte(b);
      case _DeviceColorSpace.cmyk:
        final c = component(0), m = component(1), y = component(2);
        final k = component(3);
        if (c == null || m == null || y == null || k == null) return null;
        final r = 1 - (c + k).clamp(0.0, 1.0);
        final g = 1 - (m + k).clamp(0.0, 1.0);
        final b = 1 - (y + k).clamp(0.0, 1.0);
        return (byte(r) << 16) | (byte(g) << 8) | byte(b);
      case _DeviceColorSpace.other:
        return null;
    }
  }

  int? _intOperand(CosObject? object) => switch (object) {
        CosInteger(:final value) => value,
        CosReal(:final value) => value.round(),
        _ => null,
      };
}

class _ColorCollector extends _ColorScannerBase {
  _ColorCollector({
    required super.editor,
    required super.page,
    required super.fill,
    required super.stroke,
    super.resources,
    super.initialState,
    super.includeImplicit,
  });

  final _uses = <int, _ContentColorAccumulator>{};

  void merge(Iterable<PdfContentColor> colors) {
    for (final color in colors) {
      final acc = _uses.putIfAbsent(color.rgb, _ContentColorAccumulator.new);
      acc.fillUses += color.fillUses;
      acc.strokeUses += color.strokeUses;
    }
  }

  void scan(List<ContentOperation> operations) {
    for (final op in operations) {
      for (final implicit in _implicitColors(op).toList()) {
        _trackOperation(implicit);
      }
      _trackOperation(op);
    }
  }

  @override
  void _onColor(ContentOperation op, _PaintSide side, _DeviceColorSpace space) {
    if (side == _PaintSide.fill && !fill) return;
    if (side == _PaintSide.stroke && !stroke) return;
    final rgb = _rgbFrom(op.operands, space);
    if (rgb == null) return;
    final acc = _uses.putIfAbsent(rgb, _ContentColorAccumulator.new);
    if (side == _PaintSide.fill) {
      acc.fillUses++;
    } else {
      acc.strokeUses++;
    }
  }

  List<PdfContentColor> colors() {
    final colors = [
      for (final entry in _uses.entries)
        PdfContentColor(
          rgb: entry.key,
          fillUses: entry.value.fillUses,
          strokeUses: entry.value.strokeUses,
        ),
    ];
    colors.sort((a, b) {
      final byUses = b.uses.compareTo(a.uses);
      return byUses != 0 ? byUses : a.rgb.compareTo(b.rgb);
    });
    return colors;
  }
}

class _ColorProcessor extends _ColorScannerBase {
  _ColorProcessor({
    required super.editor,
    required super.page,
    required this.finds,
    required this.replace,
    required this.tolerance,
    required super.fill,
    required super.stroke,
    super.resources,
    super.initialState,
    super.includeImplicit,
    required this.transparent,
  });

  final List<int> finds;
  final int replace;
  final int tolerance;
  final bool transparent;

  int count = 0;

  List<ContentOperation> rewrite(List<ContentOperation> operations) {
    final out = <ContentOperation>[];
    for (final op in operations) {
      out.addAll(_rewriteWithImplicit(op));
    }
    return out;
  }

  List<ContentOperation> _rewriteWithImplicit(ContentOperation op) => [
        for (final implicit in _implicitColors(op).toList())
          ..._rewriteOperation(implicit),
        ..._rewriteOperation(op),
      ];

  List<ContentOperation> _rewriteOperation(ContentOperation op) {
    switch (op.operator) {
      case 'q':
        _trackOperation(op);
        return [op];
      case 'Q':
        _trackOperation(op);
        return [op];
      case 'cs':
        _trackOperation(op);
        return [op];
      case 'CS':
        _trackOperation(op);
        return [op];
      case 'g':
        return [_deviceColor(op, _PaintSide.fill, _DeviceColorSpace.gray)];
      case 'G':
        return [_deviceColor(op, _PaintSide.stroke, _DeviceColorSpace.gray)];
      case 'rg':
        return [_deviceColor(op, _PaintSide.fill, _DeviceColorSpace.rgb)];
      case 'RG':
        return [_deviceColor(op, _PaintSide.stroke, _DeviceColorSpace.rgb)];
      case 'k':
        return [_deviceColor(op, _PaintSide.fill, _DeviceColorSpace.cmyk)];
      case 'K':
        return [_deviceColor(op, _PaintSide.stroke, _DeviceColorSpace.cmyk)];
      case 'sc' || 'scn':
        return [_currentColor(op, _PaintSide.fill)];
      case 'SC' || 'SCN':
        return [_currentColor(op, _PaintSide.stroke)];
      case 'Tr':
        _trackOperation(op);
        return [op];
      case 'S' || 's' || 'f' || 'F' || 'f*' || 'B' || 'B*' || 'b' || 'b*':
        return _rewritePathPaint(op);
      case 'Tj' || 'TJ' || "'" || '"':
        return _rewriteTextShow(op);
      default:
        return [op];
    }
  }

  ContentOperation _deviceColor(
    ContentOperation op,
    _PaintSide side,
    _DeviceColorSpace space,
  ) {
    _setSpace(side, space);
    return _maybeReplace(op, side, space);
  }

  ContentOperation _currentColor(ContentOperation op, _PaintSide side) {
    if (op.operands.any((operand) => operand is CosName)) {
      return op; // pattern names and separations are outside this pass
    }
    final space =
        side == _PaintSide.fill ? _state.fillSpace : _state.strokeSpace;
    return _maybeReplace(op, side, space);
  }

  ContentOperation _maybeReplace(
    ContentOperation op,
    _PaintSide side,
    _DeviceColorSpace space,
  ) {
    if (side == _PaintSide.fill && !fill) return op;
    if (side == _PaintSide.stroke && !stroke) return op;
    final rgb = _rgbFrom(op.operands, space);
    final matched = rgb != null && _matches(rgb);
    if (transparent) {
      if (side == _PaintSide.fill) {
        _state = _state.copyWith(transparentFill: matched);
      } else {
        _state = _state.copyWith(transparentStroke: matched);
      }
      return op;
    }
    if (rgb == null || !matched) return op;
    count++;
    _setSpace(side, _DeviceColorSpace.rgb);
    return ContentOperation(
      side == _PaintSide.fill ? 'rg' : 'RG',
      _rgbOperands(replace),
    );
  }

  bool _matches(int rgb) {
    final ar = (rgb >> 16) & 0xFF;
    final ag = (rgb >> 8) & 0xFF;
    final ab = rgb & 0xFF;
    for (final find in finds) {
      final br = (find >> 16) & 0xFF;
      final bg = (find >> 8) & 0xFF;
      final bb = find & 0xFF;
      if ((ar - br).abs() <= tolerance &&
          (ag - bg).abs() <= tolerance &&
          (ab - bb).abs() <= tolerance) {
        return true;
      }
    }
    return false;
  }

  @override
  void _onColor(ContentOperation op, _PaintSide side, _DeviceColorSpace space) {
    _maybeReplace(op, side, space);
  }

  List<ContentOperation> _rewritePathPaint(ContentOperation op) {
    if (!transparent) return [op];
    final usesFill = switch (op.operator) {
      'f' || 'F' || 'f*' || 'B' || 'B*' || 'b' || 'b*' => true,
      _ => false,
    };
    final usesStroke = switch (op.operator) {
      'S' || 's' || 'B' || 'B*' || 'b' || 'b*' => true,
      _ => false,
    };
    final dropFill = usesFill && _state.transparentFill;
    final dropStroke = usesStroke && _state.transparentStroke;
    if (!dropFill && !dropStroke) return [op];
    count += (dropFill ? 1 : 0) + (dropStroke ? 1 : 0);

    final close =
        op.operator == 's' || op.operator == 'b' || op.operator == 'b*';
    if (dropFill && dropStroke) {
      return [
        if (close) ContentOperation('h', const []),
        ContentOperation('n', const []),
      ];
    }
    if (dropFill) {
      if (!usesStroke) {
        return [ContentOperation('n', const [])];
      }
      return [ContentOperation(close ? 's' : 'S', const [])];
    }
    if (dropStroke) {
      if (!usesFill) {
        return [
          if (close) ContentOperation('h', const []),
          ContentOperation('n', const []),
        ];
      }
      final fillOp = (op.operator == 'B*' || op.operator == 'b*') ? 'f*' : 'f';
      return [
        if (close) ContentOperation('h', const []),
        ContentOperation(fillOp, const []),
      ];
    }
    return [op];
  }

  List<ContentOperation> _rewriteTextShow(ContentOperation op) {
    if (!transparent) return [op];
    final mode = _state.textRenderingMode;
    final paintsFill = _textModePaintsFill(mode);
    final paintsStroke = _textModePaintsStroke(mode);
    final dropFill = paintsFill && _state.transparentFill;
    final dropStroke = paintsStroke && _state.transparentStroke;
    if (!dropFill && !dropStroke) return [op];
    final nextMode = _textModeWithout(mode, fill: dropFill, stroke: dropStroke);
    if (nextMode == mode) return [op];
    count += (dropFill ? 1 : 0) + (dropStroke ? 1 : 0);
    return [
      ContentOperation('Tr', [CosInteger(nextMode)]),
      op,
      ContentOperation('Tr', [CosInteger(mode)]),
    ];
  }

  bool _textModePaintsFill(int mode) {
    final base = mode & 3;
    return base == 0 || base == 2;
  }

  bool _textModePaintsStroke(int mode) {
    final base = mode & 3;
    return base == 1 || base == 2;
  }

  int _textModeWithout(int mode, {required bool fill, required bool stroke}) {
    final clip = mode >= 4;
    var paintsFill = _textModePaintsFill(mode);
    var paintsStroke = _textModePaintsStroke(mode);
    if (fill) paintsFill = false;
    if (stroke) paintsStroke = false;
    final base = switch ((paintsFill, paintsStroke)) {
      (true, true) => 2,
      (true, false) => 0,
      (false, true) => 1,
      (false, false) => 3,
    };
    return base + (clip ? 4 : 0);
  }

  List<CosObject> _rgbOperands(int rgb) => [
        _component((rgb >> 16) & 0xFF),
        _component((rgb >> 8) & 0xFF),
        _component(rgb & 0xFF),
      ];

  CosObject _component(int value) {
    if (value <= 0) return CosInteger(0);
    if (value >= 255) return CosInteger(1);
    return CosReal(value / 255);
  }
}
