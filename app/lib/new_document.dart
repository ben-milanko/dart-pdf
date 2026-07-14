import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

enum _PageSizePreset {
  a4('A4', '210 × 297 mm', PdfPageSize.a4),
  letter('US Letter', '8.5 × 11 in', PdfPageSize.letter),
  legal('US Legal', '8.5 × 14 in', PdfPageSize.legal),
  a3('A3', '297 × 420 mm', PdfPageSize.a3),
  a5('A5', '148 × 210 mm', PdfPageSize.a5),
  tabloid('Tabloid', '11 × 17 in', PdfPageSize.tabloid);

  const _PageSizePreset(this.label, this.dimensions, this.size);

  final String label;
  final String dimensions;
  final PdfPageSize size;
}

/// Prompts for the page size and orientation of a new blank PDF.
Future<PdfPageSize?> showNewDocumentDialog(BuildContext context) {
  var preset = _PageSizePreset.a4;
  var orientation = Orientation.portrait;
  return showDialog<PdfPageSize>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        key: const ValueKey('new-document-dialog'),
        title: const Text('New document'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Page size'),
              const SizedBox(height: 8),
              DropdownButton<_PageSizePreset>(
                key: const ValueKey('new-document-page-size'),
                value: preset,
                isExpanded: true,
                items: [
                  for (final option in _PageSizePreset.values)
                    DropdownMenuItem(
                      value: option,
                      child: Text('${option.label} (${option.dimensions})'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => preset = value);
                },
              ),
              const SizedBox(height: 20),
              const Text('Orientation'),
              const SizedBox(height: 8),
              SegmentedButton<Orientation>(
                key: const ValueKey('new-document-orientation'),
                segments: const [
                  ButtonSegment(
                    value: Orientation.portrait,
                    icon: Icon(Icons.stay_current_portrait),
                    label: Text('Portrait'),
                  ),
                  ButtonSegment(
                    value: Orientation.landscape,
                    icon: Icon(Icons.stay_current_landscape),
                    label: Text('Landscape'),
                  ),
                ],
                selected: {orientation},
                onSelectionChanged: (value) =>
                    setState(() => orientation = value.single),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('new-document-create'),
            onPressed: () => Navigator.of(context).pop(
              orientation == Orientation.portrait
                  ? preset.size.portrait
                  : preset.size.landscape,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}
