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
    // Recover physical local dimensions, not the old BBox's pre-stretch size.
    // Unit-length basis vectors preserve rotation/mirroring without retaining
    // old non-uniform font scaling from tables resized by an earlier version.
    final quad = annotation.appearanceQuad;
    var rect = annotation.rect;
    PdfMatrix? matrix;
    if (quad != null) {
      final dx = quad[1].$1 - quad[0].$1;
      final dy = quad[1].$2 - quad[0].$2;
      final ux = quad[3].$1 - quad[0].$1;
      final uy = quad[3].$2 - quad[0].$2;
      final width = math.sqrt(dx * dx + dy * dy);
      final height = math.sqrt(ux * ux + uy * uy);
      if (width > 1e-9 && height > 1e-9) {
        rect = PdfRect(0, 0, width, height);
        matrix = PdfMatrix(dx / width, dy / width, ux / height, uy / height,
            quad[0].$1, quad[0].$2);
      }
    }
    final previous = annotation.normalAppearance;
    final bbox = previous == null
        ? null
        : pdfRectFrom(document.cos, previous.dictionary['BBox']);
    final baked = previous == null
        ? null
        : PdfAnnotationEditing(this)
            ._bakedFormMatrix(previous, annotation.rect);
    if (bbox != null &&
        baked != null &&
        (math.sqrt(baked.a * baked.a + baked.b * baked.b) - 1).abs() < 1e-6 &&
        (math.sqrt(baked.c * baked.c + baked.d * baked.d) - 1).abs() < 1e-6) {
      // Already unscaled: retain the exact frame instead of introducing new
      // serialized matrix rounding on every ordinary cell edit.
      rect = bbox;
      matrix = _formMatrix(previous!);
    }
    final rotation = _appearancePageRotation(pageIndex, null);
    table = _fitTableLayout(table, rect, rotation);
    final (writer, fonts) = _tableAppearance(rect, table, rotation);
    final form = _form(rect, writer, resources: _resources(font: fonts));
    if (matrix != null) {
      form.dictionary['Matrix'] =
          CosArray([for (final n in matrix.toList()) CosReal(n)]);
    }
    annotation.dict
      ..['DartPdfTable'] = CosString.fromText(jsonEncode(table.toJson()))
      ..['Contents'] = CosString.fromText(table.toTsv())
      ..['AP'] = CosDictionary({'N': _updater.addObject(form)});
    _markAnnotationChanged(pageIndex, annotation.dict);
    return true;
  }

  PdfTableData _fitTableLayout(PdfTableData table, PdfRect rect, int rotation) {
    final visual = PdfAnnotationEditing._orientedVisualRect(rect, rotation);
    return PdfTableData(table.cells,
        columnWidths: [
          for (final width in table.columnWidths)
            width * visual.width / table.width
        ],
        rowHeights: [
          for (final height in table.rowHeights)
            height * visual.height / table.height
        ],
        fontSize: table.fontSize,
        headerRow: table.headerRow,
        textColor: table.textColor,
        borderColor: table.borderColor,
        headerColor: table.headerColor);
  }

  bool _regenerateTableAppearance(
      PdfAnnotation annotation, PdfRect to, int rotation) {
    final table = annotation.table;
    final previous = annotation.normalAppearance;
    if (table == null || previous == null) return false;
    final layout = _fitTableLayout(table, to, rotation);
    final (writer, fonts) = _tableAppearance(to, layout, rotation);
    PdfAnnotationEditing(this)._replaceAppearance(
        annotation.dict, previous, to, writer,
        resources: _resources(font: fonts));
    annotation.dict['DartPdfTable'] =
        CosString.fromText(jsonEncode(layout.toJson()));
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
            fontSize: table.fontSize,
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
