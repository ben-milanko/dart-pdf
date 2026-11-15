import 'device.dart';
import 'render_command.dart';

/// Appends to [out] every image a tiled cell's [commands] draw, depth-first -
/// through soft masks and nested cells - in the order the wire codec
/// serializes them.
///
/// This is the order a recorder's `imageRequests` and a wire transcript's
/// images are paired in, so every place that lists a cell's images goes
/// through here.
void addCellImageRequests(
    List<PdfRenderCommand> commands, List<PdfImageRequest> out) {
  for (var i = 0; i < commands.length; i++) {
    final c = commands[i];
    if (c is PdfDrawImageCommand) {
      out.add(c.request);
    } else if (c is PdfEndSoftMaskedCommand) {
      addCellImageRequests(c.maskCommands, out);
    } else if (c is PdfDrawTiledCellCommand) {
      addCellImageRequests(c.cellCommands, out);
    }
  }
}
