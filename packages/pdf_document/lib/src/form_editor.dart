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

  /// Removes the form's XFA description (/AcroForm /XFA) and the catalog's
  /// /NeedsRendering flag, so XFA-aware viewers show the AcroForm fields and
  /// their values instead of the XFA data. Returns whether anything was
  /// removed; a no-op for forms without XFA.
  ///
  /// Every field setter calls this: this library fills only the AcroForm
  /// half of a hybrid form, and an XFA-aware viewer would otherwise keep
  /// showing the XFA packet's old values. Dropping /XFA is the usual way
  /// non-XFA tools keep a filled hybrid form consistent. The first fill in
  /// an edit removes it; later fills find nothing left to remove.
  bool removeXfa() {
    final form = acroForm;
    if (form == null) return false;
    var removed = false;
    if (form.dict.entries.remove('XFA') != null) {
      removed = true;
      final ref = document.cos.referenceTo(form.dict);
      if (ref != null) {
        _updater.replaceObject(ref.objectNumber, form.dict);
      } else {
        _updater.markChanged(document.catalog);
      }
    }
    if (document.catalog.entries.remove('NeedsRendering') != null) {
      removed = true;
      _updater.markChanged(document.catalog);
    }
    return removed;
  }

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
  /// legacy placement when none is saved. Pass
  /// [PdfFormTextVerticalAlignment.legacy] to clear it in the same edit. See
  /// [PdfFormField.textVerticalAlignment] for interoperability limits.
  ///
  /// /V stores [value] verbatim (UTF-16BE when it leaves Latin-1); the
  /// generated appearance replaces characters the byte-encoded
  /// appearance fonts cannot show with spaces.
  ///
  /// A field with /MaxLen ([PdfFormField.maxLength]) keeps only the first
  /// that many characters (Unicode code points) of [value]. A comb field
  /// ([PdfFormField.isComb]) draws one character per cell, and a password
  /// field ([PdfFormField.isPassword]) draws one `*` per character instead
  /// of the value - see [maskedPasswordText].
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
    value = truncateToMaxLength(value, field.maxLength);
    field.dict['V'] = CosString.fromText(value);
    // /V is authoritative again: drop a withheld-password marker
    field.dict.entries.remove(passwordWithheldKey);
    _regenerateVariableText(field, value, textDirection: textDirection);
    _finishFieldEdit(field);
  }

  /// The private field entry marking a password field whose value was
  /// filled but deliberately not written to /V ([setPasswordValue] with
  /// `storeValue: false`). It carries no part of the value - only that the
  /// field is filled - so a later regeneration (resize, rotation) keeps
  /// drawing the fixed mask instead of blanking the field.
  static const passwordWithheldKey = 'DartPdfPasswordWithheld';

  /// How many asterisks a withheld password draws, whatever its length.
  static const withheldPasswordMaskLength = 8;

  /// Fills a password field ([PdfFormField.isPassword]) the way §12.7.4.3
  /// asks interactive readers to: by default the value is **not** stored in
  /// the file. Any existing /V is removed (from reconciled widgets too) and
  /// the appearance shows a fixed [withheldPasswordMaskLength] asterisks
  /// when [value] is non-empty, or nothing when it is empty. A fixed mask
  /// rather than one asterisk per character, because the appearance is the
  /// only trace of the value left in the file and should not give away its
  /// length. The value itself is the caller's to keep - dart_pdf_editor
  /// holds it in a `PdfFormSecretStore`.
  ///
  /// [storeValue] `true` is plain [setTextValue]: /V holds the value and the
  /// appearance masks it one asterisk per character.
  ///
  /// When the document has no trailer /ID and [value] is withheld, a
  /// `[documentId documentId]` /ID is written (default: the SHA-256 of the
  /// bytes the document was opened from, [pdfPermanentDocumentId]), so the
  /// saved file keeps the identity the caller filed the value under.
  ///
  /// [PdfEditor.setTextValue] stays the backward-compatible default for
  /// library callers - it still writes /V for password fields.
  void setPasswordValue(
    PdfFormField field,
    String value, {
    bool storeValue = false,
    Uint8List? documentId,
  }) {
    _checkFillable(field, const {PdfFieldType.text});
    if (!field.isPassword) {
      throw ArgumentError.value(
          field.name, 'field', 'is not a password field (/Ff bit 14)');
    }
    if (storeValue) {
      setTextValue(field, value);
      return;
    }
    field.dict.entries.remove('V');
    if (value.isEmpty) {
      field.dict.entries.remove(passwordWithheldKey);
    } else {
      field.dict[passwordWithheldKey] = const CosBoolean(true);
      if (pdfTrailerPermanentId(document) == null) {
        final id = CosString(documentId ?? pdfPermanentDocumentId(document),
            isHex: true);
        _updater.setTrailerEntry('ID', CosArray([id, id]));
      }
    }
    _regenerateVariableText(field, '');
    _finishFieldEdit(field);
  }

  /// Removes the saved vertical preference and regenerates all widgets
  /// using legacy placement, without changing the value or multiline flag.
  void clearTextFieldVerticalAlignment(PdfFormField field) {
    _checkFillable(field, const {PdfFieldType.text});
    _setTextVerticalAlignment(field, PdfFormTextVerticalAlignment.legacy);
    _regenerateVariableText(field, field.value ?? '');
    _finishFieldEdit(field);
  }

  void _setTextVerticalAlignment(
      PdfFormField field, PdfFormTextVerticalAlignment? alignment) {
    if (alignment == PdfFormTextVerticalAlignment.legacy) {
      field.dict.entries.remove('DartPdfTextVerticalAlignment');
    } else if (alignment != null) {
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
      _scrollListSelectionIntoView(field, [index]);
    }
    if (field.type == PdfFieldType.listBox && options.isNotEmpty) {
      _regenerateListBox(field);
    } else {
      _regenerateVariableText(field, display);
    }
    _finishFieldEdit(field);
  }

  /// Sets a choice field to every option in [values] (export or display
  /// form; order and duplicates don't matter) - the multi-select
  /// counterpart of [setChoiceValue] for list boxes with the MultiSelect
  /// flag ([PdfFormField.isMultiSelect]).
  ///
  /// /V is written in option order as an array of export values when two
  /// or more are selected, as a single text string when exactly one is
  /// (what Acrobat writes, and what single-value readers expect), and is
  /// removed when [values] is empty. /I carries the selected option
  /// indices, sorted ascending (§12.7.5.4). /TI scrolls so the first
  /// selected row is visible, and the regenerated list-box appearance
  /// highlights every selected row.
  ///
  /// A field that isn't multi-select takes at most one value (throws
  /// otherwise); one value behaves exactly like [setChoiceValue]. Values
  /// that aren't options throw, as they do there.
  void setChoiceValues(PdfFormField field, List<String> values) {
    _checkFillable(field, const {PdfFieldType.comboBox, PdfFieldType.listBox});
    if (!field.isMultiSelect) {
      if (values.length > 1) {
        throw ArgumentError.value(
          values,
          'values',
          '"${field.name}" is not a multi-select list box',
        );
      }
      if (values.length == 1) {
        setChoiceValue(field, values.single);
        return;
      }
    }
    final options = field.options;
    final indices = <int>{};
    for (final value in values) {
      final index = options.indexWhere((o) => o.$1 == value || o.$2 == value);
      if (index < 0) {
        throw ArgumentError.value(
          value,
          'values',
          'not an option of "${field.name}" '
              '(${options.map((o) => o.$1).join(', ')})',
        );
      }
      indices.add(index);
    }
    final sorted = indices.toList()..sort();
    if (sorted.isEmpty) {
      field.dict.entries.remove('V');
      field.dict.entries.remove('I');
    } else {
      field.dict['V'] = sorted.length == 1
          ? CosString.fromText(options[sorted.single].$1)
          : CosArray([
              for (final i in sorted) CosString.fromText(options[i].$1),
            ]);
      if (field.type == PdfFieldType.listBox) {
        field.dict['I'] = CosArray([for (final i in sorted) CosInteger(i)]);
        _scrollListSelectionIntoView(field, sorted);
      }
    }
    _regenerateChoice(field);
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
          _regenerateChoice(field);
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

  /// Regenerates a choice field's appearance from its current value: a
  /// list box with options draws its rows (selection highlighted, see
  /// [_regenerateListBox]); a combo box - or a list box without /Opt -
  /// shows the selected display text like a text field.
  void _regenerateChoice(PdfFormField field) {
    if (field.type == PdfFieldType.listBox && field.options.isNotEmpty) {
      _regenerateListBox(field);
    } else {
      _regenerateVariableText(field, _choiceDisplay(field));
    }
  }

  /// A list box's auto (/DA size 0) font size - the conventional 12 pt,
  /// since shrinking every row to fit would make long lists unreadable.
  static const double _listBoxAutoFontSize = 12;

  /// Row height as a multiple of the font size.
  static const double _listBoxRowFactor = 1.15;

  /// The selected-row fill interactive viewers conventionally use for list
  /// boxes (0.6 0.757 0.855 RGB).
  static const int _listBoxHighlight = 0x99C1DA;

  /// Rows the first widget of list box [field] shows at once (at least 1).
  int _listVisibleRows(PdfFormField field) {
    final rect = field.widgetRect(0);
    if (rect == null) return 1;
    final rotation = _declaredWidgetRotation(field.widgets.first) ?? 0;
    final visual = _orientedWidgetRect(rect.width, rect.height, rotation);
    final da = _parseDefaultAppearance(field.defaultAppearance);
    final size = da.fontSize > 0 ? da.fontSize : _listBoxAutoFontSize;
    final rows = ((visual.height - 4) / (size * _listBoxRowFactor)).floor();
    return rows < 1 ? 1 : rows;
  }

  /// Updates /TI so the first of the (sorted) [selected] rows is visible,
  /// leaving it alone when it already is. The appearance reads /TI back
  /// through [PdfFormField.topIndex].
  void _scrollListSelectionIntoView(PdfFormField field, List<int> selected) {
    if (selected.isEmpty) return;
    final top = field.topIndex;
    final first = selected.first;
    if (first >= top && first < top + _listVisibleRows(field)) return;
    if (first == 0) {
      field.dict.entries.remove('TI');
    } else {
      field.dict['TI'] = CosInteger(first);
    }
  }

  /// Draws a list box the way interactive viewers show it: one row per
  /// /Opt entry from the /TI top index down, with every selected row
  /// ([PdfFormField.selectedIndices]) filled in the conventional selection
  /// highlight behind its text. Single- and multi-select list boxes share
  /// this path; only how many rows are highlighted differs.
  void _regenerateListBox(PdfFormField field) {
    final cos = document.cos;
    final da = _parseDefaultAppearance(field.defaultAppearance);
    final fontDict = _formFont(field.form, da.fontName);
    final fontWidths = fontDict == null ? null : _fieldWidthMetrics(fontDict);
    final embedded = fontDict == null
        ? null
        : PdfEmbeddedFont.fromFontDict(cos, fontDict, da.fontName);
    final rows = [
      for (final (_, display) in field.options)
        embedded != null ? display : sanitizeFieldText(display),
    ];
    final selected = field.selectedIndices.toSet();
    final top = math.min(field.topIndex, math.max(0, rows.length - 1));
    final size = da.fontSize > 0 ? da.fontSize : _listBoxAutoFontSize;
    final rowHeight = size * _listBoxRowFactor;
    const pad = 2.0;

    final widgets = field.widgets;
    for (var widgetIndex = 0; widgetIndex < widgets.length; widgetIndex++) {
      final widget = widgets[widgetIndex];
      final rect = pdfRectFrom(cos, widget['Rect']);
      if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
      final w = rect.width, h = rect.height;
      final rotation = _prepareWidgetRotation(field, widgetIndex, widget);
      final visual = _orientedWidgetRect(w, h, rotation);
      embedded?.resetUsage();

      double measure(String s) => embedded != null
          ? embedded.measure(s, size)
          : _measureFieldText(fontDict, s, size, widths: fontWidths);

      final font = embedded ??
          _DaFieldFont(
            da.fontName,
            PdfStandardFont.fromName(da.fontName).ascent,
            (s, _) => measure(s),
          );
      final writer = ContentWriter()..raw('/Tx BMC');
      _beginWidgetOrientation(writer, w, h, rotation);
      writer.save();
      _paintWidgetDecorations(writer, widget, visual);
      writer
        ..rect(visual.left + 1, visual.bottom + 1, visual.width - 2,
            visual.height - 2)
        ..clip();
      var rowTop = visual.top - pad;
      for (var i = top; i < rows.length && rowTop > visual.bottom + 1; i++) {
        final row = PdfRect(
            visual.left + 1, rowTop - rowHeight, visual.right - 1, rowTop);
        if (selected.contains(i)) {
          writer
            ..fillColor(_listBoxHighlight)
            ..rect(row.left, row.bottom, row.width, row.height)
            ..fill();
        }
        final direction = field.quadding == 2
            ? PdfTextDirection.rtl
            : PdfTextDirection.auto.resolve(rows[i]);
        writePdfTextBox(
          writer,
          row,
          [rows[i]],
          font: font,
          fontSize: size,
          align: switch (field.quadding) {
            1 => PdfTextAlign.center,
            2 => PdfTextAlign.right,
            _ => direction == PdfTextDirection.rtl
                ? PdfTextAlign.right
                : PdfTextAlign.left,
          },
          padding: pad - 1,
          lineHeight: rowHeight,
          vAlign: PdfTextBoxVAlign.centerLine,
          clip: false,
          clampAlign: true,
          measureLine: measure,
          writeColor: (w) => w.raw(da.colorOps),
          emitLine: (w, line) {
            final rendered = pdfVisualText(line, direction);
            if (embedded != null) {
              w.showGlyphHex(embedded.encodeHex(rendered));
            } else {
              w.showText(rendered);
            }
          },
        );
        rowTop -= rowHeight;
      }
      writer.restore();
      _endWidgetOrientation(writer, rotation);
      writer.raw('EMC');

      final resources = CosDictionary({
        'Font': embedded != null
            ? embedded.buildResource(_updater.addObject)
            : _appearanceFontResource(field.form, da.fontName, fontDict),
      });
      _setNormalAppearance(
          widget, _widgetForm(w, h, writer, resources: resources));
      if (!identical(widget, field.dict)) _stageFormDict(field, widget);
    }
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
        _regenerateChoice(field);
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

  /// [value] cut to its first [maxLength] characters (Unicode code points,
  /// so a surrogate pair is never split); unchanged when [maxLength] is
  /// null or the value already fits. The /MaxLen rule of [setTextValue].
  static String truncateToMaxLength(String value, int? maxLength) {
    if (maxLength == null || value.length <= maxLength) return value;
    final runes = value.runes;
    if (runes.length <= maxLength) return value;
    return String.fromCharCodes(runes.take(maxLength));
  }

  /// What a password field's appearance shows for [value]: one `*` per
  /// character, never the value itself.
  ///
  /// Asterisks rather than bullets because `*` is the same byte in every
  /// simple-font encoding (Standard, WinAnsi, MacRoman) and is present in
  /// practically every embedded subset's source font, whereas U+2022 is
  /// byte 0x95 only under WinAnsi and would print as a different glyph (or
  /// nothing) elsewhere. Masking instead of leaving the field blank keeps a
  /// filled field visibly filled, matching the masked inline editor.
  static String maskedPasswordText(String value) => '*' * value.runes.length;

  void _regenerateVariableText(
    PdfFormField field,
    String rawText, {
    PdfTextDirection textDirection = PdfTextDirection.auto,
  }) {
    final cos = document.cos;
    final isText = field.type == PdfFieldType.text;
    final maxLength = isText ? field.maxLength : null;
    final comb = isText && field.isComb;
    if (isText) {
      rawText = truncateToMaxLength(rawText, maxLength);
      // the value never reaches the page: extraction, search and screen
      // readers read the appearance, so it carries only the mask
      if (field.isPassword) {
        rawText = rawText.isEmpty &&
                field.dict[passwordWithheldKey] == const CosBoolean(true)
            ? '*' * withheldPasswordMaskLength
            : maskedPasswordText(rawText);
      }
    }
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
      } else if (comb) {
        lines = [text.replaceAll('\n', ' ')];
        if (size == 0) {
          // auto-size: the height sets the size, then the widest glyph must
          // fit its cell (a comb spans the full width, no side padding)
          size = (visual.height - 2 * pad) / lineFactor;
          final cell = visual.width / maxLength!;
          var widest = 0.0;
          for (final r in lines.first.runes) {
            widest = math.max(widest, measure(String.fromCharCode(r), size));
          }
          if (widest > cell && widest > 0) size *= cell / widest;
          size = size.clamp(4.0, 144.0);
        }
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
      void emitRun(ContentWriter w, String rendered) {
        if (embedded != null) {
          w.showGlyphHex(embedded.encodeHex(rendered));
        } else {
          w.showText(rendered);
        }
      }

      if (comb) {
        _writeCombText(
          writer,
          visual,
          pdfVisualText(lines.first, resolvedDirection),
          cells: maxLength!,
          font: font,
          fontSize: size,
          align: align,
          padding: pad,
          verticalAlignment: verticalAlignment,
          measure: (s) => measure(s, size),
          writeColor: (w) => w.raw(da.colorOps),
          emit: emitRun,
        );
      } else {
        writePdfTextBox(
          writer,
          visual,
          lines,
          font: font,
          fontSize: size,
          align: align,
          padding: pad,
          lineHeight: size * lineFactor,
          vAlign: switch (verticalAlignment) {
            PdfFormTextVerticalAlignment.top => PdfTextBoxVAlign.top,
            PdfFormTextVerticalAlignment.center => PdfTextBoxVAlign.centerBlock,
            PdfFormTextVerticalAlignment.bottom => PdfTextBoxVAlign.bottomBlock,
            PdfFormTextVerticalAlignment.legacy ||
            null =>
              multiline ? PdfTextBoxVAlign.top : PdfTextBoxVAlign.centerLine,
          },
          clampVerticalAlign: verticalAlignment != null,
          clip: false,
          clampAlign: true,
          measureLine: (s) => measure(s, size),
          writeColor: (w) => w.raw(da.colorOps),
          emitLine: (w, line) =>
              emitRun(w, pdfVisualText(line, resolvedDirection)),
        );
      }
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

  /// A comb field's single line (§12.7.4.3): [box]'s full width splits
  /// into [cells] equal cells and each character of [text] (already in
  /// visual order) is centred in its own cell. Fewer characters than cells
  /// start in the first cell, or end in the last for right quadding, or sit
  /// in the middle cells for centred quadding. The baseline follows the
  /// single-line placement (ascent-centred) unless a vertical preference is
  /// saved. Characters past [cells] are dropped - callers truncate to
  /// /MaxLen first.
  void _writeCombText(
    ContentWriter writer,
    PdfRect box,
    String text, {
    required int cells,
    required PdfTextFont font,
    required double fontSize,
    required PdfTextAlign align,
    required double padding,
    required PdfFormTextVerticalAlignment? verticalAlignment,
    required double Function(String s) measure,
    required void Function(ContentWriter w) writeColor,
    required void Function(ContentWriter w, String glyph) emit,
  }) {
    final glyphs = [
      for (final r in text.runes) String.fromCharCode(r),
    ].take(cells).toList();
    final cellWidth = box.width / cells;
    final first = switch (align) {
      PdfTextAlign.left => 0,
      PdfTextAlign.center => (cells - glyphs.length) ~/ 2,
      PdfTextAlign.right => cells - glyphs.length,
    };
    final ascent = fontSize * font.ascent / 1000;
    final y = switch (verticalAlignment) {
      PdfFormTextVerticalAlignment.top => box.top - padding - ascent,
      PdfFormTextVerticalAlignment.bottom =>
        box.bottom + padding + fontSize - ascent,
      PdfFormTextVerticalAlignment.center ||
      PdfFormTextVerticalAlignment.legacy ||
      null =>
        box.bottom + math.max(padding, (box.height - ascent) / 2),
    };
    writer
      ..beginText()
      ..font(font.resourceName, fontSize);
    writeColor(writer);
    var prevX = 0.0, prevY = 0.0;
    for (var i = 0; i < glyphs.length; i++) {
      final glyph = glyphs[i];
      if (glyph == ' ') continue;
      final x = box.left + (first + i + 0.5) * cellWidth - measure(glyph) / 2;
      writer.textAt(x - prevX, y - prevY);
      emit(writer, glyph);
      prevX = x;
      prevY = y;
    }
    writer.endText();
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
    // the XFA copy of a hybrid form still holds the old values, and an
    // XFA-aware viewer would show those instead of what was just filled
    removeXfa();
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
