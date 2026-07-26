import 'l10n/app_localizations.dart';
import 'ocr_status.dart';

/// The short chip label for an [OcrJobStatus], localized.
///
/// The [OcrPhase] and the numeric fields ([OcrJobStatus.page],
/// [OcrJobStatus.pageCount], [OcrJobStatus.downloadFraction]) are the stable
/// data; the visible string is resolved here, in the presentation layer, so the
/// model itself stays Flutter- and locale-free (it only imports `foundation`).
String ocrStatusLabel(AppLocalizations l10n, OcrJobStatus status) =>
    switch (status.phase) {
      OcrPhase.downloading => status.downloadFraction == null
          ? l10n.ocrChipDownloadingModel
          : l10n.ocrChipDownloadingModelPercent(
              (status.downloadFraction! * 100).round()),
      OcrPhase.recognising =>
        l10n.ocrChipRecognising(status.page, status.pageCount),
      OcrPhase.finishing => l10n.ocrChipFinishing,
    };
