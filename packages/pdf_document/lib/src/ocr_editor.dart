part of 'editor.dart';

/// A single fragment of recognized text positioned in PDF user space -
/// the unit an OCR engine returns and [PdfOcrEditing.injectTextLayer]
/// writes onto a page.
///
/// The point of injecting these is to make a scanned (image-only) page
/// *selectable*, *searchable*, and *extractable* without changing how it
/// looks: each span is placed as invisible text (render mode 3, §9.4.3)
/// sitting exactly over the recognized word.
class PdfOcrSpan {
  const PdfOcrSpan({
    required this.text,
    required this.bounds,
    this.confidence = 1.0,
  });

  /// The recognized characters. Code points outside Latin-1 are written as
  /// `?` in the page content (the standard fonts the layer uses are
  /// byte-encoded), but the run still occupies [bounds] so selection and
  /// search highlighting line up with the word on the page.
  final String text;

  /// Where the text sits, in PDF user space (origin bottom-left, the same
  /// space the page's own content draws in). An engine working from a
  /// raster maps pixel boxes here via `PdfOcrPageImage.userSpaceRect`
  /// (dart_pdf_editor).
  final PdfRect bounds;

  /// Engine confidence in `[0, 1]`; 1 when the engine does not report one.
  final double confidence;
}

/// Writing an OCR text layer onto a page.
extension PdfOcrEditing on PdfEditor {
  /// Injects a text layer for page [pageIndex] from already-recognized
  /// [spans], returning how many were written.
  ///
  /// Each span becomes one text-showing operation, sized and horizontally
  /// scaled (`Tz`) so its selection box matches [PdfOcrSpan.bounds]: the
  /// font size is the box's extent across the reading direction and the
  /// run's em box - the conventional ascent/descent the selection and
  /// search code reconstructs - spans the box exactly.
  ///
  /// The run reads the way the page is *displayed*: on a page with /Rotate
  /// 90, 180, or 270 its text matrix is turned to match, so a word that
  /// reads left to right on screen gets a baseline running along user-space
  /// +y, -x, or -y respectively (the bounds stay axis-aligned in user
  /// space either way). By default the text is invisible (render mode 3,
  /// §9.4.3): it paints nothing but stays selectable, searchable, and
  /// extractable, exactly like the OCR layer Acrobat/Tesseract bury under a
  /// scan. Pass [visible] true to also paint it in [color] (debugging, or a
  /// deliberately burned-in layer).
  ///
  /// Spans below [minConfidence] or with no printable text are skipped.
  /// [font] picks which base-14 font carries the layer (Helvetica by
  /// default); it is embedded with explicit /Widths so this renderer and
  /// other viewers measure the spacing identically.
  ///
  /// The whole layer is wrapped in `q`/`Q`, so the invisible render mode
  /// and horizontal scaling cannot leak into the page's own content.
  int injectTextLayer(
    int pageIndex,
    Iterable<PdfOcrSpan> spans, {
    PdfStandardFont font = PdfStandardFont.helvetica,
    double minConfidence = 0,
    bool visible = false,
    int color = 0x000000,
  }) {
    final page = document.page(pageIndex);
    final accepted = [
      for (final span in spans)
        if (span.confidence >= minConfidence &&
            span.text.trim().isNotEmpty &&
            span.bounds.height > 0 &&
            span.bounds.width > 0)
          span,
    ];
    if (accepted.isEmpty) return 0;

    final fontName = _ensureOcrFont(page, font);
    final rotation = page.rotation;
    final writer = ContentWriter()..save();
    for (final span in accepted) {
      final box = span.bounds;
      // The box's extent across and along the visual reading direction:
      // on a quarter-turned page a word's on-screen width is user-space y.
      final quarter = rotation == 90 || rotation == 270;
      final size = quarter ? box.width : box.height;
      final length = quarter ? box.height : box.width;
      final natural = measureStandardText(span.text, size, font: font);
      // Horizontal scaling that stretches the run's natural length onto the
      // box - so the invisible selection box tracks the word.
      final scale = natural > 0 ? length / natural * 100 : 100.0;
      // The baseline sits a quarter em above the box's visual bottom edge,
      // so the em box (0.75 ascent, −0.25 descent) lands with the descent
      // on that edge and the ascent on the opposite one. The rotation is
      // the inverse of /Rotate's clockwise display turn.
      final descent = size * 0.25;
      final matrix = switch (rotation) {
        // Reads along +y, glyph tops toward −x: visual bottom is box.right.
        90 => [0.0, 1.0, -1.0, 0.0, box.right - descent, box.bottom],
        // Reads along −x, glyph tops toward −y: visual bottom is box.top.
        180 => [-1.0, 0.0, 0.0, -1.0, box.right, box.top - descent],
        // Reads along −y, glyph tops toward +x: visual bottom is box.left.
        270 => [0.0, -1.0, 1.0, 0.0, box.left + descent, box.top],
        _ => null,
      };
      writer
        ..beginText()
        ..op('Tr', [visible ? 0 : 3]);
      if (visible) writer.fillColor(color);
      writer
        ..font(fontName, size)
        ..op('Tz', [scale]);
      if (matrix == null) {
        writer.textAt(box.left, box.bottom + descent);
      } else {
        writer.op('Tm', matrix);
      }
      writer
        ..showText(span.text)
        ..endText();
    }
    writer.restore();
    _appendContent(pageIndex, page, writer.takeBytes());
    return accepted.length;
  }

  /// Ensures the page's /Font resources carry a WinAnsi base-14 [font] with
  /// explicit /Widths and returns its resource name, reusing a matching one
  /// this session already added.
  String _ensureOcrFont(PdfPage page, PdfStandardFont font) {
    final cos = document.cos;
    final resources = _ownResources(page);
    final existing = cos.resolve(resources['Font']);
    final CosDictionary fonts;
    if (existing is CosDictionary && resources['Font'] is! CosReference) {
      fonts = existing;
    } else {
      fonts = CosDictionary({
        if (existing is CosDictionary) ...existing.entries,
      });
      resources['Font'] = fonts;
    }

    final baseFont = CosName(font.baseFont);
    for (final entry in fonts.entries.entries) {
      final dict = cos.resolve(entry.value);
      // Reuse only a font shaped exactly like the one we write (explicit
      // 32–255 /Widths) so the interpreter measures spacing the way
      // [injectTextLayer] assumes; a stray document Helvetica without
      // /Widths would skew the selection boxes.
      if (dict is CosDictionary &&
          dict['BaseFont'] == baseFont &&
          dict['Subtype'] == const CosName('Type1') &&
          dict['Encoding'] == const CosName('WinAnsiEncoding') &&
          dict['FirstChar'] == const CosInteger(32) &&
          dict['LastChar'] == const CosInteger(255)) {
        return entry.key;
      }
    }

    var i = 1;
    while (fonts.containsKey('OcrF$i')) {
      i++;
    }
    final name = 'OcrF$i';
    fonts[name] = CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type1'),
      'BaseFont': baseFont,
      'Encoding': const CosName('WinAnsiEncoding'),
      'FirstChar': const CosInteger(32),
      'LastChar': const CosInteger(255),
      'Widths': CosArray([for (final w in font.widths) CosInteger(w)]),
    });
    _updater.markChanged(page.dict);
    return name;
  }
}
