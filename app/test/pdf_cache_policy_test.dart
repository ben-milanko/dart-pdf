import 'package:dart_pdf_editor_app/pdf_cache_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quota reserve accounts for the incoming PDF and accepts the boundary',
      () {
    expect(pdfCacheFitsQuota(10, usage: 80, quota: 100), isTrue);
    expect(pdfCacheFitsQuota(11, usage: 80, quota: 100), isFalse);
    expect(pdfCacheFitsQuota(1, usage: 91, quota: 100), isFalse);
    expect(pdfCacheFitsQuota(1, usage: 0, quota: 0), isFalse);
  });
  test('unavailable estimates permit the independently budgeted cache', () {
    expect(pdfCacheFitsQuota(4), isTrue);
    expect(pdfCacheFitsQuota(4, usage: 10), isTrue);
    expect(pdfCacheFitsQuota(4, quota: double.nan), isTrue);
  });
}
