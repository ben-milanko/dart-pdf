import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'calibrated_color.dart';
import 'color.dart';
import 'device.dart';
import 'font_info.dart';
import 'function.dart';
import 'icc.dart';
import 'matrix.dart';
import 'path.dart';
import 'shading.dart';

/// Graphics state, mirroring §8.4. Text state parameters live here too
/// because `Tf`, `Tc` etc. are saved and restored by `q`/`Q`.
class _GraphicsState {
  _GraphicsState()
      : ctm = PdfMatrix.identity,
        fillColor = PdfColor.black,
        strokeColor = PdfColor.black,
        fillAlpha = 1,
        strokeAlpha = 1,
        stroke = const PdfStroke(),
        fillComponents = 1,
        strokeComponents = 1,
        fillPattern = null,
        fillPatternComponents = const [],
        fillTintTransform = null,
        strokeTintTransform = null,
        fillCalibrated = null,
        strokeCalibrated = null,
        fillIcc = null,
        strokeIcc = null,
        font = null,
        fontDict = null,
        fontSize = 0,
        charSpacing = 0,
        wordSpacing = 0,
        horizontalScale = 1,
        leading = 0,
        rise = 0,
        renderMode = 0;

  _GraphicsState.from(_GraphicsState other)
      : ctm = other.ctm,
        fillColor = other.fillColor,
        strokeColor = other.strokeColor,
        fillAlpha = other.fillAlpha,
        strokeAlpha = other.strokeAlpha,
        stroke = other.stroke,
        fillComponents = other.fillComponents,
        strokeComponents = other.strokeComponents,
        fillPattern = other.fillPattern,
        fillPatternComponents = other.fillPatternComponents,
        fillTintTransform = other.fillTintTransform,
        strokeTintTransform = other.strokeTintTransform,
        fillCalibrated = other.fillCalibrated,
        strokeCalibrated = other.strokeCalibrated,
        fillIcc = other.fillIcc,
        strokeIcc = other.strokeIcc,
        softMask = other.softMask,
        blendMode = other.blendMode,
        font = other.font,
        fontDict = other.fontDict,
        fontSize = other.fontSize,
        charSpacing = other.charSpacing,
        wordSpacing = other.wordSpacing,
        horizontalScale = other.horizontalScale,
        leading = other.leading,
        rise = other.rise,
        renderMode = other.renderMode;

  PdfMatrix ctm;
  PdfColor fillColor;
  PdfColor strokeColor;
  double fillAlpha;
  double strokeAlpha;
  PdfStroke stroke;

  /// Component counts of the active /Fill and /Stroke color spaces, used to
  /// interpret bare `sc`/`scn` operands.
  int fillComponents;

  /// Active Separation/DeviceN tint transforms (§8.6.6.4); null when the
  /// current space carries raw device components.
  PdfColor Function(double)? fillTintTransform;
  PdfColor Function(double)? strokeTintTransform;

  /// CIE-based CalGray/CalRGB conversions for fill/stroke spaces.
  PdfCalibratedColorSpace? fillCalibrated;
  PdfCalibratedColorSpace? strokeCalibrated;

  /// Real ICC conversions for ICCBased fill/stroke spaces; null falls
  /// back to component-count heuristics.
  IccProfile? fillIcc;
  IccProfile? strokeIcc;
  int strokeComponents;

  /// The active fill pattern (stream for tiling, dictionary for shading)
  /// when the fill space is /Pattern, plus the underlying color components
  /// for uncolored (PaintType 2) tiling patterns.
  CosObject? fillPattern;
  List<double> fillPatternComponents;

  /// The active ExtGState /SMask, shared by reference across q/Q clones so
  /// the interpreter can tell inherited masks from newly opened ones.
  _ActiveSoftMask? softMask;
  PdfBlendMode blendMode = PdfBlendMode.normal;

  PdfFontInfo? font;
  CosDictionary? fontDict;
  double fontSize;
  double charSpacing;
  double wordSpacing;
  double horizontalScale; // Tz / 100
  double leading;
  double rise;
  int renderMode;
}

class _ActiveSoftMask {
  _ActiveSoftMask(
    this.form,
    this.matrix,
    this.luminosity,
    this.frameDepth, {
    this.backdropLuminance = 0,
    this.transferScale = 1,
    this.transferOffset = 0,
  });

  final CosStream form;

  /// The CTM at the moment the mask was set — mask coordinates live there.
  final PdfMatrix matrix;
  final bool luminosity;

  /// Luminance of the /BC backdrop colour for areas the mask group leaves
  /// unpainted (default black). Only meaningful for luminosity masks.
  final double backdropLuminance;

  /// Linearised /TR transfer function: `out = value * scale + offset`.
  final double transferScale;
  final double transferOffset;

  /// q-nesting depth where the mask was opened; it closes when that frame
  /// pops (or when replaced at the same depth).
  final int frameDepth;
  bool closed = false;
}

/// Executes page content streams against a [PdfDevice].
///
/// Coverage: paths, transforms, device color spaces, clipping, text
/// positioning/showing (with metric-accurate advances), form XObjects,
/// image XObjects and inline images (decoding delegated to the device),
/// shadings, patterns, soft masks, Type3 fonts, and annotation
/// appearance streams.
class PdfInterpreter {
  PdfInterpreter({required this.cos, required this.device});

  final CosDocument cos;
  final PdfDevice device;

  static const _maxFormDepth = 16;

  var _state = _GraphicsState();
  final List<_GraphicsState> _stateStack = [];
  final Map<CosDictionary, PdfFontInfo> _fontCache = {};
  final Map<CosStream, List<ContentOperation>> _patternOpsCache = {};
  final Map<CosStream, IccProfile?> _iccCache = {};
  final List<bool> _visibilityStack = [];
  Set<CosReference>? _optionalContentOn;
  Set<CosReference>? _optionalContentOff;
  String? _optionalContentBaseState;
  int _currentFormDepth = 0;

  // Tiling-pattern streams currently being painted, by identity — a pattern
  // whose cell re-enters itself (through a form) is a reference cycle.
  final Set<CosStream> _activeTilingPatterns = Set.identity();
  PdfRect? _pageBox;

  // current path, built in page space
  List<PdfPathSegment> _segments = [];
  double _currentX = 0, _currentY = 0; // user-space current point
  double _startX = 0, _startY = 0;
  PdfFillRule? _pendingClip;

  // text matrices
  PdfMatrix _textMatrix = PdfMatrix.identity;
  PdfMatrix _lineMatrix = PdfMatrix.identity;

  // Text clipping (render modes 4–7, §9.4.1): glyph outlines painted between
  // BT and ET accumulate in page space and intersect the clip at ET. The
  // flag is set independently of the segments so a clip with no resolvable
  // outlines (e.g. a broken embedded font) correctly clips everything away.
  bool _textClipPending = false;
  final List<PdfPathSegment> _textClipSegments = [];

  void drawPage(PdfPage page) {
    _state = _GraphicsState();
    _visibilityStack.clear();
    _pageBox = page.mediaBox;
    device.save();
    try {
      _run(ContentStreamParser.parse(page.contentBytes()), page.resources, 0);
      final mask = _state.softMask;
      if (mask != null) _finalizeSoftMask(mask);
    } finally {
      device.restore();
    }
  }

  /// Runs a parsed content stream against [resources] (used by tests).
  void run(List<ContentOperation> operations, CosDictionary resources) {
    _run(operations, resources, 0);
  }

  /// Draws the page's annotation appearance streams, normally called after
  /// [drawPage] so they paint over the content (§12.5.5).
  ///
  /// Hidden and NoView annotations are skipped, as are Popups — those are
  /// only shown by a viewer when their parent note is opened.
  void drawAnnotations(PdfPage page, {bool Function(PdfAnnotation)? skip}) {
    _pageBox = page.mediaBox;
    for (final annotation in page.annotations) {
      if (annotation.isHidden || annotation.isNoView) continue;
      if (annotation.subtype == 'Popup') continue;
      if (skip != null && skip(annotation)) continue;
      final form = annotation.normalAppearance;
      if (form == null) {
        _drawFallbackAnnotation(annotation);
      } else {
        _drawAppearance(form, annotation.rect);
      }
    }
  }

  /// Draws a single annotation's appearance stream — the one-annotation
  /// slice of [drawAnnotations], for callers that need an annotation
  /// rendered in isolation (e.g. a live drag preview).
  void drawAnnotation(PdfPage page, PdfAnnotation annotation) {
    _pageBox = page.mediaBox;
    final form = annotation.normalAppearance;
    if (form == null) {
      _drawFallbackAnnotation(annotation);
    } else {
      _drawAppearance(form, annotation.rect);
    }
  }

  void _drawFallbackAnnotation(PdfAnnotation annotation) {
    switch (annotation.subtype) {
      case 'Square':
        _drawFallbackSquare(annotation);
      case 'Circle':
        _drawFallbackCircle(annotation);
      case 'Line':
        _drawFallbackLine(annotation);
      case 'Ink':
        _drawFallbackInk(annotation);
      case 'Highlight' || 'Underline' || 'StrikeOut' || 'Squiggly':
        _drawFallbackTextMarkup(annotation);
      case 'Widget':
        if (annotation is PdfWidgetAnnotation) {
          _drawFallbackWidget(annotation);
        }
    }
  }

  void _drawFallbackSquare(PdfAnnotation annotation) {
    final stroke = _annotationStroke(annotation);
    final rect = _insetRect(annotation.rect, stroke.width / 2);
    final path = _rectPath(rect);
    final fill = annotation.interiorColor;
    if (fill != null) {
      device.fillPath(path, _pdfColor(fill), PdfFillRule.nonzero,
          _annotationFillAlpha(annotation));
    }
    if (annotation.color != null || fill == null) {
      device.strokePath(path, _pdfColor(annotation.color ?? 0x000000), stroke,
          _annotationStrokeAlpha(annotation));
    }
  }

  void _drawFallbackCircle(PdfAnnotation annotation) {
    final stroke = _annotationStroke(annotation);
    final rect = _insetRect(annotation.rect, stroke.width / 2);
    final path = _ellipsePath(rect);
    final fill = annotation.interiorColor;
    if (fill != null) {
      device.fillPath(path, _pdfColor(fill), PdfFillRule.nonzero,
          _annotationFillAlpha(annotation));
    }
    if (annotation.color != null || fill == null) {
      device.strokePath(path, _pdfColor(annotation.color ?? 0x000000), stroke,
          _annotationStrokeAlpha(annotation));
    }
  }

  void _drawFallbackLine(PdfAnnotation annotation) {
    final line = annotation.line;
    if (line == null) return;
    device.strokePath(
      PdfPath([
        PdfMoveTo(line.$1.$1, line.$1.$2),
        PdfLineTo(line.$2.$1, line.$2.$2),
      ]),
      _pdfColor(annotation.color ?? 0x000000),
      _annotationStroke(annotation),
      _annotationStrokeAlpha(annotation),
    );
  }

  void _drawFallbackInk(PdfAnnotation annotation) {
    final strokes = annotation.inkList;
    if (strokes == null) return;
    final stroke = _annotationStroke(annotation).copyWith(
      cap: 1,
      join: 1,
    );
    for (final points in strokes) {
      if (points.isEmpty) continue;
      final segments = <PdfPathSegment>[
        PdfMoveTo(points.first.$1, points.first.$2)
      ];
      for (final point in points.skip(1)) {
        segments.add(PdfLineTo(point.$1, point.$2));
      }
      device.strokePath(
          PdfPath(segments),
          _pdfColor(annotation.color ?? 0x000000),
          stroke,
          _annotationStrokeAlpha(annotation));
    }
  }

  void _drawFallbackTextMarkup(PdfAnnotation annotation) {
    final quads = _quadRects(annotation);
    if (quads.isEmpty) return;
    final color = _pdfColor(annotation.color ?? 0xFFFF00);
    switch (annotation.subtype) {
      case 'Highlight':
        device.setBlendMode(PdfBlendMode.multiply);
        for (final rect in quads) {
          device.fillPath(_rectPath(rect), color, PdfFillRule.nonzero,
              _annotationFillAlpha(annotation, fallback: 0.35));
        }
        device.setBlendMode(PdfBlendMode.normal);
      case 'Underline' || 'StrikeOut':
        final atHeight = annotation.subtype == 'Underline' ? 0.08 : 0.45;
        for (final rect in quads) {
          final y = rect.bottom + rect.height * atHeight;
          device.strokePath(
            PdfPath([PdfMoveTo(rect.left, y), PdfLineTo(rect.right, y)]),
            color,
            _annotationStroke(annotation)
                .copyWith(width: math.max(1, rect.height * 0.06)),
            _annotationStrokeAlpha(annotation),
          );
        }
      case 'Squiggly':
        for (final rect in quads) {
          device.strokePath(
              _squigglyPath(rect),
              color,
              _annotationStroke(annotation)
                  .copyWith(width: math.max(1, rect.height * 0.06)),
              _annotationStrokeAlpha(annotation));
        }
    }
  }

  void _drawFallbackWidget(PdfWidgetAnnotation annotation) {
    if (annotation.fieldType != 'Tx') return;
    final value = annotation.fieldValue;
    if (value == null || value.isEmpty) return;
    final rect = annotation.rect;
    if (rect.width <= 0 || rect.height <= 0) return;

    final style = _parseWidgetDefaultAppearance(annotation);
    const pad = 2.0;
    var size = style.size;
    final text = value.replaceAll('\n', ' ');
    final width = measureHelvetica(text, size) / size;
    final ascent = size * 0.718;
    final y =
        ((rect.height - ascent) / 2 < pad ? pad : (rect.height - ascent) / 2) +
            rect.bottom;

    device.save();
    try {
      device.clipPath(
        _rectPath(PdfRect(
            rect.left + 1, rect.bottom + 1, rect.right - 1, rect.top - 1)),
        PdfFillRule.nonzero,
      );
      device.drawText(PdfTextRun(
        text: text,
        transform: PdfMatrix(size, 0, 0, size, rect.left + pad, y),
        color: style.color,
        width: width,
        fontName: style.fontName,
        fontSize: size,
      ));
    } finally {
      device.restore();
    }
  }

  ({String fontName, double size, PdfColor color})
      _parseWidgetDefaultAppearance(PdfWidgetAnnotation annotation) {
    final da = _widgetDefaultAppearance(annotation) ?? '';
    final tf = RegExp(r'/(\S+)\s+([\d.]+)\s+Tf').firstMatch(da);
    final rawName = tf?.group(1) ?? 'Helv';
    final fontName = switch (rawName) {
      'Helv' => 'Helvetica',
      'ZaDb' => 'ZapfDingbats',
      _ => rawName,
    };
    final parsedSize = double.tryParse(tf?.group(2) ?? '') ?? 12;
    final size = parsedSize <= 0 ? 12.0 : parsedSize;

    PdfColor color = PdfColor.black;
    for (final match
        in RegExp(r'([\d.]+)(?:\s+([\d.]+)\s+([\d.]+))?\s+(g|rg)\b')
            .allMatches(da)) {
      final op = match.group(4);
      if (op == 'g') {
        final gray = double.tryParse(match.group(1)!) ?? 0;
        color = PdfColor.gray(gray.clamp(0.0, 1.0));
      } else {
        final r = double.tryParse(match.group(1)!) ?? 0;
        final g = double.tryParse(match.group(2) ?? '') ?? 0;
        final b = double.tryParse(match.group(3) ?? '') ?? 0;
        color = PdfColor(
          r.clamp(0.0, 1.0),
          g.clamp(0.0, 1.0),
          b.clamp(0.0, 1.0),
        );
      }
    }
    return (fontName: fontName, size: size, color: color);
  }

  String? _widgetDefaultAppearance(PdfWidgetAnnotation annotation) {
    final cos = annotation.document.cos;
    CosDictionary? node = annotation.dict;
    final visited = <CosDictionary>{};
    while (node != null && visited.add(node)) {
      final da = cos.resolve(node['DA']);
      if (da is CosString) return da.text;
      final parent = cos.resolve(node['Parent']);
      node = parent is CosDictionary ? parent : null;
    }
    final acroForm = cos.resolve(annotation.document.catalog['AcroForm']);
    if (acroForm is CosDictionary) {
      final da = cos.resolve(acroForm['DA']);
      if (da is CosString) return da.text;
    }
    return null;
  }

  PdfStroke _annotationStroke(PdfAnnotation annotation) => PdfStroke(
        width:
            annotation.borderWidth ?? _annotationBorderWidth(annotation) ?? 1,
        dashArray: annotation.borderDash ?? const [],
      );

  double? _annotationBorderWidth(PdfAnnotation annotation) {
    final border = cos.resolve(annotation.dict['Border']);
    if (border is! CosArray || border.length < 3) return null;
    final width = cos.resolve(border[2]);
    return switch (width) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => null,
    };
  }

  double _annotationStrokeAlpha(PdfAnnotation annotation) =>
      _annotationNumber(annotation, 'CA') ?? 1;

  double _annotationFillAlpha(PdfAnnotation annotation,
          {double fallback = 1}) =>
      _annotationNumber(annotation, 'ca') ??
      _annotationNumber(annotation, 'CA') ??
      fallback;

  double? _annotationNumber(PdfAnnotation annotation, String key) {
    final value = cos.resolve(annotation.dict[key]);
    return switch (value) {
      CosInteger(:final value) => value.toDouble().clamp(0.0, 1.0),
      CosReal(:final value) => value.clamp(0.0, 1.0),
      _ => null,
    };
  }

  PdfColor _pdfColor(int rgb) => PdfColor(
        ((rgb >> 16) & 0xFF) / 255,
        ((rgb >> 8) & 0xFF) / 255,
        (rgb & 0xFF) / 255,
      );

  PdfPath _rectPath(PdfRect rect) => PdfPath([
        PdfMoveTo(rect.left, rect.bottom),
        PdfLineTo(rect.right, rect.bottom),
        PdfLineTo(rect.right, rect.top),
        PdfLineTo(rect.left, rect.top),
        const PdfClosePath(),
      ]);

  PdfRect _insetRect(PdfRect rect, double inset) {
    final dx = math.min(inset, rect.width / 2);
    final dy = math.min(inset, rect.height / 2);
    return PdfRect(
        rect.left + dx, rect.bottom + dy, rect.right - dx, rect.top - dy);
  }

  PdfPath _ellipsePath(PdfRect rect) {
    const k = 0.5522847498307936;
    final cx = (rect.left + rect.right) / 2;
    final cy = (rect.bottom + rect.top) / 2;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    return PdfPath([
      PdfMoveTo(cx + rx, cy),
      PdfCubicTo(cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry),
      PdfCubicTo(cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy),
      PdfCubicTo(cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry),
      PdfCubicTo(cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy),
      const PdfClosePath(),
    ]);
  }

  List<PdfRect> _quadRects(PdfAnnotation annotation) {
    final raw = cos.resolve(annotation.dict['QuadPoints']);
    if (raw is! CosArray) return const [];
    final rects = <PdfRect>[];
    for (var i = 0; i + 7 < raw.length; i += 8) {
      final xs = <double>[];
      final ys = <double>[];
      for (var j = 0; j < 8; j += 2) {
        final x = _numOf(cos.resolve(raw[i + j]));
        final y = _numOf(cos.resolve(raw[i + j + 1]));
        xs.add(x);
        ys.add(y);
      }
      rects.add(PdfRect(
        xs.reduce(math.min),
        ys.reduce(math.min),
        xs.reduce(math.max),
        ys.reduce(math.max),
      ));
    }
    return rects;
  }

  PdfPath _squigglyPath(PdfRect rect) {
    final y = rect.bottom + rect.height * 0.12;
    final amp = math.max(1.0, rect.height * 0.06);
    final step = amp * 2;
    final segments = <PdfPathSegment>[PdfMoveTo(rect.left, y)];
    var x = rect.left;
    var up = true;
    while (x < rect.right) {
      x = math.min(rect.right, x + step);
      segments.add(PdfLineTo(x, y + (up ? amp : -amp)));
      up = !up;
    }
    return PdfPath(segments);
  }

  /// Renders one appearance form: the /BBox corners go through /Matrix,
  /// their bounding box is fitted onto the annotation's /Rect, and the
  /// content runs clipped to the BBox (the algorithm in §12.5.5).
  void _drawAppearance(CosStream form, PdfRect rect) {
    final Uint8List content;
    try {
      content = cos.decodeStreamData(form);
    } on Exception {
      return;
    }
    final dict = form.dictionary;
    final matrixObj = cos.resolve(dict['Matrix']);
    final matrix = matrixObj is CosArray && matrixObj.length >= 6
        ? _matrixFrom(matrixObj.items)
        : PdfMatrix.identity;
    final bbox = _numbersOf(dict['BBox']);

    var ctm = matrix;
    if (bbox.length >= 4 && rect.width > 0 && rect.height > 0) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final (x, y) in [
        (bbox[0], bbox[1]),
        (bbox[2], bbox[1]),
        (bbox[2], bbox[3]),
        (bbox[0], bbox[3]),
      ]) {
        minX = math.min(minX, matrix.transformX(x, y));
        minY = math.min(minY, matrix.transformY(x, y));
        maxX = math.max(maxX, matrix.transformX(x, y));
        maxY = math.max(maxY, matrix.transformY(x, y));
      }
      if (maxX > minX && maxY > minY) {
        final sx = rect.width / (maxX - minX);
        final sy = rect.height / (maxY - minY);
        ctm = matrix.concat(PdfMatrix(
            sx, 0, 0, sy, rect.left - minX * sx, rect.bottom - minY * sy));
      }
    }

    final savedState = _state;
    final savedStackDepth = _stateStack.length;
    final savedVisibilityDepth = _visibilityStack.length;
    device.save();
    try {
      _state = _GraphicsState()..ctm = ctm;
      if (bbox.length >= 4) _clipToBox(bbox);
      final resources = cos.resolve(dict['Resources']);
      _run(
        ContentStreamParser.parse(content),
        resources is CosDictionary ? resources : CosDictionary(),
        _currentFormDepth + 1,
      );
      final mask = _state.softMask;
      if (mask != null) _finalizeSoftMask(mask);
    } finally {
      while (_stateStack.length > savedStackDepth) {
        _stateStack.removeLast();
      }
      while (_visibilityStack.length > savedVisibilityDepth) {
        _visibilityStack.removeLast();
      }
      _state = savedState;
      device.restore();
    }
  }

  void _run(
      List<ContentOperation> ops, CosDictionary resources, int formDepth) {
    final previousDepth = _currentFormDepth;
    final previousVisibilityDepth = _visibilityStack.length;
    _currentFormDepth = formDepth;
    try {
      _runOps(ops, resources, formDepth);
    } finally {
      while (_visibilityStack.length > previousVisibilityDepth) {
        _visibilityStack.removeLast();
      }
      _currentFormDepth = previousDepth;
    }
  }

  void _runOps(
      List<ContentOperation> ops, CosDictionary resources, int formDepth) {
    for (final op in ops) {
      final o = op.operands;
      switch (op.operator) {
        // --- graphics state ---
        case 'q':
          _stateStack.add(_GraphicsState.from(_state));
          device.save();
        case 'Q':
          if (_stateStack.isNotEmpty) {
            final restored = _stateStack.removeLast();
            final mask = _state.softMask;
            if (mask != null && !identical(mask, restored.softMask)) {
              _finalizeSoftMask(mask);
            }
            if (_state.blendMode != restored.blendMode) {
              device.setBlendMode(restored.blendMode);
            }
            _state = restored;
            device.restore();
          }
        case 'cm':
          _state.ctm = _matrixFrom(o).concat(_state.ctm);
        case 'w':
          _state.stroke = _state.stroke.copyWith(width: _num(o, 0));
        case 'J':
          _state.stroke = _state.stroke.copyWith(cap: _num(o, 0).toInt());
        case 'j':
          _state.stroke = _state.stroke.copyWith(join: _num(o, 0).toInt());
        case 'M':
          _state.stroke = _state.stroke.copyWith(miterLimit: _num(o, 0));
        case 'd':
          _state.stroke = _state.stroke.copyWith(
            dashArray: o.isNotEmpty && o[0] is CosArray
                ? [for (final v in (o[0] as CosArray).items) _numOf(v)]
                : const [],
            dashPhase: _num(o, 1),
          );
        case 'gs':
          _applyExtGState(_dictResource(resources, 'ExtGState', o));
        case 'ri' || 'i':
          break;

        // --- path construction ---
        case 'm':
          _moveTo(_num(o, 0), _num(o, 1));
        case 'l':
          _lineTo(_num(o, 0), _num(o, 1));
        case 'c':
          _curveTo(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3), _num(o, 4),
              _num(o, 5));
        case 'v':
          _curveTo(_currentX, _currentY, _num(o, 0), _num(o, 1), _num(o, 2),
              _num(o, 3));
        case 'y':
          _curveTo(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3), _num(o, 2),
              _num(o, 3));
        case 'h':
          _closePath();
        case 're':
          final x = _num(o, 0), y = _num(o, 1);
          final w = _num(o, 2), h = _num(o, 3);
          _moveTo(x, y);
          _lineTo(x + w, y);
          _lineTo(x + w, y + h);
          _lineTo(x, y + h);
          _closePath();

        // --- path painting ---
        case 'S':
          _paint(stroke: true);
        case 's':
          _closePath();
          _paint(stroke: true);
        case 'f' || 'F':
          _paint(fill: PdfFillRule.nonzero);
        case 'f*':
          _paint(fill: PdfFillRule.evenOdd);
        case 'B':
          _paint(fill: PdfFillRule.nonzero, stroke: true);
        case 'B*':
          _paint(fill: PdfFillRule.evenOdd, stroke: true);
        case 'b':
          _closePath();
          _paint(fill: PdfFillRule.nonzero, stroke: true);
        case 'b*':
          _closePath();
          _paint(fill: PdfFillRule.evenOdd, stroke: true);
        case 'n':
          _paint();
        case 'W':
          _pendingClip = PdfFillRule.nonzero;
        case 'W*':
          _pendingClip = PdfFillRule.evenOdd;

        // --- color ---
        case 'g':
          _state.fillColor = PdfColor.gray(_num(o, 0));
          _state.fillPattern = null;
        case 'G':
          _state.strokeColor = PdfColor.gray(_num(o, 0));
        case 'rg':
          _state.fillColor = PdfColor(_num(o, 0), _num(o, 1), _num(o, 2));
          _state.fillPattern = null;
        case 'RG':
          _state.strokeColor = PdfColor(_num(o, 0), _num(o, 1), _num(o, 2));
        case 'k':
          _state.fillColor =
              PdfColor.cmyk(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3));
          _state.fillPattern = null;
        case 'K':
          _state.strokeColor =
              PdfColor.cmyk(_num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3));
        case 'cs':
          _state.fillComponents = _componentsOf(resources, o);
          _state.fillTintTransform = _tintTransformOf(resources, o);
          _state.fillCalibrated = _calibratedColorSpaceOf(resources, o);
          _state.fillIcc = _iccProfileOf(resources, o);
          _state.fillPattern = null;
        case 'CS':
          _state.strokeComponents = _componentsOf(resources, o);
          _state.strokeTintTransform = _tintTransformOf(resources, o);
          _state.strokeCalibrated = _calibratedColorSpaceOf(resources, o);
          _state.strokeIcc = _iccProfileOf(resources, o);
        case 'sc' || 'scn':
          _state.fillPattern = null;
          if (o.isNotEmpty && o.last is CosName) {
            _state.fillPattern =
                _resource(resources, 'Pattern', o.last as CosName);
            _state.fillPatternComponents = [
              for (final v in o)
                if (v is CosInteger || v is CosReal) _numOf(v),
            ];
          } else {
            _state.fillColor = _tintedColor(_state.fillTintTransform,
                _state.fillCalibrated, _state.fillIcc, o, _state.fillColor);
          }
        case 'SC' || 'SCN':
          if (o.isNotEmpty && o.last is CosName) {
            // stroke patterns: approximate with the pattern's average color
            final color = _patternAverageColor(
                _resource(resources, 'Pattern', o.last as CosName));
            if (color != null) _state.strokeColor = color;
          } else {
            _state.strokeColor = _tintedColor(
                _state.strokeTintTransform,
                _state.strokeCalibrated,
                _state.strokeIcc,
                o,
                _state.strokeColor);
          }

        // --- text ---
        case 'BT':
          _textMatrix = PdfMatrix.identity;
          _lineMatrix = PdfMatrix.identity;
          _textClipPending = false;
          _textClipSegments.clear();
        case 'ET':
          if (_textClipPending) {
            // §9.4.1: combine the accumulated glyph outlines (nonzero rule)
            // and intersect with the current clip. No outlines → empty path
            // → everything painted afterward is clipped away.
            device.clipPath(
                PdfPath(List.of(_textClipSegments)), PdfFillRule.nonzero);
            _textClipPending = false;
            _textClipSegments.clear();
          }
        case 'Tf':
          _setFont(resources, o);
        case 'Td':
          _textLineMove(_num(o, 0), _num(o, 1));
        case 'TD':
          _state.leading = -_num(o, 1);
          _textLineMove(_num(o, 0), _num(o, 1));
        case 'Tm':
          _lineMatrix = _matrixFrom(o);
          _textMatrix = _lineMatrix;
        case 'T*':
          _textLineMove(0, -_state.leading);
        case 'TL':
          _state.leading = _num(o, 0);
        case 'Tc':
          _state.charSpacing = _num(o, 0);
        case 'Tw':
          _state.wordSpacing = _num(o, 0);
        case 'Tz':
          _state.horizontalScale = _num(o, 0) / 100;
        case 'Ts':
          _state.rise = _num(o, 0);
        case 'Tr':
          _state.renderMode = _num(o, 0).toInt();
        case 'Tj':
          if (o.isNotEmpty && o[0] is CosString) {
            _showText((o[0] as CosString).bytes);
          }
        case "'":
          _textLineMove(0, -_state.leading);
          if (o.isNotEmpty && o[0] is CosString) {
            _showText((o[0] as CosString).bytes);
          }
        case '"':
          _state.wordSpacing = _num(o, 0);
          _state.charSpacing = _num(o, 1);
          _textLineMove(0, -_state.leading);
          if (o.length > 2 && o[2] is CosString) {
            _showText((o[2] as CosString).bytes);
          }
        case 'TJ':
          if (o.isNotEmpty && o[0] is CosArray) {
            for (final item in (o[0] as CosArray).items) {
              if (item is CosString) {
                _showText(item.bytes);
              } else {
                final shift = -_numOf(item) /
                    1000 *
                    _state.fontSize *
                    _state.horizontalScale;
                _textMatrix =
                    PdfMatrix.translation(shift, 0).concat(_textMatrix);
              }
            }
          }

        // --- XObjects and inline images ---
        case 'Do':
          if (_contentVisible) _doXObject(resources, o, formDepth);
        case 'BI':
          if (_contentVisible) _drawInlineImage(o);

        case 'sh':
          if (_contentVisible) _applyShading(resources, o);

        // --- marked content, compatibility, Type3 metrics ---
        case 'BDC':
          _visibilityStack.add(_markedContentVisible(resources, o));
        case 'BMC':
          _visibilityStack.add(true);
        case 'EMC':
          if (_visibilityStack.isNotEmpty) _visibilityStack.removeLast();
        case 'MP' || 'DP':
        case 'BX' || 'EX':
        case 'd0' || 'd1':
          break;

        default:
          // unknown operator: PDF says ignore (in compatibility sections);
          // we ignore everywhere and rely on corpus testing to find gaps
          break;
      }
    }
  }

  bool get _contentVisible => _visibilityStack.every((visible) => visible);

  bool _markedContentVisible(
      CosDictionary resources, List<CosObject> operands) {
    if (operands.length < 2 ||
        operands[0] is! CosName ||
        (operands[0] as CosName).value != 'OC') {
      return true;
    }

    CosObject? property = operands[1];
    if (property is CosName) {
      final properties = cos.resolve(resources['Properties']);
      property =
          properties is CosDictionary ? properties[property.value] : null;
    }
    return _optionalContentVisible(property);
  }

  bool _optionalContentVisible(CosObject? object) {
    if (object == null) return true;
    final resolved = cos.resolve(object);
    if (resolved is! CosDictionary) return true;
    final type = cos.resolve(resolved['Type']);
    if (type is CosName && type.value == 'OCMD') {
      return _optionalContentMembershipVisible(resolved);
    }
    if (type is CosName && type.value != 'OCG') return true;
    final ref = object is CosReference ? object : cos.referenceTo(resolved);
    return ref == null ? true : _optionalContentGroupVisible(ref);
  }

  bool _optionalContentMembershipVisible(CosDictionary dict) {
    // §8.11.4.3: a /VE visibility expression, when present, takes precedence
    // over /OCGs + /P.
    final ve = cos.resolve(dict['VE']);
    if (ve is CosArray && ve.length > 0) {
      return _evaluateVisibilityExpression(ve);
    }
    final policy = cos.resolve(dict['P']);
    final policyName = policy is CosName ? policy.value : 'AnyOn';
    final groups = _optionalContentReferences(dict['OCGs']);
    if (groups.isEmpty) return true;
    final values = [
      for (final ref in groups) _optionalContentGroupVisible(ref)
    ];
    return switch (policyName) {
      'AllOn' => values.every((visible) => visible),
      'AnyOff' => values.any((visible) => !visible),
      'AllOff' => values.every((visible) => !visible),
      _ => values.any((visible) => visible),
    };
  }

  /// Evaluates a /VE visibility expression (§8.11.4.3): an array led by /And,
  /// /Or, or /Not whose operands are nested expressions or OCG references; a
  /// leaf OCG is true when its group is visible. Malformed nodes default to
  /// visible so content is never lost.
  bool _evaluateVisibilityExpression(CosObject? object) {
    final resolved = cos.resolve(object);
    if (object is CosReference && resolved is CosDictionary) {
      // A leaf operand: an OCG (or nested OCMD) reference.
      final type = cos.resolve(resolved['Type']);
      if (type is CosName && type.value == 'OCMD') {
        return _optionalContentMembershipVisible(resolved);
      }
      return _optionalContentGroupVisible(object);
    }
    if (resolved is! CosArray || resolved.length == 0) return true;
    final op = cos.resolve(resolved[0]);
    final name = op is CosName ? op.value : '';
    final operands = resolved.items.skip(1);
    switch (name) {
      case 'Not':
        final first = operands.isEmpty ? null : operands.first;
        return !_evaluateVisibilityExpression(first);
      case 'And':
        return operands.every(_evaluateVisibilityExpression);
      case 'Or':
        return operands.any(_evaluateVisibilityExpression);
      default:
        return true;
    }
  }

  Iterable<CosReference> _optionalContentReferences(CosObject? object) sync* {
    final resolved = cos.resolve(object);
    if (object is CosReference && resolved is CosDictionary) {
      yield object;
      return;
    }
    if (resolved is CosArray) {
      for (final item in resolved.items) {
        yield* _optionalContentReferences(item);
      }
    } else if (resolved is CosDictionary) {
      final ref = cos.referenceTo(resolved);
      if (ref != null) yield ref;
    }
  }

  bool _optionalContentGroupVisible(CosReference ref) {
    _ensureOptionalContentConfig();
    if (_optionalContentOff?.contains(ref) == true) return false;
    if (_optionalContentOn?.contains(ref) == true) return true;
    return _optionalContentBaseState != 'OFF';
  }

  void _ensureOptionalContentConfig() {
    if (_optionalContentOn != null) return;
    _optionalContentOn = <CosReference>{};
    _optionalContentOff = <CosReference>{};
    _optionalContentBaseState = 'ON';
    try {
      final properties = cos.resolve(cos.catalog['OCProperties']);
      if (properties is! CosDictionary) return;
      final config = cos.resolve(properties['D']);
      if (config is! CosDictionary) return;
      final base = cos.resolve(config['BaseState']);
      if (base is CosName) _optionalContentBaseState = base.value;
      _optionalContentOn!.addAll(_optionalContentReferences(config['ON']));
      _optionalContentOff!.addAll(_optionalContentReferences(config['OFF']));
    } on Object {
      // Broken optional-content config: default to visible content.
      _optionalContentOn = <CosReference>{};
      _optionalContentOff = <CosReference>{};
      _optionalContentBaseState = 'ON';
    }
  }

  // ---------- paths ----------

  void _addPoint(double x, double y, void Function(double, double) emit) {
    emit(_state.ctm.transformX(x, y), _state.ctm.transformY(x, y));
  }

  void _moveTo(double x, double y) {
    _currentX = _startX = x;
    _currentY = _startY = y;
    _addPoint(x, y, (px, py) => _segments.add(PdfMoveTo(px, py)));
  }

  void _lineTo(double x, double y) {
    _currentX = x;
    _currentY = y;
    _addPoint(x, y, (px, py) => _segments.add(PdfLineTo(px, py)));
  }

  void _curveTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    final m = _state.ctm;
    _segments.add(PdfCubicTo(
      m.transformX(x1, y1),
      m.transformY(x1, y1),
      m.transformX(x2, y2),
      m.transformY(x2, y2),
      m.transformX(x3, y3),
      m.transformY(x3, y3),
    ));
    _currentX = x3;
    _currentY = y3;
  }

  void _closePath() {
    _segments.add(const PdfClosePath());
    _currentX = _startX;
    _currentY = _startY;
  }

  void _paint({PdfFillRule? fill, bool stroke = false}) {
    final path = PdfPath(_segments);
    if (!path.isEmpty && _contentVisible) {
      if (fill != null) {
        final pattern = _state.fillPattern;
        if (pattern != null) {
          _fillWithPattern(path, fill, pattern);
        } else {
          device.fillPath(path, _state.fillColor, fill, _state.fillAlpha);
        }
      }
      if (stroke) {
        final k = _state.ctm.scaleFactor;
        final scaled = _state.stroke.copyWith(
            width: _state.stroke.width <= 0
                ? k // zero width = thinnest line
                : _state.stroke.width * k,
            // dash lengths live in user space too (§8.4.3.6)
            dashArray: [for (final d in _state.stroke.dashArray) d * k],
            dashPhase: _state.stroke.dashPhase * k);
        device.strokePath(path, _state.strokeColor, scaled, _state.strokeAlpha);
      }
      if (_pendingClip != null) {
        device.clipPath(path, _pendingClip!);
      }
    }
    _pendingClip = null;
    _segments = [];
  }

  // ---------- color ----------

  int _componentsOf(CosDictionary resources, List<CosObject> o) {
    if (o.isEmpty || o[0] is! CosName) return 1;
    final name = (o[0] as CosName).value;
    switch (name) {
      case 'DeviceGray' || 'CalGray' || 'G':
        return 1;
      case 'DeviceRGB' || 'CalRGB' || 'Lab' || 'RGB':
        return 3;
      case 'DeviceCMYK' || 'CMYK':
        return 4;
      case 'Pattern':
        return 0;
    }
    // named space in resources: ICCBased /N, or fall back to 3
    final spaces = cos.resolve(resources['ColorSpace']);
    if (spaces is CosDictionary) {
      final space = cos.resolve(spaces[name]);
      if (space is CosArray && space.length > 0) {
        final family = cos.resolve(space[0]);
        if (family is CosName &&
            family.value == 'ICCBased' &&
            space.length > 1) {
          final profile = cos.resolve(space[1]);
          if (profile is CosStream) {
            final n = cos.resolve(profile.dictionary['N']);
            if (n is CosInteger) return n.value;
          }
        }
        if (family is CosName && family.value == 'Indexed') return 1;
        if (family is CosName && family.value == 'Separation') return 1;
      }
    }
    return 3;
  }

  /// sc/scn through the active tint transform or ICC profile when one
  /// is set, else by raw component count.
  PdfColor _tintedColor(
      PdfColor Function(double)? transform,
      PdfCalibratedColorSpace? calibrated,
      IccProfile? icc,
      List<CosObject> o,
      PdfColor current) {
    final values = [
      for (final item in o)
        if (item is CosInteger || item is CosReal) _numOf(item),
    ];
    if (transform != null && values.length == 1) return transform(values[0]);
    if (calibrated != null && values.length == calibrated.components) {
      return calibrated.toSrgb(values);
    }
    if (icc != null && values.length == icc.channels) {
      return icc.toSrgb(values);
    }
    return _colorFromComponents(o, current);
  }

  PdfCalibratedColorSpace? _calibratedColorSpaceOf(
      CosDictionary resources, List<CosObject> o) {
    if (o.isEmpty || o[0] is! CosName) return null;
    final name = (o[0] as CosName).value;
    if (name == 'CalGray' || name == 'CalRGB') return null;
    final spaces = cos.resolve(resources['ColorSpace']);
    if (spaces is! CosDictionary) return null;
    return PdfCalibratedColorSpace.parse(cos, spaces[name]);
  }

  /// Parses (and caches) the ICC profile of a named ICCBased space.
  /// Null for other spaces and for profile shapes the engine cannot
  /// handle — those keep the component-count fallback.
  IccProfile? _iccProfileOf(CosDictionary resources, List<CosObject> o) {
    if (o.isEmpty || o[0] is! CosName) return null;
    final spaces = cos.resolve(resources['ColorSpace']);
    if (spaces is! CosDictionary) return null;
    final space = cos.resolve(spaces[(o[0] as CosName).value]);
    if (space is! CosArray || space.length < 2) return null;
    final family = cos.resolve(space[0]);
    if (family is! CosName || family.value != 'ICCBased') return null;
    final stream = cos.resolve(space[1]);
    if (stream is! CosStream) return null;
    return _iccCache.putIfAbsent(stream, () {
      try {
        return IccProfile.parse(cos.decodeStreamData(stream));
      } on Exception {
        return null;
      }
    });
  }

  /// A converter for Separation (or single-colorant DeviceN) spaces: the
  /// tint runs through the transform function into the alternate space
  /// (§8.6.6.4). Null for every other space.
  PdfColor Function(double)? _tintTransformOf(
      CosDictionary resources, List<CosObject> o) {
    if (o.isEmpty || o[0] is! CosName) return null;
    final spaces = cos.resolve(resources['ColorSpace']);
    if (spaces is! CosDictionary) return null;
    final space = cos.resolve(spaces[(o[0] as CosName).value]);
    if (space is! CosArray || space.length < 4) return null;
    final family = cos.resolve(space[0]);
    if (family is CosName && family.value == 'Indexed') {
      return _indexedTransform(space);
    }
    if (family is! CosName ||
        (family.value != 'Separation' && family.value != 'DeviceN')) {
      return null;
    }
    if (family.value == 'DeviceN') {
      final names = cos.resolve(space[1]);
      if (names is! CosArray || names.length != 1) return null;
    }
    final fn = PdfFunction.parse(cos, space[3]);
    if (fn == null) return null;
    final alternate = _alternateColorConverter(cos.resolve(space[2]));
    return (tint) => alternate(fn.evaluate(tint));
  }

  /// An /Indexed (palette) space `[/Indexed base hival lookup]` (§8.6.6.3):
  /// `sc <index>` rounds to the nearest integer, clamps to `[0, hival]`, and
  /// reads `n` bytes from the lookup table (n = base component count), each a
  /// raw 0–255 sample of the base space, then converts through the base.
  PdfColor Function(double)? _indexedTransform(CosArray space) {
    if (space.length < 4) return null;
    final base = cos.resolve(space[1]);
    final hivalObj = cos.resolve(space[2]);
    if (hivalObj is! CosInteger && hivalObj is! CosReal) return null;
    final hival = _numOf(hivalObj).round();
    if (hival < 0) return null;

    final lookupObj = cos.resolve(space[3]);
    final List<int> table;
    if (lookupObj is CosString) {
      table = lookupObj.bytes;
    } else if (lookupObj is CosStream) {
      try {
        table = cos.decodeStreamData(lookupObj);
      } on Exception {
        return null;
      }
    } else {
      return null;
    }

    final n = _alternateComponents(base);
    if (n <= 0) return null;
    final convert = _alternateColorConverter(base);
    return (rawIndex) {
      var index = rawIndex.round();
      if (index < 0) index = 0;
      if (index > hival) index = hival;
      final offset = index * n;
      if (offset + n > table.length) return PdfColor.black;
      return convert([for (var i = 0; i < n; i++) table[offset + i] / 255.0]);
    };
  }

  PdfColor Function(List<double>) _alternateColorConverter(CosObject space) {
    final calibrated = PdfCalibratedColorSpace.parse(cos, space);
    if (calibrated != null) return calibrated.toSrgb;
    final components = _alternateComponents(space);
    return (values) => colorFromComponents(values, components);
  }

  int _alternateComponents(CosObject space) {
    if (space is CosName) {
      return switch (space.value) {
        'DeviceGray' || 'CalGray' || 'G' => 1,
        'DeviceCMYK' || 'CMYK' => 4,
        _ => 3,
      };
    }
    if (space is CosArray && space.length > 1) {
      final family = cos.resolve(space[0]);
      if (family is CosName && family.value == 'ICCBased') {
        final profile = cos.resolve(space[1]);
        if (profile is CosStream) {
          final n = cos.resolve(profile.dictionary['N']);
          if (n is CosInteger) return n.value;
        }
      }
    }
    return 3;
  }

  PdfColor _colorFromComponents(List<CosObject> o, PdfColor current) {
    final values = [
      for (final item in o)
        if (item is CosInteger || item is CosReal) _numOf(item),
    ];
    switch (values.length) {
      case 1:
        return PdfColor.gray(values[0]);
      case 3:
        return PdfColor(values[0], values[1], values[2]);
      case 4:
        return PdfColor.cmyk(values[0], values[1], values[2], values[3]);
    }
    // pattern or unsupported: keep something visible
    return current;
  }

  void _applyExtGState(CosDictionary? gs) {
    if (gs == null) return;
    final ca = cos.resolve(gs['ca']);
    if (ca is CosInteger || ca is CosReal) _state.fillAlpha = _numOf(ca);
    final caStroke = cos.resolve(gs['CA']);
    if (caStroke is CosInteger || caStroke is CosReal) {
      _state.strokeAlpha = _numOf(caStroke);
    }
    final lw = cos.resolve(gs['LW']);
    if (lw is CosInteger || lw is CosReal) {
      _state.stroke = _state.stroke.copyWith(width: _numOf(lw));
    }
    _applyBlendMode(cos.resolve(gs['BM']));
    _applySoftMask(cos.resolve(gs['SMask']));
  }

  void _applyBlendMode(CosObject? bm) {
    var name = bm;
    if (name is CosArray && name.length > 0) name = cos.resolve(name[0]);
    if (name is! CosName) return;
    final mode = switch (name.value) {
      'Multiply' => PdfBlendMode.multiply,
      'Screen' => PdfBlendMode.screen,
      'Overlay' => PdfBlendMode.overlay,
      'Darken' => PdfBlendMode.darken,
      'Lighten' => PdfBlendMode.lighten,
      'ColorDodge' => PdfBlendMode.colorDodge,
      'ColorBurn' => PdfBlendMode.colorBurn,
      'HardLight' => PdfBlendMode.hardLight,
      'SoftLight' => PdfBlendMode.softLight,
      'Difference' => PdfBlendMode.difference,
      'Exclusion' => PdfBlendMode.exclusion,
      'Hue' => PdfBlendMode.hue,
      'Saturation' => PdfBlendMode.saturation,
      'Color' => PdfBlendMode.color,
      'Luminosity' => PdfBlendMode.luminosity,
      _ => PdfBlendMode.normal, // incl. /Normal and /Compatible
    };
    if (mode != _state.blendMode) {
      _state.blendMode = mode;
      device.setBlendMode(mode);
    }
  }

  void _applySoftMask(CosObject? smask) {
    if (smask is CosName && smask.value == 'None') {
      final mask = _state.softMask;
      if (mask != null && mask.frameDepth == _stateStack.length) {
        _finalizeSoftMask(mask);
      }
      _state.softMask = null;
      return;
    }
    if (smask is! CosDictionary) return;
    final form = cos.resolve(smask['G']);
    if (form is! CosStream) return;
    final mask = _state.softMask;
    if (mask != null && mask.frameDepth == _stateStack.length) {
      _finalizeSoftMask(mask);
    }
    final s = cos.resolve(smask['S']);
    final luminosity = s is CosName && s.value == 'Luminosity';

    // /BC backdrop colour (component values in the group's colour space) sets
    // the mask value for areas the group leaves unpainted; default black.
    var backdropLuminance = 0.0;
    final bc = cos.resolve(smask['BC']);
    if (bc is CosArray && bc.length > 0) {
      final c = [for (final v in bc.items) _numOf(cos.resolve(v))];
      backdropLuminance = switch (c.length) {
        1 => c[0],
        3 => 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2],
        4 => (1 - c[0]) * 0.3 + (1 - c[1]) * 0.59 + (1 - c[2]) * 0.11,
        _ => c[0],
      };
    }

    // /TR transfer function, linearised through its endpoints (exact for the
    // common FunctionType 2, N=1 case these masks use).
    var transferScale = 1.0;
    var transferOffset = 0.0;
    final tr = cos.resolve(smask['TR']);
    if (!(tr is CosName && tr.value == 'Identity')) {
      final fn = PdfFunction.parse(cos, smask['TR']);
      if (fn != null) {
        final lo = fn.evaluate(0);
        final hi = fn.evaluate(1);
        if (lo.isNotEmpty && hi.isNotEmpty) {
          transferOffset = lo[0];
          transferScale = hi[0] - lo[0];
        }
      }
    }

    _state.softMask = _ActiveSoftMask(
      form,
      _state.ctm,
      luminosity,
      _stateStack.length,
      backdropLuminance: backdropLuminance,
      transferScale: transferScale,
      transferOffset: transferOffset,
    );
    device.beginSoftMasked();
  }

  void _finalizeSoftMask(_ActiveSoftMask mask) {
    if (mask.closed) return;
    mask.closed = true;
    device.endSoftMasked(
      luminosity: mask.luminosity,
      backdrop: _pageBox ?? const PdfRect(-1e5, -1e5, 1e5, 1e5),
      drawMask: () => _runSoftMaskForm(mask),
      backdropLuminance: mask.backdropLuminance,
      transferScale: mask.transferScale,
      transferOffset: mask.transferOffset,
    );
  }

  /// Runs the mask group's content with a fresh graphics state in the
  /// coordinate space captured when the mask was set.
  void _runSoftMaskForm(_ActiveSoftMask mask) {
    if (_currentFormDepth >= _maxFormDepth) return;
    final Uint8List content;
    try {
      content = cos.decodeStreamData(mask.form);
    } on Exception {
      return;
    }
    final savedState = _state;
    final savedStackDepth = _stateStack.length;
    device.save();
    try {
      _state = _GraphicsState()..ctm = mask.matrix;
      final matrix = cos.resolve(mask.form.dictionary['Matrix']);
      if (matrix is CosArray && matrix.length >= 6) {
        _state.ctm = _matrixFrom(matrix.items).concat(_state.ctm);
      }
      final bbox = cos.resolve(mask.form.dictionary['BBox']);
      if (bbox is CosArray && bbox.length >= 4) {
        _clipToBox([for (var i = 0; i < 4; i++) _numOf(cos.resolve(bbox[i]))]);
      }
      final resources = cos.resolve(mask.form.dictionary['Resources']);
      _run(
        ContentStreamParser.parse(content),
        resources is CosDictionary ? resources : CosDictionary(),
        _currentFormDepth + 1,
      );
      final nested = _state.softMask;
      if (nested != null) _finalizeSoftMask(nested);
    } finally {
      while (_stateStack.length > savedStackDepth) {
        _stateStack.removeLast();
      }
      _state = savedState;
      device.restore();
    }
  }

  // ---------- text ----------

  void _setFont(CosDictionary resources, List<CosObject> o) {
    _state.fontSize = _num(o, 1);
    final fonts = cos.resolve(resources['Font']);
    CosDictionary? dict;
    if (o.isNotEmpty && o[0] is CosName && fonts is CosDictionary) {
      final resolved = cos.resolve(fonts[(o[0] as CosName).value]);
      if (resolved is CosDictionary) dict = resolved;
    }
    // An unresolvable font (no /Resources at all, or a dangling entry)
    // substitutes Helvetica so the text still paints — and stays
    // selectable/searchable — instead of vanishing.
    dict ??= _fallbackFontDict ??= (CosDictionary()
      ..entries['Type'] = const CosName('Font')
      ..entries['Subtype'] = const CosName('Type1')
      ..entries['BaseFont'] = const CosName('Helvetica'));
    _state.fontDict = dict;
    final loaded = dict;
    _state.font =
        _fontCache.putIfAbsent(loaded, () => PdfFontInfo.load(cos, loaded));
  }

  CosDictionary? _fallbackFontDict;

  void _textLineMove(double tx, double ty) {
    _lineMatrix = PdfMatrix.translation(tx, ty).concat(_lineMatrix);
    _textMatrix = _lineMatrix;
  }

  void _showText(Uint8List bytes) {
    final font = _state.font;
    final size = _state.fontSize;
    if (font == null) return;

    final codes = font.codesOf(bytes);
    final buffer = StringBuffer();
    final emScale = size * _state.horizontalScale;
    // a non-null (possibly empty-outlined) glyph list tells devices the font
    // is embedded, so they must not substitute
    final glyphs = (font.hasOutlines || font.isType3) && emScale != 0
        ? <PdfGlyphPlacement>[]
        : null;
    var advance = 0.0; // in unscaled text-space units
    for (final code in codes) {
      buffer.write(font.charFor(code));
      glyphs?.add(PdfGlyphPlacement(
        offset: advance / emScale,
        outline: font.outlineFor(code),
      ));
      if (font.isType3 &&
          _state.renderMode != 3 &&
          _state.renderMode != 7 &&
          size != 0) {
        _drawType3Glyph(font, code, advance);
      }
      var tx = font.widthOf(code) * size + _state.charSpacing;
      if (!font.isCid && code == 0x20) tx += _state.wordSpacing;
      advance += tx * _state.horizontalScale;
    }

    if (size != 0 && _contentVisible) {
      // text rendering matrix: em space → page space (§9.4.4).
      // Mode 3 (invisible) still emits the run — flagged, so painting
      // devices skip it — because it IS the text of OCR'd scans, and
      // selection/search/extraction must see it.
      final transform = PdfMatrix(
        size * _state.horizontalScale, 0, //
        0, size, //
        0, _state.rise,
      ).concat(_textMatrix).concat(_state.ctm);
      final text = buffer.toString();

      // Text rendering modes (§9.4.3): 0 fill, 1 stroke, 2 fill+stroke,
      // 3 invisible, 4–6 = 0–2 plus clip, 7 clip only. Modes ≥4 add the
      // glyph outlines to the clipping path (applied at ET).
      final mode = _state.renderMode;
      if (mode >= 4 && glyphs != null) {
        _textClipPending = true;
        for (final g in glyphs) {
          final outline = g.outline;
          if (outline == null) continue;
          _appendTransformedPath(
            _textClipSegments,
            outline,
            PdfMatrix.translation(g.offset, 0).concat(transform),
          );
        }
      }

      if (text.trim().isNotEmpty || glyphs != null) {
        final fillText =
            mode == 0 || mode == 2 || mode == 4 || mode == 6;
        final pattern = fillText ? _state.fillPattern : null;
        // A tiling pattern can't be flattened to a gradient (shading patterns
        // can — see _gradientOfPattern). Paint it through the glyph outlines as
        // a clip, then emit the run invisibly so it stays selectable without
        // the solid fill colour showing through. Needs embedded outlines; a
        // substituted font falls back to the solid fill colour.
        var paintedAsTiling = false;
        if (glyphs != null && _isTilingPattern(pattern)) {
          final glyphPath = _glyphOutlinePath(glyphs, transform);
          if (glyphPath != null) {
            _fillWithPattern(glyphPath, PdfFillRule.nonzero, pattern!);
            paintedAsTiling = true;
          }
        }
        device.drawText(PdfTextRun(
          text: text,
          transform: transform,
          color: mode == 1 || mode == 5
              ? _state.strokeColor
              : _state.fillColor,
          gradient: fillText ? _gradientOfPattern(pattern) : null,
          width: advance / emScale,
          fontName: font.baseFont,
          fontSize: size,
          glyphs: glyphs,
          invisible: mode == 3 || mode == 7 || paintedAsTiling,
        ));
      }
    }
    _textMatrix = PdfMatrix.translation(advance, 0).concat(_textMatrix);
  }

  /// Executes a Type3 glyph procedure: a tiny content stream in glyph space,
  /// mapped through /FontMatrix and the text rendering matrix (§9.6.5).
  void _drawType3Glyph(PdfFontInfo font, int code, double penAdvance) {
    if (!_contentVisible) return;
    final proc = font.type3ProcFor(code);
    if (proc == null || _currentFormDepth >= _maxFormDepth) return;
    final List<ContentOperation> ops;
    try {
      ops = _patternOpsCache.putIfAbsent(
          proc, () => ContentStreamParser.parse(cos.decodeStreamData(proc)));
    } on Exception {
      return;
    }
    if (ops.isEmpty) return;

    final m = font.type3Matrix;
    final glyphToText = PdfMatrix(m[0], m[1], m[2], m[3], m[4], m[5]);
    final size = _state.fontSize;
    final ctm = glyphToText
        .concat(PdfMatrix(
            size * _state.horizontalScale, 0, 0, size, 0, _state.rise))
        .concat(PdfMatrix.translation(penAdvance, 0))
        .concat(_textMatrix)
        .concat(_state.ctm);

    final savedState = _state;
    final savedStackDepth = _stateStack.length;
    // A CharProc is its own content stream and usually opens its own BT..ET
    // (this font draws each glyph with a nested text object). Save the outer
    // text-object state so the inner BT/Tm/ET can't clobber the caller's text
    // matrix — otherwise every glyph after the first lands at the wrong
    // position (§9.6.5: the glyph description executes in glyph space and must
    // not disturb the text object that invoked it).
    final savedTextMatrix = _textMatrix;
    final savedLineMatrix = _lineMatrix;
    final savedClipPending = _textClipPending;
    final savedClipSegments = List.of(_textClipSegments);
    device.save();
    try {
      _state = _GraphicsState.from(savedState)
        ..ctm = ctm
        ..font = null
        ..softMask = savedState.softMask;
      _run(ops, font.type3Resources ?? CosDictionary(), _currentFormDepth + 1);
    } finally {
      while (_stateStack.length > savedStackDepth) {
        _stateStack.removeLast();
      }
      _state = savedState;
      _textMatrix = savedTextMatrix;
      _lineMatrix = savedLineMatrix;
      _textClipPending = savedClipPending;
      _textClipSegments
        ..clear()
        ..addAll(savedClipSegments);
      device.restore();
    }
  }

  // ---------- patterns and shadings ----------

  /// Looks up a named resource and resolves it (dictionary or stream).
  CosObject? _resource(CosDictionary resources, String category, CosName name) {
    final group = cos.resolve(resources[category]);
    if (group is! CosDictionary) return null;
    final value = cos.resolve(group[name.value]);
    return value is CosNull ? null : value;
  }

  CosDictionary? _patternDict(CosObject? pattern) {
    if (pattern is CosStream) return pattern.dictionary;
    if (pattern is CosDictionary) return pattern;
    return null;
  }

  PdfMatrix _patternMatrix(CosDictionary dict) {
    final matrix = cos.resolve(dict['Matrix']);
    return matrix is CosArray && matrix.length >= 6
        ? _matrixFrom(matrix.items)
        : PdfMatrix.identity;
  }

  PdfColor? _patternAverageColor(CosObject? pattern) {
    final dict = _patternDict(pattern);
    if (dict == null) return null;
    final shading = PdfShading.parse(cos, dict['Shading']);
    if (shading == null) return null;
    return shading.toGradient(PdfMatrix.identity)?.averageColor ??
        shading.toMesh(PdfMatrix.identity)?.averageColor ??
        shading.toFunctionMesh(PdfMatrix.identity)?.averageColor;
  }

  PdfGradient? _gradientOfPattern(CosObject? pattern) {
    final dict = _patternDict(pattern);
    if (dict == null) return null;
    final type = cos.resolve(dict['PatternType']);
    if (type is! CosInteger || type.value != 2) return null;
    return PdfShading.parse(cos, dict['Shading'])?.toGradient(
      _patternMatrix(dict),
    );
  }

  bool _isTilingPattern(CosObject? pattern) {
    if (pattern is! CosStream) return false;
    final type = cos.resolve(pattern.dictionary['PatternType']);
    return type is CosInteger && type.value == 1;
  }

  /// The combined glyph outlines of a run as one page-space path, for filling
  /// text with a pattern. Null when no glyph carries an outline.
  PdfPath? _glyphOutlinePath(
      List<PdfGlyphPlacement> glyphs, PdfMatrix transform) {
    final segments = <PdfPathSegment>[];
    for (final g in glyphs) {
      final outline = g.outline;
      if (outline == null) continue;
      _appendTransformedPath(segments, outline,
          PdfMatrix.translation(g.offset, 0).concat(transform));
    }
    return segments.isEmpty ? null : PdfPath(segments);
  }

  void _fillWithPattern(PdfPath path, PdfFillRule rule, CosObject pattern) {
    final dict = _patternDict(pattern);
    if (dict == null) return;
    final type = cos.resolve(dict['PatternType']);
    final patternType = type is CosInteger ? type.value : 0;

    if (patternType == 2) {
      // shading pattern: the matrix maps pattern space to page space
      final shading = PdfShading.parse(cos, dict['Shading']);
      final gradient = shading?.toGradient(_patternMatrix(dict));
      if (gradient != null) {
        device.fillPathGradient(path, rule, gradient, _state.fillAlpha);
        return;
      }
      final mesh = shading?.toMesh(_patternMatrix(dict)) ??
          shading?.toFunctionMesh(_patternMatrix(dict));
      if (mesh != null) {
        device.save();
        device.clipPath(path, rule);
        device.fillMesh(mesh, _state.fillAlpha);
        device.restore();
      }
      // unsupported shading types: skip rather than paint a wrong solid
      return;
    }
    if (patternType == 1 && pattern is CosStream) {
      _fillWithTilingPattern(path, rule, pattern);
    }
  }

  /// Runs a tiling pattern's cell content once per tile across the fill
  /// area, clipped to the fill path (§8.7.3).
  void _fillWithTilingPattern(
      PdfPath path, PdfFillRule rule, CosStream pattern) {
    if (_activeTilingPatterns.contains(pattern)) {
      // A reference cycle: this pattern's cell content (via a form) fills with
      // the same pattern. Rather than recurse to the form-depth limit and
      // paint nothing, break the cycle by solid-filling the clipped area —
      // matching pdf.js, which detects the operator-list cycle and renders the
      // box. Uncolored (PaintType 2) patterns carry an explicit colour;
      // colored ones default to black like the initial fill colour.
      final fallback = _state.fillPatternComponents.isNotEmpty
          ? colorFromComponents(_state.fillPatternComponents)
          : PdfColor.black;
      device.fillPath(path, fallback, rule, _state.fillAlpha);
      return;
    }
    if (_currentFormDepth >= _maxFormDepth) return;
    final dict = pattern.dictionary;
    final matrix = _patternMatrix(dict);
    final inverse = matrix.inverted();
    if (inverse == null) return;

    final ops = _patternOpsCache.putIfAbsent(pattern, () {
      try {
        return ContentStreamParser.parse(cos.decodeStreamData(pattern));
      } on Exception {
        return const [];
      }
    });
    if (ops.isEmpty) return;

    final bbox = _numbersOf(dict['BBox']);
    if (bbox.length < 4) return;
    var xStep = _numOf(cos.resolve(dict['XStep']));
    var yStep = _numOf(cos.resolve(dict['YStep']));
    if (xStep == 0) xStep = (bbox[2] - bbox[0]).abs();
    if (yStep == 0) yStep = (bbox[3] - bbox[1]).abs();
    if (xStep == 0 || yStep == 0) return;
    xStep = xStep.abs();
    yStep = yStep.abs();

    final paintTypeObj = cos.resolve(dict['PaintType']);
    final uncolored = paintTypeObj is CosInteger && paintTypeObj.value == 2;
    final resourcesObj = cos.resolve(dict['Resources']);
    final patternResources =
        resourcesObj is CosDictionary ? resourcesObj : CosDictionary();

    // fill-area bounds in pattern space decide which tiles to run
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final segment in path.segments) {
      for (final (x, y) in _segmentPoints(segment)) {
        minX = math.min(minX, inverse.transformX(x, y));
        minY = math.min(minY, inverse.transformY(x, y));
        maxX = math.max(maxX, inverse.transformX(x, y));
        maxY = math.max(maxY, inverse.transformY(x, y));
      }
    }
    if (minX > maxX) return;
    final i0 = ((minX - bbox[0]) / xStep).floor() - 1;
    final i1 = ((maxX - bbox[0]) / xStep).ceil();
    final j0 = ((minY - bbox[1]) / yStep).floor() - 1;
    final j1 = ((maxY - bbox[1]) / yStep).ceil();
    const maxTiles = 4096;
    if ((i1 - i0 + 1) * (j1 - j0 + 1) > maxTiles) return;

    device.save();
    device.clipPath(path, rule);
    final savedState = _state;
    final savedStackDepth = _stateStack.length;
    final patternColor =
        uncolored ? colorFromComponents(_state.fillPatternComponents) : null;
    _activeTilingPatterns.add(pattern);
    try {
      for (var j = j0; j <= j1; j++) {
        for (var i = i0; i <= i1; i++) {
          _state = _GraphicsState()
            ..ctm = PdfMatrix.translation(i * xStep, j * yStep).concat(matrix);
          if (patternColor != null) {
            _state.fillColor = patternColor;
            _state.strokeColor = patternColor;
          }
          device.save();
          try {
            // §8.7.3.1: the cell content is clipped to the pattern BBox before
            // tiling — content drawn outside the cell (this pattern's red rect
            // overruns the BBox by 50 units) must not paint, leaving the white
            // border the baseline shows.
            _clipToBox(bbox);
            _run(ops, patternResources, _currentFormDepth + 1);
          } finally {
            final mask = _state.softMask;
            if (mask != null) _finalizeSoftMask(mask);
            device.restore();
          }
        }
      }
    } finally {
      _activeTilingPatterns.remove(pattern);
      while (_stateStack.length > savedStackDepth) {
        _stateStack.removeLast();
      }
      _state = savedState;
      device.restore();
    }
  }

  void _applyShading(CosDictionary resources, List<CosObject> o) {
    if (o.isEmpty || o[0] is! CosName) return;
    final shading =
        PdfShading.parse(cos, _resource(resources, 'Shading', o[0] as CosName));
    // sh geometry lives in the current user space (§8.7.4.2)
    final gradient = shading?.toGradient(_state.ctm);
    if (gradient == null) {
      // mesh and function-based shadings paint their own geometry; the
      // clip bounds them
      final mesh =
          shading?.toMesh(_state.ctm) ?? shading?.toFunctionMesh(_state.ctm);
      if (mesh != null) device.fillMesh(mesh, _state.fillAlpha);
      return;
    }
    // paint across the page; the active canvas clip bounds it
    final box = _pageBox ?? const PdfRect(-1e5, -1e5, 1e5, 1e5);
    final area = PdfPath([
      PdfMoveTo(box.left, box.bottom),
      PdfLineTo(box.right, box.bottom),
      PdfLineTo(box.right, box.top),
      PdfLineTo(box.left, box.top),
      const PdfClosePath(),
    ]);
    device.fillPathGradient(
        area, PdfFillRule.nonzero, gradient, _state.fillAlpha);
  }

  List<double> _numbersOf(CosObject? object) {
    final v = cos.resolve(object);
    if (v is! CosArray) return const [];
    return [for (final item in v.items) _numOf(cos.resolve(item))];
  }

  static Iterable<(double, double)> _segmentPoints(
      PdfPathSegment segment) sync* {
    switch (segment) {
      case PdfMoveTo(:final x, :final y) || PdfLineTo(:final x, :final y):
        yield (x, y);
      case PdfCubicTo():
        yield (segment.x1, segment.y1);
        yield (segment.x2, segment.y2);
        yield (segment.x3, segment.y3);
      case PdfClosePath():
        break;
    }
  }

  // ---------- XObjects ----------

  CosDictionary? _dictResource(
      CosDictionary resources, String category, List<CosObject> o) {
    if (o.isEmpty || o[0] is! CosName) return null;
    final group = cos.resolve(resources[category]);
    if (group is! CosDictionary) return null;
    final value = cos.resolve(group[(o[0] as CosName).value]);
    return value is CosDictionary ? value : null;
  }

  void _doXObject(CosDictionary resources, List<CosObject> o, int formDepth) {
    if (o.isEmpty || o[0] is! CosName) return;
    final group = cos.resolve(resources['XObject']);
    if (group is! CosDictionary) return;
    final xobject = cos.resolve(group[(o[0] as CosName).value]);
    if (xobject is! CosStream) return;

    final subtype = xobject.dictionary['Subtype'];
    final name = subtype is CosName ? subtype.value : '';
    if (name == 'Image') {
      device.drawImage(PdfImageRequest(
        stream: xobject,
        transform: _state.ctm,
        alpha: _state.fillAlpha,
        isStencil: cos.resolve(xobject.dictionary['ImageMask']) ==
            const CosBoolean(true),
        stencilColor: _state.fillColor,
      ));
      return;
    }
    if (name != 'Form' || formDepth >= _maxFormDepth) return;

    // a transparency group composites as one object: the alpha in effect
    // at Do applies to the group's result, and resets inside (§11.6.6) —
    // otherwise an inner `gs` back to ca 1.0 would erase the group alpha
    final groupAlpha = _state.fillAlpha;
    final isGroup = cos.resolve(xobject.dictionary['Group']) is CosDictionary;
    final groupLayer = isGroup && groupAlpha < 1;

    final outerMask = _state.softMask;
    _stateStack.add(_GraphicsState.from(_state));
    device.save();
    if (groupLayer) {
      device.beginGroup(groupAlpha);
      _state.fillAlpha = 1;
      _state.strokeAlpha = 1;
    }
    try {
      final matrix = cos.resolve(xobject.dictionary['Matrix']);
      if (matrix is CosArray && matrix.length >= 6) {
        _state.ctm = _matrixFrom(matrix.items).concat(_state.ctm);
      }
      final bbox = cos.resolve(xobject.dictionary['BBox']);
      if (bbox is CosArray && bbox.length >= 4) {
        _clipToBox([for (var i = 0; i < 4; i++) _numOf(cos.resolve(bbox[i]))]);
      }
      final innerResources = cos.resolve(xobject.dictionary['Resources']);
      final Uint8List content;
      try {
        content = cos.decodeStreamData(xobject);
      } on Exception {
        return;
      }
      _run(
        ContentStreamParser.parse(content),
        innerResources is CosDictionary ? innerResources : resources,
        formDepth + 1,
      );
    } finally {
      // masks opened inside the form must close before its device.restore
      final mask = _state.softMask;
      if (mask != null && !identical(mask, outerMask)) {
        _finalizeSoftMask(mask);
      }
      if (groupLayer) device.endGroup();
      _state = _stateStack.removeLast();
      device.restore();
    }
  }

  void _clipToBox(List<double> box) {
    final m = _state.ctm;
    final corners = [
      (box[0], box[1]),
      (box[2], box[1]),
      (box[2], box[3]),
      (box[0], box[3]),
    ];
    final segments = <PdfPathSegment>[
      for (var i = 0; i < corners.length; i++)
        i == 0
            ? PdfMoveTo(m.transformX(corners[i].$1, corners[i].$2),
                m.transformY(corners[i].$1, corners[i].$2))
            : PdfLineTo(m.transformX(corners[i].$1, corners[i].$2),
                m.transformY(corners[i].$1, corners[i].$2)),
      const PdfClosePath(),
    ];
    device.clipPath(PdfPath(segments), PdfFillRule.nonzero);
  }

  /// Appends [path]'s segments, mapped through [m], onto [out] — used to bake
  /// glyph outlines (em space) into the page-space text clipping path.
  static void _appendTransformedPath(
      List<PdfPathSegment> out, PdfPath path, PdfMatrix m) {
    for (final s in path.segments) {
      out.add(switch (s) {
        PdfMoveTo(:final x, :final y) =>
          PdfMoveTo(m.transformX(x, y), m.transformY(x, y)),
        PdfLineTo(:final x, :final y) =>
          PdfLineTo(m.transformX(x, y), m.transformY(x, y)),
        PdfCubicTo(:final x1, :final y1, :final x2, :final y2, :final x3,
                :final y3) =>
          PdfCubicTo(
              m.transformX(x1, y1),
              m.transformY(x1, y1),
              m.transformX(x2, y2),
              m.transformY(x2, y2),
              m.transformX(x3, y3),
              m.transformY(x3, y3)),
        PdfClosePath() => const PdfClosePath(),
      });
    }
  }

  void _drawInlineImage(List<CosObject> o) {
    if (o.length < 2 || o[0] is! CosDictionary || o[1] is! CosString) return;
    final abbreviated = o[0] as CosDictionary;
    // inline image dictionaries use abbreviated keys (§8.9.7, table 91)
    const expansions = {
      'W': 'Width',
      'H': 'Height',
      'BPC': 'BitsPerComponent',
      'CS': 'ColorSpace',
      'F': 'Filter',
      'D': 'Decode',
      'DP': 'DecodeParms',
      'IM': 'ImageMask',
      'I': 'Interpolate',
    };
    final dict = CosDictionary();
    abbreviated.entries.forEach((key, value) {
      dict[expansions[key] ?? key] = value;
    });
    device.drawImage(PdfImageRequest(
      stream: CosStream(dict, (o[1] as CosString).bytes),
      transform: _state.ctm,
      alpha: _state.fillAlpha,
      isStencil: dict['ImageMask'] == const CosBoolean(true),
      stencilColor: _state.fillColor,
      isInline: true,
    ));
  }

  // ---------- helpers ----------

  static double _numOf(CosObject? value) {
    if (value is CosInteger) return value.value.toDouble();
    if (value is CosReal) return value.value;
    return 0;
  }

  static double _num(List<CosObject> operands, int index) =>
      index < operands.length ? _numOf(operands[index]) : 0;

  static PdfMatrix _matrixFrom(List<CosObject> o) => PdfMatrix(
      _num(o, 0), _num(o, 1), _num(o, 2), _num(o, 3), _num(o, 4), _num(o, 5));
}
