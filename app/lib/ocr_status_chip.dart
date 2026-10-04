import 'package:flutter/material.dart';

import 'l10n/app_l10n.dart';
import 'ocr_status.dart';
import 'ocr_status_label.dart';

/// Compact app-bar indicator for a running background OCR job: a spinner that
/// keeps turning so the job visibly stays alive between updates, a short
/// label, a cancel button, and a progress bar along the chip's bottom edge
/// (determinate when the job knows how far along it is, sweeping otherwise).
class OcrStatusChip extends StatelessWidget {
  const OcrStatusChip(
      {super.key, required this.status, required this.onCancel});

  /// The running job's progress.
  final OcrJobStatus status;

  /// Asks the job to stop.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = status.fraction;
    return Tooltip(
      message: appL10n(context).editorOcrTooltip(status.title),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          key: const ValueKey('ocr-status-chip'),
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        key: ValueKey('ocr-status-spinner'),
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ocrStatusLabel(appL10n(context), status),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSecondaryContainer,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('ocr-status-cancel'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      icon: const Icon(Icons.close),
                      tooltip: appL10n(context).editorCancelOcr,
                      onPressed: onCancel,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: fraction == null
                    ? const LinearProgressIndicator(
                        key: ValueKey('ocr-status-progress'),
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                      )
                    : TweenAnimationBuilder<double>(
                        // Ease between updates so page steps glide instead
                        // of jump.
                        tween: Tween<double>(end: fraction),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, value, _) => LinearProgressIndicator(
                          key: const ValueKey('ocr-status-progress'),
                          value: value,
                          minHeight: 3,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
