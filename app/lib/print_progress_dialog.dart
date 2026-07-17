import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Modal dialog shown while a print job rasterises its pages, tracking
/// "page X of Y".
///
/// The print path renders every page up front, which is slow for large
/// documents, so the editor surfaces this rather than appearing frozen.
/// [progress] carries `(rendered, total)`, or null before the first page.
class PrintProgressDialog extends StatelessWidget {
  const PrintProgressDialog({super.key, required this.progress});

  /// The current `(rendered, total)` page counts, or null before rendering.
  final ValueListenable<(int, int)?> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Printing'),
      content: ValueListenableBuilder<(int, int)?>(
        valueListenable: progress,
        builder: (context, value, _) {
          final rendered = value?.$1 ?? 0;
          final total = value?.$2 ?? 0;
          final fraction = total > 0 ? rendered / total : null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(total > 0
                  ? 'Rendering page $rendered of $total…'
                  : 'Preparing…'),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: fraction),
            ],
          );
        },
      ),
    );
  }
}
