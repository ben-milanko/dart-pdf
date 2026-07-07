part of 'editor.dart';

/// AcroForm text-field appearance styling (§12.7.3.3): changing a text
/// field's font, size, colour, alignment, auto-size, and multiline, then
/// regenerating its appearance so it looks identical here and in other
/// viewers (no /NeedAppearances dependency).
///
/// The font may be a base-14 [PdfStandardFont] - written into the form /DR
/// as a Type1 face every viewer has - or a [PdfEmbeddedFont], embedded as a
/// Type0 face so the value shows the same everywhere. Either way the
/// appearance is rebuilt by [PdfFormFilling], which now reads the /DR font
/// back to decide the simple-byte vs Type0 show path.
extension PdfFormStyling on PdfEditor {
  /// Restyles text [field]: every non-null argument is applied and the rest
  /// left as they are, then the appearance regenerates from the field's
  /// current value.
  ///
  /// [font] is a base-14 [PdfStandardFont] or an embedded [PdfEmbeddedFont].
  /// [fontSize] is in points; pass 0 or [autoSize] `true` to fit the text to
  /// the box (the §12.7.3.3 auto-size convention). [color] is `0xRRGGBB`.
  /// [align] writes /Q (left/centre/right). [multiline] toggles the /Ff
  /// multiline flag (bit 13). Throws when [field] isn't a text field or is
  /// read-only.
  void setTextFieldStyle(
    PdfFormField field, {
    PdfTextFont? font,
    double? fontSize,
    bool? autoSize,
    int? color,
    PdfTextAlign? align,
    bool? multiline,
  }) {
    _checkFillable(field, const {PdfFieldType.text});

    if (multiline != null && multiline != field.isMultiline) {
      field.dict['Ff'] = CosInteger(multiline
          ? field.flags | PdfFormField.multilineFlag
          : field.flags & ~PdfFormField.multilineFlag);
    }
    if (align != null) field.dict['Q'] = CosInteger(align.quadding);

    if (font != null || fontSize != null || autoSize != null || color != null) {
      final current = _parseDefaultAppearance(field.defaultAppearance);
      final name =
          font == null ? current.fontName : _ensureDrFont(field.form, font);
      final size = autoSize == true ? 0.0 : (fontSize ?? current.fontSize);
      final colorOps = color != null ? _daColorOps(color) : current.colorOps;
      field.dict['DA'] =
          CosString.fromText('/$name ${_formatDaNumber(size)} Tf $colorOps');
    }

    _regenerateVariableText(field, field.value ?? '');
    _finishFieldEdit(field);
  }

  /// Ensures [font] lives in the form /DR /Font and returns the resource
  /// name /DA should reference it by. Base-14 faces reuse their conventional
  /// short name ([PdfStandardFont.resourceName]); embedded fonts are written
  /// as a Type0 face under a fresh `FF<n>` key.
  String _ensureDrFont(PdfAcroForm form, PdfTextFont font) {
    final cos = document.cos;
    final (:fonts, :dr) = _formDrFonts(form);
    String name;
    if (font is PdfStandardFont) {
      name = font.resourceName;
      if (cos.resolve(fonts[name]) is! CosDictionary) {
        fonts[name] = _updater.addObject(CosDictionary({
          'Type': const CosName('Font'),
          'Subtype': const CosName('Type1'),
          'BaseFont': CosName(font.baseFont),
          'Encoding': const CosName('WinAnsiEncoding'),
        }));
        _stageFormResources(form, fonts, dr);
      }
    } else if (font is PdfEmbeddedFont) {
      var i = 0;
      while (fonts.containsKey('FF$i')) {
        i++;
      }
      name = 'FF$i';
      // buildResource registers the descendant/descriptor/program/ToUnicode
      // as indirect objects and returns { resourceName: <Type0 dict> }; we
      // re-key the Type0 under our fresh name (the appearance re-parses the
      // program from here on every fill, so its key need only match /DA).
      final type0 = font.buildResource(_updater.addObject).entries.values.first;
      fonts[name] = _updater.addObject(type0);
      _stageFormResources(form, fonts, dr);
    } else {
      // an unknown PdfTextFont implementation: fall back to the base face
      return _ensureDrFont(form, PdfStandardFont.helvetica);
    }
    return name;
  }

  /// The form's /DR /Font dictionary, creating /DR and /Font when absent.
  ({CosDictionary fonts, CosDictionary dr}) _formDrFonts(PdfAcroForm form) {
    final cos = document.cos;
    var dr = cos.resolve(form.dict['DR']);
    if (dr is! CosDictionary) {
      dr = CosDictionary({});
      form.dict['DR'] = dr;
    }
    var fonts = cos.resolve(dr['Font']);
    if (fonts is! CosDictionary) {
      fonts = CosDictionary({});
      dr['Font'] = fonts;
    }
    return (fonts: fonts, dr: dr);
  }

  /// Stages the nearest indirect object carrying a /DR /Font mutation: the
  /// font dict, the /DR dict, the form dict, or finally the catalog -
  /// mirroring [_stageFormDict] for form-level (non-field) resources.
  void _stageFormResources(
      PdfAcroForm form, CosDictionary fonts, CosDictionary dr) {
    final cos = document.cos;
    for (final node in [fonts, dr, form.dict]) {
      final ref = cos.referenceTo(node);
      if (ref != null) {
        _updater.replaceObject(ref.objectNumber, node);
        return;
      }
    }
    _updater.markChanged(document.catalog);
  }

  /// `r g b rg` operators for a 0xRRGGBB colour.
  String _daColorOps(int rgb) {
    double channel(int shift) => ((rgb >> shift) & 0xFF) / 255.0;
    final r = _formatDaNumber(channel(16));
    final g = _formatDaNumber(channel(8));
    final b = _formatDaNumber(channel(0));
    return '$r $g $b rg';
  }

  /// Formats a /DA number without a trailing `.0` or dangling zeros.
  String _formatDaNumber(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
