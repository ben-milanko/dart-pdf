import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

/// Web stub for [PdfFileByteSource]: the browser has no `dart:io` filesystem,
/// so progressive open-by-path never runs there (web picks hand back bytes, not
/// a path). Present only so `pdf_file_source.dart` compiles for web; every
/// method throws [UnsupportedError] if something constructs and uses it anyway.
class PdfFileByteSource implements PdfByteSource {
  PdfFileByteSource(
    this.path, {
    this.cancelToken,
    this.onProgress,
  });

  final String path;
  final PdfCancelToken? cancelToken;
  final void Function(int received, int? total)? onProgress;

  Never _unsupported() =>
      throw UnsupportedError('PdfFileByteSource is not available on the web');

  @override
  Future<int?> get length async => _unsupported();

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async =>
      _unsupported();

  @override
  Future<void> close() async {}
}
