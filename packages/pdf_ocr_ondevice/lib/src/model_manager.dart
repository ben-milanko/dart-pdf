import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'ocr_model.dart';

/// Thrown when a model file cannot be downloaded, fails its integrity check,
/// or is requested on an unsupported platform.
class PdfOcrModelException implements Exception {
  PdfOcrModelException(this.message);

  final String message;

  @override
  String toString() => 'PdfOcrModelException: $message';
}

/// Progress of a [PdfOcrModelManager.download], emitted on the download's
/// stream as bytes arrive.
@immutable
class PdfOcrDownloadProgress {
  const PdfOcrDownloadProgress({
    required this.fileIndex,
    required this.fileCount,
    required this.fileName,
    required this.receivedBytes,
    required this.totalBytes,
  });

  /// Zero-based index of the file currently downloading.
  final int fileIndex;

  /// How many files the model has.
  final int fileCount;

  /// The current file's cache name.
  final String fileName;

  /// Bytes downloaded across the whole model so far.
  final int receivedBytes;

  /// Best estimate of the model's total bytes (from `content-length` headers
  /// and/or the descriptor's declared sizes), or 0 when unknown.
  final int totalBytes;

  /// Download fraction in `[0, 1]`, or null when the total is unknown.
  double? get fraction =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

/// Downloads, caches, verifies, and removes on-device OCR models.
///
/// A model is a small set of files ([PdfOcrModel.files]); the manager stores
/// each under `<app-support>/pdf_ocr_models/<model id>/<file name>` and treats
/// a model as installed once every file is present (and, for files that
/// declare a [PdfOcrModelFile.sha256], verified).
///
/// **Platform support.** On-device OCR runs on the native platforms only
/// (Android, iOS, macOS, Windows, Linux). On the web [isSupported] is false
/// and the download/cache methods throw — host an HTTP OCR service and use
/// `pdf_ocr_vlm` there instead.
class PdfOcrModelManager {
  PdfOcrModelManager({
    http.Client? client,
    Future<Directory> Function()? cacheRoot,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _cacheRoot = cacheRoot ?? _defaultCacheRoot;

  final http.Client _client;
  final bool _ownsClient;
  final Future<Directory> Function() _cacheRoot;

  /// Whether on-device OCR is supported on this platform. False on the web
  /// (no local model store / native inference runtime there).
  static bool get isSupported {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  static Future<Directory> _defaultCacheRoot() async {
    final dir = await getApplicationSupportDirectory();
    return Directory('${dir.path}/pdf_ocr_models');
  }

  /// The directory [model] is (or would be) cached in.
  Future<Directory> directory(PdfOcrModel model) async {
    final root = await _cacheRoot();
    return Directory('${root.path}/${model.id}');
  }

  /// The local [File] for one of the model's [PdfOcrModelFile]s.
  Future<File> fileFor(PdfOcrModel model, PdfOcrModelFile file) async {
    final dir = await directory(model);
    return File('${dir.path}/${file.name}');
  }

  /// Whether every file of [model] is present on disk. (This checks presence
  /// and non-emptiness; integrity is verified at download time.)
  Future<bool> isDownloaded(PdfOcrModel model) async {
    _ensureSupported();
    for (final f in model.files) {
      final file = await fileFor(model, f);
      if (!file.existsSync() || file.lengthSync() == 0) return false;
    }
    return true;
  }

  /// The on-disk paths of [model]'s files, keyed by [PdfOcrModelFile.name].
  /// Throws if the model is not fully downloaded.
  Future<Map<String, File>> localFiles(PdfOcrModel model) async {
    if (!await isDownloaded(model)) {
      throw PdfOcrModelException(
          'model "${model.id}" is not downloaded — call download() first');
    }
    return {
      for (final f in model.files) f.name: await fileFor(model, f),
    };
  }

  /// Downloads any missing files of [model], reporting [onProgress] as bytes
  /// arrive. Already-present files are skipped (re-running after a partial
  /// download resumes the rest). Each file is written to a temp name,
  /// integrity-checked, then atomically moved into place, so an interrupted
  /// download never leaves a half-written file the manager would treat as
  /// installed.
  Future<void> download(
    PdfOcrModel model, {
    void Function(PdfOcrDownloadProgress progress)? onProgress,
    bool force = false,
  }) async {
    _ensureSupported();
    final dir = await directory(model);
    await dir.create(recursive: true);

    final files = model.files;
    // Estimate the total up front from declared sizes; refine per-file from
    // content-length as each request opens.
    var declaredTotal = 0;
    for (final f in files) {
      declaredTotal += f.sizeBytes ?? 0;
    }
    var receivedSoFar = 0;

    for (var i = 0; i < files.length; i++) {
      final spec = files[i];
      final dest = File('${dir.path}/${spec.name}');
      if (!force && dest.existsSync() && dest.lengthSync() > 0) {
        receivedSoFar += dest.lengthSync();
        onProgress?.call(PdfOcrDownloadProgress(
          fileIndex: i,
          fileCount: files.length,
          fileName: spec.name,
          receivedBytes: receivedSoFar,
          totalBytes: declaredTotal,
        ));
        continue;
      }

      final tmp = File('${dest.path}.part');
      final received = await _downloadOne(
        spec,
        tmp,
        onChunk: (chunk, fileTotal) {
          receivedSoFar += chunk;
          onProgress?.call(PdfOcrDownloadProgress(
            fileIndex: i,
            fileCount: files.length,
            fileName: spec.name,
            receivedBytes: receivedSoFar,
            totalBytes: declaredTotal,
          ));
        },
      );

      if (spec.sha256 != null) {
        final digest = sha256.convert(await tmp.readAsBytes()).toString();
        if (digest != spec.sha256!.toLowerCase()) {
          await _quietDelete(tmp);
          throw PdfOcrModelException(
              'checksum mismatch for ${spec.name}: expected ${spec.sha256}, '
              'got $digest');
        }
      }
      if (received == 0) {
        await _quietDelete(tmp);
        throw PdfOcrModelException('downloaded ${spec.name} was empty');
      }
      if (dest.existsSync()) await _quietDelete(dest);
      await tmp.rename(dest.path);
    }
  }

  Future<int> _downloadOne(
    PdfOcrModelFile spec,
    File dest, {
    required void Function(int chunkBytes, int fileTotal) onChunk,
  }) async {
    final request = http.Request('GET', spec.url);
    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw PdfOcrModelException('could not reach ${spec.url}: $e');
    }
    if (response.statusCode != 200) {
      throw PdfOcrModelException(
          'download of ${spec.name} failed: HTTP ${response.statusCode} '
          'from ${spec.url}');
    }
    final fileTotal = response.contentLength ?? spec.sizeBytes ?? 0;
    final sink = dest.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onChunk(chunk.length, fileTotal);
      }
    } catch (e) {
      await sink.close();
      await _quietDelete(dest);
      throw PdfOcrModelException('download of ${spec.name} interrupted: $e');
    }
    await sink.close();
    return received;
  }

  /// Deletes [model]'s cached directory.
  Future<void> delete(PdfOcrModel model) async {
    if (kIsWeb) return;
    final dir = await directory(model);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Releases the HTTP client if this manager created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  static Future<void> _quietDelete(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // Best effort — a leftover temp file is harmless.
    }
  }

  void _ensureSupported() {
    if (!isSupported) {
      throw PdfOcrModelException(
          'on-device OCR is not supported on this platform '
          '($defaultTargetPlatform${kIsWeb ? ' / web' : ''})');
    }
  }
}
