// Native OCR is FFI/dart:io-backed (ONNX Runtime), which web builds can't
// compile, so the native implementation is only pulled in where dart:io exists.
// On the web this resolves to the same PP-OCR pipeline over onnxruntime-web.
// Use js_interop instead of html so both Wasm and dart2js web builds pick it
// up.
// Other platforms get a stub.
export 'ocr_stub.dart'
    if (dart.library.io) 'ocr_native.dart'
    if (dart.library.js_interop) 'ocr_web.dart';
