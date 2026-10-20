import 'package:flutter/foundation.dart';

import 'update_platform.dart';

/// Web build's platform ops: there is no filesystem to write to and update
/// checks are disabled on web ([UpdateService.supported] is false), so this is
/// only a compile-time placeholder. It reports no AppImage and throws if any
/// filesystem operation is somehow reached.
UpdatePlatformOps defaultUpdatePlatformOps() => const _StubUpdatePlatformOps();

class _StubUpdatePlatformOps implements UpdatePlatformOps {
  const _StubUpdatePlatformOps();

  @override
  TargetPlatform get platform => defaultTargetPlatform;

  @override
  String? get appImagePath => null;

  Never _unsupported() =>
      throw UnsupportedError('In-app updates are not available on this build');

  @override
  Future<String> downloadDirectory() => _unsupported();

  @override
  String joinPath(String dir, String name) => _unsupported();

  @override
  String parentDirectory(String path) => _unsupported();

  @override
  Future<void> writeArtifact(String path, List<int> bytes,
          {bool executable = false}) =>
      _unsupported();

  @override
  Future<void> replaceInPlace({required String from, required String to}) =>
      _unsupported();

  @override
  Future<Never> relaunchAndExit(String path) => _unsupported();

  @override
  Future<void> openArtifact(String path) => _unsupported();
}
