part of 'editor.dart';

/// AcroForm filling (§12.7): setters write the field /V and regenerate
/// each widget's appearance stream, so the filled value displays the same
/// in this renderer and in other viewers without /NeedAppearances.
///
/// Fields come from [PdfAcroForm.of] on the editor's document; edits are
/// staged on the editor and written by [PdfEditor.save].
extension PdfFormFilling on PdfEditor {
  /// The document's form, or null if it has none.
  PdfAcroForm? get acroForm => PdfAcroForm.of(document);

  /// Sets a text field's value and regenerates its appearance: wrapped
  /// for multiline fields, auto-sized when the /DA font size is 0, and
  /// aligned per /Q quadding.
  ///
  /// [multiline] toggles the field's multiline flag (/Ff bit 13) before
  /// the appearance regenerates — pass true to let long values wrap in
  /// fields authored as single-line. Null leaves the flag alone.
  ///
  /// /V stores [value] verbatim (UTF-16BE when it leaves Latin-1); the
  /// generated appearance replaces characters the byte-encoded
  /// appearance fonts cannot show with spaces.
  void setTextValue(PdfFormField field, String value, {bool? multiline}) {
    _checkFillable(field, const {PdfFieldType.text});
    if (multiline != null && multiline != field.isMultiline) {
      field.dict['Ff'] = CosInteger(multiline
          ? field.flags | PdfFormField.multilineFlag
          : field.flags & ~PdfFormField.multilineFlag);
    }
    field.dict['V'] = CosString.fromText(value);
    _regenerateVariableText(field, value);
    _finishFieldEdit(field);
  }

  /// Fills a push-button field with an image (the conventional way PDF
  /// forms carry signatures and logos): each widget's normal appearance
  /// becomes the image scaled to fit its rectangle, centered, over the
  /// widget's /MK background and border.
  void setButtonImage(PdfFormField field, PdfEmbeddableImage image) {
    _checkFillable(field, const {PdfFieldType.pushButton});
    final imageRef = _updater
        .addObject(image.toXObject((smask) => _updater.addObject(smask)));
    for (final widget in field.widgets) {
      final rect = pdfRectFrom(document.cos, widget['Rect']);
      if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
      final w = rect.width, h = rect.height;
      final scale = math.min(w / image.width, h / image.height);
      final dw = image.width * scale, dh = image.height * scale;

      final writer = ContentWriter();
      _paintWidgetDecorations(writer, widget, w, h);
      writer
        ..save()
        ..concatMatrix(dw, 0, 0, dh, (w - dw) / 2, (h - dh) / 2)
        ..drawXObject('Img0')
        ..restore();

      final form = _widgetForm(w, h, writer,
          resources:
              CosDictionary({'XObject': CosDictionary({'Img0': imageRef})}));
      _setNormalAppearance(widget, form);
      if (!identical(widget, field.dict)) _stageFormDict(field, widget);
    }
    _finishFieldEdit(field);
  }

  /// Checks or unchecks a check box. Widgets without /AP states get
  /// generated check-mark appearances.
  void setCheckBoxValue(PdfFormField field, bool checked) {
    _checkFillable(field, const {PdfFieldType.checkBox});
    _ensureButtonAppearances(field);
    final on = field.onStates.isEmpty ? 'Yes' : field.onStates.first;
    _selectButtonState(field, checked ? on : 'Off');
  }

  /// Selects radio button [onState] (one of [PdfFormField.onStates]), or
  /// clears the group with 'Off'.
  void setRadioValue(PdfFormField field, String onState) {
    _checkFillable(field, const {PdfFieldType.radioGroup});
    if (onState != 'Off' && !field.onStates.contains(onState)) {
      throw ArgumentError.value(onState, 'onState',
          'not an option of "${field.name}" (${field.onStates.join(', ')})');
    }
    _selectButtonState(field, onState);
  }

  /// Sets a combo or list box to the option matching [value] (export or
  /// display form). Combo boxes with the Edit flag accept free text.
  void setChoiceValue(PdfFormField field, String value) {
    _checkFillable(
        field, const {PdfFieldType.comboBox, PdfFieldType.listBox});
    final options = field.options;
    var display = value;
    var export = value;
    var index = -1;
    for (var i = 0; i < options.length; i++) {
      if (options[i].$1 == value || options[i].$2 == value) {
        (export, display) = options[i];
        index = i;
        break;
      }
    }
    final editable = field.type == PdfFieldType.comboBox &&
        field.flags & PdfFormField.editFlag != 0;
    if (index < 0 && options.isNotEmpty && !editable) {
      throw ArgumentError.value(value, 'value',
          'not an option of "${field.name}" '
          '(${options.map((o) => o.$1).join(', ')})');
    }
    field.dict['V'] = CosString.fromText(export);
    if (field.type == PdfFieldType.listBox && index >= 0) {
      field.dict['I'] = CosArray([CosInteger(index)]);
    }
    _regenerateVariableText(field, display);
    _finishFieldEdit(field);
  }

  // ---------------------------------------------------------------------
  // buttons

  void _selectButtonState(PdfFormField field, String state) {
    field.dict['V'] = CosName(state);
    for (final widget in field.widgets) {
      final has = _widgetStates(widget).contains(state);
      widget['AS'] = CosName(has ? state : 'Off');
      if (!identical(widget, field.dict)) _stageFormDict(field, widget);
    }
    _finishFieldEdit(field);
  }

  List<String> _widgetStates(CosDictionary widget) {
    final cos = document.cos;
    final ap = cos.resolve(widget['AP']);
    if (ap is! CosDictionary) return const [];
    final n = cos.resolve(ap['N']);
    if (n is! CosDictionary) return const [];
    return n.entries.keys.toList();
  }

  /// Generates /AP on/off states for button widgets that lack them, so a
  /// checked box is visible everywhere. Existing states are kept.
  void _ensureButtonAppearances(PdfFormField field) {
    final on = field.onStates.isEmpty ? 'Yes' : field.onStates.first;
    for (final widget in field.widgets) {
      if (_widgetStates(widget).isNotEmpty) continue;
      final rect = pdfRectFrom(document.cos, widget['Rect']);
      if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
      final w = rect.width, h = rect.height;

      ContentWriter background() {
        final writer = ContentWriter();
        _paintWidgetDecorations(writer, widget, w, h);
        return writer;
      }

      final off = background();
      final onWriter = background();
      _paintCheckMark(onWriter, w, h);

      widget['AP'] = CosDictionary({
        'N': CosDictionary({
          on: _updater.addObject(_widgetForm(w, h, onWriter)),
          'Off': _updater.addObject(_widgetForm(w, h, off)),
        }),
      });
    }
  }

  /// Strokes the standard check mark filling a [w]×[h] box (§12.7.4.2.3),
  /// shared by check-box generation and resize regeneration.
  void _paintCheckMark(ContentWriter writer, double w, double h) {
    final weight = (w < h ? w : h) * 0.12;
    writer
      ..strokeColor(0x000000)
      ..lineWidth(weight < 1 ? 1 : weight)
      ..roundLines()
      ..moveTo(w * 0.22, h * 0.52)
      ..lineTo(w * 0.42, h * 0.30)
      ..lineTo(w * 0.78, h * 0.72)
      ..stroke();
  }

  /// Rebuilds [widget]'s /AP /N on/off states at its current /Rect,
  /// preserving the existing state names (so a radio button keeps its
  /// export value). Used when a button widget is resized — unlike
  /// [_ensureButtonAppearances], it regenerates states that already
  /// exist so the mark refits the new box.
  void _regenerateButtonStates(PdfFormField field, CosDictionary widget) {
    final rect = pdfRectFrom(document.cos, widget['Rect']);
    if (rect == null || rect.width <= 0 || rect.height <= 0) return;
    final w = rect.width, h = rect.height;
    final names = _widgetStates(widget).toSet();
    if (!names.any((s) => s != 'Off')) {
      names.add(field.onStates.isEmpty ? 'Yes' : field.onStates.first);
    }
    names.add('Off');

    ContentWriter background() {
      final writer = ContentWriter();
      _paintWidgetDecorations(writer, widget, w, h);
      return writer;
    }

    final n = CosDictionary({});
    for (final state in names) {
      final writer = background();
      if (state != 'Off') _paintCheckMark(writer, w, h);
      n[state] = _updater.addObject(_widgetForm(w, h, writer));
    }
    widget['AP'] = CosDictionary({'N': n});
  }

  /// The display form of a choice field's current /V (matching an /Opt
  /// export), or the raw value, or '' when unset.
  String _choiceDisplay(PdfFormField field) {
    final value = field.value;
    if (value == null) return '';
    for (final (export, display) in field.options) {
      if (export == value) return display;
    }
    return value;
  }

  /// Resizes one widget of [fieldName] (index [widgetIndex] within the
  /// field) so its /Rect becomes [to], regenerating the widget's
  /// appearance at the new size instead of stretching it: text and
  /// choice fields re-lay their value, check boxes and radio buttons
  /// redraw their mark. Push-button, signature, and unknown fields keep
  /// their appearance — only the /Rect moves. A no-op when the field or
  /// widget index is missing.
  ///
  /// Used by the editing UI's form tool when a field's resize handle is
  /// dragged; the field is re-resolved by name inside the save so it
  /// survives the per-revision teardown.
  void resizeFormWidget(String fieldName, int widgetIndex, PdfRect to) {
    final field = acroForm?.fieldNamed(fieldName);
    if (field == null) return;
    final widgets = field.widgets;
    if (widgetIndex < 0 || widgetIndex >= widgets.length) return;
    final widget = widgets[widgetIndex];
    widget['Rect'] = CosArray([
      CosReal(to.left),
      CosReal(to.bottom),
      CosReal(to.right),
      CosReal(to.top),
    ]);
    switch (field.type) {
      case PdfFieldType.text:
        _regenerateVariableText(field, field.value ?? '');
      case PdfFieldType.comboBox:
      case PdfFieldType.listBox:
        _regenerateVariableText(field, _choiceDisplay(field));
      case PdfFieldType.checkBox:
      case PdfFieldType.radioGroup:
        _regenerateButtonStates(field, widget);
      case PdfFieldType.pushButton:
      case PdfFieldType.signature:
      case PdfFieldType.unknown:
        break; // /Rect moved; the appearance is left intact
    }
    if (!identical(widget, field.dict)) _stageFormDict(field, widget);
    _finishFieldEdit(field);
  }

  // ---------------------------------------------------------------------
  // variable text (§12.7.3.3)

  /// The appearance fonts are byte-encoded simple fonts, so code units
  /// past 0xFF can never reach the page — swap them for spaces (the
  /// trax/desktop-filler convention) instead of letting the writer
  /// emit '?'. /V keeps the original text.
  static String sanitizeFieldText(String text) {
    if (text.codeUnits.every((c) => c <= 0xFF)) return text;
    return String.fromCharCodes(
        [for (final c in text.codeUnits) c <= 0xFF ? c : 0x20]);
  }

  void _regenerateVariableText(PdfFormField field, String rawText) {
    final text = sanitizeFieldText(rawText);
    final cos = document.cos;
    final da = _parseDefaultAppearance(field.defaultAppearance);
    final fontDict = _formFont(field.form, da.fontName);

    for (final widget in field.widgets) {
      final rect = pdfRectFrom(cos, widget['Rect']);
      if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
      final w = rect.width, h = rect.height;
      const pad = 2.0;

      double measure(String s, double size) =>
          _measureFieldText(fontDict, s, size);

      final multiline = field.isMultiline;
      var size = da.fontSize;
      List<String> lines;
      if (multiline) {
        if (size == 0) {
          // auto-size: shrink until the wrapped block fits the height
          size = 12;
          while (size > 4) {
            lines = _wrapWith(measure, text, size, w - 2 * pad);
            if (lines.length * size * 1.15 <= h - 2 * pad) break;
            size -= 0.5;
          }
        }
        lines = _wrapWith(measure, text, size, w - 2 * pad);
      } else {
        final single = text.replaceAll('\n', ' ');
        if (size == 0) {
          size = (h - 2 * pad) / 1.15;
          final width = measure(single, size);
          if (width > w - 2 * pad && width > 0) {
            size *= (w - 2 * pad) / width;
          }
          size = size.clamp(4.0, 144.0);
        }
        lines = [single];
      }

      final writer = ContentWriter()..raw('/Tx BMC');
      writer.save();
      _paintWidgetDecorations(writer, widget, w, h);
      writer
        ..rect(1, 1, w - 2, h - 2)
        ..clip()
        ..beginText();
      if (da.colorOps.isNotEmpty) writer.raw(da.colorOps);
      writer.font(da.fontName, size);

      // first baseline: vertically centered for one line, top-anchored
      // for multiline (Helvetica-class ascent is 0.718 em)
      final ascent = size * 0.718;
      var prevX = 0.0;
      var prevY = 0.0;
      final firstY = multiline
          ? h - pad - ascent
          : ((h - ascent) / 2 < pad ? pad : (h - ascent) / 2);
      for (var i = 0; i < lines.length; i++) {
        final lineWidth = measure(lines[i], size);
        final x = switch (field.quadding) {
          1 => (w - lineWidth) / 2 < pad ? pad : (w - lineWidth) / 2,
          2 => w - pad - lineWidth < pad ? pad : w - pad - lineWidth,
          _ => pad,
        };
        final y = firstY - i * size * 1.15;
        writer
          ..textAt(x - prevX, y - prevY)
          ..showText(lines[i]);
        prevX = x;
        prevY = y;
      }
      writer
        ..endText()
        ..restore()
        ..raw('EMC');

      final resources = CosDictionary({
        'Font': _appearanceFontResource(field.form, da.fontName, fontDict),
      });
      final form = _widgetForm(w, h, writer, resources: resources);
      _setNormalAppearance(widget, form);
      if (!identical(widget, field.dict)) _stageFormDict(field, widget);
    }
  }

  /// Background and border from the widget's /MK appearance
  /// characteristics (§12.5.6.19), drawn in form space.
  void _paintWidgetDecorations(
      ContentWriter writer, CosDictionary widget, double w, double h) {
    final cos = document.cos;
    final mk = cos.resolve(widget['MK']);
    if (mk is! CosDictionary) return;
    final bg = _mkColor(mk['BG']);
    if (bg != null) {
      writer
        ..fillColor(bg)
        ..rect(0, 0, w, h)
        ..fill();
    }
    final bc = _mkColor(mk['BC']);
    if (bc != null) {
      var width = 1.0;
      final bs = cos.resolve(widget['BS']);
      if (bs is CosDictionary) {
        final bw = cos.resolve(bs['W']);
        if (bw is CosInteger) width = bw.value.toDouble();
        if (bw is CosReal) width = bw.value;
      }
      if (width > 0) {
        writer
          ..strokeColor(bc)
          ..lineWidth(width)
          ..rect(width / 2, width / 2, w - width, h - width)
          ..stroke();
      }
    }
  }

  /// /MK colors: an array of 1 (gray), 3 (RGB), or 4 (CMYK) components.
  int? _mkColor(CosObject? raw) {
    final cos = document.cos;
    final array = cos.resolve(raw);
    if (array is! CosArray) return null;
    final values = <double>[];
    for (final item in array.items) {
      final n = cos.resolve(item);
      if (n is CosInteger) {
        values.add(n.value.toDouble());
      } else if (n is CosReal) {
        values.add(n.value);
      } else {
        return null;
      }
    }
    final (r, g, b) = switch (values.length) {
      1 => (values[0], values[0], values[0]),
      3 => (values[0], values[1], values[2]),
      4 => (
          (1 - values[0]) * (1 - values[3]),
          (1 - values[1]) * (1 - values[3]),
          (1 - values[2]) * (1 - values[3]),
        ),
      _ => (-1.0, 0.0, 0.0),
    };
    if (r < 0) return null;
    int byte(double v) => (v.clamp(0.0, 1.0) * 255).round();
    return (byte(r) << 16) | (byte(g) << 8) | byte(b);
  }

  /// A widget appearance form: BBox [0 0 w h], mapped onto /Rect by the
  /// §12.5.5 algorithm.
  CosStream _widgetForm(double w, double h, ContentWriter content,
      {CosDictionary? resources}) {
    final bytes = content.takeBytes();
    final dict = CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Form'),
      'BBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        CosReal(w),
        CosReal(h),
      ]),
      'Length': CosInteger(bytes.length),
    });
    if (resources != null) dict['Resources'] = resources;
    return CosStream(dict, bytes);
  }

  /// Installs [form] as the widget's /AP /N, preserving other /AP entries
  /// (down/rollover appearances) when present.
  void _setNormalAppearance(CosDictionary widget, CosStream form) {
    final ref = _updater.addObject(form);
    final ap = document.cos.resolve(widget['AP']);
    if (ap is CosDictionary) {
      ap['N'] = ref;
    } else {
      widget['AP'] = CosDictionary({'N': ref});
    }
  }

  // ---------------------------------------------------------------------
  // /DA parsing, fonts, metrics

  /// Splits a /DA string into the font selection and the remaining
  /// (color) operators, replayed verbatim into the appearance.
  ({String fontName, double fontSize, String colorOps})
      _parseDefaultAppearance(String? da) {
    final tokens =
        (da ?? '').split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    var fontName = 'Helv';
    var fontSize = 0.0;
    var tfAt = -1;
    for (var i = 2; i < tokens.length; i++) {
      if (tokens[i] == 'Tf' && tokens[i - 2].startsWith('/')) {
        fontName = tokens[i - 2].substring(1);
        fontSize = double.tryParse(tokens[i - 1]) ?? 0;
        tfAt = i;
      }
    }
    final rest = [
      for (var i = 0; i < tokens.length; i++)
        if (tfAt < 0 || i < tfAt - 2 || i > tfAt) tokens[i],
    ].join(' ');
    return (
      fontName: fontName,
      fontSize: fontSize,
      colorOps: rest.isEmpty ? '0 g' : rest,
    );
  }

  /// The /DR font dictionary the /DA names, if the form declares one.
  CosDictionary? _formFont(PdfAcroForm form, String name) {
    final cos = document.cos;
    final fonts = cos.resolve(form.defaultResources?['Font']);
    if (fonts is! CosDictionary) return null;
    final font = cos.resolve(fonts[name]);
    return font is CosDictionary ? font : null;
  }

  /// The appearance's /Font resource: a reference to the /DR font when it
  /// is indirect, the dict itself when direct, or generated Helvetica as
  /// the lenient fallback for forms with broken /DR.
  CosDictionary _appearanceFontResource(
      PdfAcroForm form, String name, CosDictionary? fontDict) {
    if (fontDict == null) return _helvetica(name: name);
    final ref = document.cos.referenceTo(fontDict);
    return CosDictionary({name: ref ?? fontDict});
  }

  /// Text width in user units: explicit /Widths when the font has them,
  /// otherwise Helvetica metrics (the dominant /DR font family).
  double _measureFieldText(CosDictionary? font, String text, double size) {
    final cos = document.cos;
    if (font != null) {
      final widths = cos.resolve(font['Widths']);
      final first = cos.resolve(font['FirstChar']);
      if (widths is CosArray && first is CosInteger) {
        var total = 0.0;
        for (final code in text.codeUnits) {
          final index = code - first.value;
          double? width;
          if (index >= 0 && index < widths.length) {
            final n = cos.resolve(widths[index]);
            if (n is CosInteger) width = n.value.toDouble();
            if (n is CosReal) width = n.value;
          }
          total += width ?? 500;
        }
        return total * size / 1000;
      }
      final base = cos.resolve(font['BaseFont']);
      if (base is CosName && base.value.contains('Bold')) {
        return measureHelvetica(text, size, bold: true);
      }
    }
    return measureHelvetica(text, size);
  }

  /// Greedy word wrap using [measure]; a single overlong word overflows
  /// (and is clipped by the appearance).
  List<String> _wrapWith(double Function(String, double) measure,
      String text, double fontSize, double maxWidth) {
    final lines = <String>[];
    for (final paragraph in text.split('\n')) {
      var line = '';
      for (final word in paragraph.split(' ')) {
        final candidate = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty && measure(candidate, fontSize) > maxWidth) {
          lines.add(line);
          line = word;
        } else {
          line = candidate;
        }
      }
      lines.add(line);
    }
    return lines;
  }

  // ---------------------------------------------------------------------
  // staging

  void _checkFillable(PdfFormField field, Set<PdfFieldType> expected) {
    if (!expected.contains(field.type)) {
      throw ArgumentError(
          'field "${field.name}" is a ${field.type.name}, expected '
          '${expected.map((t) => t.name).join(' or ')}');
    }
    if (field.isReadOnly) {
      throw StateError('field "${field.name}" is read-only');
    }
  }

  void _finishFieldEdit(PdfFormField field) {
    _stageFormDict(field, field.dict);
    final form = field.form;
    if (form.needsAppearances) {
      // appearances are regenerated here, so viewers must not rebuild
      // them from scratch (Adobe's rebuild would discard ours)
      form.dict['NeedAppearances'] = const CosBoolean(false);
      _stageFormDict(field, form.dict);
    }
  }

  /// Stages the first indirect object whose serialization carries
  /// [dict]'s mutation: the dict itself, an ancestor field, the /AcroForm
  /// dictionary, or finally the catalog.
  void _stageFormDict(PdfFormField field, CosDictionary dict) {
    final cos = document.cos;
    CosDictionary? node = dict;
    final visited = <CosDictionary>{};
    while (node != null && visited.add(node)) {
      final ref = cos.referenceTo(node);
      if (ref != null) {
        _updater.replaceObject(ref.objectNumber, node);
        return;
      }
      final parent = cos.resolve(node['Parent']);
      node = parent is CosDictionary ? parent : null;
    }
    final formRef = cos.referenceTo(field.form.dict);
    if (formRef != null) {
      _updater.replaceObject(formRef.objectNumber, field.form.dict);
    } else {
      _updater.markChanged(document.catalog);
    }
  }
}
