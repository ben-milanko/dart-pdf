/// EXPERIMENTAL strip/retained-scene rendering (shader-rendering tracks):
/// Track B's sparse-strip shader device plus Track C's retained scene.
///
/// Deliberately not exported from the main `dart_pdf_editor.dart` barrel:
/// the API here is a moving target while the strip/shader replay devices are
/// built. Import this barrel explicitly to opt in.
library;

export 'src/strips/strip_batch.dart';
export 'src/strips/strip_device.dart';
export 'src/strips/strip_scene.dart';
