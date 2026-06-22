import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pdf_viewer.dart';

/// The classic "page 3 / 12" indicator, with the page number editable:
/// type a number and press enter to jump there.
///
/// Follows the viewer while it scrolls; out-of-range numbers clamp to
/// the document, junk input snaps back. Renders nothing while the
/// controller has no document.
class PdfPageNumberField extends StatefulWidget {
  const PdfPageNumberField({super.key, required this.controller, this.style});

  final PdfViewerController controller;

  /// Applied to both the field and the " / 12" suffix; defaults to the
  /// ambient [TextTheme.titleMedium].
  final TextStyle? style;

  @override
  State<PdfPageNumberField> createState() => _PdfPageNumberFieldState();
}

class _PdfPageNumberFieldState extends State<PdfPageNumberField> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onViewer);
    _focus.addListener(_onFocus);
    _reset();
  }

  @override
  void didUpdateWidget(PdfPageNumberField old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onViewer);
      widget.controller.addListener(_onViewer);
      _reset();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onViewer);
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onViewer() {
    // while the user is typing the field is theirs; it re-syncs on blur
    if (!_focus.hasFocus) _reset();
    if (mounted) setState(() {});
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _field.selection =
          TextSelection(baseOffset: 0, extentOffset: _field.text.length);
    } else {
      _reset();
    }
  }

  void _reset() => _field.text = _displayFor(widget.controller.currentPage);

  String _displayFor(int index) {
    final controller = widget.controller;
    return controller.hasPageLabels
        ? controller.pageLabel(index)
        : '${index + 1}';
  }

  void _submit(String value) {
    final controller = widget.controller;
    final count = controller.pageCount;
    final trimmed = value.trim();
    if (count == 0) {
      _reset();
      _focus.unfocus();
      return;
    }

    // A document with logical labels accepts either a typed label or a
    // physical page number; otherwise only the physical number.
    int? target;
    if (controller.hasPageLabels) {
      target = controller.pageForLabel(trimmed);
    }
    target ??= () {
      final page = int.tryParse(trimmed);
      return page == null ? null : page.clamp(1, count) - 1;
    }();

    if (target != null) {
      _field.text = _displayFor(target);
      unawaited(controller.jumpToPage(target));
    } else {
      _reset();
    }
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final count = controller.pageCount;
    if (count == 0) return const SizedBox.shrink();
    final style = widget.style ?? Theme.of(context).textTheme.titleMedium;
    final labelled = controller.hasPageLabels;
    // size for the longest content the field can hold
    final width = labelled
        ? _labelFieldWidth(controller, count)
        : 24.0 + 10.0 * count.toString().length;
    // labels can be alphanumeric (e.g. "A-3"), so relax the numeric-only
    // constraints when the document carries them.
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: width,
        child: TextField(
          key: const ValueKey('pdf-page-number-field'),
          controller: _field,
          focusNode: _focus,
          style: style,
          textAlign: TextAlign.center,
          keyboardType: labelled ? TextInputType.text : TextInputType.number,
          inputFormatters: labelled
              ? const []
              : [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            border: OutlineInputBorder(),
          ),
          onSubmitted: _submit,
        ),
      ),
      Text(
        labelled
            ? '  (${controller.currentPage + 1} / $count)'
            : ' / $count',
        style: style,
      ),
    ]);
  }

  double _labelFieldWidth(PdfViewerController controller, int count) {
    var longest = 1;
    for (var i = 0; i < count; i++) {
      final len = controller.pageLabel(i).length;
      if (len > longest) longest = len;
    }
    return (24.0 + 10.0 * longest).clamp(40.0, 120.0);
  }
}
