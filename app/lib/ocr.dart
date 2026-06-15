// Native OCR is FFI/dart:io-backed (ONNX Runtime), which dart2js can't
// compile, so the native implementation is only pulled in where dart:io exists.
// On the web this resolves to a browser-local Florence-2 implementation,
// keeping onnxruntime out of the web build while still offering OCR.
// Other platforms get a stub.
export 'ocr_stub.dart'
    if (dart.library.io) 'ocr_native.dart'
    if (dart.library.html) 'ocr_web.dart';
