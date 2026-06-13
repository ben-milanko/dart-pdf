import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'image_decoder.dart';

/// Paints interpreter callbacks onto a Flutter [Canvas].
///
/// Expects the canvas to be set up in page space (PDF user space, y-up); the
/// renderer applies the global y-flip. Text is drawn with substituted system
/// fonts, horizontally scaled to the PDF's own metrics, until the font
/// engine produces real glyph outlines. Images must be pre-decoded into
/// [images] (painting is synchronous).
class CanvasPdfDevice implements PdfDevice {
  CanvasPdfDevice(this.canvas, {this.images = const {}});

  final Canvas canvas;

  /// Decoded images keyed by [pdfImageKey] — stream identity for XObjects,
  /// value identity for inline images.
  final Map<Object, ui.Image> images;

  BlendMode _blend = BlendMode.srcOver;

  /// One entry per open transparency group: true while that group is a
  /// knockout group (§11.4.5). q/Q (save/restore) don't push here, so the
  /// top entry tracks the group directly enclosing the next paint call.
  final _knockout = <bool>[];

  /// True when the next paint call is a top-level element of a knockout
  /// group, so it must replace rather than blend over the group result.
  bool get _knockoutActive => _knockout.isNotEmpty && _knockout.last;

  /// Blend mode for a paint primitive. Knockout elements use [BlendMode.src]
  /// so only the element's own coverage is replaced in the group buffer
  /// (drawing directly, with no intermediate full-bounds layer, keeps the
  /// areas it doesn't cover — earlier elements — intact).
  BlendMode get _elementBlend => _knockoutActive ? BlendMode.src : _blend;

  /// Converts rendered luminance into alpha — the compositing core of a
  /// /Luminosity soft mask.
  static const _luminanceToAlpha = ColorFilter.matrix([
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
  ]);

  @override
  void save() => canvas.save();

  @override
  void restore() => canvas.restore();

  @override
  void setBlendMode(PdfBlendMode mode) {
    _blend = switch (mode) {
      PdfBlendMode.normal => BlendMode.srcOver,
      PdfBlendMode.multiply => BlendMode.multiply,
      PdfBlendMode.screen => BlendMode.screen,
      PdfBlendMode.overlay => BlendMode.overlay,
      PdfBlendMode.darken => BlendMode.darken,
      PdfBlendMode.lighten => BlendMode.lighten,
      PdfBlendMode.colorDodge => BlendMode.colorDodge,
      PdfBlendMode.colorBurn => BlendMode.colorBurn,
      PdfBlendMode.hardLight => BlendMode.hardLight,
      PdfBlendMode.softLight => BlendMode.softLight,
      PdfBlendMode.difference => BlendMode.difference,
      PdfBlendMode.exclusion => BlendMode.exclusion,
      PdfBlendMode.hue => BlendMode.hue,
      PdfBlendMode.saturation => BlendMode.saturation,
      PdfBlendMode.color => BlendMode.color,
      PdfBlendMode.luminosity => BlendMode.luminosity,
    };
  }

  @override
  void beginGroup(double alpha, {bool knockout = false}) {
    canvas.saveLayer(
      null,
      Paint()
        ..color =
            Color.from(alpha: alpha.clamp(0, 1), red: 0, green: 0, blue: 0)
        ..blendMode = _blend,
    );
    _knockout.add(knockout);
  }

  @override
  void endGroup() {
    _knockout.removeLast();
    canvas.restore();
  }

  @override
  void beginSoftMasked() {
    canvas.saveLayer(null, Paint());
    // The mask group's content composites as one element of any enclosing
    // knockout group, through this layer — not element by element.
    _knockout.add(false);
  }

  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {
    final hasTransfer = transferScale != 1 || transferOffset != 0;
    final paint = Paint()..blendMode = BlendMode.dstIn;
    if (luminosity) {
      // Fold the /TR transfer (linearised) into the luminance→alpha matrix:
      // alpha = luminance * scale + offset.
      paint.colorFilter = hasTransfer
          ? ColorFilter.matrix(<double>[
              0, 0, 0, 0, 0, //
              0, 0, 0, 0, 0, //
              0, 0, 0, 0, 0, //
              0.2126 * transferScale, 0.7152 * transferScale,
              0.0722 * transferScale, 0, transferOffset * 255,
            ])
          : _luminanceToAlpha;
    } else if (hasTransfer) {
      // Alpha mask: remap the captured alpha through the transfer. Unpainted
      // (transparent) areas filter to transferOffset = TR(0), so the
      // out-of-bounds backdrop falls out for free.
      paint.colorFilter = ColorFilter.matrix(<double>[
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, //
        0, 0, 0, transferScale, transferOffset * 255,
      ]);
    }
    canvas.saveLayer(null, paint);
    if (luminosity) {
      // Unpainted mask area takes the /BC backdrop luminance (default black →
      // fully transparent content); the colour filter turns it into alpha.
      final g = backdropLuminance.clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTRB(
            backdrop.left, backdrop.bottom, backdrop.right, backdrop.top),
        Paint()..color = Color.from(alpha: 1, red: g, green: g, blue: g),
      );
    }
    drawMask();
    canvas.restore(); // composite the mask into the content (dstIn)
    canvas.restore(); // composite the masked content into the page
    _knockout.removeLast();
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    canvas.drawPath(
      _toUiPath(path, rule),
      Paint()
        ..style = PaintingStyle.fill
        ..color = _toColor(color, alpha)
        ..blendMode = _elementBlend,
    );
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    canvas.drawPath(
      _toUiPath(path, rule),
      Paint()
        ..shader = _shaderFor(gradient)
        ..blendMode = _elementBlend
        ..color =
            Color.from(alpha: alpha.clamp(0, 1), red: 0, green: 0, blue: 0),
    );
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    if (mesh.vertices.isEmpty || mesh.triangles.isEmpty) return;
    final positions = Float32List(mesh.vertices.length * 2);
    final colors = Int32List(mesh.vertices.length);
    final a = (alpha.clamp(0.0, 1.0) * 255).round();
    for (var i = 0; i < mesh.vertices.length; i++) {
      final v = mesh.vertices[i];
      positions[i * 2] = v.x;
      positions[i * 2 + 1] = v.y;
      colors[i] = (a << 24) |
          ((v.color.red * 255).round().clamp(0, 255) << 16) |
          ((v.color.green * 255).round().clamp(0, 255) << 8) |
          (v.color.blue * 255).round().clamp(0, 255);
    }
    // Uint16 indices cap the vertex count; expand huge meshes instead
    final ui.Vertices vertices;
    if (mesh.vertices.length <= 0xFFFF) {
      vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: Uint16List.fromList(mesh.triangles),
      );
    } else {
      final expanded = Float32List(mesh.triangles.length * 2);
      final expandedColors = Int32List(mesh.triangles.length);
      for (var i = 0; i < mesh.triangles.length; i++) {
        final v = mesh.triangles[i];
        expanded[i * 2] = positions[v * 2];
        expanded[i * 2 + 1] = positions[v * 2 + 1];
        expandedColors[i] = colors[v];
      }
      vertices = ui.Vertices.raw(ui.VertexMode.triangles, expanded,
          colors: expandedColors);
    }
    // BlendMode.dst keeps the vertex colors (paint is the src side of
    // this mode); the paint still carries the PDF blend mode
    canvas.drawVertices(
        vertices, BlendMode.dst, Paint()..blendMode = _elementBlend);
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    var uiPath = _toUiPath(path, PdfFillRule.nonzero);
    if (stroke.dashArray.any((d) => d > 0)) {
      uiPath = _dashPath(uiPath, stroke.dashArray, stroke.dashPhase);
    }
    canvas.drawPath(
      uiPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _toColor(color, alpha)
        ..strokeWidth = stroke.width
        ..strokeCap = switch (stroke.cap) {
          1 => StrokeCap.round,
          2 => StrokeCap.square,
          _ => StrokeCap.butt,
        }
        ..strokeJoin = switch (stroke.join) {
          1 => StrokeJoin.round,
          2 => StrokeJoin.bevel,
          _ => StrokeJoin.miter,
        }
        ..strokeMiterLimit = stroke.miterLimit
        ..blendMode = _elementBlend,
    );
  }

  /// Rebuilds [source] as its dashed segments (§8.4.3.6). Zero-length
  /// "on" dashes become near-zero slivers so round caps still paint dots.
  static ui.Path _dashPath(ui.Path source, List<double> pattern, double phase) {
    // odd-length patterns repeat doubled, per spec
    final dashes = [
      for (final d in pattern)
        if (d >= 0) d,
    ];
    if (dashes.length.isOdd) dashes.addAll(List.of(dashes));
    final cycle = dashes.fold(0.0, (a, b) => a + b);
    if (dashes.isEmpty || cycle <= 0) return source;

    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      var index = 0;
      var on = true;
      var remaining = dashes[0];
      var toSkip = phase.abs() % cycle;
      while (toSkip > 0) {
        if (toSkip >= remaining) {
          toSkip -= remaining;
          index = (index + 1) % dashes.length;
          on = !on;
          remaining = dashes[index];
        } else {
          remaining -= toSkip;
          toSkip = 0;
        }
      }
      var distance = 0.0;
      while (distance < metric.length) {
        var end = distance + remaining;
        if (end > metric.length) end = metric.length;
        if (on) {
          final sliver = end - distance < 1e-3
              ? (distance + 1e-3 > metric.length
                  ? metric.length
                  : distance + 1e-3)
              : end;
          out.addPath(metric.extractPath(distance, sliver), ui.Offset.zero);
        }
        remaining -= end - distance;
        distance = end;
        if (remaining <= 1e-9) {
          index = (index + 1) % dashes.length;
          on = !on;
          remaining = dashes[index];
          // all-zero tail protection: force progress
          if (remaining <= 0 && cycle <= 1e-9) break;
        }
      }
    }
    return out;
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    // Rectangular clips (the `re W n` idiom) must not antialias: writers
    // tile big images as abutting clipped strips, and soft clip edges
    // composite to <100% coverage at every shared boundary — visible as
    // hairline seams of the backdrop. Hard edges keep abutting strips
    // pixel-exact; irregular clips keep antialiasing for quality.
    final rect = _rectOf(path);
    if (rect != null) {
      canvas.clipRect(rect, doAntiAlias: false);
    } else {
      canvas.clipPath(_toUiPath(path, rule));
    }
  }

  /// The path as a single axis-aligned rectangle, or null. The four
  /// points must be exactly the corners of their bounding box.
  static ui.Rect? _rectOf(PdfPath path) {
    final points = <ui.Offset>[];
    for (final segment in path.segments) {
      switch (segment) {
        case PdfMoveTo(:final x, :final y):
          if (points.isNotEmpty) return null;
          points.add(ui.Offset(x, y));
        case PdfLineTo(:final x, :final y):
          if (points.isEmpty) return null;
          points.add(ui.Offset(x, y));
        case PdfClosePath():
          break;
        case PdfCubicTo():
          return null;
      }
    }
    if (points.length == 5 && points.last == points.first) {
      points.removeLast();
    }
    if (points.length != 4) return null;
    final xs = points.map((p) => p.dx).toSet();
    final ys = points.map((p) => p.dy).toSet();
    if (xs.length != 2 || ys.length != 2) return null;
    for (final corner in [
      for (final x in xs)
        for (final y in ys) ui.Offset(x, y),
    ]) {
      if (!points.contains(corner)) return null;
    }
    return ui.Rect.fromLTRB(
      xs.reduce((a, b) => a < b ? a : b),
      ys.reduce((a, b) => a < b ? a : b),
      xs.reduce((a, b) => a > b ? a : b),
      ys.reduce((a, b) => a > b ? a : b),
    );
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.invisible) return; // OCR layers occupy geometry, paint nothing
    if (run.glyphs != null) {
      // embedded font: draw its real outlines, never substitute — blank
      // glyphs (invisible text layers, Type3 procs drawn by the
      // interpreter) stay blank
      _drawGlyphOutlines(run);
      return;
    }
    // No embedded font program: substitute a system font, drawn at 100px
    // and scaled down 100x (TextPainter quality degrades at tiny sizes; the
    // run transform already encodes the real size).
    const renderSize = 100.0;
    // Measure with a plain fill painter to derive width/baseline.
    final measure = TextPainter(
      text: TextSpan(text: run.text, style: _styleFor(run, foreground: null)),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline =
        measure.computeDistanceToActualBaseline(TextBaseline.alphabetic);

    canvas.save();
    canvas.transform(_toFloat64(run.transform));
    // unflip: the page transform is y-up, text rasterizes y-down
    final targetWidth = run.width * renderSize;
    final scaleX = run.width > 0 && measure.width > 0
        ? targetWidth / measure.width
        : 1.0;

    // Fill painter (modes 0/2/4/6), with a gradient shader when present.
    TextPainter? fillPainter;
    if (run.fill) {
      Paint? foreground;
      final gradient = run.gradient;
      if (gradient != null) {
        final localToPage =
            PdfMatrix.scaled(scaleX / renderSize, -1 / renderSize)
                .concat(run.transform);
        final pageToLocal = localToPage.inverted();
        if (pageToLocal != null) {
          foreground = Paint()
            ..shader = _shaderFor(gradient,
                transform: gradient.transform.concat(pageToLocal))
            ..blendMode = _elementBlend;
        }
      }
      fillPainter = foreground == null
          ? measure
          : (TextPainter(
              text: TextSpan(
                  text: run.text, style: _styleFor(run, foreground: foreground)),
              textDirection: TextDirection.ltr,
            )..layout());
    }

    // Stroke painter (modes 1/2/5/6): outline the glyphs in the stroke colour.
    // The line width is page-space; map it into the painter's 100px-per-em
    // space (canvas is scaled by run.transform then 1/renderSize).
    TextPainter? strokePainter;
    if (run.strokeColor != null) {
      final ts = run.transform.scaleFactor;
      final w = run.strokeWidth > 0 ? run.strokeWidth : ts / renderSize;
      strokePainter = TextPainter(
        text: TextSpan(
          text: run.text,
          style: _styleFor(
            run,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = ts > 0 ? w * renderSize / ts : w
              ..color = _toColor(run.strokeColor!, 1)
              ..blendMode = _elementBlend,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    canvas.scale(scaleX / renderSize, -1 / renderSize);
    fillPainter?.paint(canvas, Offset(0, -baseline));
    strokePainter?.paint(canvas, Offset(0, -baseline));
    canvas.restore();
  }

  /// Draws real glyph outlines from the embedded font. The run transform
  /// maps em space (y-up) to page space, so no unflip is needed.
  void _drawGlyphOutlines(PdfTextRun run) {
    final path = ui.Path();
    for (final glyph in run.glyphs!) {
      final outline = glyph.outline;
      if (outline == null) continue;
      path.addPath(
        _toUiPath(outline, PdfFillRule.nonzero).transform(
          _toFloat64(PdfMatrix.translation(glyph.offset, glyph.offsetY)
              .concat(run.transform)),
        ),
        Offset.zero,
      );
    }
    if (run.fill) {
      final paint = Paint()..blendMode = _elementBlend;
      final gradient = run.gradient;
      if (gradient != null) {
        paint.shader = _shaderFor(gradient);
      } else {
        paint.color = _toColor(run.color, 1);
      }
      canvas.drawPath(path, paint);
    }
    // The outline path is already in page space; stroke width is page-space.
    if (run.strokeColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = run.strokeWidth
          ..color = _toColor(run.strokeColor!, 1)
          ..blendMode = _elementBlend,
      );
    }
  }

  @override
  void drawImage(PdfImageRequest request) {
    final image = images[pdfImageKey(request)];
    if (image == null) return; // not decodable (yet): skip silently
    // antialiased edges leave hairline seams between abutting image slices
    // (PowerPoint and scanners split large images into strips)
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = false
      ..blendMode = _elementBlend;
    if (request.isStencil) {
      // stencil masks paint the fill color through the mask's alpha
      paint.colorFilter = ColorFilter.mode(
          _toColor(request.stencilColor, request.alpha), BlendMode.srcIn);
    } else {
      paint.color = Color.from(alpha: request.alpha, red: 0, green: 0, blue: 0);
    }
    canvas.save();
    canvas.transform(_toFloat64(request.transform));
    // image space: unit square, y-up; image pixels: y-down from the top
    canvas.translate(0, 1);
    canvas.scale(1, -1);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, 1, 1),
      paint,
    );
    canvas.restore();
  }

  TextStyle _styleFor(PdfTextRun run, {Paint? foreground}) {
    final name = run.fontName ?? '';
    final cjk = _cjkPrimaryFontFor(name);
    final symbol = name.contains('ZapfDingbats') || name.contains('Symbol');
    return TextStyle(
      color: foreground == null ? _toColor(run.color, 1) : null,
      foreground: foreground,
      fontSize: 100,
      fontFamily: cjk ??
          switch (name) {
            _ when name.contains('ZapfDingbats') => 'Zapf Dingbats',
            _ when name.contains('Symbol') => 'Symbol',
            _ when name.contains('Courier') || name.contains('Mono') =>
              'Courier',
            _ when name.contains('Times') || name.contains('Serif') =>
              'Times New Roman',
            _ => 'Helvetica',
          },
      fontFamilyFallback: cjk != null
          ? _cjkFontFallbacks
          : symbol
              ? _symbolFontFallbacks
              : _defaultFontFallbacks,
      fontWeight: name.contains('Bold') ? FontWeight.bold : FontWeight.normal,
      fontStyle: name.contains('Italic') || name.contains('Oblique')
          ? FontStyle.italic
          : FontStyle.normal,
      // metric scaling handles placement; kill extra spacing sources
      letterSpacing: 0,
      height: 1,
    );
  }

  static const _cjkFontFallbacks = [
    // Apple platforms. Hiragino leads: it resolves where PingFang sometimes
    // does not, and covers both Japanese and (via Sans GB) Chinese.
    'Hiragino Sans', // Japanese kana/kanji
    'Hiragino Mincho ProN',
    'PingFang SC',
    'Songti SC',
    'Heiti SC',
    'Hiragino Sans GB',
    // Android/Linux distributions.
    'Noto Sans CJK SC',
    'Noto Sans CJK JP',
    'Noto Serif CJK JP',
    'Noto Serif CJK SC',
    'Source Han Sans SC',
    'Source Han Serif SC',
    // Windows.
    'Microsoft YaHei',
    'Yu Gothic',
    'MS Gothic',
    'SimSun',
    'SimHei',
  ];

  static const _defaultFontFallbacks = [
    'Hiragino Sans',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Noto Sans CJK JP',
    'Source Han Sans SC',
    'Microsoft YaHei',
  ];

  static const _symbolFontFallbacks = [
    'Noto Sans Symbols',
    'Noto Sans Symbols 2',
    'DejaVu Sans',
    'Apple Symbols',
    'Segoe UI Symbol',
  ];

  static String? _cjkPrimaryFontFor(String name) {
    if (name.contains('ºÚÌå')) return 'Heiti SC'; // 黑体
    if (name.contains('ËÎÌå') ||
        name.contains('·ÂËÎ') ||
        name.contains('Ð¡±êËÎ')) {
      return 'STSong'; // 宋体 / 仿宋 / 小标宋
    }
    // Japanese CID fonts (Adobe-Japan1): pick a matching system face so the
    // weight/serif roughly tracks the document's. Tokens are specific enough
    // to avoid Latin look-alikes (we never match a bare "Gothic").
    if (name.contains('Mincho') ||
        name.contains('HeiseiMin') ||
        name.contains('Ryumin') ||
        name.contains('KozMin')) {
      return 'Hiragino Mincho ProN';
    }
    if (name.contains('HeiseiKakuGo') ||
        name.contains('GothicBBB') ||
        name.contains('KozGo') ||
        name.contains('Kaku') ||
        name.contains('MS-Gothic')) {
      return 'Hiragino Sans';
    }
    return null;
  }

  static Color _toColor(PdfColor color, double alpha) => Color.from(
        alpha: alpha.clamp(0, 1),
        red: color.red.clamp(0, 1),
        green: color.green.clamp(0, 1),
        blue: color.blue.clamp(0, 1),
      );

  static ui.Shader _shaderFor(PdfGradient gradient, {PdfMatrix? transform}) {
    final colors = [for (final c in gradient.colors) _toColor(c, 1)];
    final stops = List<double>.of(gradient.stops);
    // /Extend false paints nothing beyond that end: a zero-width
    // transparent stop makes TileMode.clamp continue with transparency
    // instead of the terminal color.
    if (!gradient.extendStart && colors.isNotEmpty) {
      colors.insert(0, colors.first.withAlpha(0));
      stops.insert(0, stops.first);
    }
    if (!gradient.extendEnd && colors.isNotEmpty) {
      colors.add(colors.last.withAlpha(0));
      stops.add(stops.last);
    }
    final matrix = _toFloat64(transform ?? gradient.transform);
    final c = gradient.coords;
    return gradient.isRadial
        ? ui.Gradient.radial(Offset(c[3], c[4]), c[5], colors, stops,
            TileMode.clamp, matrix, Offset(c[0], c[1]), c[2])
        : ui.Gradient.linear(Offset(c[0], c[1]), Offset(c[2], c[3]), colors,
            stops, TileMode.clamp, matrix);
  }

  static ui.Path _toUiPath(PdfPath path, PdfFillRule rule) {
    final out = ui.Path()
      ..fillType = rule == PdfFillRule.evenOdd
          ? PathFillType.evenOdd
          : PathFillType.nonZero;
    for (final segment in path.segments) {
      switch (segment) {
        case PdfMoveTo(:final x, :final y):
          out.moveTo(x, y);
        case PdfLineTo(:final x, :final y):
          out.lineTo(x, y);
        case PdfCubicTo():
          out.cubicTo(segment.x1, segment.y1, segment.x2, segment.y2,
              segment.x3, segment.y3);
        case PdfClosePath():
          out.close();
      }
    }
    return out;
  }

  static Float64List _toFloat64(PdfMatrix m) => Float64List.fromList([
        m.a, m.b, 0, 0, //
        m.c, m.d, 0, 0, //
        0, 0, 1, 0, //
        m.e, m.f, 0, 1,
      ]);
}
