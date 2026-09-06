import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';

import 'l10n/app_l10n.dart';

/// The image encodings the "Export page as image…" action offers.
enum ImageExportFormat {
  png('PNG', 'png', 'image/png', PdfRasterFormat.png),
  jpeg('JPEG', 'jpg', 'image/jpeg', PdfRasterFormat.jpeg);

  const ImageExportFormat(
      this.label, this.extension, this.mimeType, this.rasterFormat);

  final String label;
  final String extension;
  final String mimeType;
  final PdfRasterFormat rasterFormat;
}

/// The choices made in [showImageExportDialog].
class ImageExportOptions {
  const ImageExportOptions({required this.format, required this.dpi});

  final ImageExportFormat format;
  final double dpi;
}

/// Resolutions offered in the export dialog, in dots per inch.
const _dpiChoices = <double>[72, 150, 300, 600];

/// Prompts for the format and resolution of a page-to-image export. Returns
/// null when the user cancels.
Future<ImageExportOptions?> showImageExportDialog(BuildContext context) {
  var format = ImageExportFormat.png;
  var dpi = 150.0;
  return showPdfDialog<ImageExportOptions>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(appL10n(context).imgExportTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appL10n(context).imgExportFormat),
            const SizedBox(height: 8),
            SegmentedButton<ImageExportFormat>(
              segments: [
                for (final f in ImageExportFormat.values)
                  ButtonSegment(value: f, label: Text(f.label)),
              ],
              selected: {format},
              onSelectionChanged: (s) => setState(() => format = s.first),
            ),
            const SizedBox(height: 16),
            Text(appL10n(context).imgExportResolution),
            const SizedBox(height: 8),
            DropdownButton<double>(
              key: const ValueKey('export-image-dpi'),
              value: dpi,
              isExpanded: true,
              items: [
                for (final d in _dpiChoices)
                  DropdownMenuItem(
                    value: d,
                    child: Text(appL10n(context).imgExportDpiValue(d.toInt())),
                  ),
              ],
              onChanged: (d) => setState(() => dpi = d ?? dpi),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appL10n(context).cancel),
          ),
          PdfDialogSubmit(
              child: FilledButton(
            key: const ValueKey('export-image-confirm'),
            onPressed: () => Navigator.of(context).pop(
              ImageExportOptions(format: format, dpi: dpi),
            ),
            child: Text(appL10n(context).imgExportExport),
          )),
        ],
      ),
    ),
  );
}

/// A suggested filename for a one-page image export: the document [title]
/// (without a trailing `.pdf`) plus the 1-based [pageNumber] and the
/// format's [extension], e.g. `report-p3.png`.
String imageExportFileName(
    String title, int pageNumber, ImageExportFormat format) {
  var stem = title.trim();
  if (stem.toLowerCase().endsWith('.pdf')) {
    stem = stem.substring(0, stem.length - 4).trim();
  }
  if (stem.isEmpty) stem = 'page';
  return '$stem-p$pageNumber.${format.extension}';
}

/// Suggested PNG filename for an image selected with the Content tool.
String selectedContentImageFileName(String title, int pageNumber) {
  var stem = title.trim();
  if (stem.toLowerCase().endsWith('.pdf')) {
    stem = stem.substring(0, stem.length - 4).trim();
  }
  if (stem.isEmpty) stem = 'image';
  return '$stem-p$pageNumber-image.png';
}
