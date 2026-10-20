import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart' show PdfOcrSpan, PdfPage;

import 'ocr_image.dart';
import 'ocr_model_runner.dart';

/// A [PdfOcrEngine] over any [OcrModelRunner]: reads the page raster into an
/// [OcrImage], runs the backend, and maps each recognized line's pixel box to
/// PDF user space via `PdfOcrPageImage.userSpaceRect`. The engine (and the
/// geometry it owns) is independent of which recognizer runs - the native
/// [OnDeviceOcrEngine] and the web build both use it.
///
/// Web-safe: nothing here touches `dart:io` or FFI.
class OcrRunnerEngine implements PdfOcrEngine {
  OcrRunnerEngine(this.runner, {this.minConfidence = 0});

  /// The inference backend.
  final OcrModelRunner runner;

  /// Lines below this confidence are dropped before mapping.
  final double minConfidence;

  bool _loaded = false;

  /// The raster resolution (pixels per PDF point) to OCR [page] at: [target]
  /// (3 = 216 dpi) unless that would make the page's longest side exceed
  /// [maxSidePixels], in which case the ratio that fits it exactly.
  ///
  /// 216 dpi puts the ~5pt capitals of a drawing label at ~16 px - inside
  /// PP-OCR's working range, where 144 dpi (ratio 2) leaves them at ~11 px.
  /// The cap matches the detector's own side limit, so a large-format sheet
  /// is not rasterized only for detection to shrink it again, and it bounds
  /// the raster's memory (4000 x 2828 RGBA is ~45 MB; A0 at ratio 3 would be
  /// ~290 MB).
  static double pixelRatioFor(
    PdfPage page, {
    double target = 3,
    int maxSidePixels = 4000,
  }) {
    final box = page.cropBox;
    final longest = box.width > box.height ? box.width : box.height;
    if (longest <= 0) return target;
    final fit = maxSidePixels / longest;
    return fit < target ? fit : target;
  }

  @override
  Future<List<PdfOcrSpan>> recognize(PdfOcrPageImage page) async {
    if (!_loaded) {
      await runner.load();
      _loaded = true;
    }
    final image = await OcrImage.fromUiImage(page.image);
    final lines = await runner.recognize(image);
    return [
      for (final line in lines)
        if (line.confidence >= minConfidence &&
            line.text.trim().isNotEmpty &&
            line.pixelBounds.width > 0 &&
            line.pixelBounds.height > 0)
          PdfOcrSpan(
            text: line.text,
            bounds: page.userSpaceRect(line.pixelBounds),
            confidence: line.confidence,
          ),
    ];
  }

  /// Releases the backend.
  Future<void> dispose() => runner.dispose();
}
