// Shader-driven strip rendering on stock dart:ui (Track B of the strip
// experiment): solid fills, strokes, and embedded-outline text are
// CPU-rasterized into sparse strips (pdf_graphics/raster.dart) and drawn
// with ONE canvas.drawVertices per flush batch - a FragmentShader samples
// per-column coverage from an rgba8888 alpha atlas and BlendMode.modulate
// multiplies it with per-vertex colors (all M0-verified byte-accurate).
// Everything else (images, gradients, meshes, substituted text, non-normal
// blends, knockout groups) delegates to the ordinary CanvasPdfDevice.
//
// Because dart:ui has no synchronous pixels->ui.Image path, the device
// records its work on a tape (strip batches interleaved with fallback
// device ops in painter's order) during the synchronous interpreter walk
// and paints everything in [finish], after the alpha atlases decode. Both
// the batches and the fallback ops target the same canvas, so painter's
// order is exactly the tape order.
//
// A strip picture is only valid at the pixel ratio it was recorded for:
// the quads are device-pixel-aligned and the coverage was resolved at that
// ratio (rescaling filters the strips like any raster).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';

import '../canvas_device.dart';
import 'slug_batch.dart';
import 'strip_batch.dart';

/// Curve-flattening tolerance (device px) for strip-routed paths. The
/// raster core's 0.25 default (the GPU experiment's) leaves curve edges up
/// to 0.25 px off the true curve - against Skia's much finer flattening
/// that showed up as 50/255 coverage diffs on glyph-sized cubics. 0.02 px
/// keeps curve-edge parity within a few counts for ~3.5x the segment count
/// on curves (Wang's n grows with 1/sqrt(tolerance)); lines are unaffected.
const double stripFlattenTolerance = 0.02;

/// [PdfDevice] that batches strip-rasterized paint into shader draws and
/// routes everything else through an internal [CanvasPdfDevice] fallback.
///
/// Usage: construct per page, feed it a full interpreter walk, then
/// `await finish()` before ending the picture recording; call [dispose]
/// after `endRecording()` to release the atlas images.
class StripPdfDevice implements PdfDevice {
  StripPdfDevice(
    this.canvas, {
    required this.pageToDevice,
    required this.deviceWidth,
    required this.deviceHeight,
    required this.pixelRatio,
    this.images = const {},
    this.slugMinGlyphPx = 4.0,
  })  : _deviceToPage = _invertToMatrix4(pageToDevice),
        _slugEnabled = slugGlyphs {
    _generator.begin(deviceWidth, deviceHeight);
  }

  /// Experimental Slug glyph rendering (B3): outline text draws as
  /// em-space quads evaluated by shaders/pdf_slug.frag against a per-flush
  /// curve atlas instead of strip binning; glyphs whose band lists
  /// overflow keep the strip path. Snapshotted per device at construction.
  static bool slugGlyphs = false;

  final bool _slugEnabled;
  SlugBatchBuilder? _slugBuilder;
  final List<SlugBatch> _slugBatches = [];

  final ui.Canvas canvas;

  /// Page space (PDF user space, y-up) -> device pixels (y-down), including
  /// /Rotate and [pixelRatio]. Must match the canvas transform in effect
  /// when [finish] paints, or the strips land off the page.
  final PdfMatrix pageToDevice;

  final int deviceWidth;
  final int deviceHeight;

  /// The ratio baked into [pageToDevice]; recorded strips are only valid at
  /// this ratio.
  final double pixelRatio;

  /// Pre-decoded images for the fallback device (same map as
  /// [CanvasPdfDevice.images]).
  final Map<Object, ui.Image> images;

  final StripGenerator _generator = StripGenerator();
  final Float64List _deviceToPage;

  /// Painter's-order tape: [StripBatch]es interleaved with fallback ops.
  final List<Object> _tape = [];
  final List<StripBatch> _batches = [];

  PdfBlendMode _blend = PdfBlendMode.normal;
  final List<bool> _groupKnockout = [];
  final List<bool> _savedClip = [];
  bool _finished = false;

  // ---- stats (aggregated across devices for the benchmark) --------------
  static int totalFlushes = 0;
  static int totalStripQuads = 0;
  static int totalAtlasTexels = 0;
  static int totalDelegatedPaints = 0;

  /// Phase timing (microseconds), aggregated across devices: time awaiting
  /// alpha-atlas decodes vs replaying the tape (drawVertices + fallback
  /// ops). The interpret+strip-generation and toImage phases are timed by
  /// the renderer (see PdfPageRenderer profiling statics).
  static int totalAtlasDecodeMicros = 0;
  static int totalReplayMicros = 0;

  /// Slug-mode stats: glyph quads drawn and curve-atlas texels uploaded.
  static int totalSlugQuads = 0;
  static int totalSlugAtlasTexels = 0;

  static void resetStats() {
    totalFlushes = 0;
    totalStripQuads = 0;
    totalAtlasTexels = 0;
    totalDelegatedPaints = 0;
    totalAtlasDecodeMicros = 0;
    totalReplayMicros = 0;
    totalSlugQuads = 0;
    totalSlugAtlasTexels = 0;
  }

  int get flushCount => _batches.length;

  static Future<ui.FragmentProgram>? _programFuture;
  static Future<ui.FragmentProgram>? _slugProgramFuture;

  static Future<ui.FragmentProgram> _loadProgram() =>
      _programFuture ??= () async {
        try {
          return await ui.FragmentProgram.fromAsset('shaders/pdf_strips.frag');
        } catch (_) {
          return ui.FragmentProgram.fromAsset(
              'packages/dart_pdf_editor/shaders/pdf_strips.frag');
        }
      }();

  static Future<ui.FragmentProgram> _loadSlugProgram() =>
      _slugProgramFuture ??= () async {
        try {
          return await ui.FragmentProgram.fromAsset('shaders/pdf_slug.frag');
        } catch (_) {
          return ui.FragmentProgram.fromAsset(
              'packages/dart_pdf_editor/shaders/pdf_slug.frag');
        }
      }();

  /// Debug: route every paint through the fallback (no strips at all) to
  /// isolate tape/pipeline effects from strip rasterization quality.
  static bool debugDelegateAll = false;

  /// Debug: per-primitive fallback routing, for parity bisection.
  static bool debugDelegateFills = false;
  static bool debugDelegateStrokes = false;
  static bool debugDelegateText = false;

  /// Whether paint ops may take the strip path right now: normal blend and
  /// not directly inside a knockout group (knockout elements composite with
  /// BlendMode.src, which the batched srcOver quads can't express).
  bool get _stripsActive =>
      !debugDelegateAll &&
      _blend == PdfBlendMode.normal &&
      (_groupKnockout.isEmpty || !_groupKnockout.last);

  /// Straight (non-premultiplied) ARGB for ui.Vertices colors; Skia
  /// premultiplies before BlendMode.modulate applies the coverage.
  static int _argb(PdfColor color, double alpha) {
    int ch(double v) {
      final c = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
      return (c * 255 + 0.5).toInt();
    }

    return (ch(alpha) << 24) |
        (ch(color.red) << 16) |
        (ch(color.green) << 8) |
        ch(color.blue);
  }

  void _flush() {
    final batch = StripBatch.of(_generator.strips);
    if (batch != null) {
      _generator.strips.reset();
      _tape.add(batch);
      _batches.add(batch);
      totalFlushes++;
      totalStripQuads += batch.stripCount;
      totalAtlasTexels += batch.atlasWidth * batch.atlasHeight;
    }
    final slug = _slugBuilder?.build();
    if (slug != null) {
      _tape.add(slug);
      _slugBatches.add(slug);
      if (batch == null) totalFlushes++;
      totalSlugQuads += slug.quadCount;
      totalSlugAtlasTexels += slug.atlasWidth * slug.atlasHeight;
    }
  }

  /// Painter's order: a strip-routed paint arriving while slug quads are
  /// pending must not batch under them (within a window, strips draw
  /// before slug) - but the order only shows where pixels overlap, so the
  /// window closes only when the paint's page-space bbox intersects a
  /// pending glyph quad (rules/borders around text keep batching).
  void _flushIfSlugOverlaps(PdfPath path, [double pad = 0]) {
    final b = _slugBuilder;
    if (b == null || b.isEmpty) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final seg in path.segments) {
      switch (seg) {
        case PdfMoveTo(:final x, :final y):
        case PdfLineTo(:final x, :final y):
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        case PdfCubicTo():
          // control-point hull bounds the curve (conservative)
          for (final (x, y) in [
            (seg.x1, seg.y1),
            (seg.x2, seg.y2),
            (seg.x3, seg.y3)
          ]) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        case PdfClosePath():
          break;
      }
    }
    if (b.overlaps(minX - pad, minY - pad, maxX + pad, maxY + pad)) _flush();
  }

  /// Records a fallback op that paints: pending strips must land first.
  void _delegatePaint(void Function(CanvasPdfDevice d) op) {
    _flush();
    totalDelegatedPaints++;
    _tape.add(op);
  }

  /// Records a fallback op that only mutates state (no pixels).
  void _state(void Function(CanvasPdfDevice d) op) => _tape.add(op);

  // ---- PdfDevice --------------------------------------------------------

  @override
  void save() {
    _savedClip.add(false);
    _state((d) => d.save());
  }

  @override
  void restore() {
    // Strips batched under a clip must draw before the restore pops it.
    if (_savedClip.isNotEmpty && _savedClip.removeLast()) _flush();
    _state((d) => d.restore());
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    _flush(); // strips batched before the clip must not be clipped by it
    if (_savedClip.isNotEmpty) _savedClip[_savedClip.length - 1] = true;
    _state((d) => d.clipPath(path, rule));
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    if (!_stripsActive || debugDelegateFills) {
      _delegatePaint((d) => d.fillPath(path, color, rule, alpha));
      return;
    }
    _flushIfSlugOverlaps(path);
    _generator.fillPath(path, pageToDevice, rule, _argb(color, alpha),
        tolerance: stripFlattenTolerance);
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    if (!_stripsActive || debugDelegateStrokes) {
      _delegatePaint((d) => d.strokePath(path, color, stroke, alpha));
      return;
    }
    // Skia renders strokes thinner than one device pixel as a 1-px hairline
    // with the alpha modulated by the width (not a true sub-pixel band);
    // match it so thin CAD/print linework is parity-identical.
    var deviceStroke = stroke;
    var a = alpha;
    final sf = pageToDevice.scaleFactor;
    final deviceWidth = stroke.width * sf;
    if (deviceWidth < 1 && sf > 0) {
      deviceStroke = stroke.copyWith(width: 1 / sf);
      if (deviceWidth > 0) a *= deviceWidth;
    }
    _flushIfSlugOverlaps(path, deviceStroke.width / 2 + 1);
    _generator.strokePath(path, pageToDevice, deviceStroke, _argb(color, a),
        tolerance: stripFlattenTolerance);
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    _delegatePaint((d) => d.fillPathGradient(path, rule, gradient, alpha));
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    _delegatePaint((d) => d.fillMesh(mesh, alpha));
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.invisible) return;
    final glyphs = run.glyphs;
    if (!_stripsActive ||
        debugDelegateText ||
        glyphs == null ||
        !run.fill ||
        run.strokeColor != null ||
        run.gradient != null) {
      // substituted-font runs, stroked/gradient text, knockout/blended runs
      _delegatePaint((d) => d.drawText(run));
      return;
    }
    final color = _argb(run.color, 1);
    if (_slugEnabled && _addSlugRun(glyphs, run, color)) return;
    // a run that fell back to strips (overflow/minified) must still land
    // over any pending slug quads it touches
    if (_slugBuilder != null && !_slugBuilder!.isEmpty) _flush();
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final emToDevice = PdfMatrix.translation(glyph.offset, glyph.offsetY)
          .concat(run.transform)
          .concat(pageToDevice);
      _generator.fillOutline(FlattenedOutline.of(outline), emToDevice, color);
    }
  }

  /// Minification guard (device px per em): below this glyph size the
  /// per-pixel band walk aliases (features fall between the sparse sample
  /// points), so runs route to the strip path, which resolves fine
  /// coverage exactly. Mirrors gputext's minificationGuardPx.
  final double slugMinGlyphPx;

  /// Impeller snapshots one texel per texcoord unit over the batch's
  /// texcoord bounds; flush before the stacked slot cells approach the
  /// 16384 max texture dimension.
  static const double _slugMaxVExtent = 8192;

  /// Routes a whole run's glyphs to the Slug batch. Returns false (and
  /// adds nothing) when any glyph's band lists overflow or the run is
  /// below the minification guard - mixed paths within one run would
  /// thrash the window ordering, so the run then falls back to strips as
  /// a unit.
  bool _addSlugRun(List<PdfGlyphPlacement> glyphs, PdfTextRun run, int color) {
    // record-time device px per em along each axis (AA ramp width and
    // texcoord scale); translation-independent, so per run not per glyph
    final rt = run.transform.concat(pageToDevice);
    final sx = math.sqrt(rt.a * rt.a + rt.b * rt.b);
    final sy = math.sqrt(rt.c * rt.c + rt.d * rt.d);
    if (math.max(sx, sy) < slugMinGlyphPx) return false;
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline == null) continue;
      if (SlugGlyphData.of(outline).overflow) return false;
    }
    final builder = _slugBuilder ??= SlugBatchBuilder();
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final data = SlugGlyphData.of(outline);
      final emToPage = PdfMatrix.translation(glyph.offset, glyph.offsetY)
          .concat(run.transform);
      builder.addGlyph(outline, data, emToPage, sx, sy, color);
    }
    if (builder.estimatedVExtent > _slugMaxVExtent) _flush();
    return true;
  }

  @override
  void drawImage(PdfImageRequest request) {
    _delegatePaint((d) => d.drawImage(request));
  }

  @override
  void setBlendMode(PdfBlendMode mode) {
    _blend = mode;
    _state((d) => d.setBlendMode(mode));
  }

  @override
  void beginGroup(double alpha, {bool knockout = false}) {
    _flush(); // the group's layer must not capture earlier strips
    _groupKnockout.add(knockout);
    _state((d) => d.beginGroup(alpha, knockout: knockout));
  }

  @override
  void endGroup() {
    _flush(); // strips inside the group must land inside its layer
    if (_groupKnockout.isNotEmpty) _groupKnockout.removeLast();
    _state((d) => d.endGroup());
  }

  @override
  void beginSoftMasked() {
    _flush(); // earlier strips must not be captured by the content layer
    _groupKnockout.add(false);
    _state((d) => d.beginSoftMasked());
  }

  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {
    _flush(); // masked content strips land inside the content layer
    if (_groupKnockout.isNotEmpty) _groupKnockout.removeLast();
    _state((d) => d.beginSoftMaskComposite(
        luminosity: luminosity,
        backdrop: backdrop,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset));
    // The mask group's draws happen NOW (interpret time) and append to the
    // tape between the composite halves - the fallback's own endSoftMasked
    // would re-run them at replay time instead.
    drawMask();
    _flush();
    _state((d) => d.finishSoftMaskComposite());
  }

  // ---- painting ---------------------------------------------------------

  /// Decodes every batch's alpha atlas, then replays the tape onto
  /// [canvas]: fallback ops drive a real [CanvasPdfDevice], strip batches
  /// draw as shader-carrying drawVertices under the device->page transform.
  /// Await before `endRecording()`; the device is unusable afterwards.
  Future<void> finish() async {
    assert(!_finished, 'StripPdfDevice.finish() called twice');
    _finished = true;
    _flush();
    final sw = Stopwatch()..start();
    final program = await _loadProgram();
    final slugProgram =
        _slugBatches.isEmpty ? null : await _loadSlugProgram();
    await Future.wait([
      for (final b in _batches) b.decodeAtlas(),
      for (final b in _slugBatches) b.decodeAtlas(),
    ]);
    totalAtlasDecodeMicros += sw.elapsedMicroseconds;

    sw.reset();
    final fallback = CanvasPdfDevice(canvas, images: images);
    for (final entry in _tape) {
      if (entry is StripBatch) {
        _drawBatch(program, entry);
      } else if (entry is SlugBatch) {
        _drawSlugBatch(slugProgram!, entry);
      } else {
        (entry as void Function(CanvasPdfDevice))(fallback);
      }
    }
    totalReplayMicros += sw.elapsedMicroseconds;
  }

  /// Debug: slug shader diagnostic output mode (see pdf_slug.frag uDebug).
  static double debugSlugMode = 0;

  /// Debug: mode parameter (uDebug.y - e.g. curve index for mode 3).
  static double debugSlugParam = 0;

  /// Slug quads are page-space geometry - no device->page transform.
  void _drawSlugBatch(ui.FragmentProgram program, SlugBatch batch) {
    final shader = program.fragmentShader()
      ..setFloat(0, batch.atlasWidth.toDouble())
      ..setFloat(1, batch.atlasHeight.toDouble())
      ..setFloat(2, debugSlugMode)
      ..setFloat(3, debugSlugParam)
      ..setFloat(4, batch.cellHeight)
      ..setImageSampler(0, batch.atlas!);
    final paint = ui.Paint()..shader = shader;
    for (final chunk in batch.chunks) {
      canvas.drawVertices(chunk, ui.BlendMode.modulate, paint);
    }
  }

  /// Releases the decoded atlas images and vertex buffers. Call after the
  /// recording that [finish] painted into has ended (the picture keeps its
  /// own references).
  void dispose() {
    for (final b in _batches) {
      b.dispose();
    }
    for (final b in _slugBatches) {
      b.dispose();
    }
  }

  /// Debug/benchmark: draw batches with a plain paint instead of the
  /// coverage shader (wrong output - quantifies the runtime-effect cost of
  /// software rasterization).
  static bool debugNoShader = false;

  void _drawBatch(ui.FragmentProgram program, StripBatch batch) {
    final paint = ui.Paint();
    if (!debugNoShader) {
      paint.shader = program.fragmentShader()
        ..setFloat(0, batch.atlasWidth.toDouble())
        ..setFloat(1, batch.atlasHeight.toDouble())
        ..setImageSampler(0, batch.atlas!);
    }
    canvas.save();
    canvas.transform(_deviceToPage);
    for (final chunk in batch.chunks) {
      // no-shader mode draws the vertex colors directly (wrong coverage,
      // representative triangle-raster cost)
      canvas.drawVertices(chunk,
          debugNoShader ? ui.BlendMode.srcOver : ui.BlendMode.modulate, paint);
    }
    canvas.restore();
  }

  static Float64List _invertToMatrix4(PdfMatrix pageToDevice) {
    final inv = pageToDevice.inverted();
    if (inv == null) {
      throw ArgumentError('pageToDevice transform is degenerate');
    }
    return Float64List.fromList([
      inv.a, inv.b, 0, 0, //
      inv.c, inv.d, 0, 0, //
      0, 0, 1, 0, //
      inv.e, inv.f, 0, 1,
    ]);
  }
}
