part of 'editor.dart';

/// How [PdfPageResizing.resizePages] fits a page's existing content onto
/// its new paper size.
enum PdfPageResizeMode {
  /// Scale the visible page uniformly so it fits the new size, preserving
  /// its aspect ratio, and centre it - the "fit to paper" a print dialog
  /// does. Nothing is lost; a change of aspect ratio leaves margins.
  scaleToFit,

  /// Leave the content at its current size and centre it on the new
  /// paper - growing the page adds margins, shrinking it trims the edges.
  keepContentSize,
}

/// Changing a page's paper size.
extension PdfPageResizing on PdfEditor {
  /// Resizes the pages at [indices] to [width] × [height] points **as the
  /// page is displayed** - for a page turned 90° or 270° by /Rotate the
  /// width runs along its unrotated height, so "A4 landscape" means the
  /// same thing on every page whatever its rotation.
  ///
  /// The page's visible area (its crop box) is mapped onto the new paper
  /// by [mode] and centred. The existing content streams are left
  /// byte-identical: a `q cm … re W n` prologue and a `Q` epilogue wrap
  /// them, clipping to the old crop box so content that was cropped out
  /// stays hidden. The new media box starts at the origin and the crop box
  /// is set to it; /BleedBox, /TrimBox and /ArtBox follow the content and
  /// are clipped to the new paper (dropped when nothing of them remains).
  ///
  /// Annotations follow the content: /Rect and the point arrays that travel
  /// with it (/QuadPoints, /InkList, /L, /Vertices, /CL, /RD) are mapped by
  /// the same transform, and because it is uniform the §12.5.5 BBox→/Rect
  /// fit draws existing appearances exactly scaled. Explicit destinations
  /// that point into a resized page keep their old coordinates, so they
  /// may land slightly off on a scaled page.
  ///
  /// A page whose visible area already is the requested size at the origin
  /// is left untouched.
  void resizePages(
    Iterable<int> indices,
    double width,
    double height, {
    PdfPageResizeMode mode = PdfPageResizeMode.scaleToFit,
  }) {
    if (!(width > 0 && height > 0) || !width.isFinite || !height.isFinite) {
      throw ArgumentError(
          'page dimensions must be positive ($width × $height)');
    }
    final count = document.pageCount;
    final targets = {...indices};
    for (final i in targets) {
      RangeError.checkValidIndex(i, null, 'indices', count);
    }
    final changed = <int>[];
    for (final i in targets) {
      if (_resizePage(i, width, height, mode)) changed.add(i);
    }
    if (changed.isEmpty) return;
    document.invalidatePageCache();
    _markContent(changed);
    _markAnnotations(changed);
  }

  bool _resizePage(
    int index,
    double width,
    double height,
    PdfPageResizeMode mode,
  ) {
    final page = document.page(index);
    final quarter = page.rotation % 180 != 0;
    // the size in the page's own (unrotated) space
    final w = quarter ? height : width;
    final h = quarter ? width : height;
    final from = page.cropBox;
    final media = page.mediaBox;
    const epsilon = 1e-3;
    bool near(double a, double b) => (a - b).abs() < epsilon;
    if (near(from.left, 0) &&
        near(from.bottom, 0) &&
        near(from.width, w) &&
        near(from.height, h) &&
        near(media.left, 0) &&
        near(media.bottom, 0) &&
        near(media.width, w) &&
        near(media.height, h)) {
      return false;
    }
    if (from.width <= 0 || from.height <= 0) return false;

    final scale = switch (mode) {
      PdfPageResizeMode.scaleToFit => math.min(w / from.width, h / from.height),
      PdfPageResizeMode.keepContentSize => 1.0,
    };
    final dx = (w - from.width * scale) / 2 - from.left * scale;
    final dy = (h - from.height * scale) / 2 - from.bottom * scale;
    double mapX(double x) => x * scale + dx;
    double mapY(double y) => y * scale + dy;
    PdfRect mapRect(PdfRect r) =>
        PdfRect(mapX(r.left), mapY(r.bottom), mapX(r.right), mapY(r.top));

    // six decimals: ContentWriter.fmt's three would put a scale factor
    // ~0.3pt out across a page
    String f(double v) {
      if (v == v.roundToDouble() && v.abs() < 1e9) return '${v.toInt()}';
      var s = v.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
      return s == '-0' ? '0' : s;
    }

    final dict = page.dict;
    final cos = document.cos;

    // content: wrapped, never rewritten
    final existing = dict['Contents'];
    final items = switch (cos.resolve(existing)) {
      CosArray(:final items) => items,
      CosStream() => <CosObject>[existing!],
      _ => <CosObject>[],
    };
    final prologue = _updater.addObject(PdfContentEditing._stream(
      'q ${f(scale)} 0 0 ${f(scale)} ${f(dx)} ${f(dy)} cm '
      '${f(from.left)} ${f(from.bottom)} ${f(from.width)} ${f(from.height)} '
      're W n\n',
    ));
    final epilogue = _updater.addObject(PdfContentEditing._stream('\nQ\n'));
    dict['Contents'] = CosArray([prologue, ...items, epilogue]);

    // boxes
    final paper = PdfRect(0, 0, w, h);
    dict['MediaBox'] = _rectArray(paper);
    dict['CropBox'] = _rectArray(paper);
    for (final key in const ['BleedBox', 'TrimBox', 'ArtBox']) {
      final box = pdfRectFrom(cos, dict[key]);
      if (box == null) continue;
      final moved = mapRect(box).intersect(paper);
      if (moved.width > 0 && moved.height > 0) {
        dict[key] = _rectArray(moved);
      } else {
        dict.entries.remove(key);
      }
    }
    _updater.markChanged(dict);

    // annotations follow the content
    final seen = Set<CosDictionary>.identity();
    for (final annotation in page.annotations) {
      final a = annotation.dict;
      if (!seen.add(a)) continue;
      final rect = pdfRectFrom(cos, a['Rect']);
      if (rect != null) a['Rect'] = _rectArray(mapRect(rect));
      for (final key in const [
        'QuadPoints',
        'L',
        'Vertices',
        'CL',
        kPdfCalloutRegionKey,
      ]) {
        final mapped = _mapPoints(a[key], mapX, mapY);
        if (mapped != null) a[key] = mapped;
      }
      for (final key in const ['InkList', kPdfCalloutLeadersKey]) {
        final nested = cos.resolve(a[key]);
        if (nested is! CosArray) continue;
        a[key] = CosArray([
          for (final stroke in nested.items)
            _mapPoints(stroke, mapX, mapY) ?? stroke,
        ]);
      }
      // /RD insets are distances: scale only
      final rd = _mapPoints(a['RD'], (v) => v * scale, (v) => v * scale);
      if (rd != null) a['RD'] = rd;
      _markAnnotationChanged(index, a);
    }
    return true;
  }
}
