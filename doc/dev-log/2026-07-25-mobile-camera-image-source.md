# Mobile: take the picture instead of finding it (camera image source)

Every image the app inserts — the image tool, a form push button's icon,
a signature's logo backdrop — went through one function,
`pickImageBytes()` in `app/lib/file_io.dart`, which opens the OS *file*
picker. That is the right and only answer on desktop. On a phone it is
the wrong half of the story: the picture the user wants on the page is
usually still in front of the camera (a receipt, a whiteboard, a
hand-signed page), and neither Android's SAF picker nor iOS's Files sheet
can offer a camera.

So on Android/iOS the pick now starts with a source sheet — **Take
photo** / **Choose file** — and only then opens the camera or the file
picker. Desktop and web skip the sheet entirely and behave exactly as
before (`supportsCameraCapture` is false there: `image_picker`'s desktop
implementations have no camera, and a browser's file input already
surfaces one where the device has it).

New files, both in `app/lib`:

- `image_source_picker.dart` — `pickImageBytesFromSource(context)`, the
  drop-in replacement for `pickImageBytes` at the three call sites, plus
  the sheet itself. Dismissing the sheet means "cancelled", same as
  backing out of the file dialog.
- `camera_capture.dart` — the capture, and the orientation fix below.

`SignatureLogoPicker` grew a `BuildContext` parameter so the signature
dialog presents the sheet from its own context rather than the editor's.

## The capture is bounded before it crosses the channel

A phone sensor shoots 12 MP+. Every one of those bytes would land in the
saved PDF, for a picture that resolves to a fraction of a page (2000 px
across an A4 width is already ~240 dpi). So the capture asks for
`maxWidth`/`maxHeight` of 2000 and quality 88, which `image_picker`
applies **natively** — the full-size frame never reaches Dart.

## EXIF orientation has to be baked, or half of all photos land sideways

This is the part that isn't obvious. `PdfEmbeddableImage.jpeg` embeds
JPEG bytes **verbatim** under DCTDecode (that's the whole point — no
re-encode, no quality loss), and PDF image XObjects have no orientation
tag. A portrait phone shot, though, is normally stored as landscape
pixels plus an EXIF `/Orientation` of 6, and `image_picker`'s Android
resizer *deliberately* preserves that tag while rescaling
(`ExifDataCopier` documents it as "crucial for proper display"). Embedded
verbatim, that photo arrives on the page rotated 90°.

iOS doesn't have the problem — its `scaledImage:` draws through a
graphics context, which bakes the rotation into the pixels — but Android
does, so the fix lives in Dart where it covers both:

- `jpegExifOrientation()` walks the JPEG marker chain to APP1, checks the
  `Exif\0\0` header (XMP shares the marker), and reads tag `0x0112` out
  of IFD0 in whichever endianness the TIFF block declares. Anything
  missing or malformed reads as null = "assume upright".
- `uprightJpeg()` returns the **same bytes** when the orientation is
  absent or 1 — the overwhelmingly common case, and the one where the
  camera's own JPEG should reach the PDF untouched. Only a genuinely
  rotated capture pays for `decodeJpg` → `bakeOrientation` → `encodeJpg`,
  and that runs through `compute()` on a background isolate. Baking also
  clears the tag, so nothing downstream can rotate it a second time.

The **file** branch gets the same treatment, on every platform: a photo
picked out of the gallery (or off a desktop's disk) carries the very
rotation the camera wrote, so it embedded sideways before this change
too. PNGs and already-upright JPEGs take the identity path, so nothing
that was lossless stops being lossless.

## Platform wiring

- `image_picker: ^1.2.3` and `image: ^4.9.1` are new app dependencies
  (`image` was already in the resolved tree via `dart_pdf_editor`, which
  uses it to encode JPEG page exports).
- `ios/Runner/Info.plist` gained `NSCameraUsageDescription` — iOS
  **terminates** the app if the camera opens without it. No
  photo-library key is needed: `requestFullMetadata: false` keeps the
  capture off the library entirely.
- Android needs nothing. The camera runs through `ACTION_IMAGE_CAPTURE`
  and the plugin's own `FileProvider`, so there is no `CAMERA`
  permission to declare — and declaring one would only add a runtime
  prompt we don't otherwise need.

## Tests

`app/test/image_source_picker_test.dart` fakes both platforms the way the
existing `file_io_test.dart` fakes the file selector — a
`FileSelectorPlatform` for the file branch and an `ImagePickerPlatform`
for the camera — and covers: the sheet appearing on mobile and shooting
with the documented bounds, "Choose file" still reaching the file picker,
dismissal cancelling, a camera that won't open toasting rather than
throwing, and desktop never seeing the sheet. The orientation tests build
real JPEGs with `package:image`, assert the tag reads back, that an
unrotated capture is passed through by identity (`same()`), and that an
orientation-6 capture comes back with its width and height swapped and
the tag gone.

Two flutter_test gotchas here. `compute()` never completes inside a
widget test's fake-async zone — the isolate's reply is delivered on the
real event loop, which the fake clock isn't draining, and `runAsync`
can't rescue a future that was created outside it. Hence
`debugBakeOrientationOffIsolate`, a null-in-production seam the one
widget test that needs a rotated image sets to run the bake in place; the
real `compute` path stays covered by the plain (non-widget) tests.

And `debugDefaultTargetPlatformOverride` must be
cleared **before the test body returns** — the binding verifies it as an
invariant ahead of any `tearDown`, so a `tearDown`/`addTearDown` reset
fails every test. Hence the local `testWidgetsOn(description, platform,
body)` wrapper.
