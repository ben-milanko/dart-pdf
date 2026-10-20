import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Whether this platform can photograph the picture the user wants to place.
///
/// Phones and tablets only. `image_picker`'s desktop implementations have no
/// camera at all (they re-open a file dialog), and on the web the browser's
/// own file input already offers the camera where the device has one.
bool get supportsCameraCapture =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Long-edge cap asked of the camera. A phone sensor shoots 12 MP+, far past
/// what a picture placed on a page ever resolves to (2000 px across an A4
/// width is ~240 dpi) - and every byte of it lands in the saved PDF. The
/// native side does the downscale, so the full-size frame never crosses the
/// platform channel.
const double cameraCaptureMaxDimension = 2000;

/// JPEG quality for that downscale, and for the re-encode when a rotated
/// capture has to be baked upright.
const int cameraCaptureQuality = 88;

/// Takes a photo and returns its (upright) JPEG bytes, or null when the user
/// backed out of the camera without shooting.
///
/// Throws whatever the platform throws - no camera on the device, permission
/// refused - so the caller can say so.
Future<Uint8List?> captureImageFromCamera({ImagePicker? picker}) async {
  final file = await (picker ?? ImagePicker()).pickImage(
    source: ImageSource.camera,
    maxWidth: cameraCaptureMaxDimension,
    maxHeight: cameraCaptureMaxDimension,
    imageQuality: cameraCaptureQuality,
    // We only want pixels. Skipping the metadata read also keeps iOS from
    // asking for photo-library access on what is only a camera shot.
    requestFullMetadata: false,
  );
  if (file == null) return null;
  return uprightJpeg(await file.readAsBytes());
}

/// Bakes a JPEG's EXIF orientation into its pixels so it embeds upright.
///
/// `PdfEmbeddableImage.jpeg` hands JPEG bytes to the PDF verbatim (DCTDecode)
/// and PDF has no orientation tag, so a capture whose pixels are sideways
/// under an /Orientation of 6 - what Android camera apps write for a portrait
/// shot, and what `image_picker` deliberately preserves when it rescales -
/// would land on the page rotated. iOS bakes the rotation itself while
/// rescaling, so this is a no-op there.
///
/// A normal (or absent) orientation is the fast path: the bytes pass through
/// untouched, keeping the camera's own JPEG. Only a rotated one pays for a
/// decode and re-encode, and that runs off the UI isolate.
Future<Uint8List> uprightJpeg(Uint8List bytes) async {
  final orientation = jpegExifOrientation(bytes);
  if (orientation == null || orientation == 1) return bytes;
  final offIsolate = debugBakeOrientationOffIsolate;
  return offIsolate != null
      ? offIsolate(bytes)
      : compute(bakeJpegOrientation, bytes);
}

/// Test seam for the isolate hop above: `compute` never completes inside a
/// widget test's fake-async zone, so a widget test that has to reach a rotated
/// capture runs the bake in place instead. Null in production.
@visibleForTesting
Future<Uint8List> Function(Uint8List bytes)? debugBakeOrientationOffIsolate;

/// Decodes, rotates and re-encodes [bytes] per its EXIF orientation. Top-level
/// because it is what [compute] runs.
@visibleForTesting
Uint8List bakeJpegOrientation(Uint8List bytes) {
  final decoded = img.decodeJpg(bytes);
  // Undecodable here means undecodable in the embedder too - hand the original
  // bytes back and let it report the format problem.
  if (decoded == null) return bytes;
  return img.encodeJpg(
    img.bakeOrientation(decoded),
    quality: cameraCaptureQuality,
  );
}

/// Reads the EXIF orientation (TIFF tag 0x0112, values 1-8) out of a JPEG's
/// APP1 segment. Returns null when the file carries no EXIF block, no
/// orientation tag, or anything malformed on the way to it - all of which mean
/// "assume it is already upright".
int? jpegExifOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  final data = ByteData.sublistView(bytes);
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    // Some encoders pad with 0xFF fill bytes before a marker.
    if (bytes[offset + 1] == 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    // Start of scan: the pixel data begins, so any APP1 is behind us.
    if (marker == 0xDA || marker == 0xD9) return null;
    // Standalone markers carry no length word.
    if (marker >= 0xD0 && marker <= 0xD8) {
      offset += 2;
      continue;
    }
    final length = data.getUint16(offset + 2);
    if (length < 2) return null;
    final payload = offset + 4;
    final end = payload + length - 2;
    if (end > bytes.length) return null;
    if (marker == 0xE1 && _isExifHeader(bytes, payload, end)) {
      return _orientationInTiff(data, payload + 6, end);
    }
    offset = end;
  }
  return null;
}

/// `Exif\0\0`, the APP1 payload prefix that marks an EXIF block (as opposed to
/// the XMP one, which shares the marker).
bool _isExifHeader(Uint8List bytes, int start, int end) =>
    end - start >= 6 &&
    bytes[start] == 0x45 &&
    bytes[start + 1] == 0x78 &&
    bytes[start + 2] == 0x69 &&
    bytes[start + 3] == 0x66 &&
    bytes[start + 4] == 0 &&
    bytes[start + 5] == 0;

/// Walks IFD0 of the TIFF block starting at [tiff] for the orientation tag.
int? _orientationInTiff(ByteData data, int tiff, int end) {
  if (tiff + 8 > end) return null;
  final byteOrder = data.getUint16(tiff);
  if (byteOrder != 0x4949 && byteOrder != 0x4D4D) return null;
  final endian = byteOrder == 0x4949 ? Endian.little : Endian.big;
  if (data.getUint16(tiff + 2, endian) != 42) return null;
  final ifd = tiff + data.getUint32(tiff + 4, endian);
  if (ifd + 2 > end) return null;
  final entries = data.getUint16(ifd, endian);
  for (var i = 0; i < entries; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > end) return null;
    if (data.getUint16(entry, endian) != 0x0112) continue;
    // The value is inline in the entry's last four bytes (SHORT or LONG - both
    // fit), left-aligned, so a SHORT reads straight off the front of it.
    final type = data.getUint16(entry + 2, endian);
    final value = switch (type) {
      3 => data.getUint16(entry + 8, endian),
      4 => data.getUint32(entry + 8, endian),
      _ => null,
    };
    return value != null && value >= 1 && value <= 8 ? value : null;
  }
  return null;
}
