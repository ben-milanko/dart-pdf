part of 'editor.dart';

/// AcroForm structure editing: creating, renaming, retyping, and removing
/// fields, plus flattening the whole form into page content.
///
/// Everything here is lenient toward broken field trees — orphaned
/// widgets, missing pages, and unresolvable references are skipped, not
/// fatal — because template PDFs in the wild are routinely hand-mangled.
extension PdfFormAdmin on PdfEditor {
  /// Adds a single-widget text field named [name] on [pageIndex].
  /// The document gains an /AcroForm dictionary if it has none.
  PdfFormField addTextField(int pageIndex, String name, PdfRect rect,
      {bool multiline = false}) {
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

  /// Adds a push-button field — the conventional carrier for images
  /// (see [PdfFormFilling.setButtonImage]). The button renders blank
  /// until an image or appearance is set.
  PdfFormField addPushButtonField(int pageIndex, String name, PdfRect rect) {
    final dict = _newFieldDict('Btn', name, rect);
    dict['Ff'] = const CosInteger(PdfFormField.pushButtonFlag);
    final field = _installField(pageIndex, name, dict);
    // a blank normal appearance so viewers (and flattening) treat the
    // empty button as drawable rather than missing
    final rectangle = field.widgetRect(0)!;
    _setNormalAppearance(field.dict,
        _widgetForm(rectangle.width, rectangle.height, ContentWriter()));
    _stageFormDict(field, field.dict);
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
            newName, 'newName', 'another field is already named "$full"');
      }
    }
    field.dict['T'] = CosString.fromText(newName);
    _stageFormDict(field, field.dict);
  }

  /// Removes [field] from the form and detaches its widgets from their
  /// pages, so no visible artifacts remain. Widgets no page claims are
  /// skipped silently.
  void removeField(PdfFormField field) {
    final cos = document.cos;
    final widgets = field.widgets;

    // detach widgets from every page that lists them.
    for (var i = 0; i < document.pageCount; i++) {
      _PdfPageAnnotationList(this, i).removeWhere(
          (_, resolved) => _isFieldWidget(resolved, field, widgets),
          removeIfEmpty: true);
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
  }

  static bool _isFieldWidget(
      CosObject? annot, PdfFormField field, List<CosDictionary> widgets) {
    if (identical(annot, field.dict)) return true;
    for (final widget in widgets) {
      if (identical(widget, annot)) return true;
    }
    return false;
  }

  /// Rebuilds [field] as [newType] (text, check box, or push button) at
  /// its first widget's page and rectangle, keeping the name — so
  /// pipelines that resolve fields by name keep working after an
  /// operator fixes a mis-typed template field.
  ///
  /// Multi-widget fields collapse to a single widget at the first
  /// widget's rectangle. Throws [StateError] when no page/rect can be
  /// determined, [ArgumentError] for unsupported target types.
  PdfFormField changeFieldType(PdfFormField field, PdfFieldType newType) {
    const supported = {
      PdfFieldType.text,
      PdfFieldType.checkBox,
      PdfFieldType.pushButton,
    };
    if (!supported.contains(newType)) {
      throw ArgumentError.value(newType, 'newType',
          'only ${supported.map((t) => t.name).join('/')} are supported');
    }
    if (field.type == newType) return field;
    final pageIndex = field.widgetPageIndex(0);
    final rect = field.widgetRect(0);
    if (pageIndex < 0 || rect == null) {
      throw StateError('field "${field.name}" has no widget bound to a page — '
          'cannot rebuild');
    }
    final name = field.name;
    removeField(field);
    return switch (newType) {
      PdfFieldType.text => addTextField(pageIndex, name, rect),
      PdfFieldType.checkBox => addCheckBoxField(pageIndex, name, rect),
      _ => addPushButtonField(pageIndex, name, rect),
    };
  }

  /// Flattens the interactive form: paints every widget's current
  /// appearance into its page's content, then removes all fields and
  /// their widgets. Fields without a paintable appearance simply
  /// disappear. Broken structures — widgets without pages, unparseable
  /// rectangles, corrupt appearance streams — are skipped, never fatal.
  void flattenForm() {
    final form = acroForm;
    if (form == null) return;
    for (var i = 0; i < document.pageCount; i++) {
      try {
        _flattenAnnotations(i, (annot) => annot.subtype == 'Widget');
      } catch (_) {
        // a malformed page must not stop the rest of the form
      }
    }
    for (final field in form.fields) {
      try {
        removeField(field);
      } catch (_) {}
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
    final cos = document.cos;
    final existing = acroForm?.fieldNamed(name);
    if (existing != null) {
      throw ArgumentError.value(
          name, 'name', 'another field is already named "$name"');
    }
    final page = document.page(pageIndex);

    var formDict = cos.resolve(document.catalog['AcroForm']);
    if (formDict is! CosDictionary) {
      formDict = CosDictionary({
        'Fields': CosArray(),
        'DA': CosString.fromText('/Helv 0 Tf 0 g'),
        'DR': CosDictionary({
          'Font': CosDictionary({
            'Helv': _updater.addObject(CosDictionary({
              'Type': const CosName('Font'),
              'Subtype': const CosName('Type1'),
              'BaseFont': const CosName('Helvetica'),
              'Encoding': const CosName('WinAnsiEncoding'),
            })),
          }),
        }),
      });
      document.catalog['AcroForm'] = formDict;
      _updater.markChanged(document.catalog);
    }

    final ref = _updater.addObject(dict);
    // reassign rather than mutate, in case the arrays were indirect
    final fields = cos.resolve(formDict['Fields']);
    formDict['Fields'] =
        CosArray([if (fields is CosArray) ...fields.items, ref]);

    final pageRef = cos.referenceTo(page.dict);
    if (pageRef != null) dict['P'] = pageRef;
    _PdfPageAnnotationList(this, pageIndex).append(ref);

    final formRef = cos.referenceTo(formDict);
    if (formRef != null) {
      _updater.replaceObject(formRef.objectNumber, formDict);
    } else {
      _updater.markChanged(document.catalog);
    }

    final field = PdfAcroForm.of(document)?.fieldNamed(name);
    if (field == null) {
      throw StateError('field "$name" failed to register');
    }
    return field;
  }
}
