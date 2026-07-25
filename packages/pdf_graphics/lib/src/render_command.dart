import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'interpreter.dart' show PdfCancellationToken, PdfCancelledException;
import 'mesh.dart';
import 'path.dart';
import 'shading.dart';
import 'translating_device.dart';

/// A flattened, replayable record of one [PdfDevice] call.
///
/// The interpreter's output interface ([PdfDevice]) is 13 callbacks whose
/// arguments are almost entirely pure-Dart value types from `pdf_graphics`
/// ([PdfPath], [PdfColor], [PdfMatrix], [PdfStroke], [PdfGradient],
/// [PdfMesh], [PdfTextRun], …). A [RecordingPdfDevice] captures each call
/// verbatim as one of these records; [replayCommands] feeds them straight
/// back into another [PdfDevice] (the Flutter canvas device, a test
/// recorder, …). The interpreter, the device interface, and the canvas
/// device are unchanged - interpretation (the expensive parse + walk) and
/// painting are merely decoupled, which is the prerequisite for running the
/// interpret off the UI thread.
///
/// The command list is a flat sequence; the nesting of transparency groups
/// and `q`/`Q` is implicit in the open/close pairing, exactly as the canvas
/// device already tracks it. The one callback that carries control flow -
/// [PdfDevice.endSoftMasked]'s `drawMask` closure - stores the mask group's
/// own commands inline ([PdfEndSoftMaskedCommand.maskCommands]); replay
/// reconstructs the closure from them.
sealed class PdfRenderCommand {
  const PdfRenderCommand();
}

/// `q` - [PdfDevice.save].
class PdfSaveCommand extends PdfRenderCommand {
  const PdfSaveCommand();
}

/// `Q` - [PdfDevice.restore].
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

/// [PdfDevice.setOverprint].
class PdfSetOverprintCommand extends PdfRenderCommand {
  const PdfSetOverprintCommand(
      {required this.fill, required this.stroke, required this.mode});
  final bool fill;
  final bool stroke;
  final int mode;
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

/// A tiling-pattern (or Type3-glyph) cell recorded once and replayed at many
/// page-space positions (#524). [cellCommands] is the cell's full device
/// transcript at the base position; [originsX]/[originsY] are the page-space
/// deltas of every repeat, base first at (0, 0). Devices that understand the
/// command natively implement [PdfTiledCellSink] (a canvas backend can build
/// one sub-picture and stamp it per origin); everything else gets the exact
/// per-tile expansion from [replayCommands] via [TranslatingPdfDevice].
///
/// Keeping the cell nested instead of flattening it per tile is what shrinks
/// a hatched sheet's transcript from O(tiles x cell) to O(cell + tiles).
class PdfDrawTiledCellCommand extends PdfRenderCommand {
  const PdfDrawTiledCellCommand(this.cellCommands, this.originsX, this.originsY)
      : assert(originsX.length == originsY.length);
  final List<PdfRenderCommand> cellCommands;
  final Float64List originsX;
  final Float64List originsY;
}

/// Optional capability interface for devices that can consume a
/// [PdfDrawTiledCellCommand] natively instead of replaying its per-tile
/// expansion. The interpreter and [replayCommands] probe for it with `is`.
abstract interface class PdfTiledCellSink {
  void drawTiledCell(PdfDrawTiledCellCommand command);
}

/// Replays [commands] into [device], reproducing the original interpreter
/// callbacks in order. The dispatch is total over the [PdfRenderCommand]
/// hierarchy - adding a command without a case here is a compile error.
///
/// [start]/[end] replay only that index range (used by the cancellable
/// chunked replay below without copying slices of a 100k-command buffer).
void replayCommands(List<PdfRenderCommand> commands, PdfDevice device,
    {int start = 0, int? end}) {
  final stop = end ?? commands.length;
  for (var i = start; i < stop; i++) {
    final command = commands[i];
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
      case PdfSetOverprintCommand(:final fill, :final stroke, :final mode):
        device.setOverprint(fill: fill, stroke: stroke, mode: mode);
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
      case PdfDrawTiledCellCommand():
        if (device is PdfTiledCellSink) {
          (device as PdfTiledCellSink).drawTiledCell(command);
        } else {
          // Exact per-tile expansion: the base repeat replays verbatim,
          // every other repeat through a page-space translation wrapper.
          for (var t = 0; t < command.originsX.length; t++) {
            final dx = command.originsX[t], dy = command.originsY[t];
            replayCommands(
                command.cellCommands,
                dx == 0 && dy == 0
                    ? device
                    : TranslatingPdfDevice(device, dx, dy));
          }
        }
    }
  }
}

/// [replayCommands] in cooperative chunks: every [checkInterval] commands
/// it checks [cancellation] and yields to the event loop, so a message
/// (e.g. a render worker's cancel port) can preempt a long replay mid-walk
/// by throwing [PdfCancelledException] - the same scheme the interpreter's
/// async walk uses. Soft-mask groups replay atomically inside their
/// enclosing command.
Future<void> replayCommandsCancellable(
    List<PdfRenderCommand> commands, PdfDevice device,
    {PdfCancellationToken? cancellation, int checkInterval = 1024}) async {
  for (var i = 0; i < commands.length; i += checkInterval) {
    if (cancellation != null) {
      // Yield first so a cancel that arrived during the previous chunk gets
      // its listener run before the next chunk starts.
      await Future<void>.delayed(Duration.zero);
      if (cancellation.cancelled) throw const PdfCancelledException();
    }
    final end = i + checkInterval < commands.length
        ? i + checkInterval
        : commands.length;
    replayCommands(commands, device, start: i, end: end);
  }
}
