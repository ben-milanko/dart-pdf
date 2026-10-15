import 'package:dart_pdf_editor_app/ocr_web_budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pp_ocr.dart';

class _NoInference implements PpOcrInference {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const mib = 1024 * 1024;

  test('an uncapped heap keeps the pipeline defaults', () {
    expect(BrowserOcrBudget.forHeap(0), isNull);
    final pipeline = browserOcrPipeline(_NoInference(), heapBytes: 0);
    expect(pipeline.detectionPixelLimit, isNull);
    expect(pipeline.detectionSideLimit, 4000);
    expect(pipeline.recognitionBatchSize, 6);
  });

  test('a capped heap scales detection area and recognition batch', () {
    final gib = BrowserOcrBudget.forHeap(1024 * mib)!;
    expect(gib.detectionPixelLimit, 5000000);
    expect(gib.recognitionBatchSize, 4);

    final half = BrowserOcrBudget.forHeap(512 * mib)!;
    expect(half.detectionPixelLimit, 2500000);
    expect(half.recognitionBatchSize, 2);

    final quarter = BrowserOcrBudget.forHeap(256 * mib)!;
    expect(quarter.recognitionBatchSize, 1);

    expect(BrowserOcrBudget.forHeap(2048 * mib)!.recognitionBatchSize, 6);
  });

  test('the pipeline carries the budget', () {
    final pipeline = browserOcrPipeline(_NoInference(), heapBytes: 1024 * mib);
    expect(pipeline.detectionPixelLimit, 5000000);
    expect(pipeline.recognitionBatchSize, 4);
  });
}
