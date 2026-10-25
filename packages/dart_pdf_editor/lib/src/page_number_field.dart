import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'design/material_host.dart';
import 'pdf_viewer.dart';

/// The classic "page 3 / 12" indicator, with the page number editable:
/// type a number and press enter (or leave the field) to jump there.
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

  /// What the field last displayed on its own (not typed), so a blur only
  /// commits a real edit - including the blur [_submit] itself causes.
  String _shown = '';

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
      _commitOnBlur();
    }
  }

  // Leaving the field commits what was typed, however focus was lost: a
  // tap outside, the browser's keyboard "Done" (mobile web gives a bare
  // number pad with no return key, and the blur arrives before any tap
  // reaches Flutter), or tabbing away. An untouched field just re-syncs
  // rather than re-jumping (which would snap the scroll to the page top).
  void _commitOnBlur() {
    if (_field.text.trim() == _shown) {
      _reset();
    } else {
      _submit(_field.text);
    }
  }

  void _reset() => _show(_displayFor(widget.controller.currentPage));

  void _show(String text) => _field.text = _shown = text;

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
      _show(_displayFor(target));
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
          // iOS's plain number pad has no return key, so there was no
          // way to submit; `signed` maps to numbers-and-punctuation there
          // (which has one) and to the same digit pad elsewhere. Digits
          // stay enforced by the formatter.
          keyboardType: labelled
              ? TextInputType.text
              : const TextInputType.numberWithOptions(signed: true),
          textInputAction: TextInputAction.go,
          inputFormatters:
              labelled ? const [] : [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            border: OutlineInputBorder(),
          ),
          onSubmitted: _submit,
          // a tap outside drops focus on every platform; the blur commits
          onTapOutside: (_) => _focus.unfocus(),
          contextMenuBuilder: pdfTextContextMenu,
        ),
      ),
      Text(
        labelled ? '  (${controller.currentPage + 1} / $count)' : ' / $count',
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
