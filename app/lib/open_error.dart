// Turns platform file-open failures into short user-facing details without
// leaking an exception class, errno, or a potentially very long local path.
export 'open_error_stub.dart' if (dart.library.io) 'open_error_io.dart';
