import 'package:pdf_document/pdf_document.dart';

import '../color.dart';
import '../device.dart';
import '../matrix.dart';
import '../mesh.dart';
import '../path.dart';
import '../render_command.dart';
import '../shading.dart';
import 'strip_binning_device.dart';
import 'strip_batch_data.dart';

/// Cheap, geometry-free estimate of how a command transcript fragments when
/// replayed through the sparse-strip device.
///
/// Every non-empty strip batch needs its own alpha-atlas upload. PDFs that
/// wrap each tiny shape in a clip can therefore be much slower through strips
/// than through the ordinary canvas even when their total command count is
/// high. This profile follows the strip device's exact painter-order routing
/// and flush state without flattening paths, generating coverage, or touching
/// a platform image codec.
class StripReplayProfile {
  const StripReplayProfile({
    required this.estimatedBatchCount,
    required this.flushPointCount,
    required this.delegatedPaintCount,
    required this.routedPaintCount,
  });

  factory StripReplayProfile.of(List<PdfRenderCommand> commands) {
    final profiler = _StripReplayProfiler();
    replayCommands(commands, profiler);
    return profiler.finish();
  }

  /// Flush intervals containing at least one strip-routed paint command.
  ///
  /// This can conservatively exceed a real plan's batch count when a path is
  /// empty or wholly outside the device viewport. It never performs geometry
  /// work merely to refine the estimate.
  final int estimatedBatchCount;

  /// Every painter-order flush point, including empty ones.
  final int flushPointCount;

  /// Paint commands that must use the ordinary device fallback.
  final int delegatedPaintCount;

  /// Fill, stroke, and outline-text commands eligible for strip routing.
  final int routedPaintCount;
}

class _StripReplayProfiler extends StripBinningDevice {
  _StripReplayProfiler()
      : super(
          pageToDevice: PdfMatrix.identity,
          deviceWidth: 1,
          deviceHeight: 1,
          pixelRatio: 1,
          binningEnabled: false,
        );

  var _pendingRoutedPaint = false;
  var _estimatedBatchCount = 0;
  var _routedPaintCount = 0;
  var _finished = false;

  void _markRoutedPaint() {
    _pendingRoutedPaint = true;
    _routedPaintCount++;
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    if (stripsActive && !delegateFills) _markRoutedPaint();
    super.fillPath(path, color, rule, alpha);
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    if (stripsActive && !delegateStrokes) _markRoutedPaint();
    super.strokePath(path, color, stroke, alpha);
  }

  @override
  void drawText(PdfTextRun run) {
    if (!run.invisible &&
        stripsActive &&
        !delegateText &&
        run.hasOutlines &&
        run.fill &&
        run.strokeColor == null &&
        run.gradient == null) {
      _markRoutedPaint();
    }
    super.drawText(run);
  }

  @override
  void emitBatch(int ordinal, StripBatchData? data) {
    if (_pendingRoutedPaint) _estimatedBatchCount++;
    _pendingRoutedPaint = false;
  }

  StripReplayProfile finish() {
    assert(!_finished, 'StripReplayProfile.finish() called twice');
    _finished = true;
    flushPending();
    return StripReplayProfile(
      estimatedBatchCount: _estimatedBatchCount,
      flushPointCount: flushPointCount,
      delegatedPaintCount: delegatedPaintCount,
      routedPaintCount: _routedPaintCount,
    );
  }

  @override
  void delegateSave() {}
  @override
  void delegateRestore() {}
  @override
  void delegateClipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void delegateSetBlendMode(PdfBlendMode mode) {}
  @override
  void delegateBeginGroup(double alpha, {required bool knockout}) {}
  @override
  void delegateEndGroup() {}
  @override
  void delegateBeginSoftMasked() {}
  @override
  void delegateBeginSoftMaskComposite({
    required bool luminosity,
    required PdfRect backdrop,
    required double backdropLuminance,
    required double transferScale,
    required double transferOffset,
  }) {}
  @override
  void delegateFinishSoftMaskComposite() {}
  @override
  void delegateFillPath(
      PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {}
  @override
  void delegateStrokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {}
  @override
  void delegateFillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {}
  @override
  void delegateFillMesh(PdfMesh mesh, double alpha) {}
  @override
  void delegateDrawText(PdfTextRun run) {}
  @override
  void delegateDrawImage(PdfImageRequest request) {}
}
