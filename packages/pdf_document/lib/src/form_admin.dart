part of 'editor.dart';

/// AcroForm structure editing: creating, renaming, retyping, and removing
/// fields, plus flattening the whole form into page content.
///
/// Everything here is lenient toward broken field trees - orphaned
/// widgets, missing pages, and unresolvable references are skipped, not
/// fatal - because template PDFs in the wild are routinely hand-mangled.
extension PdfFormAdmin on PdfEditor {
  /// Adds a single-widget text field named [name] on [pageIndex].
  /// The document gains an /AcroForm dictionary if it has none.
  PdfFormField addTextField(
    int pageIndex,
    String name,
    PdfRect rect, {
    bool multiline = false,
  }) {
    final dict = _newFieldDict('Tx', name, rect);
    if (multiline) dict['Ff'] = const CosInteger(PdfFormField.multilineFlag);
    return _installField(pageIndex, name, dict);
  }

  /// Adds a check-box field (off by default) with generated check-mark
  /// appearance states.
  PdfFormField addCheckBoxField(int pageIndex, String name, PdfRect rect) {
    final dict = _newFieldDict('Btn', name, rect);
    dict['V'] = const CosName('Off');
    dict['AS'] = const CosName('Off');
    final field = _installField(pageIndex, name, dict);
    _ensureButtonAppearances(field);
    _stageFormDict(field, field.dict);
    return field;
  }

  /// Adds a push-button field - the conventional carrier for images
  /// (see [PdfFormFilling.setButtonImage]). The button renders blank
  /// until an image or appearance is set.
  PdfFormField addPushButtonField(int pageIndex, String name, PdfRect rect) {
    final dict = _newFieldDict('Btn', name, rect);
    dict['Ff'] = const CosInteger(PdfFormField.pushButtonFlag);
    final field = _installField(pageIndex, name, dict);
    // a blank normal appearance so viewers (and flattening) treat the
    // empty button as drawable rather than missing
    final rectangle = field.widgetRect(0)!;
    _setNormalAppearance(
      field.dict,
      _widgetForm(rectangle.width, rectangle.height, ContentWriter()),
    );
    _stageFormDict(field, field.dict);
    return field;
  }

  /// Adds a radio group named [name] on [pageIndex]: one parent field with
  /// a kid widget per entry of [buttons], each selecting its own on-state
  /// (the value the field takes when that button is chosen). Every widget
  /// gets generated /AP /N and /D {onState, Off} appearances. [selected]
  /// pre-selects one of the on-states; the group starts off otherwise.
  ///
  /// Throws [ArgumentError] when [buttons] is empty, an on-state is empty,
  /// "Off" or repeated, [selected] names no button, or [name] is taken.
  /// Add more buttons later with [addRadioButton].
  PdfFormField addRadioGroup(
    int pageIndex,
    String name,
    List<(PdfRect rect, String onState)> buttons, {
    String? selected,
  }) {
    if (buttons.isEmpty) {
      throw ArgumentError.value(buttons, 'buttons', 'must not be empty');
    }
    _checkRadioStates(buttons.map((b) => b.$2));
    if (selected != null && !buttons.any((b) => b.$2 == selected)) {
      throw ArgumentError.value(selected, 'selected', 'names no button');
    }
    _checkFreshName(name);
    // pre-check the page index before anything is staged
    document.page(pageIndex);
    final parent = CosDictionary({
      'FT': const CosName('Btn'),
      'T': CosString.fromText(name),
      'Ff': const CosInteger(
        PdfFormField.radioFlag | PdfFormField.noToggleToOffFlag,
      ),
      'V': CosName(selected ?? 'Off'),
      'Kids': CosArray(),
    });
    final formDict = _ensureAcroFormDict();
    final parentRef = _updater.addObject(parent);
    for (final (rect, onState) in buttons) {
      _appendRadioKid(parent, parentRef, pageIndex, rect, onState);
    }
    _appendRootField(formDict, parentRef);
    _stageAcroForm(formDict);
    final field = _registeredField(name, [pageIndex]);
    _generateRadioStates(field);
    return field;
  }

  /// Adds another button to the radio group [group] at [rect] on
  /// [pageIndex] (any page - a group may span several), selecting
  /// [onState]. Returns the group re-read with the new widget last in
  /// [PdfFormField.widgets].
  ///
  /// Throws [ArgumentError] when [group] is not a radio group or [onState]
  /// is empty, "Off" or already used by the group, and [StateError] when
  /// the group is a single merged field/widget dictionary (it has no
  /// /Kids to extend) or is not an indirect object.
  PdfFormField addRadioButton(
    PdfFormField group,
    int pageIndex,
    PdfRect rect,
    String onState,
  ) {
    if (group.type != PdfFieldType.radioGroup) {
      throw ArgumentError.value(
        group.type,
        'group',
        'field "${group.name}" is not a radio group',
      );
    }
    _checkRadioStates([...group.onStates, onState]);
    final parent = group.dict;
    final parentRef = document.cos.referenceTo(parent);
    final kids = document.cos.resolve(parent['Kids']);
    if (parentRef == null || kids is! CosArray) {
      throw StateError(
        'radio group "${group.name}" is a single merged widget - '
        'it has no /Kids to add a button to',
      );
    }
    document.page(pageIndex);
    _appendRadioKid(parent, parentRef, pageIndex, rect, onState);
    _stageFormDict(group, parent);
    final field = _registeredField(group.name, [pageIndex]);
    _generateRadioStates(field);
    return field;
  }

  /// Adds a combo box (drop-down) named [name] offering [options] as
  /// (export value, display text) pairs. [editable] sets the Edit flag, so
  /// a filler may type a value that is not in the list.
  PdfFormField addComboBoxField(
    int pageIndex,
    String name,
    PdfRect rect,
    List<(String export, String display)> options, {
    bool editable = false,
  }) {
    final dict = _newFieldDict('Ch', name, rect);
    dict['Ff'] = CosInteger(
      PdfFormField.comboFlag | (editable ? PdfFormField.editFlag : 0),
    );
    dict['Opt'] = _optArray(options);
    final field = _installField(pageIndex, name, dict);
    _regenerateChoice(field);
    _stageFormDict(field, field.dict);
    return field;
  }

  /// Adds a list box named [name] offering [options] as (export value,
  /// display text) pairs. [multiSelect] sets the MultiSelect flag, letting
  /// a filler choose more than one option.
  PdfFormField addListBoxField(
    int pageIndex,
    String name,
    PdfRect rect,
    List<(String export, String display)> options, {
    bool multiSelect = false,
  }) {
    final dict = _newFieldDict('Ch', name, rect);
    if (multiSelect) {
      dict['Ff'] = const CosInteger(PdfFormField.multiSelectFlag);
    }
    dict['Opt'] = _optArray(options);
    final field = _installField(pageIndex, name, dict);
    _regenerateChoice(field);
    _stageFormDict(field, field.dict);
    return field;
  }

  /// Replaces a combo or list box's /Opt with [options] (export, display)
  /// pairs and, when given, its Edit ([editable], combo boxes) and
  /// MultiSelect ([multiSelect], list boxes) flags. Selected values the new
  /// options still offer are kept (all of them for a multi-select list box,
  /// the first otherwise) with /I and /TI rewritten to match; values no
  /// longer offered are dropped unless the combo box is editable. The
  /// appearance is regenerated through the same choice renderer filling
  /// uses, so a list box redraws every option row.
  PdfFormField setChoiceOptions(
    PdfFormField field,
    List<(String export, String display)> options, {
    bool? editable,
    bool? multiSelect,
  }) {
    if (field.type != PdfFieldType.comboBox &&
        field.type != PdfFieldType.listBox) {
      throw ArgumentError.value(
        field.type,
        'field',
        'field "${field.name}" is not a choice field',
      );
    }
    var flags = field.flags;
    if (editable != null && field.type == PdfFieldType.comboBox) {
      flags = editable
          ? flags | PdfFormField.editFlag
          : flags & ~PdfFormField.editFlag;
    }
    if (multiSelect != null && field.type == PdfFieldType.listBox) {
      flags = multiSelect
          ? flags | PdfFormField.multiSelectFlag
          : flags & ~PdfFormField.multiSelectFlag;
    }
    // read the current selection before /Opt changes under it
    final current = field.values;
    field.dict['Ff'] = CosInteger(flags);
    field.dict['Opt'] = _optArray(options);
    for (final key in const ['V', 'I', 'TI']) {
      field.dict.entries.remove(key);
    }
    final editableCombo = field.type == PdfFieldType.comboBox &&
        flags & PdfFormField.editFlag != 0;
    if (editableCombo) {
      // free text is a legal value, offered or not
      if (current.isNotEmpty) field.dict['V'] = CosString.fromText(current[0]);
    } else {
      // keep what is still offered, in option order, at most one unless
      // the (list box) field is multi-select
      final indices = <int>{
        for (final v in current)
          if (options.indexWhere((o) => o.$1 == v) case final i when i >= 0) i,
      }.toList()
        ..sort();
      final kept = field.isMultiSelect ? indices : indices.take(1).toList();
      if (kept.isNotEmpty) {
        field.dict['V'] = kept.length == 1
            ? CosString.fromText(options[kept.single].$1)
            : CosArray([
                for (final i in kept) CosString.fromText(options[i].$1),
              ]);
        if (field.type == PdfFieldType.listBox) {
          field.dict['I'] = CosArray([for (final i in kept) CosInteger(i)]);
          _scrollListSelectionIntoView(field, kept);
        }
      }
    }
    _regenerateChoice(field);
    _finishFieldEdit(field);
    return field;
  }

  /// Adds an unsigned signature field named [name]: a visible /FT /Sig
  /// widget at [rect] for someone to sign later - [PdfSigning.saveSigned]
  /// and the PAdES/self-signed paths fill it by `fieldName`. The form's
  /// /SigFlags gains SignaturesExist (bit 1).
  PdfFormField addSignatureField(int pageIndex, String name, PdfRect rect) {
    final dict = _newFieldDict('Sig', name, rect);
    final field = _installField(pageIndex, name, dict);
    // a blank normal appearance, as for an empty push button, so the
    // unsigned box is drawable (and flattens) rather than missing
    final rectangle = field.widgetRect(0)!;
    _setNormalAppearance(
      field.dict,
      _widgetForm(rectangle.width, rectangle.height, ContentWriter()),
    );
    _stageFormDict(field, field.dict);
    final formDict = field.form.dict;
    final flags = document.cos.resolve(formDict['SigFlags']);
    final current = flags is CosInteger ? flags.value : 0;
    if (current & 1 == 0) {
      formDict['SigFlags'] = CosInteger(current | 1);
      _stageAcroForm(formDict);
    }
    return field;
  }

  /// Renames [field]: rewrites its partial /T so the fully qualified
  /// name becomes its parent prefix joined with [newName]. Throws
  /// [ArgumentError] when [newName] is empty or the resulting name
  /// collides with another field.
  void renameField(PdfFormField field, String newName) {
    if (newName.isEmpty) {
      throw ArgumentError.value(newName, 'newName', 'must be non-empty');
    }
    final cos = document.cos;
    final partial = cos.resolve(field.dict['T']);
    final own = partial is CosString ? partial.text : '';
    var prefix = field.name;
    if (own.isNotEmpty && prefix.endsWith(own)) {
      prefix = prefix.substring(0, prefix.length - own.length);
      if (prefix.endsWith('.')) prefix = prefix.substring(0, prefix.length - 1);
    }
    final full = prefix.isEmpty ? newName : '$prefix.$newName';
    if (full == field.name) return;
    for (final other in field.form.fields) {
      if (!identical(other.dict, field.dict) && other.name == full) {
        throw ArgumentError.value(
          newName,
          'newName',
          'another field is already named "$full"',
        );
      }
    }
    field.dict['T'] = CosString.fromText(newName);
    _stageFormDict(field, field.dict);
    _markMetadata();
  }

  /// Removes [field] from the form and detaches its widgets from their
  /// pages, so no visible artifacts remain. Widgets no page claims are
  /// skipped silently.
  void removeField(PdfFormField field) {
    final cos = document.cos;
    final widgets = field.widgets;
    final pages = <int>{};
    var unknownPage = false;
    for (var i = 0; i < widgets.length; i++) {
      final page = field.widgetPageIndex(i);
      if (page < 0) {
        unknownPage = true;
      } else {
        pages.add(page);
      }
    }

    // detach widgets from every page that lists them.
    for (var i = 0; i < document.pageCount; i++) {
      _PdfPageAnnotationList(this, i).removeWhere(
        (_, resolved) => _isFieldWidget(resolved, field, widgets),
        removeIfEmpty: true,
      );
    }

    // pull the field node out of its parent /Kids or the form /Fields
    final parent = cos.resolve(field.dict['Parent']);
    final container = parent is CosDictionary
        ? cos.resolve(parent['Kids'])
        : cos.resolve(field.form.dict['Fields']);
    if (container is CosArray) {
      final remaining = [
        for (final item in container.items)
          if (!identical(cos.resolve(item), field.dict)) item,
      ];
      if (parent is CosDictionary) {
        parent['Kids'] = CosArray(remaining);
        _stageFormDict(field, parent);
      } else {
        field.form.dict['Fields'] = CosArray(remaining);
        final ref = cos.referenceTo(field.form.dict);
        if (ref != null) {
          _updater.replaceObject(ref.objectNumber, field.form.dict);
        } else {
          _updater.markChanged(document.catalog);
        }
      }
    }
    // Removing a field also rewrites every page's /Annots array. Report that
    // lane explicitly so viewers discard cached widget rectangles and hit
    // targets, rather than retaining the interactive highlight over the new
    // page revision.
    _markAnnotations(unknownPage ? null : pages);
  }

  static bool _isFieldWidget(
    CosObject? annot,
    PdfFormField field,
    List<CosDictionary> widgets,
  ) {
    if (identical(annot, field.dict)) return true;
    for (final widget in widgets) {
      if (identical(widget, annot)) return true;
    }
    return false;
  }

  /// Rebuilds [field] as [newType] at its first widget's page and
  /// rectangle, keeping the name - so pipelines that resolve fields by
  /// name keep working after an operator fixes a mis-typed template field.
  ///
  /// Every creatable type is a target: text, check box, push button,
  /// radio group, combo box, list box, and (unsigned) signature. What
  /// carries over is what still means something in the new type: a
  /// choice field keeps its options between combo and list box; a check
  /// box becomes a one-button radio group with the same on-state; a radio group becomes a combo or list box offering its
  /// on-states. Values are not carried over.
  ///
  /// Multi-widget fields collapse to a single widget at the first
  /// widget's rectangle. Throws [StateError] when no page/rect can be
  /// determined or [field] is a signed signature (retyping would discard
  /// the signature), [ArgumentError] for [PdfFieldType.unknown].
  PdfFormField changeFieldType(PdfFormField field, PdfFieldType newType) {
    if (newType == PdfFieldType.unknown) {
      throw ArgumentError.value(
        newType,
        'newType',
        'a field cannot be converted to an unknown type',
      );
    }
    if (field.type == newType) return field;
    if (field.type == PdfFieldType.signature &&
        document.cos.resolve(field.dict['V']) is CosDictionary) {
      throw StateError(
        'field "${field.name}" is signed - retyping would discard the '
        'signature',
      );
    }
    final pageIndex = field.widgetPageIndex(0);
    final rect = field.widgetRect(0);
    if (pageIndex < 0 || rect == null) {
      throw StateError(
        'field "${field.name}" has no widget bound to a page - '
        'cannot rebuild',
      );
    }
    final name = field.name;
    final options = switch (field.type) {
      PdfFieldType.comboBox || PdfFieldType.listBox => field.options,
      PdfFieldType.radioGroup => [for (final s in field.onStates) (s, s)],
      _ => const <(String, String)>[],
    };
    final onState = field.type == PdfFieldType.checkBox ||
            field.type == PdfFieldType.radioGroup
        ? field.widgetOnState(0)
        : null;
    removeField(field);
    return switch (newType) {
      PdfFieldType.text => addTextField(pageIndex, name, rect),
      PdfFieldType.checkBox => addCheckBoxField(pageIndex, name, rect),
      PdfFieldType.pushButton => addPushButtonField(pageIndex, name, rect),
      PdfFieldType.radioGroup =>
        addRadioGroup(pageIndex, name, [(rect, onState ?? 'Choice1')]),
      PdfFieldType.comboBox => addComboBoxField(pageIndex, name, rect, options),
      PdfFieldType.listBox => addListBoxField(pageIndex, name, rect, options),
      PdfFieldType.signature => addSignatureField(pageIndex, name, rect),
      PdfFieldType.unknown => throw StateError('unreachable'),
    };
  }

  /// Flattens the interactive form: paints every widget's current
  /// appearance into its page's content, then removes all fields and
  /// their widgets. Missing appearances are generated first, so empty
  /// fields retain their background and border after flattening. Broken
  /// structures - widgets without pages, unparseable rectangles, corrupt
  /// appearance streams - are skipped, never fatal. The form's XFA copy
  /// is removed too ([PdfFormFilling.removeXfa]).
  void flattenForm() {
    final form = acroForm;
    if (form == null) return;
    for (final field in form.fields) {
      try {
        _prepareFieldForFlatten(field);
      } catch (_) {
        // a malformed field must not stop the rest of the form
      }
    }
    for (var i = 0; i < document.pageCount; i++) {
      try {
        _flattenAnnotations(
          i,
          (annot) => annot.subtype == 'Widget',
          syncAnnotations: false,
        );
      } catch (_) {
        // a malformed page must not stop the rest of the form
      }
    }
    for (final field in form.fields) {
      try {
        removeField(field);
      } catch (_) {}
    }
    // with the fields gone, an XFA-aware viewer would bring them back from
    // the XFA packet over the flattened page content
    removeXfa();
  }

  /// Materializes normal appearances that a viewer would otherwise have to
  /// synthesize from the field value and widget characteristics. In
  /// particular, untouched empty text fields commonly have no /AP at all.
  void _prepareFieldForFlatten(PdfFormField field) {
    final missing = <int>[];
    final widgets = field.widgets;
    for (var i = 0; i < widgets.length; i++) {
      final annotation = PdfAnnotation.fromDict(document, widgets[i]);
      if (field.widgetPageIndex(i) >= 0 &&
          !annotation.isHidden &&
          !annotation.isNoView &&
          annotation.normalAppearance == null) {
        missing.add(i);
      }
    }
    if (missing.isEmpty) return;

    switch (field.type) {
      case PdfFieldType.text:
        _regenerateVariableText(field, field.value ?? '');
      case PdfFieldType.comboBox:
      case PdfFieldType.listBox:
        _regenerateChoice(field);
      case PdfFieldType.checkBox:
      case PdfFieldType.radioGroup:
        _ensureButtonAppearances(field);
        final state = field.value ?? 'Off';
        for (final i in missing) {
          final widget = widgets[i];
          final states = _widgetStates(widget);
          widget['AS'] = CosName(states.contains(state) ? state : 'Off');
        }
      case PdfFieldType.pushButton:
      case PdfFieldType.signature:
      case PdfFieldType.unknown:
        for (final i in missing) {
          final widget = widgets[i];
          final rect = pdfRectFrom(document.cos, widget['Rect']);
          if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
          final rotation = _prepareWidgetRotation(field, i, widget);
          final visual = PdfFormFilling._orientedWidgetRect(
            rect.width,
            rect.height,
            rotation,
          );
          final writer = ContentWriter();
          PdfFormFilling._beginWidgetOrientation(
            writer,
            rect.width,
            rect.height,
            rotation,
          );
          _paintWidgetDecorations(writer, widget, visual);
          PdfFormFilling._endWidgetOrientation(writer, rotation);
          _setNormalAppearance(
            widget,
            _widgetForm(rect.width, rect.height, writer),
          );
        }
    }
  }

  // ---------------------------------------------------------------------

  /// A merged field + widget dictionary (single-widget field).
  CosDictionary _newFieldDict(String fieldType, String name, PdfRect rect) =>
      CosDictionary({
        'Type': const CosName('Annot'),
        'Subtype': const CosName('Widget'),
        'FT': CosName(fieldType),
        'T': CosString.fromText(name),
        'Rect': CosArray([
          CosReal(rect.left),
          CosReal(rect.bottom),
          CosReal(rect.right),
          CosReal(rect.top),
        ]),
        'F': const CosInteger(4), // print
      });

  /// Registers [dict] as a root field and a page annotation, creating
  /// the /AcroForm dictionary when the document has none.
  PdfFormField _installField(int pageIndex, String name, CosDictionary dict) {
    _checkFreshName(name);
    _prepareWidget(dict, pageIndex);
    final formDict = _ensureAcroFormDict();
    final ref = _updater.addObject(dict);
    _appendRootField(formDict, ref);
    _PdfPageAnnotationList(this, pageIndex).append(ref);
    _stageAcroForm(formDict);
    return _registeredField(name, [pageIndex]);
  }

  /// A kid widget (no /T - the parent field names it) for a field split
  /// into several widgets, such as a radio group's buttons.
  CosDictionary _newKidWidget(PdfRect rect, CosReference parent) =>
      CosDictionary({
        'Type': const CosName('Annot'),
        'Subtype': const CosName('Widget'),
        'Parent': parent,
        'Rect': CosArray([
          CosReal(rect.left),
          CosReal(rect.bottom),
          CosReal(rect.right),
          CosReal(rect.top),
        ]),
        'F': const CosInteger(4), // print
      });

  /// Adds one radio button widget to the group [parent] (already an
  /// indirect object at [parentRef]) on [pageIndex]: /Kids and the page's
  /// /Annots gain it, and it carries placeholder /AP state names so
  /// [_generateRadioStates] can paint them.
  void _appendRadioKid(
    CosDictionary parent,
    CosReference parentRef,
    int pageIndex,
    PdfRect rect,
    String onState,
  ) {
    final widget = _newKidWidget(rect, parentRef);
    final selected = document.cos.resolve(parent['V']);
    widget['AS'] = CosName(
      selected is CosName && selected.value == onState ? onState : 'Off',
    );
    widget['AP'] = CosDictionary({
      'N': CosDictionary({
        onState: CosNull.instance,
        'Off': CosNull.instance,
      }),
    });
    _prepareWidget(widget, pageIndex);
    final ref = _updater.addObject(widget);
    final kids = document.cos.resolve(parent['Kids']);
    parent['Kids'] = CosArray([
      if (kids is CosArray) ...kids.items,
      ref,
    ]);
    _PdfPageAnnotationList(this, pageIndex).append(ref);
  }

  /// Paints the on/off states of every radio widget in [field] that still
  /// carries the placeholder states [_appendRadioKid] set, through the same
  /// generator a fill or resize uses, and mirrors /N into /D (the down
  /// appearance) so the button shows its state while pressed.
  void _generateRadioStates(PdfFormField field) {
    final cos = document.cos;
    final widgets = field.widgets;
    for (var i = 0; i < widgets.length; i++) {
      final widget = widgets[i];
      final ap = cos.resolve(widget['AP']);
      if (ap is! CosDictionary) continue;
      final n = cos.resolve(ap['N']);
      if (n is! CosDictionary || n.entries.values.any((v) => v is! CosNull)) {
        continue;
      }
      _regenerateButtonStates(field, i, widget);
      final fresh = cos.resolve(widget['AP']);
      if (fresh is CosDictionary) {
        final normal = cos.resolve(fresh['N']);
        if (normal is CosDictionary) {
          fresh['D'] = CosDictionary(Map.of(normal.entries));
        }
      }
      _stageFormDict(field, widget);
    }
  }

  static void _checkRadioStates(Iterable<String> states) {
    final seen = <String>{};
    for (final state in states) {
      if (state.isEmpty || state == 'Off') {
        throw ArgumentError.value(
          state,
          'onState',
          'must be non-empty and not "Off"',
        );
      }
      if (!seen.add(state)) {
        throw ArgumentError.value(
          state,
          'onState',
          'each button in a group needs its own on-state',
        );
      }
    }
  }

  /// Rewrites /Opt from [options]: a plain string when the export and
  /// display forms agree, an [export display] pair otherwise (§12.7.5.4).
  static CosArray _optArray(List<(String, String)> options) => CosArray([
        for (final (export, display) in options)
          if (export == display)
            CosString.fromText(export)
          else
            CosArray([CosString.fromText(export), CosString.fromText(display)]),
      ]);

  void _checkFreshName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must be non-empty');
    }
    if (acroForm?.fieldNamed(name) != null) {
      throw ArgumentError.value(
        name,
        'name',
        'another field is already named "$name"',
      );
    }
  }

  /// Page-dependent widget entries: /P, and /MK /R so a widget on a
  /// rotated page draws upright.
  void _prepareWidget(CosDictionary widget, int pageIndex) {
    final page = document.page(pageIndex);
    if (page.rotation != 0) {
      final mk = document.cos.resolve(widget['MK']);
      if (mk is CosDictionary) {
        mk['R'] = CosInteger(page.rotation);
      } else {
        widget['MK'] = CosDictionary({'R': CosInteger(page.rotation)});
      }
    }
    final pageRef = document.cos.referenceTo(page.dict);
    if (pageRef != null) widget['P'] = pageRef;
  }

  /// The document's /AcroForm dictionary, created (with a Helvetica /DR
  /// and an auto-size /DA) when the document has none.
  CosDictionary _ensureAcroFormDict() {
    final existing = document.cos.resolve(document.catalog['AcroForm']);
    if (existing is CosDictionary) return existing;
    final formDict = CosDictionary({
      'Fields': CosArray(),
      'DA': CosString.fromText('/Helv 0 Tf 0 g'),
      'DR': CosDictionary({
        'Font': CosDictionary({
          'Helv': _updater.addObject(
            CosDictionary({
              'Type': const CosName('Font'),
              'Subtype': const CosName('Type1'),
              'BaseFont': const CosName('Helvetica'),
              'Encoding': const CosName('WinAnsiEncoding'),
            }),
          ),
        }),
      }),
    });
    document.catalog['AcroForm'] = formDict;
    _updater.markChanged(document.catalog);
    return formDict;
  }

  void _appendRootField(CosDictionary formDict, CosReference ref) {
    // reassign rather than mutate, in case the array was indirect
    final fields = document.cos.resolve(formDict['Fields']);
    formDict['Fields'] = CosArray([
      if (fields is CosArray) ...fields.items,
      ref,
    ]);
  }

  void _stageAcroForm(CosDictionary formDict) {
    final formRef = document.cos.referenceTo(formDict);
    if (formRef != null) {
      _updater.replaceObject(formRef.objectNumber, formDict);
    } else {
      _updater.markChanged(document.catalog);
    }
  }

  PdfFormField _registeredField(String name, Iterable<int> pages) {
    final field = PdfAcroForm.of(document)?.fieldNamed(name);
    if (field == null) {
      throw StateError('field "$name" failed to register');
    }
    _markVisual(pages);
    return field;
  }
}
