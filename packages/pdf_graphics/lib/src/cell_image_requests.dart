import 'device.dart';
import 'render_command.dart';

/// Which tiled cells a recorder has already listed the images of, by the
/// identity of their command list.
typedef ListedCells = Set<List<PdfRenderCommand>>;

ListedCells newListedCells() => Set<List<PdfRenderCommand>>.identity();

/// Appends to [out] the images [stamp] adds to a recorder's
/// `imageRequests`: the cell's images, depth-first through soft masks and
/// nested cells - the first time this cell is seen, and nothing after that.
///
/// A cell is its command list, by identity. That is exactly how the wire codec
/// shares one (`_writeTiledCellReference`): the first stamp writes the cell's
/// body, images included, and every later stamp of the same list is a
/// back-reference that writes none. So `imageRequests` and a wire transcript's
/// images stay in step, one for one, which is what
/// `compactTranscriptSourceCommands` pairs them by.
///
/// It used to be once per stamp. The interpreter stamps a Type3 glyph cell per
/// letter, so a page of bitmap-font text listed each glyph's image thousands
/// of times (35,128 entries for 156 images over one six-page document), and
/// everything that walks the list paid for it.
void addStampedCellImageRequests(PdfDrawTiledCellCommand stamp,
    List<PdfImageRequest> out, ListedCells listed) {
  // The interpreter stamps a Type3 glyph cell once per letter, so this runs
  // tens of thousands of times a page and all but a few hundred of them are
  // repeats. Those stamps carry a share, and a share remembers who listed it
  // last: one comparison, where looking the list up in [listed] was a tenth
  // of recording a bitmap-font page.
  final share = stamp.share;
  if (share != null) {
    if (identical(share.listedIn, listed)) return;
    share.listedIn = listed;
  }
  final cell = stamp.cellCommands;
  if (!listed.add(cell)) return;
  _addImageRequests(cell, out, listed);
}

void _addImageRequests(List<PdfRenderCommand> commands,
    List<PdfImageRequest> out, ListedCells listed) {
  for (var i = 0; i < commands.length; i++) {
    final c = commands[i];
    if (c is PdfDrawImageCommand) {
      out.add(c.request);
    } else if (c is PdfEndSoftMaskedCommand) {
      // A soft mask's commands are written in full wherever they appear;
      // only the cells inside them are shared.
      _addImageRequests(c.maskCommands, out, listed);
    } else if (c is PdfDrawTiledCellCommand) {
      addStampedCellImageRequests(c, out, listed);
    }
  }
}
