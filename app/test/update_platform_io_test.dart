@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/update_platform_io.dart';

/// Exercises the real (dart:io) platform ops against a temp directory. The two
/// operations that can't be unit-tested — `relaunchAndExit` (calls exit(0)) and
/// `openArtifact` (spawns the OS handler via url_launcher) — are covered by the
/// installer's fake-ops tests instead.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('dartpdf-update-test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final ops = IoUpdatePlatformOps();

  test('joinPath uses the platform separator and avoids doubling it', () {
    final sep = Platform.pathSeparator;
    expect(ops.joinPath('dir', 'file.bin'), 'dir${sep}file.bin');
    expect(ops.joinPath('dir$sep', 'file.bin'), 'dir${sep}file.bin');
  });

  test('parentDirectory returns the containing directory', () {
    final child = ops.joinPath(tmp.path, 'child.bin');
    expect(ops.parentDirectory(child), tmp.path);
  });

  test('appImagePath is null when not running as an AppImage', () {
    // The test runner is not an AppImage, so $APPIMAGE is unset/invalid.
    expect(ops.appImagePath, isNull);
  });

  test('downloadDirectory resolves to a real writable directory', () async {
    final dir = await ops.downloadDirectory();
    expect(dir, isNotEmpty);
    expect(Directory(dir).existsSync(), isTrue);
  });

  test('writeArtifact writes the bytes', () async {
    final path = ops.joinPath(tmp.path, 'plain.bin');
    await ops.writeArtifact(path, [1, 2, 3, 4]);
    expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
  });

  test('writeArtifact marks the file executable when asked', () async {
    final path = ops.joinPath(tmp.path, 'runnable.bin');
    await ops.writeArtifact(path, [0, 1, 2], executable: true);
    expect(File(path).readAsBytesSync(), [0, 1, 2]);
    if (!Platform.isWindows) {
      // Owner-execute bit (0o100) set by chmod +x.
      expect(File(path).statSync().mode & 0x40, isNonZero);
    }
  }, skip: Platform.isWindows ? 'chmod is a no-op on Windows' : false);

  test('replaceInPlace atomically renames over the target', () async {
    final target = ops.joinPath(tmp.path, 'target.bin');
    final staged = ops.joinPath(tmp.path, 'staged.bin');
    await ops.writeArtifact(target, [9, 9, 9]);
    await ops.writeArtifact(staged, [1, 2, 3]);
    await ops.replaceInPlace(from: staged, to: target);
    expect(File(target).readAsBytesSync(), [1, 2, 3]);
    expect(File(staged).existsSync(), isFalse);
  });

  test('reports the host platform', () {
    expect(ops.platform, defaultTargetPlatform);
  });
}
