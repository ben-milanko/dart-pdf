import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Web stub for [OnDeviceOcr]: on-device OCR needs ONNX Runtime (FFI /
/// dart:io), which dart2js can't compile, so the web build gets this no-op
/// instead. [isSupported] is false, so the OCR menu action is never shown.
class OnDeviceOcr {
  OnDeviceOcr();

  /// On-device OCR is unavailable on the web.
  static bool get isSupported => false;

  void dispose() {}

  Future<Uint8List?> run(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    required void Function(String message) onToast,
  }) async {
    onToast('On-device OCR is not available on the web');
    return null;
  }
}
