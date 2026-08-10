import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'budgeted_cache.dart';
import 'image_decoder.dart';
import 'perf_log.dart';

const _redToAlpha = <double>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
];

/// Paints interpreter callbacks onto a Flutter [Canvas].
///
/// Expects the canvas to be set up in page space (PDF user space, y-up); the
/// renderer applies the global y-flip. Text is drawn with substituted system
/// fonts, horizontally scaled to the PDF's own metrics, until the font
/// engine produces real glyph outlines. Images must be pre-decoded into
/// [images] (painting is synchronous).
class CanvasPdfDevice implements PdfDevice, PdfTiledCellSink {
  CanvasPdfDevice(this.canvas, {this.images = const {}, this.pixelRatio = 1});

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

  /// Place substituted glyphs at the PDF's own per-character pen offsets
  /// ([PdfTextRun.charOffsets]) instead of letting the substitute distribute
  /// them (#649).
  ///
  /// The uniform horizontal scale that makes a substituted run's total advance
  /// match the PDF pins the run's two endpoints and nothing in between, so
  /// interior glyphs land wherever the substitute's own advances put them -
  /// measured at up to 4.4pt of drift on a 77-character 12pt Helvetica line,
  /// zero at both ends and worst mid-run. Everything geometric (selection
  /// bands, search highlights, markup placed over a selection, content-element
  /// hit boxes) derives from the PDF's advances, so all of it reads as offset
  /// against the drawn glyphs by that much.
  ///
  /// Placing each character at its own offset makes the interior correct by
  /// construction. It drops the substitute's cross-character kerning, which is
  /// the point: a PDF expresses its kerning as TJ adjustments, those are
  /// already in the offsets, and the substitute's own kerning is error.
  static bool exactSubstitutedGlyphPlacement = true;

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
  static int debugTextPainterBuilds = 0;

  /// Zeroes the shaping accumulators before a measured replay.
  static void debugResetTextShape() {
    debugTextShapeUs = 0;
    debugTextShapeMiss = 0;
    debugTextShapeHit = 0;
    debugTextPainterBuilds = 0;
  }

  /// Ordered fallbacks used for normal substituted text — test hook.
  @visibleForTesting
  static List<String> get debugDefaultFontFallbacks => _defaultFontFallbacks;

  /// Diagnostic kill switches for the command replay benchmark.
  @visibleForTesting
  static bool debugReuseSolidPaints = true;
  @visibleForTesting
  static bool debugDrawSimpleLines = true;

  /// Overprint fallback-compositing kill switch (the A/B baseline is "off").
  /// Off, [setOverprint] still records the state but fills/strokes composite
  /// normally, exactly as before overprint was consumed.
  ///
  /// This governs only the RGB stand-in below. Faithful overprint is resolved
  /// upstream in the interpreter's colorant buffer (issue #502), which hands
  /// this device an already-composited colour with the overprint flag cleared;
  /// `PdfInterpreter.debugResolveOverprint` is that path's switch.
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
    // [mode] (OPM 0/1) only distinguishes which DeviceCMYK components are
    // written, which is a colorant-space question: it is acted on by
    // PdfOverprintCompositor upstream and cannot be acted on here, so it is
    // intentionally not stored. Empirically (issue #502) no fixed RGB blend
    // that keys off OPM beats darken-always in this device: gating OPM-0 to a
    // knockout fixes the "over CMYK" patches but reintroduces the fail-marker
    // on the "over spot" patches (a separation colorant must survive the
    // knockout), and vice-versa. See
    // doc/dev-log/2026-07-23-overprint-rgb-ceiling.md.
    _fillOverprint = fill;
    _strokeOverprint = stroke;
  }

  /// Overprint (§8.6.7) is a subtractive colorant operation this RGB canvas
  /// cannot reproduce exactly, so it is normally resolved before reaching here:
  /// the interpreter's colorant buffer composites the draw in ink space and
  /// delivers the resulting colour with the flag cleared (issue #502).
  ///
  /// The flag only survives to this device when the buffer declined - the
  /// backdrop was an image, a gradient, a transparency group, or a colour space
  /// with no colorant reading. Then the historical stand-in applies: the fill
  /// composites with [BlendMode.darken] (per-channel min), which over a
  /// coloured backdrop preserves the darker colorant channels and clips the
  /// lighter ones, and over white is a no-op, so pages that set overprint
  /// defensively over the page background are unaffected. An explicit blend
  /// mode (/BM) or a knockout group takes precedence.
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
    var picture = _tiledCellPictures[command.cellCommands];
    if (picture == null) {
      final recorder = ui.PictureRecorder();
      final cell = CanvasPdfDevice(Canvas(recorder),
          images: images, pixelRatio: pixelRatio);
      replayCommands(command.cellCommands, cell);
      picture = recorder.endRecording();
      _tiledCellPictures[command.cellCommands] = picture;
    }
    for (var t = 0; t < command.originsX.length; t++) {
      canvas.save();
      canvas.translate(command.originsX[t], command.originsY[t]);
      canvas.drawPicture(picture);
      canvas.restore();
    }
  }

  /// Cell sub-pictures keyed by the *cell command list* (not the command):
  /// Type3 glyph stamping (#535) emits one single-origin command per glyph
  /// occurrence, all sharing one recorded cell - keying by the list gives
  /// every occurrence the same picture. An [Expando] so a picture lives
  /// exactly as long as the transcript retaining the list does - transcripts
  /// are already budgeted by the retained-record caches, and a cell picture
  /// (a handful of ops) is negligible next to its command list.
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
    // Edge whitespace (a leading/trailing space carrying a large Tw to reach a
    // table column) must open a real gap, not stretch the visible glyphs.
    // TextPainter drops leading/trailing whitespace from both placement and
    // layout.width, so paint a run trimmed to its visible core and shift it
    // right by the leading-whitespace advance; the original run's
    // width/transform stay full so extraction still sees the true gap. The
    // common no-edge-whitespace run is used as-is.
    final paintRun = run.leadingSpace != 0 || run.visibleWidth != null
        ? _trimmedForPaint(run)
        : run;

    // A gradient or a stroke paints through its own whole-run painter below,
    // which no per-character layout can stand in for - those keep whole-run
    // shaping so painter and layout stay width-consistent.
    final wholeRunPaint =
        paintRun.gradient != null || paintRun.strokeColor != null;
    // The PDF's own per-character pen offsets, when this run carries them and
    // its script lays one glyph out per character (#649). Preferred over both
    // the composed and the whole-run path: it is the only one whose interior
    // matches the geometry selection and search are computed from.
    final placements = exactSubstitutedGlyphPlacement && !wholeRunPaint
        ? _placeableOffsets(paintRun)
        : null;
    final compose = placements == null &&
        perGlyphSubstitutedText &&
        !wholeRunPaint &&
        paintRun.letterSpacing == 0 &&
        paintRun.wordSpacing == 0 &&
        _composableRun(paintRun.text);
    final layout = placements != null
        ? _placedLayout(paintRun, placements)
        : _measureLayout(paintRun, compose: compose);

    canvas.save();
    canvas.transform(_toFloat64(run.transform));
    // unflip: the page transform is y-up, text rasterizes y-down.
    if (run.leadingSpace != 0) canvas.translate(run.leadingSpace, 0);
    final targetWidth = paintRun.width * renderSize;
    final scaleX = paintRun.width > 0 && layout.width > 0
        ? targetWidth / layout.width
        : 1.0;

    // Fill (modes 0/2/4/6). A plain fill paints the cached/composed layout
    // (colour baked in); a gradient fill needs a fresh painter carrying the
    // shader, which can't be cached because the shader depends on this run's
    // own transform. The cached/composed layout serves every plain fill.
    TextPainter? gradientFill;
    if (paintRun.fill) {
      final gradient = paintRun.gradient;
      if (gradient != null) {
        final localToPage =
            PdfMatrix.scaled(scaleX / renderSize, -1 / renderSize)
                .concat(run.transform);
        final pageToLocal = localToPage.inverted();
        if (pageToLocal != null) {
          gradientFill = TextPainter(
            text: TextSpan(
                text: paintRun.text,
                style: _styleFor(paintRun,
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
    if (paintRun.strokeColor != null) {
      final ts = run.transform.scaleFactor;
      final w =
          paintRun.strokeWidth > 0 ? paintRun.strokeWidth : ts / renderSize;
      strokePainter = TextPainter(
        text: TextSpan(
          text: paintRun.text,
          style: _styleFor(
            paintRun,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = ts > 0 ? w * renderSize / ts : w
              ..color = _toColor(paintRun.strokeColor!, 1)
              ..blendMode = _elementBlend,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    canvas.scale(scaleX / renderSize, -1 / renderSize);
    if (paintRun.fill) {
      if (gradientFill != null) {
        gradientFill.paint(canvas, Offset(0, -layout.baseline));
      } else {
        layout.paint(canvas, Offset(0, -layout.baseline));
      }
    }
    strokePainter?.paint(canvas, Offset(0, -layout.baseline));
    canvas.restore();
  }

  /// A copy of [run] trimmed to its visible core for painting: edge whitespace
  /// removed from the text, and the width reduced to the visible-glyph advance
  /// (`visibleWidth - leadingSpace`). [leadingSpace] itself is applied by the
  /// caller as a canvas translation, so it is zeroed here. Everything else -
  /// transform, colour, spacing, stroke, gradient - is carried through unchanged.
  static PdfTextRun _trimmedForPaint(PdfTextRun run) {
    final text = run.text;
    var start = 0;
    var end = text.length;
    while (start < end && _isTrimWhitespace(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isTrimWhitespace(text.codeUnitAt(end - 1))) {
      end--;
    }
    final core = text.substring(start, end);
    final coreWidth = (run.visibleWidth ?? run.width) - run.leadingSpace;
    // Rebase the per-character offsets onto the trimmed text. They are rebased
    // by the caller's own translation ([leadingSpace]), not by `offsets[start]`,
    // so a disagreement between this trim and the interpreter's per-glyph
    // visibility test shifts nothing: every character keeps its absolute
    // position on the page.
    final offsets = run.charOffsets;
    final coreOffsets = offsets != null && offsets.length == text.length + 1
        ? [for (var i = start; i <= end; i++) offsets[i] - run.leadingSpace]
        : null;
    return PdfTextRun(
      text: core,
      charOffsets: coreOffsets,
      transform: run.transform,
      color: run.color,
      width: coreWidth,
      gradient: run.gradient,
      fontName: run.fontName,
      fontSize: run.fontSize,
      fill: run.fill,
      strokeColor: run.strokeColor,
      strokeWidth: run.strokeWidth,
      letterSpacing: run.letterSpacing,
      wordSpacing: run.wordSpacing,
      mcid: run.mcid,
    );
  }

  /// The code units [String.trim] strips - the interpreter's
  /// `text.trim().isNotEmpty` visibility test, which produced leadingSpace /
  /// visibleWidth, uses the same set. Tested by index rather than by trimming a
  /// substring so the character offsets can be sliced to match.
  static bool _isTrimWhitespace(int cu) =>
      (cu >= 0x09 && cu <= 0x0D) ||
      cu == 0x20 ||
      cu == 0x85 ||
      cu == 0xA0 ||
      cu == 0x1680 ||
      (cu >= 0x2000 && cu <= 0x200A) ||
      cu == 0x2028 ||
      cu == 0x2029 ||
      cu == 0x202F ||
      cu == 0x205F ||
      cu == 0x3000 ||
      cu == 0xFEFF;

  /// A laid-out painter (+ width/baseline) for a substituted-font run, served
  /// from the process-wide cache. The key is (text, font, colour) — everything
  /// [_styleFor] reads — so the cached painter and its metrics are exact.
  _TextLayout _measureLayout(PdfTextRun run, {required bool compose}) {
    // Composed runs are transient (built per paint from the glyph cache), so
    // they skip the run cache and its miss/hit instrumentation entirely.
    if (compose) return _composeLayout(run);
    final c = run.color;
    final key = '${run.text} ${run.fontName ?? ''} '
        '${c.red},${c.green},${c.blue} '
        '${run.letterSpacing},${run.wordSpacing}';
    return _cachedLayout(key, () => _shapeLayout(run));
  }

  /// The run-cache lookup, with the shaping instrumentation (#454) wrapped
  /// around it: [build] runs only on a miss, so timing it isolates the shaping
  /// cost and the flag separates miss from hit.
  _TextLayout _cachedLayout(String key, _TextLayout Function() build) {
    if (!PdfPerfLog.enabled) return _textCache.getOrAdd(key, build);
    var missed = false;
    final layout = _textCache.getOrAdd(key, () {
      missed = true;
      final clock = Stopwatch()..start();
      final l = build();
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
    debugTextPainterBuilds++;
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
  /// Laid out without the run's Tc/Tw: a per-character layout is positioned by
  /// its caller, which knows the real advances, so baking spacing into the
  /// glyph would double-count it - and it would make the key a lie.
  _TextLayout _glyphLayout(int rune, PdfTextRun run) {
    final c = run.color;
    final key = '$rune ${run.fontName ?? ''} ${c.red},${c.green},${c.blue}';
    return _glyphCache.getOrAdd(key, () {
      debugTextPainterBuilds++;
      final painter = TextPainter(
        text: TextSpan(
            text: String.fromCharCode(rune),
            style: _styleFor(run, foreground: null, applySpacing: false)),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline =
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      return _TextLayout(painter, painter.width, baseline);
    });
  }

  /// The per-character pen offsets to paint [run] at, or null when this run
  /// must keep whole-run (or naturally composed) placement (#649).
  ///
  /// Requires a table of the right shape, a positive advance to scale against,
  /// and a script that lays one glyph out per character - see [_placeableRun].
  static List<double>? _placeableOffsets(PdfTextRun run) {
    final offsets = run.charOffsets;
    if (offsets == null || run.text.isEmpty || run.width <= 0) return null;
    if (offsets.length != run.text.length + 1) return null;
    return _placeableRun(run.text) ? offsets : null;
  }

  /// How far, in em, a word's own shaped advance may differ from the PDF's
  /// before [_buildPlacedLayout] stops shaping it whole and places its
  /// characters individually. 0.02 em is 0.24pt at 12pt - an order of
  /// magnitude under the drift this fixes, and small enough that the
  /// difference is invisible where it is tolerated.
  static const double _placementToleranceEm = 0.02;

  /// A run laid out at the PDF's own pen offsets (#649) instead of at the
  /// substitute's cumulative advances, served from the run cache. The key
  /// carries the offsets as well as everything [_styleFor] reads, because the
  /// same text under different advances is a different layout.
  _TextLayout _placedLayout(PdfTextRun run, List<double> offsets) {
    final c = run.color;
    final key = '${run.text} ${run.fontName ?? ''} '
        '${c.red},${c.green},${c.blue} p${_offsetsHash(offsets)}';
    // A run with nothing to scale against falls back to whole-run shaping,
    // cached under this key too so the failed attempt is not repeated.
    return _cachedLayout(
        key, () => _buildPlacedLayout(run, offsets) ?? _shapeLayout(run));
  }

  /// Builds the layout [_placedLayout] caches: one part per **word** - a
  /// maximal span of non-whitespace characters - drawn at that word's own
  /// offset, so a word can never drift from the geometry selection and search
  /// are computed from. A word whose shaped advance disagrees with the PDF's
  /// by more than [_placementToleranceEm] is broken down further and placed
  /// character by character, which is what a run of prose against a mismatched
  /// substitute needs. Whitespace lays no ink down and is positioned by the
  /// offsets around it, so it gets no part at all.
  ///
  /// Words rather than characters throughout because the draw call is the
  /// cost: a `drawParagraph` per character measured 3.7x the record pass and
  /// 1.6x the full DPR-2 raster on a page of non-embedded prose. Shaping a
  /// word whole also keeps its internal kerning, which the PDF's own advances
  /// do not contradict at this tolerance.
  ///
  /// The glyph *shapes* take one uniform horizontal scale, so their proportions
  /// stay even (scaling each word to its own advance would squeeze an `i` far
  /// harder than an `o`); only the origins become exact. That scale is
  /// `Σ natural ÷ Σ PDF advance` over the ink-bearing characters alone, so
  /// neither the substitute's idea of a space (Skia's width for a lone
  /// whitespace layout is not something to build on) nor the run's Tc/Tw
  /// (already inside [offsets]) can skew it.
  ///
  /// The caller derives `scaleX = run.width × renderSize ÷ layout.width` and
  /// paints under `scaleX / renderSize`, so reporting `run.width × k` for a
  /// layout laid out at `k` units per em recovers `renderSize ÷ k` whatever the
  /// run's total advance is - and every part lands on exactly its own offset.
  ///
  /// Null when there is nothing measurable to scale against.
  _TextLayout? _buildPlacedLayout(PdfTextRun run, List<double> offsets) {
    final text = run.text;
    var natural = 0.0; // Σ natural width of the ink-bearing glyphs
    var advance = 0.0; // Σ PDF advance of the same glyphs
    for (var i = 0; i < text.length;) {
      final step = _runeLengthAt(text, i);
      if (!_isTrimWhitespace(text.codeUnitAt(i))) {
        natural += _glyphLayout(_runeAt(text, i), run).width;
        advance += offsets[i + step] - offsets[i];
      }
      i += step;
    }
    if (natural <= 0 || advance <= 0) return null;

    final k = natural / advance; // layout units per em
    final style = _styleFor(run, foreground: null, applySpacing: false);
    final parts = <_GlyphRun>[];
    double? baseline;
    var i = 0;
    while (i < text.length) {
      if (_isTrimWhitespace(text.codeUnitAt(i))) {
        i++;
        continue;
      }
      var end = i;
      while (end < text.length && !_isTrimWhitespace(text.codeUnitAt(end))) {
        end += _runeLengthAt(text, end);
      }
      if (_wordHolds(run, offsets, i, end, k)) {
        final word = _shapeString(text.substring(i, end), style);
        baseline ??= word.baseline;
        parts.add(_GlyphRun(word, offsets[i] * k));
      } else {
        for (var j = i; j < end;) {
          final step = _runeLengthAt(text, j);
          // The natural-width pass above has already populated this exact
          // glyph/style in the shared cache. Retain that painter for the
          // placed run instead of shaping a fresh paragraph for every
          // character of every unique CAD label. The retained reference keeps
          // it alive if the glyph-cache LRU later evicts its own ownership;
          // disposing this placed layout releases the borrowed reference.
          final glyph = _glyphLayout(_runeAt(text, j), run).retain();
          baseline ??= glyph.baseline;
          parts.add(_GlyphRun(glyph, offsets[j] * k));
          j += step;
        }
      }
      i = end;
    }
    if (parts.isEmpty) return null;
    return _TextLayout.composed(parts, run.width * k, baseline ?? 0,
        ownsParts: true);
  }

  /// Whether the word `[start, end)` of [run] can be shaped whole without any
  /// of its characters landing more than [_placementToleranceEm] from the
  /// offset the PDF gives it.
  ///
  /// Checked at *every* character boundary, not just the word's end: matching
  /// only a total is the very defect this replaces, and a two-character word
  /// can have an exact total with a badly placed interior. The substitute's own
  /// per-character advances stand in for where the shaped word would put each
  /// character, so cross-character kerning is unaccounted for - a fraction of
  /// the tolerance, and it only ever moves a word from whole-shaped to
  /// per-character placement, which is the safe direction.
  bool _wordHolds(
      PdfTextRun run, List<double> offsets, int start, int end, double k) {
    final tolerance = _placementToleranceEm;
    var natural = 0.0; // em, from the substitute's own advances
    for (var i = start; i < end;) {
      final step = _runeLengthAt(run.text, i);
      if ((natural - (offsets[i] - offsets[start])).abs() > tolerance) {
        return false;
      }
      natural += _glyphLayout(_runeAt(run.text, i), run).width / k;
      i += step;
    }
    return (natural - (offsets[end] - offsets[start])).abs() <= tolerance;
  }

  /// One laid-out [TextPainter] for [text] in [style], owned by the caller.
  _TextLayout _shapeString(String text, TextStyle style) {
    debugTextPainterBuilds++;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return _TextLayout(painter, painter.width,
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic));
  }

  /// Order-sensitive hash of a run's character offsets, for the layout key.
  static int _offsetsHash(List<double> offsets) {
    var h = 0x811c9dc5;
    for (final offset in offsets) {
      h = ((h ^ offset.hashCode) * 0x01000193) & 0x3FFFFFFF;
    }
    return h;
  }

  /// 2 when [i] starts a surrogate pair in [s], 1 otherwise.
  static int _runeLengthAt(String s, int i) {
    final cu = s.codeUnitAt(i);
    if (cu < 0xD800 || cu > 0xDBFF || i + 1 >= s.length) return 1;
    final low = s.codeUnitAt(i + 1);
    return low >= 0xDC00 && low <= 0xDFFF ? 2 : 1;
  }

  /// The code point starting at [i] in [s].
  static int _runeAt(String s, int i) => _runeLengthAt(s, i) == 2
      ? 0x10000 +
          ((s.codeUnitAt(i) - 0xD800) << 10) +
          (s.codeUnitAt(i + 1) - 0xDC00)
      : s.codeUnitAt(i);

  /// Whether [text] can be painted one character at a time at positions the
  /// caller dictates.
  ///
  /// Unlike [_composableRun] this does not care about kerning - the PDF's
  /// offsets replace it - only that the script needs no shaping: one glyph per
  /// character, in logical order, with no combining marks, joining behaviour,
  /// reordering, or format characters. So it admits Latin, Greek, Cyrillic,
  /// the common symbol blocks and CJK/kana/Hangul-syllable text (ordinary
  /// prose, which [_composableRun] excludes outright), and rejects Arabic,
  /// Hebrew, Indic, South-East Asian, Hangul jamo, combining sequences and
  /// anything astral, all of which keep whole-run shaping.
  static bool _placeableRun(String text) {
    for (var i = 0; i < text.length; i++) {
      if (!_placeableChar(text.codeUnitAt(i))) return false;
    }
    return true;
  }

  static bool _placeableChar(int cu) =>
      // ASCII printable, Latin-1 Supplement, Latin Extended-A/B, IPA and the
      // spacing modifier letters (0x2B0-0x2FF); 0x300+ is combining marks.
      (cu >= 0x20 && cu <= 0x2FF && cu != 0x7F) ||
      // Greek and Coptic; Cyrillic either side of its combining block
      // (0x483-0x489).
      (cu >= 0x370 && cu <= 0x482) ||
      (cu >= 0x48A && cu <= 0x52F) ||
      // General punctuation, minus the format and bidi controls at 0x200B-
      // 0x200F / 0x202A-0x202E / 0x2060+, and minus the combining marks at
      // 0x20D0+.
      (cu >= 0x2010 && cu <= 0x2027) ||
      (cu >= 0x2030 && cu <= 0x205E) ||
      (cu >= 0x20A0 && cu <= 0x20BF) ||
      // Letterlike, number forms, arrows, maths, technical, enclosed
      // alphanumerics, box drawing, geometric shapes and dingbats.
      (cu >= 0x2100 && cu <= 0x23FF) ||
      (cu >= 0x2460 && cu <= 0x27BF) ||
      // CJK punctuation and kana, minus the combining voiced marks
      // (0x3099/0x309A); ideographs; Hangul syllables (precomposed - jamo at
      // 0x1100 compose and are excluded); CJK compatibility; halfwidth and
      // fullwidth forms.
      (cu >= 0x3000 && cu <= 0x3098) ||
      (cu >= 0x309B && cu <= 0x30FF) ||
      (cu >= 0x3400 && cu <= 0x4DBF) ||
      (cu >= 0x4E00 && cu <= 0x9FFF) ||
      (cu >= 0xAC00 && cu <= 0xD7A3) ||
      (cu >= 0xF900 && cu <= 0xFAFF) ||
      (cu >= 0xFF01 && cu <= 0xFFEE);

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
    0x2E,
    0x2C,
    0x2D,
    0x2B,
    0x2F,
    0x3A,
    0x3D,
    0x28,
    0x29,
    0x25,
    0x23,
    0x2A,
    0x5F,
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
    final softMask = pdfGpuSoftMaskOf(image);
    // antialiased edges leave hairline seams between abutting image slices
    // (PowerPoint and scanners split large images into strips)
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = false
      ..blendMode = softMask == null ? _elementBlend : BlendMode.srcOver;
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
    if (softMask != null) {
      // Isolate the base + mask so the PDF blend mode applies to the finished
      // composite, not to the base against a transparent temporary surface.
      // The mask JPEG is grayscale, so its red sample is the specified alpha.
      canvas.saveLayer(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..blendMode = _elementBlend,
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, 1, 1),
      paint,
    );
    if (softMask != null) {
      canvas.drawImageRect(
        softMask,
        Rect.fromLTWH(
          0,
          0,
          softMask.width.toDouble(),
          softMask.height.toDouble(),
        ),
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..isAntiAlias = false
          ..blendMode = BlendMode.dstIn
          ..colorFilter = const ColorFilter.matrix(_redToAlpha),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  TextStyle _styleFor(PdfTextRun run,
      {Paint? foreground, bool applySpacing = true}) {
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
      // Reproduce the PDF's Tc/Tw as real tracking/word spacing (em → the 100px
      // render em) so the substitute's own advances match run.width. Without
      // this the layout is tight and run.width's spacing is recovered by
      // stretching the glyph shapes - which explodes when a space carries a
      // large Tw (issue: over-wide table digits). letterSpacing/wordSpacing 0
      // (the common case) is a no-op, so unspaced runs are unchanged. A
      // per-character layout opts out: its caller places it from the PDF's own
      // offsets, which already carry Tc/Tw.
      letterSpacing: applySpacing ? run.letterSpacing * 100 : 0,
      wordSpacing: applySpacing ? run.wordSpacing * 100 : 0,
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
      : parts = null,
        ownsParts = false;

  /// A run built from several sub-layouts.
  ///
  /// With [ownsParts] false (#454's per-character composition) the parts are
  /// glyph-cache layouts this one does NOT own; such a layout is transient -
  /// built per paint, never cached - so the referenced glyphs cannot be
  /// evicted under it on the single thread. With [ownsParts] true (#649's
  /// word placement) the parts were shaped for this layout alone, which is
  /// what lets it be cached: nothing else can dispose them out from under it.
  _TextLayout.composed(List<_GlyphRun> this.parts, this.width, this.baseline,
      {this.ownsParts = false})
      : painter = null;

  final TextPainter? painter;
  final List<_GlyphRun>? parts;

  /// Whether [dispose] must dispose [parts] as well as [painter].
  final bool ownsParts;
  final double width;
  final double baseline;
  int _references = 1;
  bool _disposed = false;

  /// Adds one owner of this immutable layout. Exact-placement run layouts use
  /// this for glyph-cache entries they embed: cache eviction and run eviction
  /// can then happen in either order without handing either owner a disposed
  /// paragraph.
  _TextLayout retain() {
    assert(!_disposed);
    _references++;
    return this;
  }

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

  /// Disposes what this layout owns: its own painter, and its parts when they
  /// were shaped for it rather than borrowed from the glyph cache.
  void dispose() {
    if (_disposed) return;
    _references--;
    if (_references > 0) return;
    _disposed = true;
    painter?.dispose();
    if (ownsParts) {
      for (final part in parts!) {
        part.glyph.dispose();
      }
    }
  }
}

/// One character's layout within a composed run: the shared glyph-cache
/// layout and its x-offset (natural, un-scaled 100px-per-em space).
class _GlyphRun {
  const _GlyphRun(this.glyph, this.dx);
  final _TextLayout glyph;
  final double dx;
}
