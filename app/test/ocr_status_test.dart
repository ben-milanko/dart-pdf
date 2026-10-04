// The app-bar OCR chip is driven by OcrJobStatus - its fraction (determinate
// where we know it, indeterminate otherwise) and the short label per phase. The
// label itself now lives in the presentation layer (`ocrStatusLabel`), resolved
// from the localizations; here we drive it through the English bundle.
import 'package:dart_pdf_editor_app/l10n/app_localizations_en.dart';
import 'package:dart_pdf_editor_app/ocr_status.dart';
import 'package:dart_pdf_editor_app/ocr_status_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('downloading: fraction follows the download, label shows percent', () {
    const s = OcrJobStatus(
      phase: OcrPhase.downloading,
      title: 'Scan.pdf',
      downloadFraction: 0.42,
    );
    expect(s.fraction, 0.42);
    expect(ocrStatusLabel(l10n, s), 'Downloading model 42%');
  });

  test('downloading with unknown total is indeterminate', () {
    const s = OcrJobStatus(phase: OcrPhase.downloading, title: 'Scan.pdf');
    expect(s.fraction, isNull);
    expect(ocrStatusLabel(l10n, s), 'Downloading OCR model…');
  });

  test('recognising: only finished pages count and label names the page', () {
    const s = OcrJobStatus(
      phase: OcrPhase.recognising,
      title: 'Scan.pdf',
      page: 3,
      pageCount: 12,
    );
    // Page 3 is in progress, so two of twelve are done.
    expect(s.fraction, closeTo(2 / 12, 1e-9));
    expect(ocrStatusLabel(l10n, s), 'OCR page 3 of 12');
  });

  test('a single page does not read as done while it is being recognized', () {
    const s = OcrJobStatus(
      phase: OcrPhase.recognising,
      title: 'Scan.pdf',
      page: 1,
      pageCount: 1,
    );
    expect(s.fraction, 0);
    expect(ocrStatusLabel(l10n, s), 'Reading text…');
  });

  test('within-page progress advances the fraction', () {
    const s = OcrJobStatus(
      phase: OcrPhase.recognising,
      title: 'Scan.pdf',
      page: 2,
      pageCount: 4,
      pageFraction: 0.5,
    );
    expect(s.fraction, closeTo(1.5 / 4, 1e-9));
  });

  test('preparing the model is indeterminate', () {
    const s = OcrJobStatus(phase: OcrPhase.preparing, title: 'Scan.pdf');
    expect(s.fraction, isNull);
    expect(ocrStatusLabel(l10n, s), 'Loading OCR model…');
  });

  test('recognising with no pages yet is indeterminate (no divide-by-zero)',
      () {
    const s = OcrJobStatus(phase: OcrPhase.recognising, title: 'Scan.pdf');
    expect(s.fraction, isNull);
  });

  test('finishing is indeterminate with a finishing label', () {
    const s = OcrJobStatus(phase: OcrPhase.finishing, title: 'Scan.pdf');
    expect(s.fraction, isNull);
    expect(ocrStatusLabel(l10n, s), 'Finishing OCR…');
  });
}
