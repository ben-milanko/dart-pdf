part of 'editor.dart';

/// Form scripts on the fill path (see `form_scripts.dart`): user entry is
/// checked by the field's keystroke and validate helpers, and every value
/// change re-runs the form's calculations in /CO order within the same
/// edit. Format helpers apply where the appearance is generated
/// ([PdfFormFilling]'s variable-text regeneration), so /V keeps the raw
/// value.
extension PdfFormScriptFilling on PdfEditor {
  /// Sets a text field the way a user entering [value] would: the field's
  /// keystroke script (on commit) and validate script check it first, and
  /// the possibly normalised value is what [setTextValue] stores - a
  /// number typed as "1.234,50" in a comma-decimal field stores "1234.50".
  ///
  /// Throws [PdfFieldInputException] (an [ArgumentError]) with a message the
  /// UI can show when a script refuses the value; nothing is changed then.
  /// Fields without recognised scripts store [value] verbatim, exactly like
  /// [setTextValue], which remains the programmatic setter that skips the
  /// checks (as assigning a field value from script does).
  PdfFieldInputResult enterTextValue(
    PdfFormField field,
    String value, {
    PdfTextDirection textDirection = PdfTextDirection.auto,
  }) {
    _checkFillable(field, const {PdfFieldType.text});
    final result = field.checkInput(value);
    if (!result.isValid) throw PdfFieldInputException(field.name, result);
    setTextValue(field, result.value, textDirection: textDirection);
    return result;
  }

  /// Re-runs every supported calculate script in the form's calculation
  /// order and writes the fields whose value changed (read-only calculated
  /// fields included), regenerating their appearances. [skip] names a field
  /// to leave alone. Returns what changed. The fill setters call this after
  /// each value change; call it directly after bulk edits made another way.
  List<PdfCalculatedValue> recalculateFields({String? skip}) {
    final form = acroForm;
    if (form == null) return const [];
    return _applyCalculations(form, skip: skip);
  }

  /// The fill setters' hook: recalculates after [field]'s value changed,
  /// keeping the value just entered in [field] itself.
  void _recalculateAfter(PdfFormField field) {
    _applyCalculations(field.form, skip: field.name);
  }

  List<PdfCalculatedValue> _applyCalculations(PdfAcroForm form,
      {String? skip}) {
    final changed = form.calculate(skip: skip);
    for (final c in changed) {
      final field = c.field;
      field.dict['V'] = CosString.fromText(c.value);
      _regenerateVariableText(field, c.value);
      _finishFieldEdit(field);
    }
    return changed;
  }
}
