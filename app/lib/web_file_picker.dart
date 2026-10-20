import 'dart:async';
import 'dart:js_interop';

import 'package:file_selector/file_selector.dart';
import 'package:web/web.dart' as web;

/// Web file picker that reads each chosen file's bytes straight from the
/// browser [web.File] with `File.arrayBuffer()`, returning in-memory [XFile]s
/// built via [XFile.fromData].
///
/// It deliberately bypasses `file_selector_web`, whose picked XFiles are
/// blob-URL-only (`XFile(URL.createObjectURL(file))`). Their [XFile.readAsBytes]
/// re-hydrates the blob by firing an `XMLHttpRequest` at that `blob:` URL, and
/// that request never completes under the cross-origin isolation (COOP +
/// COEP `credentialless`) the deployed site sets for SharedArrayBuffer - so
/// opening a picked PDF - and later a signing key/certificate - hung forever
/// on app.dart-pdf.com. Reading the [web.File] directly touches only the
/// in-memory blob, which works under isolation, and [XFile.fromData] keeps
/// those bytes so a later [XFile.readAsBytes] never hits the XHR path. See
/// doc/dev-log/2026-07-19-web-pick-coep-hang.md.
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
      // Read every picked file's bytes before completing so the returned XFiles
      // are fully in-memory (no lazy blob-URL fetch downstream).
      () async {
        try {
          final out = <XFile>[];
          for (var i = 0; i < fileList.length; i++) {
            final file = fileList.item(i);
            if (file == null) continue;
            final buffer = (await file.arrayBuffer().toDart).toDart;
            final bytes = buffer.asUint8List();
            out.add(XFile.fromData(
              bytes,
              name: file.name,
              mimeType: file.type.isEmpty ? fallbackMimeType : file.type,
              length: bytes.length,
            ));
          }
          finish(out);
        } catch (error) {
          if (!completer.isCompleted) {
            input.remove();
            completer.completeError(error);
          }
        }
      }();
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
