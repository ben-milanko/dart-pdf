import 'package:flutter/foundation.dart';

/// How an available update can be applied on the running platform.
enum UpdateApplyMode {
  /// Replace the running binary on disk and relaunch it. Used for the Linux
  /// AppImage, which is a single self-contained executable - the one desktop
  /// packaging where an atomic self-replace is clean and reliable.
  inPlaceRelaunch,

  /// Download the artifact and hand it to the OS: run the installer
  /// (`.dmg` / `.exe`) or reveal it so the user completes the update. Used on
  /// macOS and Windows, where swapping a running app bundle is fragile and the
  /// bundles are unsigned anyway.
  openArtifact,

  /// No supported in-app apply path (web, mobile, a Linux tarball install, or
  /// a release with no direct artifact). Callers fall back to the browser
  /// download.
  unsupported,
}

/// The filesystem and process operations the in-app updater needs, factored
/// behind an interface so [UpdateInstaller] stays testable (a fake records the
/// calls) and web-compilable (the real implementation pulls in `dart:io` only
/// through a conditional import; the web stub reports [UpdateApplyMode
/// .unsupported]).
abstract class UpdatePlatformOps {
  TargetPlatform get platform;

  /// Absolute path of the running AppImage (`$APPIMAGE`), or null when the
  /// process is not an AppImage - the signal that a clean single-file
  /// self-replace is possible on Linux.
  String? get appImagePath;

  /// A user-visible directory for hand-off downloads (the Downloads folder,
  /// falling back to a temp directory), where the macOS/Windows installer
  /// artifact is saved before the OS opens it.
  Future<String> downloadDirectory();

  /// Joins [dir] and [name] with the platform path separator.
  String joinPath(String dir, String name);

  /// The directory containing [path]. In-place AppImage staging writes here so
  /// the replace is a same-filesystem (atomic) rename.
  String parentDirectory(String path);

  /// Writes [bytes] to [path] (overwriting), marking it executable when asked.
  Future<void> writeArtifact(String path, List<int> bytes,
      {bool executable = false});

  /// Atomically moves [from] onto [to], replacing it. Both paths must live on
  /// the same filesystem so the rename is atomic (no half-written binary).
  Future<void> replaceInPlace({required String from, required String to});

  /// Launches [path] detached and terminates this process so the freshly
  /// written binary takes over. Never returns.
  Future<Never> relaunchAndExit(String path);

  /// Opens [path] with the OS default handler (the installer), falling back to
  /// revealing it in the file manager so the user can run it themselves.
  Future<void> openArtifact(String path);
}
