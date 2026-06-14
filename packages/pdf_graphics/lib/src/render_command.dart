import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'mesh.dart';
import 'path.dart';
import 'shading.dart';

/// A flattened, replayable record of one [PdfDevice] call.
///
/// The interpreter's output interface ([PdfDevice]) is 13 callbacks whose
/// arguments are almost entirely pure-Dart value types from `pdf_graphics`
/// ([PdfPath], [PdfColor], [PdfMatrix], [PdfStroke], [PdfGradient],
/// [PdfMesh], [PdfTextRun], …). A [RecordingPdfDevice] captures each call
/// verbatim as one of these records; [replayCommands] feeds them straight
/// back into another [PdfDevice] (the Flutter canvas device, a test
/// recorder, …). The interpreter, the device interface, and the canvas
/// device are unchanged — interpretation (the expensive parse + walk) and
/// painting are merely decoupled, which is the prerequisite for running the
/// interpret off the UI thread.
///
/// The command list is a flat sequence; the nesting of transparency groups
/// and `q`/`Q` is implicit in the open/close pairing, exactly as the canvas
/// device already tracks it. The one callback that carries control flow —
/// [PdfDevice.endSoftMasked]'s `drawMask` closure — stores the mask group's
/// own commands inline ([PdfEndSoftMaskedCommand.maskCommands]); replay
/// reconstructs the closure from them.
sealed class PdfRenderCommand {
  const PdfRenderCommand();
}

/// `q` — [PdfDevice.save].
class PdfSaveCommand extends PdfRenderCommand {
  const PdfSaveCommand();
}

/// `Q` — [PdfDevice.restore].
class PdfRestoreCommand extends PdfRenderCommand {
  const PdfRestoreCommand();
}

/// [PdfDevice.fillPath].
class PdfFillPathCommand extends PdfRenderCommand {
  const PdfFillPathCommand(this.path, this.color, this.rule, this.alpha);
  final PdfPath path;
  final PdfColor color;
  final PdfFillRule rule;
  final double alpha;
}

/// [PdfDevice.fillPathGradient].
class PdfFillPathGradientCommand extends PdfRenderCommand {
  const PdfFillPathGradientCommand(
      this.path, this.rule, this.gradient, this.alpha);
  final PdfPath path;
  final PdfFillRule rule;
  final PdfGradient gradient;
  final double alpha;
}

/// [PdfDevice.fillMesh].
class PdfFillMeshCommand extends PdfRenderCommand {
  const PdfFillMeshCommand(this.mesh, this.alpha);
  final PdfMesh mesh;
  final double alpha;
}

/// [PdfDevice.strokePath].
class PdfStrokePathCommand extends PdfRenderCommand {
  const PdfStrokePathCommand(this.path, this.color, this.stroke, this.alpha);
  final PdfPath path;
  final PdfColor color;
  final PdfStroke stroke;
  final double alpha;
}

/// [PdfDevice.clipPath].
class PdfClipPathCommand extends PdfRenderCommand {
  const PdfClipPathCommand(this.path, this.rule);
  final PdfPath path;
  final PdfFillRule rule;
}

/// [PdfDevice.drawText].
class PdfDrawTextCommand extends PdfRenderCommand {
  const PdfDrawTextCommand(this.run);
  final PdfTextRun run;
}

/// [PdfDevice.drawImage].
class PdfDrawImageCommand extends PdfRenderCommand {
  const PdfDrawImageCommand(this.request);
  final PdfImageRequest request;
}

/// [PdfDevice.setBlendMode].
class PdfSetBlendModeCommand extends PdfRenderCommand {
  const PdfSetBlendModeCommand(this.mode);
  final PdfBlendMode mode;
}

/// [PdfDevice.beginGroup].
class PdfBeginGroupCommand extends PdfRenderCommand {
  const PdfBeginGroupCommand(this.alpha, {this.knockout = false});
  final double alpha;
  final bool knockout;
}

/// [PdfDevice.endGroup].
class PdfEndGroupCommand extends PdfRenderCommand {
  const PdfEndGroupCommand();
}

/// [PdfDevice.beginSoftMasked].
class PdfBeginSoftMaskedCommand extends PdfRenderCommand {
  const PdfBeginSoftMaskedCommand();
}

/// [PdfDevice.endSoftMasked]. The `drawMask` closure's device calls are
/// captured in [maskCommands]; replay rebuilds the closure as a nested
/// [replayCommands] over them.
class PdfEndSoftMaskedCommand extends PdfRenderCommand {
  const PdfEndSoftMaskedCommand({
    required this.luminosity,
    required this.backdrop,
    required this.maskCommands,
    this.backdropLuminance = 0,
    this.transferScale = 1,
    this.transferOffset = 0,
  });
  final bool luminosity;
  final PdfRect backdrop;
  final List<PdfRenderCommand> maskCommands;
  final double backdropLuminance;
  final double transferScale;
  final double transferOffset;
}

/// Replays [commands] into [device], reproducing the original interpreter
/// callbacks in order. The dispatch is total over the [PdfRenderCommand]
/// hierarchy — adding a command without a case here is a compile error.
void replayCommands(List<PdfRenderCommand> commands, PdfDevice device) {
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand():
        device.save();
      case PdfRestoreCommand():
        device.restore();
      case PdfFillPathCommand(:final path, :final color, :final rule, :final alpha):
        device.fillPath(path, color, rule, alpha);
      case PdfFillPathGradientCommand(
          :final path,
          :final rule,
          :final gradient,
          :final alpha
        ):
        device.fillPathGradient(path, rule, gradient, alpha);
      case PdfFillMeshCommand(:final mesh, :final alpha):
        device.fillMesh(mesh, alpha);
      case PdfStrokePathCommand(
          :final path,
          :final color,
          :final stroke,
          :final alpha
        ):
        device.strokePath(path, color, stroke, alpha);
      case PdfClipPathCommand(:final path, :final rule):
        device.clipPath(path, rule);
      case PdfDrawTextCommand(:final run):
        device.drawText(run);
      case PdfDrawImageCommand(:final request):
        device.drawImage(request);
      case PdfSetBlendModeCommand(:final mode):
        device.setBlendMode(mode);
      case PdfBeginGroupCommand(:final alpha, :final knockout):
        device.beginGroup(alpha, knockout: knockout);
      case PdfEndGroupCommand():
        device.endGroup();
      case PdfBeginSoftMaskedCommand():
        device.beginSoftMasked();
      case PdfEndSoftMaskedCommand(
          :final luminosity,
          :final backdrop,
          :final maskCommands,
          :final backdropLuminance,
          :final transferScale,
          :final transferOffset
        ):
        device.endSoftMasked(
          luminosity: luminosity,
          backdrop: backdrop,
          backdropLuminance: backdropLuminance,
          transferScale: transferScale,
          transferOffset: transferOffset,
          drawMask: () => replayCommands(maskCommands, device),
        );
    }
  }
}
