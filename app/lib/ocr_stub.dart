import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ocr_status.dart';

export 'ocr_status.dart';

/// Web stub for [OnDeviceOcr]: on-device OCR needs ONNX Runtime (FFI /
/// dart:io), which dart2js can't compile, so the web build gets this no-op
/// instead. [isSupported] is false, so the OCR menu action is never shown.
class OnDeviceOcr {
  OnDeviceOcr();

  /// Never active on the web; present so the app bar's listener compiles.
  final ValueNotifier<OcrJobStatus?> status = ValueNotifier(null);

  /// On-device OCR is unavailable on the web.
  static bool get isSupported => false;

  bool get isBusy => false;

  void cancel() {}

  void dispose() => status.dispose();

  Future<void> start(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
    required void Function(Uint8List result) onComplete,
  }) async {
    onToast('On-device OCR is not available on the web');
  }
}
