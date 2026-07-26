import 'package:flutter/material.dart';

import '../l10n/pdf_l10n.dart';

/// A generous ceiling for the typed readout of an open-ended point/size
/// slider (stroke width, font size, eraser radius, char spacing, font
/// width…). The slider's own scale stays fixed; typing an exact value can
/// go past it, but is capped here so an accidental huge number can't blow
/// up appearance generation or rendering. It is deliberately far larger
/// than any slider max yet small enough to stay safe.
const double kPdfTypedSizeMax = 1000;

/// The numeric readout beside a slider, editable in place: the user can type
/// an exact value instead of nudging the slider (a general rule across the
/// editing UI - any slider's value is directly typeable).
///
/// Tracks the slider's [value] while not focused (so a drag updates the
/// text), and on Enter or focus loss parses, clamps to [fieldMin]..[fieldMax],
/// and commits through [onSubmit] - the same callback the slider fires on
/// change-end. Invalid text reverts to the current value.
///
/// The slider that owns this readout is scaled to [min]..[max], but typing
/// is allowed a wider range: [fieldMin]/[fieldMax] default to [min]/[max]
/// (so the readout matches the slider unless a caller opts in), and callers
/// pass a looser pair to let an exact value exceed the slider's scale - the
/// scale stays put while the field accepts more, within reason.
///
/// [display] formats the value for show (e.g. `42` or `40%`); [parse] inverts
/// it back to the underlying value (defaults to [double.tryParse], so pass a
/// custom one for percentage or unit-suffixed readouts).
class PdfSliderValueField extends StatefulWidget {
  const PdfSliderValueField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onSubmit,
    double? Function(String)? parse,
    double? fieldMin,
    double? fieldMax,
    this.width = 52,
    this.varies = false,
  })  : parse = parse ?? double.tryParse,
        fieldMin = fieldMin ?? min,
        fieldMax = fieldMax ?? max;

  final double value;

  /// The lower/upper bound of the slider's scale - the thumb never moves
  /// outside these.
  final double min;
  final double max;

  /// The clamp applied to a *typed* value. Defaults to [min]/[max]; pass a
  /// wider range to let the field accept values the slider can't reach.
  final double fieldMin;
  final double fieldMax;

  final String Function(double) display;
  final double? Function(String) parse;
  final ValueChanged<double> onSubmit;

  /// Width of the field box; the default fits a 3-digit value or `100%`.
  final double width;

  /// Shows a `Varies` placeholder instead of claiming [value] is common.
  /// The slider may still use [value] as its starting thumb position; typing
  /// or dragging commits one concrete value through [onSubmit].
  final bool varies;

  @override
  State<PdfSliderValueField> createState() => _PdfSliderValueFieldState();
}

class _PdfSliderValueFieldState extends State<PdfSliderValueField> {
  late final TextEditingController _controller = TextEditingController(
      text: widget.varies ? '' : widget.display(widget.value));
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(PdfSliderValueField old) {
    super.didUpdateWidget(old);
    // a slider drag (or an external restyle) moved the value: reflect it,
    // unless the user is mid-edit in this field
    if (!_focus.hasFocus &&
        (widget.value != old.value || widget.varies != old.varies)) {
      _controller.text = widget.varies ? '' : widget.display(widget.value);
    }
  }

  void _commit() {
    final parsed = widget.parse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = widget.varies ? '' : widget.display(widget.value);
      return;
    }
    final clamped = parsed.clamp(widget.fieldMin, widget.fieldMax).toDouble();
    _controller.text = widget.display(clamped);
    widget.onSubmit(clamped);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          hintText: widget.varies ? pdfL10n(context).propVaries : null,
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
