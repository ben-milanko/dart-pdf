import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A PDF handed to the app by the operating system - an "open with", a share,
/// a file association, or a launch argument.
@immutable
class IncomingFile {
  const IncomingFile(
      {required this.name,
      this.path,
      this.bytes,
      this.bookmark,
      this.combine = false})
      : assert(path != null || bytes != null,
            'an incoming file needs a path or bytes');

  final String name;

  /// The on-disk path, when the OS gave us one (desktop file associations,
  /// drag-drop). Treated as a writable origin for in-place save.
  final String? path;

  /// The raw bytes, when the OS handed us content without a usable path
  /// (Android content:// streams, web file handles).
  final Uint8List? bytes;

  /// macOS security-scoped bookmark for [path], when the native runner can
  /// provide one. Persisted with recents/session entries for later reopens.
  final String? bookmark;

  /// True when the file came from the OS's "Combine with DartPDF" entry (a
  /// file manager's right-click menu or `--combine`): the batch it arrives in
  /// is to be combined into one document rather than opened side by side.
  final bool combine;
}

/// The single conduit for files the OS opens in the app, across every
/// platform. The native side of each runner talks to one [MethodChannel]:
///
///  - Dart → native `getInitialFiles`: the files the app cold-started with
///    (runners that predate it answer `getInitialFile` with one file).
///  - native → Dart `openFile` / `openFiles`: one file, or several handed
///    over in one request (a multi-file "Open with"), delivered while the app
///    is running (a second "open with", a share, a drag onto the dock icon).
///
/// Files arrive as batches - one per OS request - so several files opened
/// together can be offered as one choice (open side by side, or combine).
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
  final _files = StreamController<List<IncomingFile>>.broadcast();

  /// Batches of files the OS opens after launch, one per OS request.
  Stream<List<IncomingFile>> get files => _files.stream;

  /// Begins listening for warm-start opens from the native side.
  void start() {
    _channel.setMethodCallHandler((call) async {
      final batch = switch (call.method) {
        'openFile' => _decodeAll([call.arguments]),
        'openFiles' => _decodeAll(call.arguments),
        _ => const <IncomingFile>[],
      };
      if (batch.isNotEmpty) _files.add(batch);
      return null;
    });
  }

  /// Returns the files the app was launched with (empty for none). Safe
  /// everywhere: a missing native handler (tests, web) yields no files instead
  /// of throwing.
  Future<List<IncomingFile>> initialFiles() async {
    try {
      return _decodeAll(
          await _channel.invokeMethod<dynamic>('getInitialFiles'));
    } on MissingPluginException {
      // A runner without the batch call (or no runner at all).
    } catch (_) {
      return const [];
    }
    try {
      return _decodeAll(
          [await _channel.invokeMethod<dynamic>('getInitialFile')]);
    } catch (_) {
      return const [];
    }
  }

  /// Injects files from a non-channel source (the web launch-queue bridge).
  void push(List<IncomingFile> files) {
    if (files.isNotEmpty) _files.add(files);
  }

  void dispose() => _files.close();

  List<IncomingFile> _decodeAll(dynamic args) => [
        if (args is List)
          for (final item in args)
            if (_decode(item) case final file?) file,
      ];

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
      bookmark: args['bookmark'] as String?,
      combine: args['combine'] == true,
    );
  }
}
