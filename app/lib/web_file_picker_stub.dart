import 'package:file_selector/file_selector.dart';

/// Non-web stub for [pickPdfFilesWeb]/[pickPdfFileWeb]. The picker is only ever
/// routed here on the web (see `file_io.dart`), so these must never be called
/// off-web - `file_selector` handles the native pickers.
Future<List<XFile>> pickPdfFilesWeb({bool multiple = true}) =>
    throw UnsupportedError('pickPdfFilesWeb is web-only');

Future<XFile?> pickPdfFileWeb() =>
    throw UnsupportedError('pickPdfFileWeb is web-only');
