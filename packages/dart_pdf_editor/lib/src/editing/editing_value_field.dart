import 'package:flutter/material.dart';

/// The numeric readout beside a slider, editable in place: the user can type
/// an exact value instead of nudging the slider (a general rule across the
/// editing UI - any slider's value is directly typeable).
///
/// Tracks the slider's [value] while not focused (so a drag updates the
/// text), and on Enter or focus loss parses, clamps to [min]..[max], and
/// commits through [onSubmit] - the same callback the slider fires on
/// change-end. Invalid text reverts to the current value.
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
    this.width = 52,
  }) : parse = parse ?? double.tryParse;

  final double value;
  final double min;
  final double max;
  final String Function(double) display;
  final double? Function(String) parse;
  final ValueChanged<double> onSubmit;

  /// Width of the field box; the default fits a 3-digit value or `100%`.
  final double width;

  @override
  State<PdfSliderValueField> createState() => _PdfSliderValueFieldState();
}

class _PdfSliderValueFieldState extends State<PdfSliderValueField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.display(widget.value));
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
    if (!_focus.hasFocus && widget.value != old.value) {
      _controller.text = widget.display(widget.value);
    }
  }

  void _commit() {
    final parsed = widget.parse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = widget.display(widget.value);
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max).toDouble();
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
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
