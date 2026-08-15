// The routing/state/flush core of sparse-strip rendering, shared between
// the live shader device (dart_pdf_editor's StripPdfDevice) and headless
// worker-side binning (StripPlanBinner). Pure Dart - no dart:ui.
//
// THE CRITICAL INVARIANT this class exists to hold: the sequence of flush
// points and the strip-vs-delegate routing of EVERY op are decided only
// here, so a headless replay of the same command list on another isolate
// produces strip batches that interleave at exactly the same flush points
// as the UI-side device. Subclasses only decide what to DO with a batch
// (upload + tape it, collect it into a plan, verify it) and where the
// delegated ops go (a CanvasPdfDevice tape, or nowhere).
import 'package:pdf_document/pdf_document.dart' show PdfRect;

import '../color.dart';
import '../device.dart';
import '../matrix.dart';
import '../mesh.dart';
import '../path.dart';
import '../shading.dart';
import 'flatten.dart';
import 'strip_batch_data.dart';
import 'strip_generator.dart';

/// Curve-flattening tolerance (device px) for strip-routed paths. The
/// raster core's 0.25 default (the GPU experiment's) leaves curve edges up
/// to 0.25 px off the true curve - against Skia's much finer flattening
/// that showed up as 50/255 coverage diffs on glyph-sized cubics. 0.02 px
/// keeps curve-edge parity within a few counts for ~3.5x the segment count
/// on curves (Wang's n grows with 1/sqrt(tolerance)); lines are unaffected.
const double stripFlattenTolerance = 0.02;

/// Straight (non-premultiplied) ARGB for strip vertex colors; the engine
/// premultiplies vertex colors before BlendMode.modulate applies coverage.
int stripArgbColor(PdfColor color, double alpha) {
  int ch(double v) {
    final c = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
    return (c * 255 + 0.5).toInt();
  }

  return (ch(alpha) << 24) |
      (ch(color.red) << 16) |
      (ch(color.green) << 8) |
      ch(color.blue);
}

/// [PdfDevice] base that bins solid fills, strokes, and embedded-outline
/// text into sparse strips ([StripGenerator]) and routes everything else -
/// and every flush-point decision - through abstract hooks.
///
/// Strip-routed ops feed [generator]; at every flush point (a delegated
/// paint, a clip, a restore that pops a clip, group/soft-mask boundaries,
/// and the final [flushPending]) the generator's accumulated strips are
/// snapshotted into a [StripBatchData] and handed to [emitBatch] together
/// with the flush point's ordinal. Empty flush points still count an
/// ordinal (and call [emitBatch] with null data) so ordinals line up
/// across isolates.
///
/// With [binningEnabled] false the generator is never fed or flushed -
/// routing and flush ordinals are still tracked identically, which is how
/// the precomputed-plan device consumes worker-binned batches without
/// paying any flatten/bin cost.
///
/// The per-primitive delegate predicates ([delegateAll]/[delegateFills]/
/// [delegateStrokes]/[delegateText]) are instance state, captured at
/// construction from whatever debug switches the subclass exposes - they
/// are part of the routing decision, so any of them being set on one side
/// but not the other desyncs flush ordinals. Worker plans must not be used
/// while a debug-delegate flag is set (the worker isolate has its own
/// statics and would bin the full routing).
abstract class StripBinningDevice implements PdfDevice {
  StripBinningDevice({
    required this.pageToDevice,
    required this.deviceWidth,
    required this.deviceHeight,
    required this.pixelRatio,
    this.binningEnabled = true,
    this.delegateAll = false,
    this.delegateFills = false,
    this.delegateStrokes = false,
    this.delegateText = false,
  }) {
    if (binningEnabled) generator.begin(deviceWidth, deviceHeight);
  }

  /// Page space (PDF user space, y-up) -> device pixels (y-down), including
  /// /Rotate and [pixelRatio].
  final PdfMatrix pageToDevice;

  final int deviceWidth;
  final int deviceHeight;

  /// The ratio baked into [pageToDevice]; binned strips are only valid at
  /// this ratio.
  final double pixelRatio;

  /// Whether strip-routed ops actually feed [generator]. False in
  /// precomputed-plan mode: routing and flush ordinals still advance, but
  /// no flatten/stroke-expansion/coverage work runs.
  final bool binningEnabled;

  /// Debug routing predicates (see the class doc).
  final bool delegateAll;
  final bool delegateFills;
  final bool delegateStrokes;
  final bool delegateText;

  final StripGenerator generator = StripGenerator();

  PdfBlendMode _blend = PdfBlendMode.normal;
  bool _fillOverprint = false;
  bool _strokeOverprint = false;
  final List<bool> _groupKnockout = [];
  // Per open group: true when the group was *entered* under a non-Normal blend
  // mode. Such a group composites as one object with that blend on its own
  // layer, and the interpreter resets the in-group blend to Normal (§11.6.6) so
  // inner elements don't blend twice - which would otherwise re-enable strip
  // binning for the group's own content while the canvas device draws it
  // directly, diverging the two. Keeping the content on the delegate holds
  // strip/canvas parity.
  final List<bool> _groupBlended = [];
  final List<bool> _savedClip = [];
  int _flushOrdinal = 0;

  /// Flush points seen so far (every flush point counts, empty or not).
  int get flushPointCount => _flushOrdinal;

  /// Delegated paint ops routed through the fallback so far.
  int delegatedPaintCount = 0;

  /// Whether paint ops may take the strip path right now: normal blend and
  /// not directly inside a knockout group (knockout elements composite with
  /// BlendMode.src, which batched srcOver quads can't express).
  bool get stripsActive =>
      !delegateAll &&
      _blend == PdfBlendMode.normal &&
      (_groupKnockout.isEmpty || !_groupKnockout.last) &&
      (_groupBlended.isEmpty || !_groupBlended.last);

  /// Runs one flush point: snapshots the generator's strips (when binning)
  /// and hands them to [emitBatch] with this point's ordinal. Call once
  /// more from the subclass's finish step so trailing strips land.
  void flushPending() {
    final ordinal = _flushOrdinal++;
    StripBatchData? data;
    if (binningEnabled) {
      data = StripBatchData.of(generator.strips, ordinal);
      if (data != null) generator.strips.reset();
    }
    emitBatch(ordinal, data);
  }

  void _delegatePaint(void Function() forward) {
    flushPending(); // pending strips must land under the delegated paint
    delegatedPaintCount++;
    forward();
  }

  // ---- abstract hooks ----------------------------------------------------

  /// Called at every flush point with the strips binned since the previous
  /// one ([data] null when nothing was binned, or when [binningEnabled] is
  /// off). [ordinal] is the flush point's 0-based index.
  void emitBatch(int ordinal, StripBatchData? data);

  /// Delegated state ops (no pixels; not flush points except [clipPath] and
  /// the group boundaries, which the base flushes before forwarding).
  void delegateSave();
  void delegateRestore();
  void delegateClipPath(PdfPath path, PdfFillRule rule);
  void delegateSetBlendMode(PdfBlendMode mode);
  void delegateSetOverprint(
      {required bool fill, required bool stroke, required int mode});
  void delegateBeginGroup(double alpha, {required bool knockout});
  void delegateEndGroup();
  void delegateBeginSoftMasked();

  /// The two halves of the soft-mask composite. The base runs the mask
  /// group's `drawMask()` between them - through THIS device, so mask-group
  /// strips bin (and flush) identically on every subclass.
  void delegateBeginSoftMaskComposite({
    required bool luminosity,
    required PdfRect backdrop,
    required double backdropLuminance,
    required double transferScale,
    required double transferOffset,
  });
  void delegateFinishSoftMaskComposite();

  /// Delegated paint ops (the base flushes before each).
  void delegateFillPath(
      PdfPath path, PdfColor color, PdfFillRule rule, double alpha);
  void delegateStrokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha);
  void delegateFillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha);
  void delegateFillMesh(PdfMesh mesh, double alpha);
  void delegateDrawText(PdfTextRun run);
  void delegateDrawImage(PdfImageRequest request);

  // ---- PdfDevice ----------------------------------------------------------

  @override
  void save() {
    _savedClip.add(false);
    delegateSave();
  }

  @override
  void restore() {
    // Strips batched under a clip must draw before the restore pops it.
    if (_savedClip.isNotEmpty && _savedClip.removeLast()) flushPending();
    delegateRestore();
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    flushPending(); // strips batched before the clip must not be clipped
    if (_savedClip.isNotEmpty) _savedClip[_savedClip.length - 1] = true;
    delegateClipPath(path, rule);
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    if (!stripsActive || delegateFills || _fillOverprint) {
      _delegatePaint(() => delegateFillPath(path, color, rule, alpha));
      return;
    }
    if (!binningEnabled) return;
    generator.fillPath(path, pageToDevice, rule, stripArgbColor(color, alpha),
        tolerance: stripFlattenTolerance);
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    if (!stripsActive || delegateStrokes || _strokeOverprint) {
      _delegatePaint(() => delegateStrokePath(path, color, stroke, alpha));
      return;
    }
    if (!binningEnabled) return;
    // A stroke thinner than one device pixel is painted as a solid one-pixel
    // line, matching the canvas device (see CanvasPdfDevice's stroke floor)
    // and every reference viewer.
    //
    // This used to also scale alpha down by the sub-pixel width, reproducing
    // Skia's own behaviour for a thin stroke. That is faithful to Skia but not
    // to the page: a 0.06 pt CAD hairline came out at ~6% opacity, which is
    // the washed-out thin linework this fixes. Both paths now paint it solid.
    var deviceStroke = stroke;
    final a = alpha;
    final sf = pageToDevice.scaleFactor;
    final hairWidth = stroke.width * sf;
    if (hairWidth < 1 && sf > 0) {
      deviceStroke = stroke.copyWith(width: 1 / sf);
    }
    generator.strokePath(
        path, pageToDevice, deviceStroke, stripArgbColor(color, a),
        tolerance: stripFlattenTolerance);
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    _delegatePaint(() => delegateFillPathGradient(path, rule, gradient, alpha));
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    _delegatePaint(() => delegateFillMesh(mesh, alpha));
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.invisible) return;
    final glyphs = run.glyphs;
    if (!stripsActive ||
        delegateText ||
        glyphs == null ||
        !run.fill ||
        run.strokeColor != null ||
        run.gradient != null) {
      // substituted-font runs, stroked/gradient text, knockout/blended runs
      _delegatePaint(() => delegateDrawText(run));
      return;
    }
    if (!binningEnabled) return;
    final color = stripArgbColor(run.color, run.fillAlpha);
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final emToDevice = PdfMatrix.translation(glyph.offset, glyph.offsetY)
          .concat(run.transform)
          .concat(pageToDevice);
      generator.fillOutline(FlattenedOutline.of(outline), emToDevice, color);
    }
  }

  @override
  void drawImage(PdfImageRequest request) {
    _delegatePaint(() => delegateDrawImage(request));
  }

  @override
  void setBlendMode(PdfBlendMode mode) {
    _blend = mode;
    delegateSetBlendMode(mode);
  }

  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {
    // Overprint (§8.6.7) composites with BlendMode.darken on the canvas device,
    // which batched srcOver strip quads can't express - so an overprinting fill
    // or stroke routes to the delegate (see fillPath/strokePath), exactly like a
    // non-Normal blend mode. Forward the state so the delegate darkens to match
    // the pure-canvas render and strip/canvas parity holds (issue #502).
    _fillOverprint = fill;
    _strokeOverprint = stroke;
    delegateSetOverprint(fill: fill, stroke: stroke, mode: mode);
  }

  @override
  void beginGroup(double alpha, {bool knockout = false}) {
    flushPending(); // the group's layer must not capture earlier strips
    _groupKnockout.add(knockout);
    // Observed before the interpreter resets the in-group blend to Normal.
    _groupBlended.add(_blend != PdfBlendMode.normal);
    delegateBeginGroup(alpha, knockout: knockout);
  }

  @override
  void endGroup() {
    flushPending(); // strips inside the group must land inside its layer
    if (_groupKnockout.isNotEmpty) _groupKnockout.removeLast();
    if (_groupBlended.isNotEmpty) _groupBlended.removeLast();
    delegateEndGroup();
  }

  @override
  void beginSoftMasked() {
    flushPending(); // earlier strips must not be captured by the layer
    _groupKnockout.add(false);
    delegateBeginSoftMasked();
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
    flushPending(); // masked content strips land inside the content layer
    if (_groupKnockout.isNotEmpty) _groupKnockout.removeLast();
    delegateBeginSoftMaskComposite(
        luminosity: luminosity,
        backdrop: backdrop,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset);
    // The mask group's draws happen NOW and route through this device, so
    // they bin/flush between the composite halves on every subclass.
    drawMask();
    flushPending();
    delegateFinishSoftMaskComposite();
  }
}
