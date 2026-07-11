// Shader-driven strip rendering on stock dart:ui (Track B of the strip
// experiment): solid fills, strokes, and embedded-outline text are
// CPU-rasterized into sparse strips (pdf_graphics/raster.dart) and drawn
// with ONE canvas.drawVertices per flush batch - a FragmentShader samples
// per-column coverage from an rgba8888 alpha atlas and BlendMode.modulate
// multiplies it with per-vertex colors (all M0-verified byte-accurate).
// Everything else (images, gradients, meshes, substituted text, non-normal
// blends, knockout groups) delegates to the ordinary CanvasPdfDevice.
//
// The routing/state/flush logic lives in pdf_graphics' StripBinningDevice
// (dart:ui-free) so a worker isolate can bin the exact same batches; this
// subclass only owns the dart:ui half: the tape of fallback closures, the
// StripBatch uploads, and the shader draw.
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

export 'package:pdf_graphics/raster.dart'
    show
        StripPlan,
        StripPlanBinner,
        StripPlanMismatchError,
        decodeStripPlan,
        encodeStripPlan,
        stripFlattenTolerance;

/// [PdfDevice] that batches strip-rasterized paint into shader draws and
/// routes everything else through an internal [CanvasPdfDevice] fallback.
///
/// Usage: construct per page, feed it a full interpreter walk, then
/// `await finish()` before ending the picture recording; call [dispose]
/// after `endRecording()` to release the atlas images.
class StripPdfDevice extends StripBinningDevice {
  /// [precomputed] feeds the device a worker-binned [StripPlan] instead of
  /// binning locally: generator feeds are skipped entirely and each flush
  /// point consumes the plan batch tagged with its ordinal. The plan must
  /// have been binned for this exact geometry - [usablePlan] guards that
  /// (and the debug-delegate flags, which force local binning) - and
  /// [finish] verifies the flush-point count and full consumption before
  /// painting anything, throwing [StripPlanMismatchError] on desync so the
  /// caller can transparently re-run with local binning.
  factory StripPdfDevice(
    ui.Canvas canvas, {
    required PdfMatrix pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    Map<Object, ui.Image> images = const {},
    StripPlan? precomputed,
    double slugMinGlyphPx = 4,
    bool? enableSlugGlyphs,
  }) {
    final slugEnabled = enableSlugGlyphs ?? slugGlyphs;
    return StripPdfDevice._(
      canvas,
      usablePlan(precomputed,
          pageToDevice: pageToDevice,
          deviceWidth: deviceWidth,
          deviceHeight: deviceHeight,
          slugEnabled: slugEnabled),
      pageToDevice: pageToDevice,
      deviceWidth: deviceWidth,
      deviceHeight: deviceHeight,
      pixelRatio: pixelRatio,
      images: images,
      slugMinGlyphPx: slugMinGlyphPx,
      slugEnabled: slugEnabled,
    );
  }

  StripPdfDevice._(
    this.canvas,
    this._plan, {
    required super.pageToDevice,
    required super.deviceWidth,
    required super.deviceHeight,
    required super.pixelRatio,
    required this.images,
    required this.slugMinGlyphPx,
    required bool slugEnabled,
  })  : _deviceToPage = _invertToMatrix4(pageToDevice),
        _slugEnabled = slugEnabled,
        super(
          // A usable plan replaces local binning entirely; the debug
          // verification mode bins locally TOO so emitBatch can compare.
          binningEnabled: _plan == null || debugVerifyPrecomputed,
          delegateAll: debugDelegateAll,
          delegateFills: debugDelegateFills,
          delegateStrokes: debugDelegateStrokes,
          delegateText: debugDelegateText,
        );

  /// The validated precomputed plan (null = local binning) and the index of
  /// the next unconsumed plan batch.
  final StripPlan? _plan;
  int _planNext = 0;
  int _planSlugNext = 0;
  int _planSlugFallbackNext = 0;

  /// Whether this device consumes a precomputed plan (after validation).
  bool get usesPrecomputedPlan => _plan != null;

  /// Validates [plan] for a device about to be constructed with this
  /// geometry: null when no plan, when any debug-delegate flag forces local
  /// binning (the flags change ROUTING and the plan's producer ran without
  /// them), or - counted in [totalPlanMismatches] - when the plan was binned
  /// for different geometry (stale zoom/region). The matrix comparison is
  /// exact: the six coefficients round-trip bit-exactly through the worker.
  static StripPlan? usablePlan(
    StripPlan? plan, {
    required PdfMatrix pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    bool slugEnabled = false,
  }) {
    if (plan == null) return null;
    if (plan.slugGlyphs != slugEnabled) return null;
    if (debugDelegateAll ||
        debugDelegateFills ||
        debugDelegateStrokes ||
        debugDelegateText) {
      return null;
    }
    final m = plan.pageToDevice;
    if (plan.deviceWidth != deviceWidth ||
        plan.deviceHeight != deviceHeight ||
        plan.tolerance != stripFlattenTolerance ||
        m.a != pageToDevice.a ||
        m.b != pageToDevice.b ||
        m.c != pageToDevice.c ||
        m.d != pageToDevice.d ||
        m.e != pageToDevice.e ||
        m.f != pageToDevice.f) {
      totalPlanMismatches++;
      return null;
    }
    return plan;
  }

  /// Experimental Slug glyph rendering (B3): outline text draws as
  /// em-space quads evaluated by shaders/pdf_slug.frag against a per-flush
  /// curve atlas instead of strip binning; glyphs whose band lists
  /// overflow keep the strip path. Snapshotted per device at construction.
  static bool slugGlyphs = false;

  final bool _slugEnabled;
  final double slugMinGlyphPx;
  SlugBatchBuilder? _slugBuilder;
  final List<SlugBatch> _slugBatches = [];
  int _slugQuadCount = 0;
  int _slugFallbackOutlineRuns = 0;

  /// Per-device Slug routing result, unlike the aggregate benchmark stats.
  int get slugQuadCount => _slugQuadCount;
  int get slugFallbackOutlineRuns => _slugFallbackOutlineRuns;

  final ui.Canvas canvas;

  /// Pre-decoded images for the fallback device (same map as
  /// [CanvasPdfDevice.images]).
  final Map<Object, ui.Image> images;

  final Float64List _deviceToPage;

  /// Painter's-order tape: [StripBatch]es interleaved with fallback ops.
  final List<Object> _tape = [];
  final List<StripBatch> _batches = [];

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

  /// Time spent synchronously routing the command list through the device
  /// (binning included when local; only routing + plan-batch upload when
  /// precomputed) - accumulated by [PdfRetainedScene]'s strip replays. With
  /// [totalReplayMicros] this is the UI-thread-blocking share of a settle.
  static int totalRouteMicros = 0;

  /// Precomputed plans rejected (stale geometry) or failing verification at
  /// [finish] - each one transparently fell back to local binning.
  static int totalPlanMismatches = 0;

  /// Pictures painted from a verified precomputed plan (no local binning).
  static int totalPlanPictures = 0;

  /// Slug-mode stats: glyph quads drawn and curve-atlas texels uploaded.
  static int totalSlugQuads = 0;
  static int totalSlugAtlasTexels = 0;
  static int totalSlugFallbackOutlineRuns = 0;

  static void resetStats() {
    totalFlushes = 0;
    totalStripQuads = 0;
    totalAtlasTexels = 0;
    totalDelegatedPaints = 0;
    totalAtlasDecodeMicros = 0;
    totalReplayMicros = 0;
    totalRouteMicros = 0;
    totalPlanMismatches = 0;
    totalPlanPictures = 0;
    totalSlugQuads = 0;
    totalSlugAtlasTexels = 0;
    totalSlugFallbackOutlineRuns = 0;
  }

  int get flushCount => _batches.length;

  // Cache resolved engine values, never the Future itself. A Future created
  // in a widget test's FakeAsync zone becomes unusable after that test; the
  // resolved program is zone-independent and can be returned from a fresh
  // Future in every caller's current zone.
  static ui.FragmentProgram? _program;
  static ui.FragmentProgram? _slugProgram;

  static Future<ui.FragmentProgram> _loadProgram() async {
    final cached = _program;
    if (cached != null) return cached;
    final loaded = await _loadProgramAsset('shaders/pdf_strips.frag',
        'packages/dart_pdf_editor/shaders/pdf_strips.frag');
    return _program ??= loaded;
  }

  static Future<ui.FragmentProgram> _loadSlugProgram() async {
    final cached = _slugProgram;
    if (cached != null) return cached;
    final loaded = await _loadProgramAsset('shaders/pdf_slug.frag',
        'packages/dart_pdf_editor/shaders/pdf_slug.frag');
    return _slugProgram ??= loaded;
  }

  static Future<ui.FragmentProgram> _loadProgramAsset(
      String primary, String packagePath) async {
    try {
      return await ui.FragmentProgram.fromAsset(primary);
    } catch (_) {
      return ui.FragmentProgram.fromAsset(packagePath);
    }
  }

  /// Debug: route every paint through the fallback (no strips at all) to
  /// isolate tape/pipeline effects from strip rasterization quality.
  ///
  /// The debug-delegate flags change ROUTING, so they force local binning:
  /// callers must not feed a device a worker-binned plan while any of them
  /// is set (the worker isolate carries its own statics and would bin the
  /// full routing, desyncing flush ordinals).
  static bool debugDelegateAll = false;

  /// Debug: per-primitive fallback routing, for parity bisection.
  static bool debugDelegateFills = false;
  static bool debugDelegateStrokes = false;
  static bool debugDelegateText = false;

  /// Debug/test: with a precomputed plan, ALSO bin locally at every flush
  /// point and assert the plan's batch matches (ordinal presence, strip
  /// count, vertex arrays, atlas bytes) - the strongest form of the
  /// flush-ordinal parity invariant. Test-only; throws [StateError] on the
  /// first divergence.
  static bool debugVerifyPrecomputed = false;

  // ---- StripBinningDevice hooks ------------------------------------------

  @override
  void emitBatch(int ordinal, StripBatchData? data) {
    final plan = _plan;
    if (plan != null) {
      StripBatchData? planData;
      if (_planNext < plan.batches.length &&
          plan.batches[_planNext].flushOrdinal == ordinal) {
        planData = plan.batches[_planNext++];
      }
      if (debugVerifyPrecomputed) _verifyAgainstPlan(ordinal, data, planData);
      data = planData;
    }
    if (data == null) return;
    final batch = StripBatch.fromData(data);
    _tape.add(batch);
    _batches.add(batch);
    totalFlushes++;
    totalStripQuads += batch.stripCount;
    totalAtlasTexels += batch.atlasWidth * batch.atlasHeight;
  }

  /// Records a fallback op that paints (the base already flushed).
  void _paint(void Function(CanvasPdfDevice d) op) {
    totalDelegatedPaints++;
    _tape.add(op);
  }

  /// Records a fallback op that only mutates state (no pixels).
  void _state(void Function(CanvasPdfDevice d) op) => _tape.add(op);

  @override
  void delegateSave() => _state((d) => d.save());

  @override
  void delegateRestore() => _state((d) => d.restore());

  @override
  void delegateClipPath(PdfPath path, PdfFillRule rule) =>
      _state((d) => d.clipPath(path, rule));

  @override
  void delegateSetBlendMode(PdfBlendMode mode) =>
      _state((d) => d.setBlendMode(mode));

  @override
  void delegateBeginGroup(double alpha, {required bool knockout}) =>
      _state((d) => d.beginGroup(alpha, knockout: knockout));

  @override
  void delegateEndGroup() => _state((d) => d.endGroup());

  @override
  void delegateBeginSoftMasked() => _state((d) => d.beginSoftMasked());

  @override
  void delegateBeginSoftMaskComposite({
    required bool luminosity,
    required PdfRect backdrop,
    required double backdropLuminance,
    required double transferScale,
    required double transferOffset,
  }) {
    // The mask group's draws happen at interpret time and append to the
    // tape between the composite halves - the fallback's own endSoftMasked
    // would re-run them at replay time instead.
    _state((d) => d.beginSoftMaskComposite(
        luminosity: luminosity,
        backdrop: backdrop,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset));
  }

  @override
  void delegateFinishSoftMaskComposite() =>
      _state((d) => d.finishSoftMaskComposite());

  @override
  void delegateFillPath(
          PdfPath path, PdfColor color, PdfFillRule rule, double alpha) =>
      _paint((d) => d.fillPath(path, color, rule, alpha));

  @override
  void delegateStrokePath(
          PdfPath path, PdfColor color, PdfStroke stroke, double alpha) =>
      _paint((d) => d.strokePath(path, color, stroke, alpha));

  @override
  void delegateFillPathGradient(
          PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) =>
      _paint((d) => d.fillPathGradient(path, rule, gradient, alpha));

  @override
  void delegateFillMesh(PdfMesh mesh, double alpha) =>
      _paint((d) => d.fillMesh(mesh, alpha));

  @override
  void delegateDrawText(PdfTextRun run) => _paint((d) => d.drawText(run));

  @override
  void delegateDrawImage(PdfImageRequest request) =>
      _paint((d) => d.drawImage(request));

  @override
  void drawText(PdfTextRun run) {
    final glyphs = run.glyphs;
    if (!_slugEnabled ||
        run.invisible ||
        !stripsActive ||
        delegateText ||
        glyphs == null ||
        !run.fill ||
        run.strokeColor != null ||
        run.gradient != null) {
      super.drawText(run);
      return;
    }

    // Finish strips that precede this run, then commit the complete run as one
    // Slug batch immediately. Immediate commit is deliberately conservative
    // while the worker-plan and glyph-layer paths are integrated: it preserves
    // painter order without changing StripBinningDevice's flush ordinals.
    flushPending();
    final plan = _plan;
    if (plan != null) {
      final ordinal = flushPointCount - 1;
      if (_planSlugNext < plan.slugBatches.length &&
          plan.slugBatches[_planSlugNext].flushOrdinal == ordinal) {
        _addSlugBatch(plan.slugBatches[_planSlugNext++]);
        return;
      }
      if (_planSlugFallbackNext >= plan.slugFallbackOrdinals.length ||
          plan.slugFallbackOrdinals[_planSlugFallbackNext] != ordinal) {
        // Slug-eligible run with no outline quads: successful no-op, not a
        // fallback. This distinction is explicit in the worker plan so the
        // UI never has to inspect outlines to recover routing.
        return;
      }
      _planSlugFallbackNext++;
      // The worker applied the same eligibility checks and routed this run
      // into strips. With binning disabled, super only advances routing; its
      // planned strip batch is consumed at the next flush point.
      _slugFallbackOutlineRuns++;
      totalSlugFallbackOutlineRuns++;
      super.drawText(run);
      return;
    }
    if (!_addSlugRun(glyphs, run, stripArgbColor(run.color, 1))) {
      _slugFallbackOutlineRuns++;
      totalSlugFallbackOutlineRuns++;
      super.drawText(run);
      return;
    }
    _flushSlug(flushPointCount - 1);
  }

  static const double _slugMaxVExtent = 8192;

  bool _addSlugRun(List<PdfGlyphPlacement> glyphs, PdfTextRun run, int color) {
    final deviceTransform = run.transform.concat(pageToDevice);
    final sx = math.sqrt(deviceTransform.a * deviceTransform.a +
        deviceTransform.b * deviceTransform.b);
    final sy = math.sqrt(deviceTransform.c * deviceTransform.c +
        deviceTransform.d * deviceTransform.d);
    if (math.max(sx, sy) < slugMinGlyphPx) return false;

    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline != null && SlugGlyphData.of(outline).overflow) return false;
    }

    final builder = _slugBuilder ??= SlugBatchBuilder();
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final emToPage = PdfMatrix.translation(glyph.offset, glyph.offsetY)
          .concat(run.transform);
      builder.addGlyph(
        outline,
        SlugGlyphData.of(outline),
        emToPage,
        sx,
        sy,
        color,
      );
    }
    if (builder.estimatedVExtent > _slugMaxVExtent) {
      _flushSlug(flushPointCount - 1);
    }
    return true;
  }

  void _flushSlug(int ordinal) {
    final data = _slugBuilder?.build(ordinal);
    if (data == null) return;
    _addSlugBatch(data);
  }

  void _addSlugBatch(SlugBatchData data) {
    final batch = SlugBatch.fromData(data);
    _tape.add(batch);
    _slugBatches.add(batch);
    totalFlushes++;
    totalSlugQuads += batch.quadCount;
    _slugQuadCount += batch.quadCount;
    totalSlugAtlasTexels += batch.atlasWidth * batch.atlasHeight;
  }

  // ---- painting ---------------------------------------------------------

  /// Decodes every batch's alpha atlas, then replays the tape onto
  /// [canvas]: fallback ops drive a real [CanvasPdfDevice], strip batches
  /// draw as shader-carrying drawVertices under the device->page transform.
  /// Await before `endRecording()`; the device is unusable afterwards.
  Future<void> finish() async {
    assert(!_finished, 'StripPdfDevice.finish() called twice');
    _finished = true;
    flushPending();
    _flushSlug(flushPointCount - 1);
    final plan = _plan;
    if (plan != null &&
        (flushPointCount != plan.totalFlushPoints ||
            _planNext != plan.batches.length ||
            _planSlugNext != plan.slugBatches.length ||
            _planSlugFallbackNext != plan.slugFallbackOrdinals.length)) {
      // Desync is only detectable once the walk is complete; nothing has
      // painted yet (painting starts below), so the caller can discard the
      // recording and re-run with local binning.
      totalPlanMismatches++;
      throw StripPlanMismatchError(
          'flush points: device $flushPointCount vs plan '
          '${plan.totalFlushPoints}; consumed $_planNext of '
          '${plan.batches.length} strip and $_planSlugNext of '
          '${plan.slugBatches.length} Slug batches; consumed '
          '$_planSlugFallbackNext of ${plan.slugFallbackOrdinals.length} '
          'Slug fallbacks');
    }
    if (plan != null && !debugVerifyPrecomputed) totalPlanPictures++;
    final sw = Stopwatch()..start();
    final program = await _loadProgram();
    final slugProgram = _slugBatches.isEmpty ? null : await _loadSlugProgram();
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

  /// debugVerifyPrecomputed: byte-compares the locally-binned [local] batch
  /// with the plan's [fromPlan] at flush point [ordinal].
  static void _verifyAgainstPlan(
      int ordinal, StripBatchData? local, StripBatchData? fromPlan) {
    void fail(String what) => throw StateError(
        'precomputed plan diverges at flush point $ordinal: $what');
    if ((local == null) != (fromPlan == null)) {
      fail('local ${local == null ? 'empty' : 'batch'} vs plan '
          '${fromPlan == null ? 'empty' : 'batch'}');
    }
    if (local == null || fromPlan == null) return;
    if (local.stripCount != fromPlan.stripCount) {
      fail('stripCount ${local.stripCount} vs ${fromPlan.stripCount}');
    }
    if (local.atlasWidth != fromPlan.atlasWidth ||
        local.atlasHeight != fromPlan.atlasHeight) {
      fail('atlas ${local.atlasWidth}x${local.atlasHeight} vs '
          '${fromPlan.atlasWidth}x${fromPlan.atlasHeight}');
    }
    bool bytesEqual(List<int> a, List<int> b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    if (!bytesEqual(local.atlasPixels, fromPlan.atlasPixels)) {
      fail('atlas bytes differ');
    }
    if (local.chunks.length != fromPlan.chunks.length) {
      fail('chunk count ${local.chunks.length} vs ${fromPlan.chunks.length}');
    }
    for (var c = 0; c < local.chunks.length; c++) {
      final a = local.chunks[c], b = fromPlan.chunks[c];
      if (a.alphaBase != b.alphaBase ||
          a.positions.length != b.positions.length ||
          !bytesEqual(a.indices, b.indices) ||
          !bytesEqual(a.colors, b.colors)) {
        fail('chunk $c vertex data differs');
      }
      for (var i = 0; i < a.positions.length; i++) {
        if (a.positions[i] != b.positions[i] ||
            a.textureCoordinates[i] != b.textureCoordinates[i]) {
          fail('chunk $c float data differs at $i');
        }
      }
    }
  }

  void _drawBatch(ui.FragmentProgram program, StripBatch batch) {
    canvas.save();
    canvas.transform(_deviceToPage);
    for (var i = 0; i < batch.chunks.length; i++) {
      final paint = ui.Paint();
      if (!debugNoShader) {
        // One shader instance per chunk: texcoords are chunk-relative (so
        // Impeller's shader-snapshot texture stays within limits) and uBase
        // restores the chunk's global alpha-texel origin.
        paint.shader = program.fragmentShader()
          ..setFloat(0, batch.atlasWidth.toDouble())
          ..setFloat(1, batch.atlasHeight.toDouble())
          ..setFloat(2, batch.chunkAlphaBases[i].toDouble())
          ..setImageSampler(0, batch.atlas!);
      }
      // no-shader mode draws the vertex colors directly (wrong coverage,
      // representative triangle-raster cost)
      canvas.drawVertices(batch.chunks[i],
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
