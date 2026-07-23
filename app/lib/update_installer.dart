import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'update_platform.dart';
import 'update_platform_stub.dart'
    if (dart.library.io) 'update_platform_io.dart';

/// Thrown when the user cancels an in-progress update download.
class UpdateCancelledException implements Exception {
  const UpdateCancelledException();
  @override
  String toString() => 'Update cancelled';
}

/// Thrown when the download or apply step fails (HTTP error, truncated file,
/// write failure). Carries a short human-readable [message].
class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);
  final String message;
  @override
  String toString() => 'UpdateInstallException: $message';
}

/// What happened when an update was applied.
enum UpdateInstallOutcome {
  /// The running binary was replaced and the app is relaunching (Linux
  /// AppImage). In practice the process exits before this is observed.
  relaunching,

  /// The artifact was downloaded and handed to the OS installer (macOS /
  /// Windows). The app keeps running.
  handedOff,

  /// This platform/release has no in-app apply path; the caller should open
  /// the browser download instead.
  unsupported,
}

/// Downloads a newer release artifact and applies it in place on desktop.
///
/// This turns the update *checker* into an actual updater where it can be done
/// safely: the Linux AppImage is a single executable, so the new build is
/// downloaded, verified against the release's reported size, written next to
/// the running image, and atomically renamed over it before relaunching. On
/// macOS and Windows - where swapping a running, unsigned bundle is fragile -
/// the artifact is downloaded and handed to the OS installer instead of just
/// opening a browser tab.
///
/// The filesystem/process work goes through an injectable [UpdatePlatformOps]
/// and the download through an injectable [http.Client], so the whole flow is
/// unit-testable without touching the real disk or network.
class UpdateInstaller {
  UpdateInstaller({
    UpdatePlatformOps? ops,
    http.Client Function()? clientFactory,
  })  : _ops = ops ?? defaultUpdatePlatformOps(),
        _clientFactory = clientFactory ?? http.Client.new;

  final UpdatePlatformOps _ops;
  final http.Client Function() _clientFactory;

  /// How [assetName] would be applied on the current platform, without
  /// downloading anything. [assetName] is the release artifact's file name
  /// (e.g. `dartpdf-linux-x86_64.AppImage`); null when the release exposes
  /// only its web page.
  UpdateApplyMode modeFor(String? assetName) {
    if (assetName == null || assetName.isEmpty) {
      return UpdateApplyMode.unsupported;
    }
    switch (_ops.platform) {
      case TargetPlatform.linux:
        // A clean, atomic self-replace is only possible when the running
        // process is an AppImage and the artifact is one too. A tarball
        // install has no single file to swap, so fall back to the browser.
        final isAppImage = assetName.toLowerCase().endsWith('.appimage');
        return (isAppImage && _ops.appImagePath != null)
            ? UpdateApplyMode.inPlaceRelaunch
            : UpdateApplyMode.unsupported;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return UpdateApplyMode.openArtifact;
      default:
        return UpdateApplyMode.unsupported;
    }
  }

  /// Downloads [url] and applies it according to [modeFor]. [assetName] names
  /// the artifact; [expectedSize], when known, is checked against the number of
  /// bytes received so a truncated download is never written over the install.
  ///
  /// [onProgress] reports `(received, total)` bytes (total null until known).
  /// [isCancelled] is polled while streaming so a UI cancel button can abort
  /// (throwing [UpdateCancelledException]).
  ///
  /// Returns [UpdateInstallOutcome.unsupported] without downloading when the
  /// platform has no apply path. Throws [UpdateInstallException] on failure.
  Future<UpdateInstallOutcome> downloadAndApply({
    required String url,
    required String assetName,
    int? expectedSize,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final mode = modeFor(assetName);
    if (mode == UpdateApplyMode.unsupported) {
      return UpdateInstallOutcome.unsupported;
    }

    final bytes = await _download(
      url,
      expectedSize: expectedSize,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );

    switch (mode) {
      case UpdateApplyMode.inPlaceRelaunch:
        await _applyInPlace(bytes);
        // relaunchAndExit terminates the process; unreachable in practice.
        return UpdateInstallOutcome.relaunching;
      case UpdateApplyMode.openArtifact:
        await _applyByHandoff(bytes, assetName);
        return UpdateInstallOutcome.handedOff;
      case UpdateApplyMode.unsupported:
        return UpdateInstallOutcome.unsupported;
    }
  }

  Future<void> _applyInPlace(Uint8List bytes) async {
    final target = _ops.appImagePath;
    if (target == null) {
      throw const UpdateInstallException('The running app is not an AppImage');
    }
    // Stage the new image next to the target so the replace is a
    // same-filesystem atomic rename (a temp dir is often a different mount).
    final dir = _ops.parentDirectory(target);
    final staged = _ops.joinPath(dir, '.dartpdf-update.AppImage.part');
    try {
      await _ops.writeArtifact(staged, bytes, executable: true);
      await _ops.replaceInPlace(from: staged, to: target);
    } catch (e) {
      throw UpdateInstallException('Could not write the update: $e');
    }
    await _ops.relaunchAndExit(target);
  }

  Future<void> _applyByHandoff(Uint8List bytes, String assetName) async {
    try {
      final dir = await _ops.downloadDirectory();
      final path = _ops.joinPath(dir, assetName);
      await _ops.writeArtifact(path, bytes);
      await _ops.openArtifact(path);
    } catch (e) {
      throw UpdateInstallException('Could not save the update: $e');
    }
  }

  Future<Uint8List> _download(
    String url, {
    int? expectedSize,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final client = _clientFactory();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw UpdateInstallException('Download failed (HTTP '
            '${response.statusCode})');
      }
      final total = expectedSize ?? response.contentLength;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      onProgress?.call(0, total);
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) {
          throw const UpdateCancelledException();
        }
        builder.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      final bytes = builder.toBytes();
      if (bytes.isEmpty) {
        throw const UpdateInstallException('The download was empty');
      }
      if (expectedSize != null && bytes.length != expectedSize) {
        throw UpdateInstallException('The download was incomplete '
            '(${bytes.length} of $expectedSize bytes)');
      }
      return bytes;
    } on UpdateCancelledException {
      rethrow;
    } on UpdateInstallException {
      rethrow;
    } catch (e) {
      throw UpdateInstallException('Download failed: $e');
    } finally {
      client.close();
    }
  }
}
