import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// Whether the browser's native image codec is reachable from this scope.
///
/// The main-thread path needs only `createImageBitmap` + `Blob` - unlike the
/// worker's decode it does NOT need `OffscreenCanvas`, because
/// [ui_web.createImageFromImageBitmap] consumes the bitmap straight into a GPU
/// image with no canvas readback. That is exactly why this recovers the win on
/// browsers whose worker scope lacks `OffscreenCanvas` (#458): the main thread
/// still has the codec.
bool get browserJpegDecodeAvailable =>
    globalContext.has('createImageBitmap') && globalContext.has('Blob');

/// Decodes [jpeg] with the browser's native codec into a GPU-resident
/// [ui.Image], far faster than the engine's WASM codec under CanvasKit.
///
/// When [targetWidth]/[targetHeight] are both given the codec downscales during
/// decode (the display-resolution cap), matching what
/// `ui.instantiateImageCodec(targetWidth:, targetHeight:)` does. Returns null if
/// the codec is unavailable, the decode throws, or the bitmap comes back empty -
/// the caller then falls back to the engine codec.
Future<ui.Image?> decodeJpegWithBrowser(
  Uint8List jpeg, {
  int? targetWidth,
  int? targetHeight,
}) async {
  if (!browserJpegDecodeAvailable) return null;
  web.ImageBitmap? bitmap;
  try {
    final blob = web.Blob(
      <JSAny>[jpeg.toJS].toJS,
      web.BlobPropertyBag(type: 'image/jpeg'),
    );
    // createImageBitmap premultiplies alpha by default, which is the format
    // createImageFromImageBitmap requires. JPEG is opaque regardless.
    final promise = targetWidth != null && targetHeight != null
        ? web.window.createImageBitmap(
            blob,
            web.ImageBitmapOptions(
              resizeWidth: targetWidth,
              resizeHeight: targetHeight,
              resizeQuality: 'high',
            ),
          )
        : web.window.createImageBitmap(blob);
    bitmap = await promise.toDart;
    if (bitmap.width <= 0 || bitmap.height <= 0) return null;
    // Hands the bitmap to the engine, which takes ownership and consumes it -
    // do NOT close() it afterwards.
    final image = await ui_web.createImageFromImageBitmap(bitmap as JSAny);
    bitmap = null;
    return image;
  } catch (_) {
    bitmap?.close();
    return null;
  }
}
