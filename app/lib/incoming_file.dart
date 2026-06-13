import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A PDF handed to the app by the operating system — an "open with", a share,
/// a file association, or a launch argument.
@immutable
class IncomingFile {
  const IncomingFile({required this.name, this.path, this.bytes})
      : assert(path != null || bytes != null,
            'an incoming file needs a path or bytes');

  final String name;

  /// The on-disk path, when the OS gave us one (desktop file associations,
  /// drag-drop). Treated as a writable origin for in-place save.
  final String? path;

  /// The raw bytes, when the OS handed us content without a usable path
  /// (Android content:// streams, web file handles).
  final Uint8List? bytes;
}

/// The single conduit for files the OS opens in the app, across every
/// platform. The native side of each runner talks to one [MethodChannel]:
///
///  - Dart → native `getInitialFile`: the file the app cold-started with.
///  - native → Dart `openFile`: a file delivered while the app is running
///    (a second "open with", a share, a drag onto the dock icon).
///
/// Web is fed separately (the launch-queue bridge calls [push] directly), and
/// desktop drag-drop is handled in the widget layer. When no native handler is
/// registered (e.g. widget tests) every call degrades to a no-op.
class IncomingFileService {
  IncomingFileService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Reverse-DNS channel name, shared verbatim by every native runner.
  static const channelName = 'dev.milanko.dartpdf/incoming';

  final MethodChannel _channel;
  final _files = StreamController<IncomingFile>.broadcast();

  /// Files the OS opens after launch.
  Stream<IncomingFile> get files => _files.stream;

  /// Begins listening for warm-start opens from the native side.
  void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFile') {
        final file = _decode(call.arguments);
        if (file != null) _files.add(file);
      }
      return null;
    });
  }

  /// Returns the file the app was launched with, or null. Safe everywhere:
  /// a missing native handler (tests, web) yields null instead of throwing.
  Future<IncomingFile?> initialFile() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('getInitialFile');
      return _decode(result);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Injects a file from a non-channel source (the web launch-queue bridge).
  void push(IncomingFile file) => _files.add(file);

  void dispose() => _files.close();

  IncomingFile? _decode(dynamic args) {
    if (args is! Map) return null;
    final path = args['path'] as String?;
    final bytes = args['bytes'] as Uint8List?;
    if ((path == null || path.isEmpty) && bytes == null) return null;
    final name = (args['name'] as String?)?.trim();
    return IncomingFile(
      name: name == null || name.isEmpty ? 'document.pdf' : name,
      path: (path != null && path.isEmpty) ? null : path,
      bytes: bytes,
    );
  }
}
