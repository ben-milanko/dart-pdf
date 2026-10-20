part of 'editor.dart';

/// Paints a solid page background into the document itself - the baked form
/// of a viewer's display-only paper colour, so other readers show it too.
extension PdfPageBackgroundEditing on PdfEditor {
  /// The first line of every background stream [fillPageBackground] writes.
  /// A content-stream comment (§7.2.4), so readers ignore it; it is how a
  /// later fill finds and replaces an earlier one instead of stacking a
  /// second rectangle under it.
  static const backgroundMarker = '%DartPdfPageBackground';

  /// Fills every page from [fromPage] to [toPage] inclusive (defaults: the
  /// whole document) with [color] (`0xRRGGBB`) **behind** its existing
  /// content - a stream at the front of /Contents filling the media box,
  /// tagged `/Artifact <</Type /Background>>` so tagged-PDF readers skip it.
  ///
  /// A page that already carries a background written by this method has
  /// that stream replaced, so re-baking another colour never accumulates
  /// rectangles. Pure white is still written when asked for: it is what
  /// replaces an earlier tint.
  void fillPageBackground(int color, {int fromPage = 0, int? toPage}) {
    if (document.pageCount == 0) return;
    final first = fromPage.clamp(0, document.pageCount - 1);
    final last =
        (toPage ?? document.pageCount - 1).clamp(0, document.pageCount - 1);
    final r = ((color >> 16) & 0xFF) / 255;
    final g = ((color >> 8) & 0xFF) / 255;
    final b = (color & 0xFF) / 255;
    String f(double v) => ContentWriter.fmt(v);
    final cos = document.cos;
    for (var i = first; i <= last; i++) {
      final page = document.page(i);
      final box = page.mediaBox;
      final text = '$backgroundMarker\n'
          '/Artifact <</Type /Background>> BDC\n'
          'q ${f(r)} ${f(g)} ${f(b)} rg '
          '${f(box.left)} ${f(box.bottom)} ${f(box.width)} ${f(box.height)} '
          're f Q\nEMC\n';
      final fill = _updater.addObject(PdfContentEditing._stream(text));
      final dict = page.dict;
      final existing = dict['Contents'];
      final items = switch (cos.resolve(existing)) {
        CosArray(:final items) => items,
        CosStream() => <CosObject>[existing!],
        _ => <CosObject>[],
      };
      final next = List<CosObject>.of(items);
      if (next.isNotEmpty && _isBackgroundStream(cos.resolve(next.first))) {
        next[0] = fill;
      } else {
        next.insert(0, fill);
      }
      dict['Contents'] = CosArray(next);
      _updater.markChanged(dict);
      _markContent([i]);
    }
  }

  static bool _isBackgroundStream(CosObject? object) {
    if (object is! CosStream || object.dictionary['Filter'] != null) {
      return false;
    }
    final marker = PdfPageBackgroundEditing.backgroundMarker;
    final bytes = object.rawBytes;
    if (bytes.length < marker.length) return false;
    for (var i = 0; i < marker.length; i++) {
      if (bytes[i] != marker.codeUnitAt(i)) return false;
    }
    return true;
  }
}
