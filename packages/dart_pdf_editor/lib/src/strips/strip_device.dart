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
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';

import '../canvas_device.dart';
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
  }) =>
      StripPdfDevice._(
        canvas,
        usablePlan(precomputed,
            pageToDevice: pageToDevice,
            deviceWidth: deviceWidth,
            deviceHeight: deviceHeight),
        pageToDevice: pageToDevice,
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
        pixelRatio: pixelRatio,
        images: images,
      );

  StripPdfDevice._(
    this.canvas,
    this._plan, {
    required super.pageToDevice,
    required super.deviceWidth,
    required super.deviceHeight,
    required super.pixelRatio,
    required this.images,
  })  : _deviceToPage = _invertToMatrix4(pageToDevice),
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
  }) {
    if (plan == null) return null;
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
  }

  int get flushCount => _batches.length;

  static Future<ui.FragmentProgram>? _programFuture;

  static Future<ui.FragmentProgram> _loadProgram() =>
      _programFuture ??= () async {
        try {
          return await ui.FragmentProgram.fromAsset('shaders/pdf_strips.frag');
        } catch (_) {
          return ui.FragmentProgram.fromAsset(
              'packages/dart_pdf_editor/shaders/pdf_strips.frag');
        }
      }();

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

  // ---- painting ---------------------------------------------------------

  /// Decodes every batch's alpha atlas, then replays the tape onto
  /// [canvas]: fallback ops drive a real [CanvasPdfDevice], strip batches
  /// draw as shader-carrying drawVertices under the device->page transform.
  /// Await before `endRecording()`; the device is unusable afterwards.
  Future<void> finish() async {
    assert(!_finished, 'StripPdfDevice.finish() called twice');
    _finished = true;
    flushPending();
    final plan = _plan;
    if (plan != null &&
        (flushPointCount != plan.totalFlushPoints ||
            _planNext != plan.batches.length)) {
      // Desync is only detectable once the walk is complete; nothing has
      // painted yet (painting starts below), so the caller can discard the
      // recording and re-run with local binning.
      totalPlanMismatches++;
      throw StripPlanMismatchError(
          'flush points: device $flushPointCount vs plan '
          '${plan.totalFlushPoints}; consumed $_planNext of '
          '${plan.batches.length} batches');
    }
    if (plan != null && !debugVerifyPrecomputed) totalPlanPictures++;
    final sw = Stopwatch()..start();
    final program = await _loadProgram();
    await Future.wait([for (final b in _batches) b.decodeAtlas()]);
    totalAtlasDecodeMicros += sw.elapsedMicroseconds;

    sw.reset();
    final fallback = CanvasPdfDevice(canvas, images: images);
    for (final entry in _tape) {
      if (entry is StripBatch) {
        _drawBatch(program, entry);
      } else {
        (entry as void Function(CanvasPdfDevice))(fallback);
      }
    }
    totalReplayMicros += sw.elapsedMicroseconds;
  }

  /// Releases the decoded atlas images and vertex buffers. Call after the
  /// recording that [finish] painted into has ended (the picture keeps its
  /// own references).
  void dispose() {
    for (final b in _batches) {
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
      if (a.positions.length != b.positions.length ||
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
