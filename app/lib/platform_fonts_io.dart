import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

/// Enumerates the OS-installed `.ttf`/`.otf` fonts under the platform's
/// standard font directories and returns them as embeddable
/// [PdfPlatformFont]s for the editor's font menu.
///
/// Only filenames are read here - the font *program* loads lazily, the first
/// time a font is actually picked, so scanning hundreds of installed fonts at
/// startup never reads their (sometimes large) bytes. One entry is kept per
/// family (the regular face is preferred), so the menu shows "DejaVu Sans"
/// once rather than once per weight. TrueType collections (`.ttc`) are skipped
/// because they bundle several faces and can't embed directly.
///
/// The directory walk, the file-name parsing and the sort run on a helper
/// isolate: a Noto-heavy Linux install lists thousands of files (30-45 ms), and
/// the host calls this while it builds its first editor frame. Only the
/// finished (family, path) list crosses back.
///
/// Best-effort throughout: an unreadable directory, a permission error, or a
/// font that fails to parse on pick is simply skipped.
Future<List<PdfPlatformFont>> loadPlatformFonts() async {
  final records = await Isolate.run(_scanFontRecords);
  return [
    for (final (family, path) in records)
      PdfPlatformFont(
        label: family,
        family: family,
        loadBytes: () => _readFontBytes(path),
      ),
  ];
}

const _maxFonts = 300;

/// Scans the platform's font directories into at most [_maxFonts]
/// (family, path) records, sorted case-insensitively by family. Top-level so
/// [Isolate.run] is handed a plain function rather than a closure.
List<(String, String)> _scanFontRecords() {
  final candidates = <String, _FamilyCandidate>{};
  for (final dir in _fontDirectories()) {
    _scanDirectory(dir, candidates);
  }
  final sorted = candidates.values.toList()
    ..sort((a, b) => a.family.toLowerCase().compareTo(b.family.toLowerCase()));
  // Bound the menu: pathological font collections shouldn't produce thousands
  // of items. One-per-family already keeps this well under the cap in practice.
  return [for (final c in sorted.take(_maxFonts)) (c.family, c.path)];
}

/// The standard system + user font directories per platform. Each is guarded
/// with an existence check before scanning, so listing one that's absent on a
/// given install is harmless.
List<Directory> _fontDirectories() {
  final home = _homeDirectory();
  if (Platform.isMacOS) {
    return [
      Directory('/System/Library/Fonts'),
      Directory('/Library/Fonts'),
      if (home != null) Directory('$home/Library/Fonts'),
    ];
  }
  if (Platform.isWindows) {
    final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final localAppData = Platform.environment['LOCALAPPDATA'];
    return [
      Directory('$windir\\Fonts'),
      if (localAppData != null)
        Directory('$localAppData\\Microsoft\\Windows\\Fonts'),
    ];
  }
  if (Platform.isAndroid) {
    return [
      Directory('/system/fonts'),
      Directory('/system/font'),
      Directory('/data/fonts'),
    ];
  }
  // Linux and other Unix-likes.
  return [
    Directory('/usr/share/fonts'),
    Directory('/usr/local/share/fonts'),
    if (home != null) Directory('$home/.fonts'),
    if (home != null) Directory('$home/.local/share/fonts'),
  ];
}

String? _homeDirectory() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

void _scanDirectory(Directory dir, Map<String, _FamilyCandidate> out) {
  if (!dir.existsSync()) return;
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(recursive: true, followLinks: false);
  } catch (_) {
    return; // unreadable tree - skip it
  }
  for (final entry in entries) {
    if (entry is! File) continue;
    final path = entry.path;
    final fileName = _baseName(path);
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) continue; // no extension (or a dotfile)
    final ext = fileName.substring(dot + 1).toLowerCase();
    if (ext != 'ttf' && ext != 'otf') continue; // .ttc can't embed directly
    final base = fileName.substring(0, dot);
    final (family, isRegular) = _parseFamily(base);
    if (family.isEmpty) continue;
    final existing = out[family];
    // Prefer the regular face; otherwise keep the first one seen.
    if (existing == null || (!existing.isRegular && isRegular)) {
      out[family] = _FamilyCandidate(path, family, isRegular);
    }
  }
}

String _baseName(String path) {
  final slash = math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return slash < 0 ? path : path.substring(slash + 1);
}

/// Derives a display family name and a regular-face flag from a font's file
/// name. Splits a trailing `-Style` suffix, spaces out CamelCase and
/// underscores, and treats the plain/Regular/Book/Roman/Normal faces as the
/// preferred one to show.
(String, bool) _parseFamily(String base) {
  var name = base;
  var style = '';
  final dash = base.lastIndexOf('-');
  if (dash > 0) {
    name = base.substring(0, dash);
    style = base.substring(dash + 1);
  }
  final pretty = _prettify(name);
  final s = style.toLowerCase();
  final isRegular = s.isEmpty ||
      s == 'regular' ||
      s == 'book' ||
      s == 'roman' ||
      s == 'normal';
  return (pretty, isRegular);
}

String _prettify(String raw) {
  // CamelCase → spaced, underscores → spaces, then collapse whitespace.
  final spaced = raw
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return spaced;
}

Future<Uint8List?> _readFontBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null; // uninstalled or unreadable since discovery
  }
}

class _FamilyCandidate {
  _FamilyCandidate(this.path, this.family, this.isRegular);
  final String path;
  final String family;
  final bool isRegular;
}
