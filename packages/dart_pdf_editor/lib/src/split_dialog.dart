import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import 'dialog.dart';
import 'l10n/pdf_l10n.dart';

/// Asks for comma-separated page ranges, one output PDF per item.
///
/// Input is one-based (for example `1-3, 7, 10-12`); the result contains
/// zero-based inclusive ranges validated against [pageCount]. Cancellation
/// returns null. Hosts can pass the result to
/// `PdfEditingController.exportPageRanges` or [PdfSplitter.split].
Future<List<PdfPageRange>?> showPdfSplitDialog(
  BuildContext context, {
  required int pageCount,
}) {
  if (pageCount < 1) {
    throw RangeError.range(pageCount, 1, null, 'pageCount');
  }
  return showPdfDialog<List<PdfPageRange>>(
    context: context,
    builder: (_) => _SplitDialog(pageCount: pageCount),
  );
}

class _SplitDialog extends StatefulWidget {
  const _SplitDialog({required this.pageCount});

  final int pageCount;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  final _input = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final ranges = PdfSplitter.parseRanges(
        _input.text,
        pageCount: widget.pageCount,
      );
      Navigator.of(context).pop(ranges);
    } on FormatException {
      setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    return AlertDialog(
      key: const ValueKey('pdf-split-dialog'),
      title: Text(l10n.splitTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.pageRangePageCount(widget.pageCount)),
            const SizedBox(height: 12),
            Text(l10n.splitHelp),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('pdf-split-ranges'),
              controller: _input,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              decoration: InputDecoration(
                labelText: l10n.splitRanges,
                hintText: '1-3, 7, 10-12',
                errorText:
                    _invalid ? l10n.splitInvalidRanges(widget.pageCount) : null,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('pdf-split-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        PdfDialogSubmit(
            child: FilledButton(
          key: const ValueKey('pdf-split-confirm'),
          onPressed: _submit,
          child: Text(l10n.splitConfirm),
        )),
      ],
    );
  }
}
