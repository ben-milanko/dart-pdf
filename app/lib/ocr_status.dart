import 'package:flutter/foundation.dart';

/// What phase an [OnDeviceOcr] job is in.
enum OcrPhase {
  /// Fetching the model on first use (one-time).
  downloading,

  /// Loading the (already downloaded) model and warming it up - no byte
  /// progress to report, so the chip shows an indeterminate bar.
  preparing,

  /// Running the recognizer over the document's pages.
  recognising,

  /// Assembling the OCR'd PDF after the last page.
  finishing,
}

/// A snapshot of a running on-device OCR job - drives the app-bar progress
/// chip so OCR runs in the background while the user keeps using the PDF.
/// A `null` status (see `OnDeviceOcr.status`) means no job is active.
@immutable
class OcrJobStatus {
  const OcrJobStatus({
    required this.phase,
    required this.title,
    this.page = 0,
    this.pageCount = 0,
    this.downloadFraction,
    this.pageFraction,
  });

  /// What the job is doing right now.
  final OcrPhase phase;

  /// The document being OCR'd (for the chip tooltip).
  final String title;

  /// 1-based page currently being recognized (0 outside [OcrPhase.recognising]).
  /// This page is still in progress - [page] - 1 pages are done.
  final int page;

  /// Total page count of the document.
  final int pageCount;

  /// Download completion in `[0, 1]`, or null when unknown / not downloading.
  final double? downloadFraction;

  /// How far through the current [page] the recognizer is, in `[0, 1]`, or
  /// null when the engine reports no within-page progress.
  final double? pageFraction;

  /// Completion in `[0, 1]` for a determinate indicator, or null for an
  /// indeterminate one. While recognizing, only the pages already finished
  /// (plus the current page's [pageFraction]) count, so a one-page document
  /// does not read as complete the moment it starts.
  double? get fraction => switch (phase) {
        OcrPhase.downloading => downloadFraction,
        OcrPhase.preparing => null,
        OcrPhase.recognising => pageCount > 0
            ? ((page - 1).clamp(0, pageCount) +
                    (pageFraction ?? 0).clamp(0.0, 1.0)) /
                pageCount
            : null,
        OcrPhase.finishing => null,
      };

  // The short chip label lives in the presentation layer (`ocrStatusLabel` in
  // `ocr_status_label.dart`) so this model stays locale-free.
}
