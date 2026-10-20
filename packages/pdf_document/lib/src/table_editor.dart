part of 'editor.dart';

extension PdfTableEditing on PdfEditor {
  void addTable(int pageIndex, PdfRect rect, PdfTableData table,
      {String? author}) {
    final (writer, fonts) =
        _tableAppearance(rect, table, _appearancePageRotation(pageIndex, null));
    final dict =
        _markupDict('Stamp', rect, table.borderColor, table.toTsv(), author)
          ..['DartPdfTable'] = CosString.fromText(jsonEncode(table.toJson()));
    _addAnnotation(pageIndex, dict,
        _form(rect, writer, resources: _resources(font: fonts)));
  }

  bool updateTable(
      int pageIndex, PdfAnnotation annotation, PdfTableData table) {
    if (annotation.table == null ||
        annotation.isLocked ||
        annotation.isReadOnly ||
        annotation.isLockedContents) {
      return false;
    }
    // Regenerate in the existing appearance's local frame. Reusing its BBox
    // and Matrix preserves rotation, mirroring and local-axis resizing.
    final previous = annotation.normalAppearance;
    final rect = previous == null
        ? annotation.rect
        : pdfRectFrom(document.cos, previous.dictionary['BBox']) ??
            annotation.rect;
    final (writer, fonts) =
        _tableAppearance(rect, table, _appearancePageRotation(pageIndex, null));
    final form = _form(rect, writer, resources: _resources(font: fonts));
    if (previous != null) {
      form.dictionary['Matrix'] = CosArray(
          [for (final n in _formMatrix(previous).toList()) CosReal(n)]);
    }
    annotation.dict
      ..['DartPdfTable'] = CosString.fromText(jsonEncode(table.toJson()))
      ..['Contents'] = CosString.fromText(table.toTsv())
      ..['AP'] = CosDictionary({'N': _updater.addObject(form)});
    _markAnnotationChanged(pageIndex, annotation.dict);
    return true;
  }

  (ContentWriter, CosDictionary) _tableAppearance(
      PdfRect rect, PdfTableData table, int rotation) {
    PdfTextFont font = PdfStandardFont.helvetica;
    if (table.cells
        .expand((r) => r)
        .any((s) => s.codeUnits.any((c) => c > 255))) {
      font = PdfUnicodeFont(PdfStandardFont.helvetica)..resetUsage();
    }
    final vr = PdfAnnotationEditing._orientedVisualRect(rect, rotation);
    final w = ContentWriter()..save();
    if (rotation != 0) {
      PdfAnnotationEditing._orientedCounterRotation(w, rect, rotation);
    }
    final sx = vr.width / table.width;
    final sy = vr.height / table.height;
    var top = vr.top;
    for (var r = 0; r < table.rowCount; r++) {
      final h = table.rowHeights[r] * sy;
      var left = vr.left;
      for (var c = 0; c < table.columnCount; c++) {
        final width = table.columnWidths[c] * sx;
        final cell = PdfRect(left, top - h, left + width, top);
        w.append(_freeTextContent(cell, table.cells[r][c],
            fontSize: table.fontSize * math.min(sx, sy),
            font: font,
            textDirection: PdfTextDirection.auto,
            color: table.textColor,
            fillColor: r == 0 && table.headerRow ? table.headerColor : 0xFFFFFF,
            borderColor: table.borderColor,
            borderWidth: .5));
        left += width;
      }
      top -= h;
    }
    w.restore();
    final fonts = font is PdfUnicodeFont
        ? font.buildResource(_updater.addObject)
        : _standardFont(PdfStandardFont.helvetica);
    return (w, fonts);
  }
}
