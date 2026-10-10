// Where the preview tour writes the frames it captures (see preview_main.dart):
// files on a device or the simulator, nothing on the web.
export 'preview_capture_stub.dart'
    if (dart.library.io) 'preview_capture_io.dart';
