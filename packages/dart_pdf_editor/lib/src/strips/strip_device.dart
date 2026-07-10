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

export 'package:pdf_graphics/raster.dart' show stripFlattenTolerance;

/// [PdfDevice] that batches strip-rasterized paint into shader draws and
/// routes everything else through an internal [CanvasPdfDevice] fallback.
///
/// Usage: construct per page, feed it a full interpreter walk, then
/// `await finish()` before ending the picture recording; call [dispose]
/// after `endRecording()` to release the atlas images.
class StripPdfDevice extends StripBinningDevice {
  StripPdfDevice(
    this.canvas, {
    required super.pageToDevice,
    required super.deviceWidth,
    required super.deviceHeight,
    required super.pixelRatio,
    this.images = const {},
  })  : _deviceToPage = _invertToMatrix4(pageToDevice),
        super(
          delegateAll: debugDelegateAll,
          delegateFills: debugDelegateFills,
          delegateStrokes: debugDelegateStrokes,
          delegateText: debugDelegateText,
        );

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

  static void resetStats() {
    totalFlushes = 0;
    totalStripQuads = 0;
    totalAtlasTexels = 0;
    totalDelegatedPaints = 0;
    totalAtlasDecodeMicros = 0;
    totalReplayMicros = 0;
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

  // ---- StripBinningDevice hooks ------------------------------------------

  @override
  void emitBatch(int ordinal, StripBatchData? data) {
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
