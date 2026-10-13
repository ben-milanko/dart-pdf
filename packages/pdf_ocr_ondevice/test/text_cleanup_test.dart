import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

void main() {
  test('drawing symbols are removed from a recognized line', () {
    expect(cleanRecognizedText('F12 ●'), 'F12');
    expect(cleanRecognizedText('▲8'), '8');
    expect(cleanRecognizedText('A4381TPS▼'), 'A4381TPS');
    expect(cleanRecognizedText('5 ▲ A  6'), '5 A 6');
  });

  test('a line with no letter or digit left is dropped', () {
    expect(cleanRecognizedText('●'), isNull);
    expect(cleanRecognizedText(' • '), isNull);
    expect(cleanRecognizedText('…'), isNull);
    expect(cleanRecognizedText(''), isNull);
  });

  test('ordinary text passes through untouched', () {
    expect(cleanRecognizedText('(FSFCR)'), '(FSFCR)');
    expect(cleanRecognizedText('• Item 3'), '• Item 3');
    expect(cleanRecognizedText('第一章'), '第一章');
  });
}
