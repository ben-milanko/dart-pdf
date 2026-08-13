import 'jpeg_accelerator_stub.dart'
    if (dart.library.js_interop) 'jpeg_accelerator_web.dart'
    if (dart.library.ffi) 'jpeg_accelerator_native.dart' as implementation;

/// Installs the fastest available four-component JPEG decoder in this
/// isolate/worker. Safe to call repeatedly.
void installPdfJpegAccelerator() => implementation.installPdfJpegAccelerator();
