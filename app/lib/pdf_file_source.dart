// The local-file [PdfByteSource] (`PdfFileByteSource`), backed by a real
// `RandomAccessFile` on native targets and a throwing stub on the web (no
// `dart:io` there). A conditional import keeps `file_io.dart` and the app open
// path compiling for every platform while only native builds pull in the real
// filesystem implementation. See `pdf_file_source_io.dart` for the contract.
export 'pdf_file_source_stub.dart'
    if (dart.library.io) 'pdf_file_source_io.dart';
