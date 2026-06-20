// The app-bar OCR chip is driven by OcrJobStatus — its fraction (determinate
// where we know it, indeterminate otherwise) and short label per phase.
import 'package:dart_pdf_editor_app/ocr_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloading: fraction follows the download, label shows percent', () {
    const s = OcrJobStatus(
      phase: OcrPhase.downloading,
      title: 'Scan.pdf',
      downloadFraction: 0.42,
    );
    expect(s.fraction, 0.42);
    expect(s.label, 'Downloading model 42%');
  });

  test('downloading with unknown total is indeterminate', () {
    const s = OcrJobStatus(phase: OcrPhase.downloading, title: 'Scan.pdf');
    expect(s.fraction, isNull);
    expect(s.label, 'Downloading OCR model…');
  });

  test('recognising: fraction is page/pageCount and label counts pages', () {
    const s = OcrJobStatus(
      phase: OcrPhase.recognising,
      title: 'Scan.pdf',
      page: 3,
      pageCount: 12,
    );
    expect(s.fraction, closeTo(0.25, 1e-9));
    expect(s.label, 'OCR 3/12');
  });

  test('recognising with no pages yet is indeterminate (no divide-by-zero)',
      () {
    const s = OcrJobStatus(phase: OcrPhase.recognising, title: 'Scan.pdf');
    expect(s.fraction, isNull);
  });

  test('finishing is indeterminate with a finishing label', () {
    const s = OcrJobStatus(phase: OcrPhase.finishing, title: 'Scan.pdf');
    expect(s.fraction, isNull);
    expect(s.label, 'Finishing OCR…');
  });
}
