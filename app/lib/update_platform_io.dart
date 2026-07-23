import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_platform.dart';

/// Native (`dart:io`) platform ops for the in-app updater: real filesystem
/// writes, an atomic rename to swap the running AppImage, and OS hand-off for
/// the macOS/Windows installer artifacts.
UpdatePlatformOps defaultUpdatePlatformOps() => IoUpdatePlatformOps();

class IoUpdatePlatformOps implements UpdatePlatformOps {
  @override
  TargetPlatform get platform => defaultTargetPlatform;

  @override
  String? get appImagePath {
    // AppImage runtimes export $APPIMAGE with the absolute path of the mounted
    // image file (the thing on disk, not the FUSE mount point). Only trust it
    // when it points at a real file we could rewrite.
    final path = Platform.environment['APPIMAGE'];
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  @override
  Future<String> downloadDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads.path;
    } catch (_) {
      // Fall through to the system temp directory below.
    }
    return Directory.systemTemp.path;
  }

  @override
  String joinPath(String dir, String name) {
    final sep = Platform.pathSeparator;
    return dir.endsWith(sep) ? '$dir$name' : '$dir$sep$name';
  }

  @override
  String parentDirectory(String path) => File(path).parent.path;

  @override
  Future<void> writeArtifact(String path, List<int> bytes,
      {bool executable = false}) async {
    await File(path).writeAsBytes(bytes, flush: true);
    if (executable && !Platform.isWindows) {
      // Dart's File API has no chmod; shell out. A failure here surfaces to the
      // caller, which aborts before swapping the running binary.
      final result = await Process.run('chmod', ['+x', path]);
      if (result.exitCode != 0) {
        throw FileSystemException(
            'chmod +x failed: ${result.stderr}', path);
      }
    }
  }

  @override
  Future<void> replaceInPlace(
      {required String from, required String to}) async {
    // Same-filesystem rename: atomic, and on Linux it replaces the path even
    // while the old inode is still mapped by the running process.
    await File(from).rename(to);
  }

  @override
  Future<Never> relaunchAndExit(String path) async {
    await Process.start(path, const [], mode: ProcessStartMode.detached);
    exit(0);
  }

  @override
  Future<void> openArtifact(String path) async {
    // Go through url_launcher (NSWorkspace on macOS, ShellExecute on Windows,
    // xdg-open on Linux) rather than spawning a shell: it is the path that
    // works under the macOS App Sandbox, where `Process.start('open', …)` is
    // denied. Opening the file runs the installer (`.dmg` mounts; `.exe`
    // launches) or opens it with the default handler.
    final launched =
        await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
    if (!launched) {
      throw const FileSystemException('Could not open the downloaded update');
    }
  }
}
