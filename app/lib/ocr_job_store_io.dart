import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'ocr_jobs.dart';

OcrJobStorage openOcrJobStorage() => FileOcrJobStorage();

class FileOcrJobStorage implements OcrJobStorage {
  FileOcrJobStorage({this.directory});
  final Directory? directory;
  static final Set<String> _held = {};
  static int _serial = 0;

  Future<Directory> _dir() async {
    final dir = directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/ocr_jobs');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String key) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key');
    }
    return File('${(await _dir()).path}/$key');
  }

  @override
  Future<List<String>> keys() async => [
        await for (final entry in (await _dir()).list())
          if (entry is File &&
              !entry.path.contains('.tmp-') &&
              !entry.path.endsWith('.lock'))
            entry.uri.pathSegments.last,
      ];

  @override
  Future<Uint8List?> read(String key) async {
    try {
      return await (await _file(key)).readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final file = await _file(key);
    final temp = File('${file.path}.tmp-$pid-${_serial++}');
    await temp.writeAsBytes(bytes, flush: true);
    // Dart rename replaces an existing file atomically on supported desktop
    // and mobile filesystems. Never truncate the committed file as a fallback.
    await temp.rename(file.path);
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (await _file(key)).delete();
    } on PathNotFoundException {
      // Already acknowledged/removed.
    }
  }

  @override
  Future<OcrJobLease?> claim(String id) async {
    final file = await _file('${id}_owner');
    final path = '${file.path}.lock';
    if (!_held.add(path)) return null;
    RandomAccessFile? handle;
    try {
      handle = await File(path).open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      return _FileLease(handle, () => _held.remove(path));
    } on FileSystemException catch (error) {
      final locked = handle != null &&
          const [11, 13, 32, 33].contains(error.osError?.errorCode);
      await handle?.close();
      _held.remove(path);
      if (!locked) rethrow;
      return null;
    }
  }
}

class _FileLease implements OcrJobLease {
  _FileLease(this.handle, this.onRelease);
  final RandomAccessFile handle;
  final void Function() onRelease;
  @override
  Future<void> release() async {
    try {
      await handle.close();
    } finally {
      onRelease();
    }
  }
}
