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
  /// the appearance regenerates - pass true to let long values wrap in
  /// fields authored as single-line. Null leaves the flag alone.
  ///
  /// [verticalAlignment] saves a dart-pdf vertical placement preference for
  /// the whole wrapped block. Null retains the saved preference, or the
  /// legacy placement when none is saved. See
  /// [PdfFormField.textVerticalAlignment] for interoperability limits.
  ///
  /// /V stores [value] verbatim (UTF-16BE when it leaves Latin-1); the
  /// generated appearance replaces characters the byte-encoded
  /// appearance fonts cannot show with spaces.
  void setTextValue(
    PdfFormField field,
    String value, {
    bool? multiline,
    PdfFormTextVerticalAlignment? verticalAlignment,
    PdfTextDirection textDirection = PdfTextDirection.auto,
  }) {
    _checkFillable(field, const {PdfFieldType.text});
    if (multiline != null && multiline != field.isMultiline) {
      field.dict['Ff'] = CosInteger(
        multiline
            ? field.flags | PdfFormField.multilineFlag
            : field.flags & ~PdfFormField.multilineFlag,
      );
    }
    _setTextVerticalAlignment(field, verticalAlignment);
    field.dict['V'] = CosString.fromText(value);
    _regenerateVariableText(field, value, textDirection: textDirection);
    _finishFieldEdit(field);
  }

  /// Removes the saved vertical preference and regenerates all widgets
  /// using legacy placement, without changing the value or multiline flag.
  void clearTextFieldVerticalAlignment(PdfFormField field) {
    _checkFillable(field, const {PdfFieldType.text});
    field.dict.entries.remove('DartPdfTextVerticalAlignment');
    _regenerateVariableText(field, field.value ?? '');
    _finishFieldEdit(field);
  }

  void _setTextVerticalAlignment(
      PdfFormField field, PdfFormTextVerticalAlignment? alignment) {
    if (alignment != null) {
      field.dict['DartPdfTextVerticalAlignment'] =
          CosString.fromText(alignment.name);
    }
  }

  /// Fills a push-button field with an image (the conventional way PDF
  /// forms carry signatures and logos): each widget's normal appearance
  /// becomes the image scaled to fit its rectangle, centered, over the
  /// widget's /MK background and border.
  void setButtonImage(PdfFormField field, PdfEmbeddableImage image) {
    _checkFillable(field, const {PdfFieldType.pushButton});
    final imageRef = _updater.addObject(
      image.toXObject((smask) => _updater.addObject(smask)),
    );
    final widgets = field.widgets;
    for (var i = 0; i < widgets.length; i++) {
      final widget = widgets[i];
      final rect = pdfRectFrom(document.cos, widget['Rect']);
      if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
      final w = rect.width, h = rect.height;
      final rotation = _prepareWidgetRotation(field, i, widget);
      final form = _buttonImageForm(
        widget,
        w,
        h,
        rotation,
        image.width.toDouble(),
        image.height.toDouble(),
        imageRef,
      );
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
      throw ArgumentError.value(
        onState,
        'onState',
        'not an option of "${field.name}" (${field.onStates.join(', ')})',
      );
    }
    _selectButtonState(field, onState);
  }

  /// Sets a combo or list box to the option matching [value] (export or
  /// display form). Combo boxes with the Edit flag accept free text.
  void setChoiceValue(PdfFormField field, String value) {
    _checkFillable(field, const {PdfFieldType.comboBox, PdfFieldType.listBox});
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
      throw ArgumentError.value(
        value,
        'value',
        'not an option of "${field.name}" '
            '(${options.map((o) => o.$1).join(', ')})',
      );
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

  static int _normalizeWidgetRotation(int rotation) {
    final value = rotation % 360;
    return value < 0 ? value + 360 : value;
  }

  int _widgetPageRotation(PdfFormField field, int widgetIndex) {
    final pageIndex = field.widgetPageIndex(widgetIndex);
    if (pageIndex < 0 || pageIndex >= document.pageCount) return 0;
    return _normalizeWidgetRotation(document.page(pageIndex).rotation);
  }

  int? _declaredWidgetRotation(CosDictionary widget) {
    final mk = document.cos.resolve(widget['MK']);
    if (mk is! CosDictionary) return null;
    final raw = document.cos.resolve(mk['R']);
    return switch (raw) {
      CosInteger(:final value) => _normalizeWidgetRotation(value),
      CosReal(:final value) => _normalizeWidgetRotation(value.round()),
      _ => null,
    };
  }

  /// The widget's /MK /R is the persistent declaration; fields without one
  /// inherit the page's rotation so appearances authored by this editor stay
  /// upright on an already-rotated page.
  int _prepareWidgetRotation(
      PdfFormField field, int widgetIndex, CosDictionary widget) {
    final declared = _declaredWidgetRotation(widget);
    if (declared != null) return declared;
    final rotation = _widgetPageRotation(field, widgetIndex);
    if (rotation != 0) _setWidgetRotation(widget, rotation);
    return rotation;
  }

  void _setWidgetRotation(CosDictionary widget, int rotation) {
    final existing = document.cos.resolve(widget['MK']);
    final mk = CosDictionary({
      if (existing is CosDictionary) ...existing.entries,
    });
    final normalized = _normalizeWidgetRotation(rotation);
    if (normalized == 0) {
      mk.entries.remove('R');
    } else {
      mk['R'] = CosInteger(normalized);
    }
    if (mk.entries.isEmpty) {
      widget.entries.remove('MK');
    } else {
      // Reassign rather than mutate: /MK may itself be indirect.
      widget['MK'] = mk;
    }
  }

  static PdfRect _orientedWidgetRect(double w, double h, int rotation) {
    if (rotation == 0 || rotation == 180) return PdfRect(0, 0, w, h);
    final cx = w / 2, cy = h / 2;
    return PdfRect(cx - h / 2, cy - w / 2, cx + h / 2, cy + w / 2);
  }

  static void _beginWidgetOrientation(
      ContentWriter writer, double w, double h, int rotation) {
    if (rotation == 0) return;
    writer.save();
    writePdfCounterRotation(writer, w / 2, h / 2, rotation);
  }

  static void _endWidgetOrientation(ContentWriter writer, int rotation) {
    if (rotation != 0) writer.restore();
  }

  CosStream _buttonImageForm(
    CosDictionary widget,
    double w,
    double h,
    int rotation,
    double imageWidth,
    double imageHeight,
    CosObject imageObject,
  ) {
    final visual = _orientedWidgetRect(w, h, rotation);
    final scale =
        math.min(visual.width / imageWidth, visual.height / imageHeight);
    final dw = imageWidth * scale, dh = imageHeight * scale;
    final writer = ContentWriter();
    _beginWidgetOrientation(writer, w, h, rotation);
    _paintWidgetDecorations(writer, widget, visual);
    writer
      ..save()
      ..concatMatrix(
        dw,
        0,
        0,
        dh,
        visual.left + (visual.width - dw) / 2,
        visual.bottom + (visual.height - dh) / 2,
      )
      ..drawXObject('Img0')
      ..restore();
    _endWidgetOrientation(writer, rotation);
    return _widgetForm(
      w,
      h,
      writer,
      resources: CosDictionary({
        'XObject': CosDictionary({'Img0': imageObject}),
      }),
    );
  }

  /// Rebuilds form appearances on a page after its persistent /Rotate
  /// changes. The page transform moves each widget rectangle; /MK /R plus
  /// the generated appearance's counter-rotation keeps the field contents
  /// upright in the newly oriented document.
  void _regenerateFormAppearancesOnPage(int pageIndex) {
    final form = acroForm;
    if (form == null) return;
    final rotation =
        _normalizeWidgetRotation(document.page(pageIndex).rotation);
    for (final field in form.fields) {
      final widgets = field.widgets;
      final targets = <int>[];
      for (var i = 0; i < widgets.length; i++) {
        if (field.widgetPageIndex(i) != pageIndex) continue;
        targets.add(i);
        _setWidgetRotation(widgets[i], rotation);
        _stageFormDict(field, widgets[i]);
      }
      if (targets.isEmpty) continue;
      switch (field.type) {
        case PdfFieldType.text:
          _regenerateVariableText(field, field.value ?? '');
          _stageFormDict(field, field.dict);
        case PdfFieldType.comboBox:
        case PdfFieldType.listBox:
          _regenerateVariableText(field, _choiceDisplay(field));
          _stageFormDict(field, field.dict);
        case PdfFieldType.checkBox:
        case PdfFieldType.radioGroup:
          for (final i in targets) {
            _regenerateButtonStates(field, i, widgets[i]);
            _stageFormDict(field, widgets[i]);
          }
        case PdfFieldType.pushButton:
        case PdfFieldType.signature:
        case PdfFieldType.unknown:
          break;
      }
    }
  }

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
    final widgets = field.widgets;
    for (var i = 0; i < widgets.length; i++) {
      final widget = widgets[i];
      if (_widgetStates(widget).isNotEmpty) continue;
      final rect = pdfRectFrom(document.cos, widget['Rect']);
      if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
      final w = rect.width, h = rect.height;
      final rotation = _prepareWidgetRotation(field, i, widget);
      final visual = _orientedWidgetRect(w, h, rotation);

      ContentWriter appearance({required bool checked}) {
        final writer = ContentWriter();
        _beginWidgetOrientation(writer, w, h, rotation);
        _paintWidgetDecorations(writer, widget, visual);
        if (checked) _paintCheckMark(writer, visual);
        _endWidgetOrientation(writer, rotation);
        return writer;
      }

      widget['AP'] = CosDictionary({
        'N': CosDictionary({
          on: _updater.addObject(_widgetForm(w, h, appearance(checked: true))),
          'Off':
              _updater.addObject(_widgetForm(w, h, appearance(checked: false))),
        }),
      });
    }
  }

  /// Strokes the standard check mark filling a [w]×[h] box (§12.7.4.2.3),
  /// shared by check-box generation and resize regeneration.
  void _paintCheckMark(ContentWriter writer, PdfRect rect) {
    final size = math.min(rect.width, rect.height);
    final weight = size * 0.12;
    final x = rect.left + (rect.width - size) / 2;
    final y = rect.bottom + (rect.height - size) / 2;
    writer
      ..strokeColor(0x000000)
      ..lineWidth(weight < 1 ? 1 : weight)
      ..roundLines()
      ..moveTo(x + size * 0.22, y + size * 0.52)
      ..lineTo(x + size * 0.42, y + size * 0.30)
      ..lineTo(x + size * 0.78, y + size * 0.72)
      ..stroke();
  }

  /// Rebuilds [widget]'s /AP /N on/off states at its current /Rect,
  /// preserving the existing state names (so a radio button keeps its
  /// export value). Used when a button widget is resized - unlike
  /// [_ensureButtonAppearances], it regenerates states that already
  /// exist so the mark refits the new box.
  void _regenerateButtonStates(
      PdfFormField field, int widgetIndex, CosDictionary widget) {
    final rect = pdfRectFrom(document.cos, widget['Rect']);
    if (rect == null || rect.width <= 0 || rect.height <= 0) return;
    final w = rect.width, h = rect.height;
    final rotation = _prepareWidgetRotation(field, widgetIndex, widget);
    final visual = _orientedWidgetRect(w, h, rotation);
    final names = _widgetStates(widget).toSet();
    if (!names.any((s) => s != 'Off')) {
      names.add(field.onStates.isEmpty ? 'Yes' : field.onStates.first);
    }
    names.add('Off');

    ContentWriter appearance({required bool checked}) {
      final writer = ContentWriter();
      _beginWidgetOrientation(writer, w, h, rotation);
      _paintWidgetDecorations(writer, widget, visual);
      if (checked) _paintCheckMark(writer, visual);
      _endWidgetOrientation(writer, rotation);
      return writer;
    }

    final n = CosDictionary({});
    for (final state in names) {
      n[state] = _updater
          .addObject(_widgetForm(w, h, appearance(checked: state != 'Off')));
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
  /// their appearance - only the /Rect moves. A no-op when the field or
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
        _regenerateButtonStates(field, widgetIndex, widget);
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
  /// past 0xFF can never reach the page - swap them for spaces (the
  /// trax/desktop-filler convention) instead of letting the writer
  /// emit '?'. /V keeps the original text.
  static String sanitizeFieldText(String text) {
    if (text.codeUnits.every((c) => c <= 0xFF)) return text;
    return String.fromCharCodes([
      for (final c in text.codeUnits) c <= 0xFF ? c : 0x20,
    ]);
  }

  void _regenerateVariableText(
    PdfFormField field,
    String rawText, {
    PdfTextDirection textDirection = PdfTextDirection.auto,
  }) {
    final cos = document.cos;
    final da = _parseDefaultAppearance(field.defaultAppearance);
    final verticalAlignment = field.textVerticalAlignment;
    final fontDict = _formFont(field.form, da.fontName);
    // an embedded (Type0) /DR font shows text as 2-byte glyph ids: reparse
    // its program so the appearance can encode and measure with it. A
    // base-14 /DR entry stays on the simple byte path. Text past Latin-1 is
    // only sanitized for the simple fonts - an embedded font can show it.
    // /Widths resolved once for this regeneration. The auto-size loop
    // re-measures the same text up to ~16 times while shrinking, and each
    // measure used to `cos.resolve` one array entry PER CHARACTER (#406).
    final fontWidths = fontDict == null ? null : _fieldWidthMetrics(fontDict);
    final embedded = fontDict == null
        ? null
        : PdfEmbeddedFont.fromFontDict(cos, fontDict, da.fontName);
    final text = embedded != null ? rawText : sanitizeFieldText(rawText);

    final widgets = field.widgets;
    for (var widgetIndex = 0; widgetIndex < widgets.length; widgetIndex++) {
      final widget = widgets[widgetIndex];
      final rect = pdfRectFrom(cos, widget['Rect']);
      if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
      final w = rect.width, h = rect.height;
      final rotation = _prepareWidgetRotation(field, widgetIndex, widget);
      final visual = _orientedWidgetRect(w, h, rotation);
      const pad = 2.0;
      embedded?.resetUsage();

      double measure(String s, double size) => embedded != null
          ? embedded.measure(s, size)
          : _measureFieldText(fontDict, s, size, widths: fontWidths);

      final multiline = field.isMultiline;
      // Line boxes are laid out and clipped in the field's own /Widths (or the
      // base-14 fallback); the shared builder consumes it through [PdfTextFont]
      // for the resource name and ascent while measurement stays on [measure].
      final font = embedded ??
          _DaFieldFont(
            da.fontName,
            PdfStandardFont.fromName(da.fontName).ascent,
            measure,
          );
      const lineFactor = 1.15;
      var size = da.fontSize;
      List<String> lines;
      List<String> wrap(double s) =>
          pdfWrapText(text, visual.width - 2 * pad, (c) => measure(c, s));
      if (multiline) {
        if (size == 0) {
          // auto-size: shrink until the wrapped block fits the height
          size = 12;
          while (size > 4) {
            lines = wrap(size);
            if (lines.length * size * lineFactor <= visual.height - 2 * pad) {
              break;
            }
            size -= 0.5;
          }
        }
        lines = wrap(size);
      } else {
        final single = text.replaceAll('\n', ' ');
        if (size == 0) {
          size = (visual.height - 2 * pad) / lineFactor;
          final width = measure(single, size);
          if (width > visual.width - 2 * pad && width > 0) {
            size *= (visual.width - 2 * pad) / width;
          }
          size = size.clamp(4.0, 144.0);
        }
        lines = [single];
      }

      double? firstBaselineY;
      if (verticalAlignment != null) {
        // Match the shared centre-block metric: em-height lines separated
        // by the existing leading, with no extra leading outside the block.
        // Clamp overflowing blocks to the top so the beginning stays visible.
        final blockHeight = size + (lines.length - 1) * size * lineFactor;
        final spare = math.max(0.0, visual.height - 2 * pad - blockHeight);
        final offset = switch (verticalAlignment) {
          PdfFormTextVerticalAlignment.top => 0.0,
          PdfFormTextVerticalAlignment.center => spare / 2,
          PdfFormTextVerticalAlignment.bottom => spare,
        };
        firstBaselineY = visual.top - pad - offset - size * font.ascent / 1000;
      }

      final resolvedDirection = field.quadding == 2
          ? PdfTextDirection.rtl
          : textDirection.resolve(rawText);
      final align = switch (field.quadding) {
        1 => PdfTextAlign.center,
        2 => PdfTextAlign.right,
        _ => resolvedDirection == PdfTextDirection.rtl
            ? PdfTextAlign.right
            : PdfTextAlign.left,
      };
      final writer = ContentWriter()..raw('/Tx BMC');
      _beginWidgetOrientation(writer, w, h, rotation);
      writer.save();
      _paintWidgetDecorations(writer, widget, visual);
      // The clip is inset a point from the box (not the text padding), so it is
      // emitted here and the shared builder runs with its own clip disabled.
      writer
        ..rect(visual.left + 1, visual.bottom + 1, visual.width - 2,
            visual.height - 2)
        ..clip();
      writePdfTextBox(
        writer,
        visual,
        lines,
        font: font,
        fontSize: size,
        align: align,
        padding: pad,
        lineHeight: size * lineFactor,
        vAlign: multiline ? PdfTextBoxVAlign.top : PdfTextBoxVAlign.centerLine,
        firstBaselineY: firstBaselineY,
        clip: false,
        clampAlign: true,
        measureLine: (s) => measure(s, size),
        writeColor: (w) => w.raw(da.colorOps),
        emitLine: (w, line) {
          final rendered = pdfVisualText(line, resolvedDirection);
          if (embedded != null) {
            w.showGlyphHex(embedded.encodeHex(rendered));
          } else {
            w.showText(rendered);
          }
        },
      );
      writer.restore();
      _endWidgetOrientation(writer, rotation);
      writer.raw('EMC');

      // the embedded font's resource carries only the glyphs just shown
      // (encodeHex recorded them); build it after the content stream
      final resources = CosDictionary({
        'Font': embedded != null
            ? embedded.buildResource(_updater.addObject)
            : _appearanceFontResource(field.form, da.fontName, fontDict),
      });
      final form = _widgetForm(w, h, writer, resources: resources);
      _setNormalAppearance(widget, form);
      if (!identical(widget, field.dict)) _stageFormDict(field, widget);
    }
  }

  /// Background and border from the widget's /MK appearance
  /// characteristics (§12.5.6.19), drawn in form space.
  void _paintWidgetDecorations(
    ContentWriter writer,
    CosDictionary widget,
    PdfRect rect,
  ) {
    final cos = document.cos;
    final mk = cos.resolve(widget['MK']);
    if (mk is! CosDictionary) return;
    final bg = _mkColor(mk['BG']);
    if (bg != null) {
      writer
        ..fillColor(bg)
        ..rect(rect.left, rect.bottom, rect.width, rect.height)
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
          ..rect(rect.left + width / 2, rect.bottom + width / 2,
              rect.width - width, rect.height - width)
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
  CosStream _widgetForm(
    double w,
    double h,
    ContentWriter content, {
    CosDictionary? resources,
  }) {
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
  /// (down/rollover appearances) when present. Returns the form's reference
  /// so callers can reuse the one appearance stream (e.g. repeating a
  /// signature box on several pages).
  CosReference _setNormalAppearance(CosDictionary widget, CosStream form) {
    final ref = _updater.addObject(form);
    final ap = document.cos.resolve(widget['AP']);
    if (ap is CosDictionary) {
      ap['N'] = ref;
    } else {
      widget['AP'] = CosDictionary({'N': ref});
    }
    return ref;
  }

  // ---------------------------------------------------------------------
  // /DA parsing, fonts, metrics

  /// Splits a /DA string into the font selection and the remaining
  /// (color) operators, replayed verbatim into the appearance.
  ({String fontName, double fontSize, String colorOps}) _parseDefaultAppearance(
    String? da,
  ) {
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
    PdfAcroForm form,
    String name,
    CosDictionary? fontDict,
  ) {
    if (fontDict == null) return _helvetica(name: name);
    final ref = document.cos.referenceTo(fontDict);
    return CosDictionary({name: ref ?? fontDict});
  }

  /// Text width in user units: explicit /Widths when the font has them,
  /// otherwise Helvetica metrics (the dominant /DR font family).
  /// A font's /FirstChar plus its /Widths flattened to plain doubles, or null
  /// when the font carries no usable metrics.
  (int, List<double>)? _fieldWidthMetrics(CosDictionary font) {
    final cos = document.cos;
    final widths = cos.resolve(font['Widths']);
    final first = cos.resolve(font['FirstChar']);
    if (widths is! CosArray || first is! CosInteger) return null;
    return (
      first.value,
      <double>[
        for (final item in widths.items)
          switch (cos.resolve(item)) {
            CosInteger(:final value) => value.toDouble(),
            CosReal(:final value) => value,
            // Matches the per-character fallback this replaces: a missing or
            // non-numeric entry measures as 500.
            _ => 500.0,
          },
      ],
    );
  }

  double _measureFieldText(CosDictionary? font, String text, double size,
      {(int, List<double>)? widths}) {
    final cos = document.cos;
    if (font != null) {
      final metrics = widths ?? _fieldWidthMetrics(font);
      if (metrics != null) {
        final (first, table) = metrics;
        var total = 0.0;
        for (final code in text.codeUnits) {
          final index = code - first;
          total += index >= 0 && index < table.length ? table[index] : 500;
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

  // ---------------------------------------------------------------------
  // staging

  void _checkFillable(PdfFormField field, Set<PdfFieldType> expected) {
    if (!expected.contains(field.type)) {
      throw ArgumentError(
        'field "${field.name}" is a ${field.type.name}, expected '
        '${expected.map((t) => t.name).join(' or ')}',
      );
    }
    if (field.isReadOnly) {
      throw StateError('field "${field.name}" is read-only');
    }
  }

  void _finishFieldEdit(PdfFormField field) {
    final pages = <int>{};
    var unknownPage = false;
    for (var i = 0; i < field.widgets.length; i++) {
      final page = field.widgetPageIndex(i);
      if (page < 0) {
        unknownPage = true;
      } else {
        pages.add(page);
      }
    }
    // A reconciled field holds its canonical value on the /Fields dict we
    // just wrote; the adopted page widgets may still carry the producer's
    // stale /V, which would otherwise shadow it on read-back. Drop it so
    // the field value and the regenerated appearance stay consistent.
    for (final widget in field.reconciledWidgets) {
      if (identical(widget, field.dict)) continue;
      if (widget.entries.remove('V') != null) _stageFormDict(field, widget);
    }
    _stageFormDict(field, field.dict);
    final form = field.form;
    if (form.needsAppearances) {
      // appearances are regenerated here, so viewers must not rebuild
      // them from scratch (Adobe's rebuild would discard ours)
      form.dict['NeedAppearances'] = const CosBoolean(false);
      _stageFormDict(field, form.dict);
    }
    _markVisual(unknownPage ? null : pages);
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

/// Adapts a variable-text field's /DA font to [PdfTextFont] for the shared
/// text-box builder. The [resourceName] and [ascent] drive the appearance's
/// /Font selection and baseline; measurement stays on the field's own /Widths
/// (or the base-14 fallback) through the [_measure] closure so wrapping and
/// alignment match exactly what the simple-font path drew before.
class _DaFieldFont implements PdfTextFont {
  _DaFieldFont(this.resourceName, this.ascent, this._measure);

  @override
  final String resourceName;

  @override
  final int ascent;

  final double Function(String text, double fontSize) _measure;

  @override
  double measure(String text, double fontSize) => _measure(text, fontSize);
}
