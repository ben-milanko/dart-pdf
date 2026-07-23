import 'dart:typed_data';
import 'dart:ui' as ui;

/// Whether the browser's native image codec can decode a JPEG on this platform.
///
/// False everywhere but the web: native Flutter already decodes JPEG on a
/// background raster thread through the engine codec, so there is nothing to
/// route around. See browser_jpeg_decode_web.dart for the web implementation
/// and why it exists (#458).
bool get browserJpegDecodeAvailable => false;

/// Decodes [jpeg] to a GPU-resident [ui.Image] with the browser's own image
/// codec, downscaling to [targetWidth]x[targetHeight] during decode when both
/// are given.
///
/// Returns null off the web, and on the web when the codec path is unavailable
/// or the decode fails - callers fall back to [ui.instantiateImageCodec].
Future<ui.Image?> decodeJpegWithBrowser(
  Uint8List jpeg, {
  int? targetWidth,
  int? targetHeight,
}) async => null;
