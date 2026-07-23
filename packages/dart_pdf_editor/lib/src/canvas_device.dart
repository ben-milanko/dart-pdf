import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'budgeted_cache.dart';
import 'image_decoder.dart';
import 'perf_log.dart';

/// Paints interpreter callbacks onto a Flutter [Canvas].
///
/// Expects the canvas to be set up in page space (PDF user space, y-up); the
/// renderer applies the global y-flip. Text is drawn with substituted system
/// fonts, horizontally scaled to the PDF's own metrics, until the font
/// engine produces real glyph outlines. Images must be pre-decoded into
/// [images] (painting is synchronous).
class CanvasPdfDevice implements PdfDevice, PdfTiledCellSink {
  CanvasPdfDevice(this.canvas,
      {this.images = const {}, this.pixelRatio = 1});

  final Canvas canvas;

  /// Device pixels per page unit at the scale this device is painting for.
  ///
  /// Only used to floor stroke widths at one device pixel (see
  /// [_strokeWidthFor]). 1 is the identity assumption for a picture recorded
  /// without a known target scale.
  final double pixelRatio;

  /// Stroke width to paint, never thinner than one device pixel.
  ///
  /// Skia paints a stroke narrower than a pixel as a one-pixel line with its
  /// **alpha scaled down** by the sub-pixel width, rather than as a true
  /// sub-pixel band. Faithful to Skia, but not to the page: CAD and schematic
  /// producers emit 0.06 pt / 0.12 pt lines meaning "hairline", and those came
  /// out at ~6% and ~12% opacity - the pale, washed-out linework this floor
  /// fixes. Reference viewers paint them as solid one-pixel lines.
  ///
  /// A width of 0 arrives here unchanged from the interpreter and is floored
  /// the same way, which is PDF 32000-1 8.4.3.2's "thinnest line that can be
  /// rendered at device resolution: 1 device pixel" - and, unlike the old
  /// user-space resolution, it stays one pixel at every zoom.
  @visibleForTesting
  double strokeWidthFor(double width) {
    if (pixelRatio <= 0) return width;
    // 0 is Skia's hairline: exactly one device pixel at *any* canvas
    // transform, at full alpha. That matters because a recorded picture is
    // replayed at several ratios (base raster, deep-zoom detail patch,
    // retained scene), so a page-space floor baked at record time would be
    // right for one of them and too thick for the rest. A hairline is correct
    // for all of them.
    return width * pixelRatio < 1 ? 0 : width;
  }

  /// Decoded images keyed by [pdfImageKey] — stream identity for XObjects,
  /// value identity for inline images.
  final Map<Object, ui.Image> images;

  /// Process-wide cache of laid-out substituted-text painters. Shaping is the
  /// dominant paint-pass cost and the same runs recur across pages and
  /// re-renders, so this is shared by every render (like the decoded-image
  /// cache). Keyed by (text, font, colour); bounded by entry count, evicting
  /// the least-recently-used layout and disposing its painter. Registered with
  /// [PdfCacheRegistry] so a memory-pressure signal reaches it too (it used to
  /// be deaf to pressure); [clearTextLayoutCache] drops it on demand.
  static final PdfBudgetedCache<String, _TextLayout> _textCache =
      PdfBudgetedCache<String, _TextLayout>(
    maxEntries: 2048,
    disposer: (layout) => layout.dispose(),
    clearsUnderMemoryPressure: true,
    debugLabel: 'text-layout',
  );

  /// Per-character layout cache backing [perGlyphSubstitutedText] (#454): a
  /// single laid-out [TextPainter] per (character, font, colour). A run of
  /// unique labels shares the same handful of digits/letters, so this hits
  /// near-100% where the run cache misses every time. Small (an alphabet, not a
  /// corpus of runs), so its bound is generous and it rarely evicts - which also
  /// keeps the transient composed runs that reference it safe.
  static final PdfBudgetedCache<String, _TextLayout> _glyphCache =
      PdfBudgetedCache<String, _TextLayout>(
    maxEntries: 4096,
    disposer: (layout) => layout.dispose(),
    clearsUnderMemoryPressure: true,
    debugLabel: 'glyph-layout',
  );

  /// Compose substituted-font runs from cached per-character layouts instead of
  /// shaping the whole run (#454). Unique labels (which miss the run cache and
  /// re-shape every time - the replay-bound CAD pathology) then reuse
  /// per-character shaping and drop toward the warm-cache floor. Restricted to
  /// pure-fill runs whose text has no kernable adjacency (see [_composableRun]);
  /// everything else keeps whole-run shaping. On by default: a real-Chrome probe
  /// across Helvetica/Arial/Courier put the composed-vs-whole-run pixel diff at
  /// 0% for every run this gate admits (kerning-pair uppercase words, the only
  /// divergent case, are excluded), so the speed-up carries no fidelity cost.
  static bool perGlyphSubstitutedText = true;

  /// Em-space [ui.Path] per embedded-glyph outline, keyed by outline identity.
  /// An [Expando] ties each entry to its [PdfPath]'s lifetime (the font's own
  /// outline cache), so it needs no bound and frees with the font.
  static final _glyphPaths = Expando<ui.Path>('glyphUiPaths');

  /// Drops every cached text layout (memory pressure / tests). The
  /// decoded-image cache ([PdfImageCache]) is separate.
  static void clearTextLayoutCache() {
    _textCache.clear();
    _glyphCache.clear();
  }

  /// Number of cached text layouts — test hook.
  @visibleForTesting
  static int get debugTextLayoutCacheLength => _textCache.length;

  /// Number of cached per-character glyph layouts — test hook (#454).
  @visibleForTesting
  static int get debugGlyphLayoutCacheLength => _glyphCache.length;

  /// Within-replay substituted-text shaping split (#454). [debugTextShapeUs] is
  /// the time spent in cache-miss `TextPainter` layout — the "shaping" the
  /// replay-bound CAD pages are made of — and [debugTextShapeMiss]/
  /// [debugTextShapeHit] are the run-cache miss/hit counts (unique labels miss,
  /// which is the whole problem). Only written while [PdfPerfLog.enabled]; the
  /// replay caller resets before a replay and reads after. Static because the
  /// device is constructed fresh per replay.
  static int debugTextShapeUs = 0;
  static int debugTextShapeMiss = 0;
  static int debugTextShapeHit = 0;

  /// Zeroes the shaping accumulators before a measured replay.
  static void debugResetTextShape() {
    debugTextShapeUs = 0;
    debugTextShapeMiss = 0;
    debugTextShapeHit = 0;
  }

  /// Ordered fallbacks used for normal substituted text — test hook.
  @visibleForTesting
  static List<String> get debugDefaultFontFallbacks => _defaultFontFallbacks;

  /// Diagnostic kill switches for the command replay benchmark.
  @visibleForTesting
  static bool debugReuseSolidPaints = true;
  @visibleForTesting
  static bool debugDrawSimpleLines = true;

  /// Overprint compositing kill switch (the A/B baseline is "off"). Off,
  /// [setOverprint] still records the state but fills/strokes composite
  /// normally, exactly as before overprint was consumed.
  @visibleForTesting
  static bool debugOverprintCompositing = true;

  BlendMode _blend = BlendMode.srcOver;

  // Most CAD command buffers contain tens of thousands of paths but only a
  // handful of consecutive paint styles. ui.Canvas snapshots a Paint at each
  // draw, so the immutable prepared object can be reused until a style field
  // or effective blend mode changes. Keep just the last value (rather than a
  // map): the command stream is run-grouped, and lookup/allocation overhead on
  // light pages stays constant.
  Paint? _fillPaint;
  PdfColor? _fillColor;
  double _fillAlpha = -1;
  BlendMode? _fillBlend;
  Paint? _strokePaint;
  PdfColor? _strokeColor;
  PdfStroke? _strokeStyle;
  double _strokeAlpha = -1;
  BlendMode? _strokeBlend;

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

  bool _fillOverprint = false;
  bool _strokeOverprint = false;

  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {
    // [mode] (OPM 0/1) only distinguishes which DeviceCMYK components a
    // colorant buffer would write; the RGB `darken` approximation below cannot
    // act on it, so it is intentionally not stored. Empirically (issue #502)
    // no fixed RGB blend that keys off OPM beats darken-always here: gating
    // OPM-0 to a knockout fixes the "over CMYK" patches but reintroduces the
    // fail-marker on the "over spot" patches (a separation colorant must
    // survive the knockout), and vice-versa - the two only diverge in colorant
    // space. See doc/dev-log/2026-07-23-overprint-rgb-ceiling.md.
    _fillOverprint = fill;
    _strokeOverprint = stroke;
  }

  /// Overprint (§8.6.7) is a subtractive colorant operation this RGB canvas
  /// cannot reproduce exactly. While the nonstroking flag (/op) is set, a fill
  /// composites with [BlendMode.darken] (per-channel min): over a coloured
  /// backdrop it preserves the darker colorant channels and clips the lighter
  /// ones - a passable stand-in for "the ink darkens what it covers instead of
  /// knocking it out" - and over white it is a no-op, so pages that set
  /// overprint defensively over the page background are unaffected. An explicit
  /// blend mode (/BM) or a knockout group takes precedence.
  BlendMode get _fillElementBlend {
    if (_knockoutActive) return BlendMode.src;
    if (debugOverprintCompositing &&
        _fillOverprint &&
        _blend == BlendMode.srcOver) {
      return BlendMode.darken;
    }
    return _blend;
  }

  /// Stroking (/OP) counterpart of [_fillElementBlend].
  BlendMode get _strokeElementBlend {
    if (_knockoutActive) return BlendMode.src;
    if (debugOverprintCompositing &&
        _strokeOverprint &&
        _blend == BlendMode.srcOver) {
      return BlendMode.darken;
    }
    return _blend;
  }

  @override
  void drawTiledCell(PdfDrawTiledCellCommand command) {
    // Record the cell once as a sub-picture and stamp it per origin -
    // PDFium's DrawPatternBitmap shape, on Skia's terms. Only when plain
    // srcOver compositing is in effect: an active blend mode, knockout
    // group, or overprint approximation must apply per paint primitive,
    // which drawPicture cannot express - those (rare) states take the exact
    // per-tile expansion instead.
    if (_blend != BlendMode.srcOver ||
        _knockoutActive ||
        _fillOverprint ||
        _strokeOverprint) {
      for (var t = 0; t < command.originsX.length; t++) {
        final dx = command.originsX[t], dy = command.originsY[t];
        replayCommands(command.cellCommands,
            dx == 0 && dy == 0 ? this : TranslatingPdfDevice(this, dx, dy));
      }
      return;
    }
    // The retained transcript replays this same command object every frame
    // (and at every zoom bucket), so the sub-picture is cached against the
    // command's identity: recorded once for its lifetime, GC'd with it.
    // A picture is vector - stamping it is resolution-independent, so one
    // recording serves every scale. (Cells with decoded images resolve them
    // from this device's [images] at record time; the transcript cache
    // replaces image-bearing commands wholesale on re-decode, so the cached
    // picture can never hold a stale image.)
    var picture = _tiledCellPictures[command];
    if (picture == null) {
      final recorder = ui.PictureRecorder();
      final cell = CanvasPdfDevice(Canvas(recorder),
          images: images, pixelRatio: pixelRatio);
      replayCommands(command.cellCommands, cell);
      picture = recorder.endRecording();
      _tiledCellPictures[command] = picture;
    }
    for (var t = 0; t < command.originsX.length; t++) {
      canvas.save();
      canvas.translate(command.originsX[t], command.originsY[t]);
      canvas.drawPicture(picture);
      canvas.restore();
    }
  }

  /// Cell sub-pictures keyed by the tiled command that produced them. An
  /// [Expando] so a picture lives exactly as long as its command does -
  /// transcripts are already budgeted by the retained-record caches, and a
  /// cell picture (a handful of ops) is negligible next to its command list.
  static final Expando<ui.Picture> _tiledCellPictures = Expando();

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
    beginSoftMaskComposite(
        luminosity: luminosity,
        backdrop: backdrop,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset);
    drawMask();
    finishSoftMaskComposite();
  }

  /// First half of [endSoftMasked]'s compositing: opens the dstIn layer the
  /// mask group's content paints into (with the luminance/transfer colour
  /// filter and the /BC backdrop). Split out for callers that must
  /// interleave their own work with the mask draws - the strip device
  /// flushes its batched quads between the mask content and
  /// [finishSoftMaskComposite] - while keeping the exact canvas sequence.
  void beginSoftMaskComposite(
      {required bool luminosity,
      required PdfRect backdrop,
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
  }

  /// Second half of [endSoftMasked]'s compositing: composites the mask into
  /// the captured content (dstIn) and the masked content into the page.
  void finishSoftMaskComposite() {
    canvas.restore(); // composite the mask into the content (dstIn)
    canvas.restore(); // composite the masked content into the page
    _knockout.removeLast();
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    canvas.drawPath(
      _toUiPath(path, rule),
      _solidFillPaint(color, alpha),
    );
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    canvas.drawPath(
      _toUiPath(path, rule),
      Paint()
        ..shader = _shaderFor(gradient)
        ..blendMode = _fillElementBlend
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
        vertices, BlendMode.dst, Paint()..blendMode = _fillElementBlend);
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    final segments = path.segments;
    if (debugDrawSimpleLines &&
        stroke.dashArray.isEmpty &&
        segments.length == 2) {
      switch ((segments[0], segments[1])) {
        case (
            PdfMoveTo(:final x, :final y),
            PdfLineTo(x: final x2, y: final y2)
          ):
          canvas.drawLine(Offset(x, y), Offset(x2, y2),
              _solidStrokePaint(color, stroke, alpha));
          return;
        default:
          break;
      }
    }
    var uiPath = _toUiPath(path, PdfFillRule.nonzero);
    if (stroke.dashArray.any((d) => d > 0)) {
      uiPath = _dashPath(uiPath, stroke.dashArray, stroke.dashPhase);
    }
    canvas.drawPath(
      uiPath,
      _solidStrokePaint(color, stroke, alpha),
    );
  }

  Paint _solidFillPaint(PdfColor color, double alpha) {
    final blend = _fillElementBlend;
    if (!debugReuseSolidPaints) {
      return Paint()
        ..style = PaintingStyle.fill
        ..color = _toColor(color, alpha)
        ..blendMode = blend;
    }
    final cached = _fillPaint;
    if (cached != null &&
        _fillColor == color &&
        _fillAlpha == alpha &&
        _fillBlend == blend) {
      return cached;
    }
    _fillColor = color;
    _fillAlpha = alpha;
    _fillBlend = blend;
    return _fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _toColor(color, alpha)
      ..blendMode = blend;
  }

  Paint _solidStrokePaint(PdfColor color, PdfStroke stroke, double alpha) {
    final blend = _strokeElementBlend;
    if (!debugReuseSolidPaints) {
      return Paint()
        ..style = PaintingStyle.stroke
        ..color = _toColor(color, alpha)
        ..strokeWidth = strokeWidthFor(stroke.width)
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
        ..blendMode = blend;
    }
    final cached = _strokePaint;
    final style = _strokeStyle;
    if (cached != null &&
        _strokeColor == color &&
        style != null &&
        style.width == stroke.width &&
        style.cap == stroke.cap &&
        style.join == stroke.join &&
        style.miterLimit == stroke.miterLimit &&
        _strokeAlpha == alpha &&
        _strokeBlend == blend) {
      return cached;
    }
    _strokeColor = color;
    _strokeStyle = stroke;
    _strokeAlpha = alpha;
    _strokeBlend = blend;
    return _strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = _toColor(color, alpha)
      ..strokeWidth = strokeWidthFor(stroke.width)
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
      ..blendMode = blend;
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
    // Shaping the run is the single largest cost in the paint pass and the
    // same (text, font, colour) recur heavily within and across pages — reuse
    // a cached laid-out painter (immutable, repaints at any transform) and its
    // metrics. The plain painter doubles as the fill painter in the common
    // no-gradient case, exactly as the un-cached path did.
    //
    // Per-glyph composition (#454) applies only to plain fills of simple-script
    // runs; a gradient, a stroke, or complex text keeps whole-run shaping so the
    // fresh gradient/stroke painters and the layout stay width-consistent.
    final compose = perGlyphSubstitutedText &&
        run.gradient == null &&
        run.strokeColor == null &&
        _composableRun(run.text);
    final layout = _measureLayout(run, compose: compose);

    canvas.save();
    canvas.transform(_toFloat64(run.transform));
    // unflip: the page transform is y-up, text rasterizes y-down
    final targetWidth = run.width * renderSize;
    final scaleX = run.width > 0 && layout.width > 0
        ? targetWidth / layout.width
        : 1.0;

    // Fill (modes 0/2/4/6). A plain fill paints the cached/composed layout
    // (colour baked in); a gradient fill needs a fresh painter carrying the
    // shader, which can't be cached because the shader depends on this run's
    // own transform. The cached/composed layout serves every plain fill.
    TextPainter? gradientFill;
    if (run.fill) {
      final gradient = run.gradient;
      if (gradient != null) {
        final localToPage =
            PdfMatrix.scaled(scaleX / renderSize, -1 / renderSize)
                .concat(run.transform);
        final pageToLocal = localToPage.inverted();
        if (pageToLocal != null) {
          gradientFill = TextPainter(
            text: TextSpan(
                text: run.text,
                style: _styleFor(
                    run,
                    foreground: Paint()
                      ..shader = _shaderFor(gradient,
                          transform: gradient.transform.concat(pageToLocal))
                      ..blendMode = _elementBlend)),
            textDirection: TextDirection.ltr,
          )..layout();
        }
      }
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
    if (run.fill) {
      if (gradientFill != null) {
        gradientFill.paint(canvas, Offset(0, -layout.baseline));
      } else {
        layout.paint(canvas, Offset(0, -layout.baseline));
      }
    }
    strokePainter?.paint(canvas, Offset(0, -layout.baseline));
    canvas.restore();
  }

  /// A laid-out painter (+ width/baseline) for a substituted-font run, served
  /// from the process-wide cache. The key is (text, font, colour) — everything
  /// [_styleFor] reads — so the cached painter and its metrics are exact.
  _TextLayout _measureLayout(PdfTextRun run, {required bool compose}) {
    // Composed runs are transient (built per paint from the glyph cache), so
    // they skip the run cache and its miss/hit instrumentation entirely.
    if (compose) return _composeLayout(run);
    final c = run.color;
    final key = '${run.text} ${run.fontName ?? ''} '
        '${c.red},${c.green},${c.blue}';
    if (!PdfPerfLog.enabled) {
      return _textCache.getOrAdd(key, () => _shapeLayout(run));
    }
    // Instrumented path (#454): the factory runs only on a miss, so timing it
    // isolates the shaping cost, and the flag separates miss from hit.
    var missed = false;
    final layout = _textCache.getOrAdd(key, () {
      missed = true;
      final clock = Stopwatch()..start();
      final l = _shapeLayout(run);
      debugTextShapeUs += clock.elapsedMicroseconds;
      return l;
    });
    if (missed) {
      debugTextShapeMiss++;
    } else {
      debugTextShapeHit++;
    }
    return layout;
  }

  _TextLayout _shapeLayout(PdfTextRun run) {
    final painter = TextPainter(
      text: TextSpan(text: run.text, style: _styleFor(run, foreground: null)),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    return _TextLayout(painter, painter.width, baseline);
  }

  /// Builds a run layout by placing per-character layouts (each shaped once and
  /// cached in [_glyphCache]) at their cumulative natural advances. The total
  /// natural width still feeds the same `scaleX` that stretches the run to the
  /// PDF's own advance, so the run's overall placement is unchanged; only the
  /// intra-run distribution differs (no cross-character kerning) - which is why
  /// [_composableRun] gates it to text where that difference is nil-to-tiny.
  _TextLayout _composeLayout(PdfTextRun run) {
    final parts = <_GlyphRun>[];
    var dx = 0.0;
    double? baseline;
    for (final rune in run.text.runes) {
      final glyph = _glyphLayout(rune, run);
      parts.add(_GlyphRun(glyph, dx));
      dx += glyph.width;
      baseline ??= glyph.baseline;
    }
    return _TextLayout.composed(parts, dx, baseline ?? 0);
  }

  /// A single character's cached layout, keyed like the run cache but per rune.
  _TextLayout _glyphLayout(int rune, PdfTextRun run) {
    final c = run.color;
    final key = '$rune ${run.fontName ?? ''} ${c.red},${c.green},${c.blue}';
    return _glyphCache.getOrAdd(key, () {
      final painter = TextPainter(
        text: TextSpan(
            text: String.fromCharCode(rune),
            style: _styleFor(run, foreground: null)),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline =
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      return _TextLayout(painter, painter.width, baseline);
    });
  }

  /// Whether [text] can be composed from independent per-character layouts
  /// without visibly changing the result. Composition drops cross-character
  /// kerning, so the run must contain no kernable adjacency: every character is
  /// an ASCII digit, uppercase letter, space, or common technical punctuation
  /// (no lowercase - those ligate), AND a letter only ever neighbours a digit or
  /// a space, never another letter or punctuation. That is exactly the shape of
  /// coordinate/survey/part labels ("N1234.567 E7654.321", "PLATE 12/48"), where
  /// tabular digits and isolated letters do not kern - a real-Chrome probe put
  /// the whole-run-vs-composed pixel diff at 0% for such runs and 20-56% for
  /// kerning-pair uppercase words (PAY, AVENUE, WATER), which this gate excludes.
  static bool _composableRun(String text) {
    if (text.isEmpty) return false;
    final u = text.codeUnits;
    for (var i = 0; i < u.length; i++) {
      final cu = u[i];
      if (!_composableChar(cu)) return false;
      // A letter may only sit next to a digit or a space; a letter beside
      // another letter or beside punctuation is a kerning pair in the
      // substitute fonts, so the whole run falls back to whole-run shaping.
      if (i > 0) {
        final prev = u[i - 1];
        final curLetter = _isAsciiUpper(cu);
        final prevLetter = _isAsciiUpper(prev);
        if (curLetter && !(_isAsciiDigit(prev) || prev == 0x20)) return false;
        if (prevLetter && !(_isAsciiDigit(cu) || cu == 0x20)) return false;
      }
    }
    return true;
  }

  static bool _isAsciiUpper(int cu) => cu >= 0x41 && cu <= 0x5A;
  static bool _isAsciiDigit(int cu) => cu >= 0x30 && cu <= 0x39;
  static bool _composableChar(int cu) =>
      _isAsciiDigit(cu) ||
      _isAsciiUpper(cu) ||
      cu == 0x20 || // space
      _composablePunct.contains(cu);

  // . , - + / : = ( ) % # * _
  static const _composablePunct = <int>{
    0x2E, 0x2C, 0x2D, 0x2B, 0x2F, 0x3A, 0x3D, 0x28, 0x29, 0x25, 0x23, 0x2A, 0x5F,
  };

  /// The em-space [ui.Path] for a glyph outline, built once per outline
  /// instance and memoized by identity. Glyph outlines fill nonzero.
  static ui.Path _glyphUiPath(PdfPath outline) =>
      _glyphPaths[outline] ??= _toUiPath(outline, PdfFillRule.nonzero);

  /// Draws real glyph outlines from the embedded font. The run transform
  /// maps em space (y-up) to page space, so no unflip is needed.
  void _drawGlyphOutlines(PdfTextRun run) {
    final path = ui.Path();
    for (final glyph in run.glyphs!) {
      final outline = glyph.outline;
      if (outline == null) continue;
      // The em-space ui.Path of a glyph is identical at every occurrence —
      // the font engine hands back the same outline instance per glyph — so
      // build it once and only re-transform it into place (a fast native op),
      // skipping the per-glyph rebuild from PdfPath segments. The cache is keyed
      // by outline identity and GC-tied to the font's own outline lifetime.
      path.addPath(
        _glyphUiPath(outline).transform(
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
    // Shipped in the optional dart_pdf_editor_assets package (registered by
    // registerBundledEditorAssets), so Arabic (including presentation forms
    // copied from shaped PDFs), Hebrew, Greek and Cyrillic render consistently
    // even when the host's Helvetica substitute has no suitable fallback. When
    // that package isn't present this family simply isn't registered and the
    // later candidates apply.
    'packages/dart_pdf_editor_assets/DejaVu Sans',
    // The unprefixed family is used when this package itself is the Flutter
    // application under test, and by hosts that register DejaVu system-wide.
    'DejaVu Sans',
    // Platform Arabic faces. These also cover the Arabic Presentation Forms
    // commonly exposed by PDFs that store already-shaped text.
    'Geeza Pro',
    '.SF Arabic',
    'Noto Naskh Arabic',
    'Noto Sans Arabic',
    'Segoe UI',
    'Arial Unicode MS',
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

/// A laid-out substituted-text painter plus the metrics the renderer needs.
/// The painter's paragraph is immutable after layout and repaints at any
/// canvas transform, so one entry serves every occurrence of the run; width
/// and baseline are constant for a given (text, font, colour) so the per-run
/// horizontal squeeze (scaleX) and baseline offset are recomputed cheaply.
class _TextLayout {
  /// A whole-run layout: one [TextPainter] the cache owns and disposes.
  _TextLayout(TextPainter this.painter, this.width, this.baseline)
      : parts = null;

  /// A run composed from per-character layouts (#454). [parts] reference
  /// glyph-cache layouts this layout does NOT own (the glyph cache disposes
  /// them); a composed layout is transient - built per paint, never cached -
  /// so the referenced glyphs cannot be evicted under it on the single thread.
  _TextLayout.composed(List<_GlyphRun> this.parts, this.width, this.baseline)
      : painter = null;

  final TextPainter? painter;
  final List<_GlyphRun>? parts;
  final double width;
  final double baseline;

  /// Paints the run at [offset] in the painter's 100px-per-em space.
  void paint(Canvas canvas, Offset offset) {
    final p = painter;
    if (p != null) {
      p.paint(canvas, offset);
      return;
    }
    for (final g in parts!) {
      g.glyph.painter!.paint(canvas, offset.translate(g.dx, 0));
    }
  }

  /// Disposes the owned painter; a composed layout owns none (its glyphs
  /// belong to the glyph cache).
  void dispose() => painter?.dispose();
}

/// One character's layout within a composed run: the shared glyph-cache
/// layout and its x-offset (natural, un-scaled 100px-per-em space).
class _GlyphRun {
  const _GlyphRun(this.glyph, this.dx);
  final _TextLayout glyph;
  final double dx;
}

