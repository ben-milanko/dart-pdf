import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'camera_capture.dart';
import 'file_io.dart';
import 'l10n/app_l10n.dart';

/// Where the picture the user wants to place comes from.
enum ImagePickSource { camera, file }

/// Picks an image for the editor - the image tool, a form push button's icon,
/// or a signature's logo backdrop.
///
/// On a phone or tablet the picture is as often in front of the camera as it
/// is a file (a receipt, a whiteboard, a hand-signed page), and the OS file
/// picker cannot offer the camera - so ask first, then take the photo or open
/// the file picker. Everywhere else there is no camera worth offering and this
/// goes straight to the file picker, exactly as before.
///
/// Returns null when the user cancels, at either step.
Future<Uint8List?> pickImageBytesFromSource(BuildContext context) async {
  final l10n = appL10n(context);
  if (!supportsCameraCapture) return _pickImageFile(l10n.fileTypeImages);

  final messenger = ScaffoldMessenger.maybeOf(context);
  final source = await _showImageSourceSheet(context);
  if (source == null) return null;
  if (source == ImagePickSource.file) {
    return _pickImageFile(l10n.fileTypeImages);
  }

  try {
    return await captureImageFromCamera();
  } catch (_) {
    // No camera on the device, or camera access refused - the OS has already
    // had its say in that case, so keep ours to a toast.
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.imageSourceCameraFailed)),
    );
    return null;
  }
}

/// A file pick, put upright the same way a capture is: a photo picked out of
/// the gallery (or off a desktop's disk) carries the very EXIF rotation the
/// camera wrote, and the PDF embeds JPEG bytes verbatim either way. Anything
/// already upright - and every PNG - passes through untouched.
Future<Uint8List?> _pickImageFile(String label) async {
  final bytes = await pickImageBytes(label);
  return bytes == null ? null : uprightJpeg(bytes);
}

/// Asks where the picture should come from. Returns null when the sheet is
/// dismissed without a choice.
Future<ImagePickSource?> _showImageSourceSheet(BuildContext context) {
  final l10n = appL10n(context);
  return showModalBottomSheet<ImagePickSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l10n.imageSourceTakePhoto),
            onTap: () => Navigator.pop(context, ImagePickSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(l10n.imageSourceChooseFile),
            onTap: () => Navigator.pop(context, ImagePickSource.file),
          ),
        ],
      ),
    ),
  );
}
