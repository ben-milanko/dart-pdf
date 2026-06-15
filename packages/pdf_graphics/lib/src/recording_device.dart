import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'mesh.dart';
import 'path.dart';
import 'render_command.dart';
import 'shading.dart';

/// A [PdfDevice] that records every interpreter callback into a flat,
/// replayable [commands] list instead of painting.
///
/// It performs no rendering and touches no `dart:ui`, so it can run anywhere
/// the interpreter does — including a background isolate, where the heavy
/// content-stream parse and walk happen — and its output ([commands]) is fed
/// back through [replayCommands] into a real painting device on the side that
/// owns the canvas. The recorded arguments are the interpreter's own value
/// types ([PdfPath], [PdfColor], [PdfTextRun], …), all immutable, so the list
/// is a faithful, side-effect-free transcript of the page.
///
/// Image requests are recorded verbatim ([PdfDrawImageCommand] keeps the
/// [PdfImageRequest], including its [CosStream]); the side that replays
/// decodes them as it does today. [imageRequests] exposes them in encounter
/// order for callers that want to drive decoding off the recording rather
/// than a separate scan pass.
class RecordingPdfDevice implements PdfDevice {
  /// The recorded top-level command sequence.
  final List<PdfRenderCommand> commands = [];

  /// Every image the page referenced, in the order the interpreter drew them
  /// (including those inside soft-mask groups). The same list the device's
  /// [drawImage] calls produced — useful for decoding ahead of replay.
  final List<PdfImageRequest> imageRequests = [];

  /// The list new commands append to. Normally [commands]; temporarily a
  /// soft mask's nested list while its `drawMask` closure runs.
  late List<PdfRenderCommand> _target = commands;

  @override
  void save() => _target.add(const PdfSaveCommand());

  @override
  void restore() => _target.add(const PdfRestoreCommand());

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) =>
      _target.add(PdfFillPathCommand(path, color, rule, alpha));

  @override
  void fillPathGradient(
          PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) =>
      _target.add(PdfFillPathGradientCommand(path, rule, gradient, alpha));

  @override
  void fillMesh(PdfMesh mesh, double alpha) =>
      _target.add(PdfFillMeshCommand(mesh, alpha));

  @override
  void strokePath(
          PdfPath path, PdfColor color, PdfStroke stroke, double alpha) =>
      _target.add(PdfStrokePathCommand(path, color, stroke, alpha));

  @override
  void clipPath(PdfPath path, PdfFillRule rule) =>
      _target.add(PdfClipPathCommand(path, rule));

  @override
  void drawText(PdfTextRun run) => _target.add(PdfDrawTextCommand(run));

  @override
  void drawImage(PdfImageRequest request) {
    imageRequests.add(request);
    _target.add(PdfDrawImageCommand(request));
  }

  @override
  void setBlendMode(PdfBlendMode mode) =>
      _target.add(PdfSetBlendModeCommand(mode));

  @override
  void beginGroup(double alpha, {bool knockout = false}) =>
      _target.add(PdfBeginGroupCommand(alpha, knockout: knockout));

  @override
  void endGroup() => _target.add(const PdfEndGroupCommand());

  @override
  void beginSoftMasked() => _target.add(const PdfBeginSoftMaskedCommand());

  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {
    // The captured content has already been recorded into the current target.
    // Divert the mask group's own painting into a nested list, then record the
    // end marker carrying it; replay rebuilds the drawMask closure from it.
    final maskCommands = <PdfRenderCommand>[];
    final saved = _target;
    _target = maskCommands;
    drawMask();
    _target = saved;
    _target.add(PdfEndSoftMaskedCommand(
      luminosity: luminosity,
      backdrop: backdrop,
      maskCommands: maskCommands,
      backdropLuminance: backdropLuminance,
      transferScale: transferScale,
      transferOffset: transferOffset,
    ));
  }
}
