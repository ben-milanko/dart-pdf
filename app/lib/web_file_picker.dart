import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:web/web.dart' as web;

/// Web file picker that reads each chosen file's bytes straight from the
/// browser [web.File] with `File.arrayBuffer()` ([PickedWebFile]).
///
/// It deliberately bypasses `file_selector_web`, whose picked XFiles are
/// blob-URL-only (`XFile(URL.createObjectURL(file))`). Their [XFile.readAsBytes]
/// re-hydrates the blob by firing an `XMLHttpRequest` at that `blob:` URL, and
/// that request never completes under the cross-origin isolation (COOP +
/// COEP `credentialless`) the deployed site sets for SharedArrayBuffer - so
/// opening a picked PDF - and later a signing key/certificate - hung forever
/// on app.dart-pdf.com. Reading the [web.File] directly touches only the
/// browser's file handle, which works under isolation, so [XFile.readAsBytes]
/// never hits the XHR path. See doc/dev-log/2026-07-19-web-pick-coep-hang.md.
///
/// The picker completes as soon as the files are chosen; the bytes are read
/// when a caller asks for them. A file on a cloud-synced or network folder
/// can take many seconds to read, and reading it here left the app showing
/// nothing between the picker closing and the document opening.
Future<List<XFile>> pickInMemoryFilesWeb({
  required String accept,
  required String fallbackMimeType,
  bool multiple = true,
}) {
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = accept
    ..multiple = multiple;
  // A detached input can misfire in some browsers; keep it out of layout but in
  // the document, and remove it once we have an answer.
  input.style.display = 'none';
  web.document.body?.appendChild(input);

  final completer = Completer<List<XFile>>();
  void finish(List<XFile> files) {
    if (completer.isCompleted) return;
    input.remove();
    completer.complete(files);
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final fileList = input.files;
      if (fileList == null || fileList.length == 0) {
        finish(const <XFile>[]);
        return;
      }
      finish([
        for (var i = 0; i < fileList.length; i++)
          if (fileList.item(i) case final file?)
            PickedWebFile(file, fallbackMimeType: fallbackMimeType),
      ]);
    }.toJS,
  );

  // Fired when the dialog is dismissed with no selection (Chromium/Firefox);
  // browsers without it just leave the picker resolved only on a real pick.
  input.addEventListener(
      'cancel',
      (web.Event _) {
        finish(const <XFile>[]);
      }.toJS);

  input.click();
  return completer.future;
}

Future<XFile?> pickInMemoryFileWeb({
  required String accept,
  required String fallbackMimeType,
}) async {
  final files = await pickInMemoryFilesWeb(
    accept: accept,
    fallbackMimeType: fallbackMimeType,
    multiple: false,
  );
  return files.isEmpty ? null : files.first;
}

Future<List<XFile>> pickPdfFilesWeb({bool multiple = true}) =>
    pickInMemoryFilesWeb(
      accept: '.pdf,application/pdf',
      fallbackMimeType: 'application/pdf',
      multiple: multiple,
    );

/// Single-file variant: the first pick, or null when cancelled.
Future<XFile?> pickPdfFileWeb() => pickInMemoryFileWeb(
      accept: '.pdf,application/pdf',
      fallbackMimeType: 'application/pdf',
    );

/// An [XFile] over a browser [web.File] that reads its bytes only on demand,
/// with `File.arrayBuffer()` (never a `blob:` URL XHR, which hangs under the
/// deployed site's cross-origin isolation). [name], [mimeType] and [length]
/// come from the file's metadata, so a caller can label and size it without
/// reading it. The bytes are read once and kept, so repeat reads are free.
class PickedWebFile extends XFile {
  PickedWebFile(this._file, {required String fallbackMimeType})
      : _mimeType = _file.type.isEmpty ? fallbackMimeType : _file.type,
        super(_file.name);

  final web.File _file;
  final String _mimeType;
  Future<Uint8List>? _bytes;

  @override
  String get name => _file.name;

  @override
  String? get mimeType => _mimeType;

  @override
  Future<int> length() async => _file.size;

  @override
  Future<DateTime> lastModified() async =>
      DateTime.fromMillisecondsSinceEpoch(_file.lastModified);

  @override
  Future<Uint8List> readAsBytes() => _bytes ??= _file.arrayBuffer().toDart.then(
        (buffer) => buffer.toDart.asUint8List(),
        // A failed read stays retryable rather than cached.
        onError: (Object error, StackTrace stack) {
          _bytes = null;
          return Future<Uint8List>.error(error, stack);
        },
      );

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final bytes = await readAsBytes();
    yield Uint8List.sublistView(bytes, start ?? 0, end ?? bytes.length);
  }
}
