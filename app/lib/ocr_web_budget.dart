import 'package:pdf_ocr_ondevice/pp_ocr.dart';

/// Builds the browser [PpOcrPipeline] for onnxruntime-web's heap.
///
/// [heapBytes] is the wasm heap's maximum when the bridge had to cap it
/// (iOS WebKit refuses ORT's 4 GB shared memory, see `web/index.html`), or 0
/// when it got the full 4 GB - then the pipeline keeps its defaults. Under a
/// cap, detection's working set grows with the page's pixel count and a
/// recognition batch's with its line count, so both scale with the heap. The
/// numbers were measured on onnxruntime-web 1.30 with the PP-OCRv5 mobile
/// models: a 1 GiB heap ran a 5.9 MP detection but not 7.9 MP, and a 512 MiB
/// heap ran a batch of two 3200 px lines but not six - see
/// doc/dev-log/2026-10-14-ios-web-ocr-shared-memory.md.
PpOcrPipeline browserOcrPipeline(PpOcrInference inference,
    {required int heapBytes}) {
  final budget = BrowserOcrBudget.forHeap(heapBytes);
  if (budget == null) return PpOcrPipeline(inference);
  return PpOcrPipeline(
    inference,
    detectionPixelLimit: budget.detectionPixelLimit,
    recognitionBatchSize: budget.recognitionBatchSize,
  );
}

/// The detection area and recognition batch that fit a capped OCR heap.
class BrowserOcrBudget {
  const BrowserOcrBudget({
    required this.detectionPixelLimit,
    required this.recognitionBatchSize,
  });

  /// The budget for a [heapBytes] heap, or null when it isn't capped (0).
  static BrowserOcrBudget? forHeap(int heapBytes) {
    if (heapBytes <= 0) return null;
    const mib = 1024 * 1024;
    return BrowserOcrBudget(
      // 5 MP per GiB, under the ~5.9 MP measured to fit.
      detectionPixelLimit: heapBytes * 5000000 ~/ (1024 * mib),
      // One line per 256 MiB, at most the pipeline's default of 6.
      recognitionBatchSize: (heapBytes ~/ (256 * mib)).clamp(1, 6),
    );
  }

  final int detectionPixelLimit;
  final int recognitionBatchSize;
}
