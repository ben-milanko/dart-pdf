import 'package:flutter/foundation.dart';

/// What phase an [OnDeviceOcr] job is in.
enum OcrPhase {
  /// Fetching the model on first use (one-time).
  downloading,

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
  });

  /// What the job is doing right now.
  final OcrPhase phase;

  /// The document being OCR'd (for the chip tooltip).
  final String title;

  /// 1-based page currently being recognized (0 outside [OcrPhase.recognising]).
  final int page;

  /// Total page count of the document.
  final int pageCount;

  /// Download completion in `[0, 1]`, or null when unknown / not downloading.
  final double? downloadFraction;

  /// Completion in `[0, 1]` for a determinate indicator, or null for a
  /// spinner (indeterminate).
  double? get fraction => switch (phase) {
        OcrPhase.downloading => downloadFraction,
        OcrPhase.recognising => pageCount > 0 ? page / pageCount : null,
        OcrPhase.finishing => null,
      };

  // The short chip label lives in the presentation layer (`ocrStatusLabel` in
  // `ocr_status_label.dart`) so this model stays locale-free.
}
