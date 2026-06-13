import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks the user for an inclusive page range, returning it 0-based as
/// `(start, end)` — or null when cancelled. [pageCount] bounds the input
/// and seeds the default span (the whole document, unless [initialStart]/
/// [initialEnd] narrow it). Fields are shown 1-based.
///
/// Used by the editor shell's "Export pages…" action; exposed for hosts
/// building their own chrome around [PdfEditingController.exportPageRange].
Future<({int start, int end})?> showPdfPageRangeDialog(
  BuildContext context, {
  required int pageCount,
  int? initialStart,
  int? initialEnd,
  String title = 'Export pages',
  String confirmLabel = 'Export',
}) {
  return showDialog<({int start, int end})>(
    context: context,
    builder: (context) => _PdfPageRangeDialog(
      pageCount: pageCount,
      initialStart: (initialStart ?? 0).clamp(0, pageCount - 1),
      initialEnd: (initialEnd ?? pageCount - 1).clamp(0, pageCount - 1),
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PdfPageRangeDialog extends StatefulWidget {
  const _PdfPageRangeDialog({
    required this.pageCount,
    required this.initialStart,
    required this.initialEnd,
    required this.title,
    required this.confirmLabel,
  });

  final int pageCount;
  final int initialStart;
  final int initialEnd;
  final String title;
  final String confirmLabel;

  @override
  State<_PdfPageRangeDialog> createState() => _PdfPageRangeDialogState();
}

class _PdfPageRangeDialogState extends State<_PdfPageRangeDialog> {
  late final TextEditingController _from =
      TextEditingController(text: '${widget.initialStart + 1}');
  late final TextEditingController _to =
      TextEditingController(text: '${widget.initialEnd + 1}');

  String? _error;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  /// Parses a 1-based field to a 0-based index within range, or null.
  int? _parse(TextEditingController field) {
    final n = int.tryParse(field.text.trim());
    if (n == null || n < 1 || n > widget.pageCount) return null;
    return n - 1;
  }

  void _submit() {
    final start = _parse(_from);
    final end = _parse(_to);
    if (start == null || end == null) {
      setState(() => _error = 'Enter pages between 1 and ${widget.pageCount}.');
      return;
    }
    if (end < start) {
      setState(() => _error = 'The last page must not be before the first.');
      return;
    }
    Navigator.of(context).pop((start: start, end: end));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController controller, Key key) =>
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );

    return AlertDialog(
      key: const ValueKey('pdf-page-range-dialog'),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.pageCount} pages',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(children: [
            field('From', _from, const ValueKey('pdf-page-range-from')),
            const SizedBox(width: 16),
            field('To', _to, const ValueKey('pdf-page-range-to')),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('pdf-page-range-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pdf-page-range-confirm'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
