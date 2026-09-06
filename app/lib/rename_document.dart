import 'package:dart_pdf_editor/dart_pdf_editor.dart' show showPdfDialog;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_l10n.dart';
import 'middle_ellipsis_text.dart';

/// Renames the app's document copy and the filename used when sharing it.
Future<String?> showRenameDocumentDialog(BuildContext context, String name) =>
    showPdfDialog<String>(
      context: context,
      builder: (_) => _RenameDocumentDialog(name: name),
    );

class _RenameDocumentDialog extends StatefulWidget {
  const _RenameDocumentDialog({required this.name});

  final String name;

  @override
  State<_RenameDocumentDialog> createState() => _RenameDocumentDialogState();
}

class _RenameDocumentDialogState extends State<_RenameDocumentDialog> {
  late final _name = TextEditingController(text: widget.name)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: pdfDisplayName(widget.name).length,
    );

  String? get _filename {
    var stem = _name.text.trim();
    while (stem.toLowerCase().endsWith('.pdf')) {
      stem = stem.substring(0, stem.length - 4).trim();
    }
    if (stem.replaceAll('.', '').trim().isEmpty) return null;
    return '$stem.pdf';
  }

  void _submit() {
    final filename = _filename;
    if (filename != null) Navigator.of(context).pop(filename);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    return AlertDialog(
      title: Text(l10n.rename),
      content: TextField(
        key: const ValueKey('rename-document-name'),
        controller: _name,
        autofocus: true,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        autocorrect: false,
        inputFormatters: [
          FilteringTextInputFormatter.deny(RegExp(r'[/\\\x00-\x1f\x7f]')),
        ],
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('rename-document-confirm'),
          onPressed: _filename == null ? null : _submit,
          child: Text(l10n.rename),
        ),
      ],
    );
  }
}
