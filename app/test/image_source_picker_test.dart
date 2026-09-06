import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:dart_pdf_editor_app/camera_capture.dart';
import 'package:dart_pdf_editor_app/image_source_picker.dart';

/// Stands in for the OS file picker (the "Choose file" branch).
class _FakeFileSelector extends fs.FileSelectorPlatform {
  _FakeFileSelector(this.file);

  final fs.XFile? file;
  bool opened = false;

  @override
  Future<fs.XFile?> openFile({
    List<fs.XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    opened = true;
    return file;
  }
}

/// Stands in for the camera (the "Take photo" branch).
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker({this.photo, this.error});

  final Uint8List? photo;
  final Object? error;
  ImageSource? requestedSource;
  ImagePickerOptions? options;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    requestedSource = source;
    this.options = options;
    if (error != null) throw error!;
    final bytes = photo;
    return bytes == null ? null : XFile.fromData(bytes, name: 'photo.jpg');
  }
}

/// A real (tiny) JPEG, optionally tagged with an EXIF orientation.
Uint8List _jpeg({int width = 8, int height = 4, int? orientation}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 40, 40));
  // A stripe down the left edge, so a rotation is visible in the pixels.
  img.fillRect(image,
      x1: 0, y1: 0, x2: 0, y2: height - 1, color: img.ColorRgb8(0, 0, 0));
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(image, quality: 95);
}

/// Starts a pick and hands back its still-pending future, so the test can
/// drive the sheet before awaiting the result.
Future<Future<Uint8List?>> _startPick(WidgetTester tester) async {
  late Future<Uint8List?> pending;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => pending = pickImageBytesFromSource(context),
          child: const Text('pick'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('pick'));
  await tester.pumpAndSettle();
  return pending;
}

/// A [testWidgets] that runs as [platform]. The override has to be cleared
/// before the body returns - the binding checks it as an invariant, ahead of
/// any tearDown.
void testWidgetsOn(
  String description,
  TargetPlatform platform,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  group('source sheet', () {
    testWidgetsOn('mobile offers the camera, and shoots when it is chosen',
        TargetPlatform.android, (tester) async {
      final camera = _FakeImagePicker(photo: _jpeg());
      final originalCamera = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = camera;
      addTearDown(() => ImagePickerPlatform.instance = originalCamera);
      final files = _FakeFileSelector(null);
      final originalFiles = fs.FileSelectorPlatform.instance;
      fs.FileSelectorPlatform.instance = files;
      addTearDown(() => fs.FileSelectorPlatform.instance = originalFiles);

      final picked = await _startPick(tester);
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose file'), findsOneWidget);

      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();

      expect(await picked, isNotNull);
      expect(camera.requestedSource, ImageSource.camera);
      // The full-size sensor frame never crosses the channel.
      expect(camera.options!.maxWidth, cameraCaptureMaxDimension);
      expect(camera.options!.maxHeight, cameraCaptureMaxDimension);
      expect(camera.options!.imageQuality, cameraCaptureQuality);
      expect(files.opened, isFalse);
    });

    testWidgetsOn('"Choose file" still goes to the OS file picker',
        TargetPlatform.android, (tester) async {
      final camera = _FakeImagePicker(photo: _jpeg());
      final originalCamera = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = camera;
      addTearDown(() => ImagePickerPlatform.instance = originalCamera);
      final files =
          _FakeFileSelector(fs.XFile.fromData(_jpeg(), name: 'photo.jpg'));
      final originalFiles = fs.FileSelectorPlatform.instance;
      fs.FileSelectorPlatform.instance = files;
      addTearDown(() => fs.FileSelectorPlatform.instance = originalFiles);

      final picked = await _startPick(tester);
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(await picked, isNotNull);
      expect(files.opened, isTrue);
      expect(camera.requestedSource, isNull);
    });

    testWidgetsOn('a rotated file pick is put upright too',
        TargetPlatform.android, (tester) async {
      final files = _FakeFileSelector(
          fs.XFile.fromData(_jpeg(orientation: 6), name: 'photo.jpg'));
      final originalFiles = fs.FileSelectorPlatform.instance;
      fs.FileSelectorPlatform.instance = files;
      addTearDown(() => fs.FileSelectorPlatform.instance = originalFiles);

      // A widget test cannot await the real isolate hop (`compute` makes no
      // progress in the fake-async zone), so bake in place here. The isolate
      // path itself is covered by the plain tests below.
      debugBakeOrientationOffIsolate = (bytes) async =>
          bakeJpegOrientation(bytes);
      addTearDown(() => debugBakeOrientationOffIsolate = null);

      final picked = await _startPick(tester);
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      final bytes = await picked;
      expect(jpegExifOrientation(bytes!), isNull);
      expect(img.decodeJpg(bytes)!.width, 4);
    });

    testWidgetsOn('dismissing the sheet cancels the pick',
        TargetPlatform.android, (tester) async {
      final files = _FakeFileSelector(null);
      final originalFiles = fs.FileSelectorPlatform.instance;
      fs.FileSelectorPlatform.instance = files;
      addTearDown(() => fs.FileSelectorPlatform.instance = originalFiles);

      final picked = await _startPick(tester);
      await tester.tapAt(const Offset(400, 20)); // the scrim
      await tester.pumpAndSettle();

      expect(await picked, isNull);
      expect(files.opened, isFalse);
    });

    testWidgetsOn('a camera that will not open toasts instead of throwing',
        TargetPlatform.android, (tester) async {
      final camera = _FakeImagePicker(error: StateError('no camera'));
      final originalCamera = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = camera;
      addTearDown(() => ImagePickerPlatform.instance = originalCamera);

      final picked = await _startPick(tester);
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();

      expect(await picked, isNull);
      expect(find.text("Couldn't take a photo"), findsOneWidget);
    });

    testWidgetsOn('desktop skips the sheet and opens the file picker',
        TargetPlatform.linux, (tester) async {
      final files =
          _FakeFileSelector(fs.XFile.fromData(_jpeg(), name: 'photo.jpg'));
      final originalFiles = fs.FileSelectorPlatform.instance;
      fs.FileSelectorPlatform.instance = files;
      addTearDown(() => fs.FileSelectorPlatform.instance = originalFiles);

      final picked = await _startPick(tester);
      expect(find.text('Take photo'), findsNothing);

      expect(await picked, isNotNull);
      expect(files.opened, isTrue);
    });
  });

  group('EXIF orientation', () {
    test('reads the orientation tag out of a JPEG', () {
      expect(jpegExifOrientation(_jpeg(orientation: 6)), 6);
      expect(jpegExifOrientation(_jpeg(orientation: 1)), 1);
    });

    test('a JPEG without EXIF, or a non-JPEG, reads as unrotated', () {
      expect(jpegExifOrientation(_jpeg()), isNull);
      expect(jpegExifOrientation(Uint8List.fromList([1, 2, 3, 4])), isNull);
      expect(jpegExifOrientation(Uint8List(0)), isNull);
    });

    test('an unrotated capture is embedded byte-for-byte', () async {
      final bytes = _jpeg();
      expect(await uprightJpeg(bytes), same(bytes));
      final tagged = _jpeg(orientation: 1);
      expect(await uprightJpeg(tagged), same(tagged));
    });

    test('a rotated capture is baked upright', () async {
      // Orientation 6: the pixels are stored rotated 90° counter-clockwise
      // from how the photo should read, so upright swaps width and height.
      final bytes = _jpeg(width: 8, height: 4, orientation: 6);
      final upright = img.decodeJpg(await uprightJpeg(bytes))!;
      expect(upright.width, 4);
      expect(upright.height, 8);
      // The tag is cleared, so nothing downstream rotates it a second time.
      expect(jpegExifOrientation(await uprightJpeg(bytes)), isNull);
    });
  });
}
