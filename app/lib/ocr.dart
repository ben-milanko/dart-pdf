// On-device OCR is FFI/dart:io-backed (ONNX Runtime), which dart2js can't
// compile, so the real implementation is only pulled in where dart:io exists.
// On the web this resolves to a stub whose OnDeviceOcr.isSupported is false,
// keeping onnxruntime out of the web build entirely.
export 'ocr_stub.dart' if (dart.library.io) 'ocr_native.dart';
