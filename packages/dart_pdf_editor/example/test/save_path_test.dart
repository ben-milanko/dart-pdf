import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_viewer_example/main.dart';

void main() {
  test('pdfSavePathWithExtension appends pdf to extensionless paths', () {
    expect(pdfSavePathWithExtension('/tmp/report'), '/tmp/report.pdf');
    expect(pdfSavePathWithExtension(r'C:\Users\me\report'),
        r'C:\Users\me\report.pdf');
  });

  test('pdfSavePathWithExtension preserves existing pdf extension', () {
    expect(pdfSavePathWithExtension('/tmp/report.pdf'), '/tmp/report.pdf');
    expect(pdfSavePathWithExtension('/tmp/report.PDF'), '/tmp/report.PDF');
    expect(pdfSavePathWithExtension('/tmp.v1/report'), '/tmp.v1/report.pdf');
  });
}
