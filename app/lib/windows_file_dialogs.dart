import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The runner channel that shows Windows' common-item dialogs.
///
/// `file_selector_windows` cannot show them here: it takes the dialog's owner
/// window from the plugin registrar's implicit `FlutterView`, and DartPDF's
/// desktop runners start the engine without one so Dart owns every native
/// window (see window_support.dart). `registrar->GetView()` is then null and
/// the plugin dereferences it, taking the process down the first time the user
/// opens a document or picks a save location. The runner knows its active
/// window without a view, so it drives the dialogs itself
/// (windows/runner/file_dialogs.cpp).
@visibleForTesting
const windowsFileDialogChannel =
    MethodChannel('dev.milanko.dartpdf/file_dialogs');

/// Routes `file_selector` through DartPDF's own Windows dialogs.
///
/// Installed process-wide on Windows so both runner bootstraps take one code
/// path. Every method falls back to the implementation it replaced when the
/// runner carries no dialog channel, which keeps a Dart build running against
/// an older runner working.
class WindowsFileDialogs extends FileSelectorPlatform {
  WindowsFileDialogs({
    MethodChannel channel = windowsFileDialogChannel,
    FileSelectorPlatform? fallback,
  })  : _channel = channel,
        _fallback = fallback;

  final MethodChannel _channel;
  final FileSelectorPlatform? _fallback;

  /// Replaces [FileSelectorPlatform.instance] on Windows, and reports whether
  /// it did. A no-op elsewhere: macOS and Linux dialogs need no Flutter view,
  /// and the web/mobile implementations are unrelated.
  static bool installIfNeeded() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;
    final previous = FileSelectorPlatform.instance;
    if (previous is WindowsFileDialogs) return true;
    FileSelectorPlatform.instance = WindowsFileDialogs(fallback: previous);
    return true;
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final result = await _show(
      'openFile',
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
    if (result == null) {
      return _fallback?.openFile(
        acceptedTypeGroups: acceptedTypeGroups,
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
      );
    }
    return result.paths.isEmpty ? null : XFile(result.paths.first);
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final result = await _show(
      'openFiles',
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
    if (result == null) {
      return await _fallback?.openFiles(
            acceptedTypeGroups: acceptedTypeGroups,
            initialDirectory: initialDirectory,
            confirmButtonText: confirmButtonText,
          ) ??
          const <XFile>[];
    }
    return [for (final path in result.paths) XFile(path)];
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    final result = await _show(
      'getSaveLocation',
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: options.initialDirectory,
      confirmButtonText: options.confirmButtonText,
      suggestedName: options.suggestedName,
    );
    if (result == null) {
      return _fallback?.getSaveLocation(
        acceptedTypeGroups: acceptedTypeGroups,
        options: options,
      );
    }
    if (result.paths.isEmpty) return null;
    return FileSaveLocation(
      result.paths.first,
      activeFilter: result.activeFilter(acceptedTypeGroups),
    );
  }

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) async {
    final result = await _show(
      'getDirectoryPath',
      acceptedTypeGroups: null,
      initialDirectory: options.initialDirectory,
      confirmButtonText: options.confirmButtonText,
    );
    if (result == null) {
      return _fallback?.getDirectoryPathWithOptions(options);
    }
    return result.paths.isEmpty ? null : result.paths.first;
  }

  @override
  Future<List<String>> getDirectoryPathsWithOptions(
      FileDialogOptions options) async {
    final result = await _show(
      'getDirectoryPaths',
      acceptedTypeGroups: null,
      initialDirectory: options.initialDirectory,
      confirmButtonText: options.confirmButtonText,
    );
    if (result == null) {
      return await _fallback?.getDirectoryPathsWithOptions(options) ??
          const <String>[];
    }
    return result.paths;
  }

  /// Invokes [method] on the runner, or returns null when this runner has no
  /// dialog channel so the caller can fall back.
  Future<_DialogResult?> _show(
    String method, {
    required List<XTypeGroup>? acceptedTypeGroups,
    required String? initialDirectory,
    required String? confirmButtonText,
    String? suggestedName,
  }) async {
    final groups = [
      for (final group in acceptedTypeGroups ?? const <XTypeGroup>[])
        _encodeTypeGroup(group),
    ];
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(method, {
        'acceptedTypeGroups': groups,
        if (initialDirectory != null) 'initialDirectory': initialDirectory,
        if (confirmButtonText != null) 'confirmButtonText': confirmButtonText,
        if (suggestedName != null) 'suggestedName': suggestedName,
      });
      return _DialogResult.fromReply(reply);
    } on MissingPluginException {
      return null;
    }
  }
}

/// Encodes one filter entry, rejecting a group Windows cannot express - the
/// same contract (and error) as `file_selector_windows`, so a mis-declared
/// group fails loudly here rather than silently widening the dialog.
Map<String, Object?> _encodeTypeGroup(XTypeGroup group) {
  if (!group.allowsAny && (group.extensions?.isEmpty ?? true)) {
    throw ArgumentError(
      'Provided type group $group does not allow all files, but does not set '
      'any of the Windows-supported filter categories. "extensions" must be '
      'non-empty for Windows if anything is non-empty.',
    );
  }
  return {
    'label': group.label ?? '',
    'extensions': [...?group.extensions],
  };
}

/// The runner's reply: the chosen paths, plus the one-based index of the type
/// filter that was active (0 when the dialog reported none).
@immutable
class _DialogResult {
  const _DialogResult(this.paths, this.filterIndex);

  factory _DialogResult.fromReply(Map<String, Object?>? reply) {
    if (reply == null) return const _DialogResult([], 0);
    final paths = <String>[
      for (final path in (reply['paths'] as List<Object?>?) ?? const [])
        if (path is String && path.isNotEmpty) path,
    ];
    return _DialogResult(paths, (reply['filterIndex'] as int?) ?? 0);
  }

  final List<String> paths;
  final int filterIndex;

  /// The group [filterIndex] points at, or null when the dialog reported no
  /// filter (or one outside the list we sent).
  XTypeGroup? activeFilter(List<XTypeGroup>? groups) {
    if (groups == null || filterIndex < 1 || filterIndex > groups.length) {
      return null;
    }
    return groups[filterIndex - 1];
  }
}
