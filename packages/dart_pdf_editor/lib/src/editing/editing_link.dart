import 'package:flutter/material.dart';

import '../l10n/pdf_l10n.dart';
import 'editing_controller.dart';

/// The two shapes a hyperlink target can take in the Add-link dialog.
enum _LinkKind { web, page }

/// The default [showPdfAddLinkDialog]: a small Material dialog that collects a
/// hyperlink target - an external web address, or a page in this same
/// document. Returns the chosen [PdfLinkTarget], or null if the user cancels
/// or leaves the field empty.
///
/// [pageCount] bounds the internal page picker; [currentPage] (zero-based)
/// seeds it. [initialUrl] pre-fills the web field (e.g. a URL already sitting
/// in the selected text).
Future<PdfLinkTarget?> showPdfAddLinkDialog(
  BuildContext context, {
  required int pageCount,
  required int currentPage,
  String initialUrl = '',
}) {
  return showDialog<PdfLinkTarget>(
    context: context,
    builder: (context) => _AddLinkDialog(
      pageCount: pageCount,
      currentPage: currentPage,
      initialUrl: initialUrl,
    ),
  );
}

/// Supplies the target for a link the link tool ([PdfEditTool.link]) or the
/// text-selection "Add link" action is placing. Return null to cancel.
/// [pageCount] is the document's page count and [currentPage] the zero-based
/// page the link is being drawn on (a sensible default for an internal jump).
typedef PdfLinkPrompt = Future<PdfLinkTarget?> Function(
  BuildContext context, {
  required int pageCount,
  required int currentPage,
  String initialUrl,
});

class _AddLinkDialog extends StatefulWidget {
  const _AddLinkDialog({
    required this.pageCount,
    required this.currentPage,
    required this.initialUrl,
  });

  final int pageCount;
  final int currentPage;
  final String initialUrl;

  @override
  State<_AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<_AddLinkDialog> {
  late final TextEditingController _url =
      TextEditingController(text: widget.initialUrl);
  // one-based in the UI; defaults to the page the link sits on
  late final TextEditingController _page = TextEditingController(
      text: '${(widget.currentPage + 1).clamp(1, widget.pageCount)}');
  _LinkKind _kind = _LinkKind.web;

  @override
  void dispose() {
    _url.dispose();
    _page.dispose();
    super.dispose();
  }

  PdfLinkTarget? _result() {
    if (_kind == _LinkKind.web) {
      final uri = _url.text.trim();
      return uri.isEmpty ? null : PdfLinkTarget.uri(uri);
    }
    final oneBased = int.tryParse(_page.text.trim());
    if (oneBased == null) return null;
    final zeroBased = (oneBased - 1).clamp(0, widget.pageCount - 1);
    return PdfLinkTarget.page(zeroBased);
  }

  void _submit() => Navigator.of(context).pop(_result());

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    return AlertDialog(
      title: Text(l10n.linkDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_LinkKind>(
            segments: [
              ButtonSegment(
                value: _LinkKind.web,
                icon: const Icon(Icons.link),
                label: Text(l10n.linkKindWeb),
              ),
              ButtonSegment(
                value: _LinkKind.page,
                icon: const Icon(Icons.description_outlined),
                label: Text(l10n.linkKindPage),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          if (_kind == _LinkKind.web)
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.linkUrlLabel,
                hintText: 'https://example.com',
              ),
              onSubmitted: (_) => _submit(),
            )
          else
            TextField(
              controller: _page,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.linkPageLabel,
                helperText: '1 – ${widget.pageCount}',
              ),
              onSubmitted: (_) => _submit(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
