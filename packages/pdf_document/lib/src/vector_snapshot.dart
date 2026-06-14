part of 'editor.dart';

/// A detached, **vector** copy of a rectangular region of a page — the page
/// content and resources under the region, resolved and copied inline so
/// the snapshot survives edits, undo, and even closing the source document.
///
/// It is the payload behind the Snapshot tool's "paste as vector":
/// [PdfVectorSnapshotEditing.pasteVectorSnapshot] re-materializes it onto
/// any page as a /Stamp annotation whose appearance *draws* the captured
/// graphics, so it stays sharp at any zoom (unlike a raster snapshot) and
/// stays movable/resizable/deletable like any annotation.
///
/// Capture with [PdfVectorSnapshotEditing.captureVectorSnapshot].
///
/// Page /Rotate is not baked in: the captured content keeps the source
/// page's native (unrotated) orientation.
class PdfVectorSnapshot {
  PdfVectorSnapshot._(this.region, this._content, this._resources);

  /// The captured region in the source page's user space (points, origin
  /// bottom-left).
  final PdfRect region;

  /// The source page's content streams, decoded and concatenated — the
  /// operators the appearance replays, clipped to [region] by the form's
  /// BBox.
  final Uint8List _content;

  /// The source page's /Resources, deep-copied inline (fonts, images,
  /// nested XObjects), detached from the source document.
  final CosDictionary _resources;
}

/// Capturing and pasting vector regions ([PdfVectorSnapshot]) — the vector
/// half of the Snapshot tool, complementing the raster capture in
/// `dart_pdf_editor`.
extension PdfVectorSnapshotEditing on PdfEditor {
  /// Captures [region] (the source page's user space) of page [pageIndex]
  /// as a detached vector snapshot. Read-only: the document is untouched.
  ///
  /// The whole page content travels with the snapshot; the region only
  /// becomes a clip when the snapshot is pasted (the form's BBox), so a
  /// capture is cheap and a paste shows exactly what was under the box.
  PdfVectorSnapshot captureVectorSnapshot(int pageIndex, PdfRect region) {
    final page = document.page(pageIndex);
    final content = page.contentBytes();
    final resources =
        _SnapshotCopier(document).copy(page.resources) as CosDictionary;
    return PdfVectorSnapshot._(region, content, resources);
  }

  /// Pastes [snapshot] onto page [pageIndex], scaled to fill [targetRect],
  /// as a /Stamp annotation whose appearance draws the captured graphics
  /// as vectors.
  ///
  /// The captured region becomes its own Form XObject — BBox = the source
  /// region, content = the page's operators — so it clips to the region;
  /// the annotation's appearance then maps that form onto [targetRect]
  /// (§12.5.5 identity, like an image stamp).
  void pasteVectorSnapshot(
    int pageIndex,
    PdfRect targetRect,
    PdfVectorSnapshot snapshot, {
    double opacity = 1,
    String? author,
    String? name,
  }) {
    final region = snapshot.region;
    if (region.width <= 0 || region.height <= 0) return;

    // the captured region as its own Form XObject: the BBox clips the page
    // content to the region, in the source page's user space
    final captured = CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Form'),
        'BBox': _rectArray(region),
        'Resources': _copyDetached(snapshot._resources) as CosDictionary,
        'Length': CosInteger(snapshot._content.length),
      }),
      Uint8List.fromList(snapshot._content),
    );
    // the resources hold fonts / images / nested forms as inline streams —
    // hoist them to indirect objects (§7.3.8) before the form references them
    _hoistStreams(captured.dictionary);
    final capturedRef = _updater.addObject(captured);

    // the appearance maps the region box onto the target rect, then draws
    // the captured form (which clips to its own BBox in source coordinates)
    final sx = targetRect.width / region.width;
    final sy = targetRect.height / region.height;
    final w = ContentWriter();
    final gs = _alphaState(opacity);
    if (gs != null) w.extGState('GS0');
    w
      ..save()
      ..concatMatrix(sx, 0, 0, sy, targetRect.left - sx * region.left,
          targetRect.bottom - sy * region.bottom)
      ..drawXObject('Cap')
      ..restore();
    _addAnnotation(
      pageIndex,
      _markupDict('Stamp', targetRect, 0x000000, null, author),
      _form(targetRect, w,
          resources: _resources(
              extGState: gs, xObject: CosDictionary({'Cap': capturedRef}))),
      name: name,
    );
  }
}
