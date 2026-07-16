import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';

/// The platform channel every native runner registers (see
/// `windows/runner/native_print.cpp`, the macOS/iOS Swift handlers, the Android
/// handler, and the Linux runner).
const MethodChannel _channel = MethodChannel('dev.milanko.dartpdf/native_print');

/// Prints the PDF [pdfBytes] through the running platform's own print system,
/// without any bundled PDF engine.
///
/// Two strategies, tried in order:
///
///  1. **Vector** (`printPdf`): hand the whole PDF to the OS print system,
///     which renders its vector content directly - CoreGraphics on Apple, the
///     print framework on Android, the browser on web. No rasterising here, so
///     text stays selectable and the output is crisp and small. This is the
///     path on iOS, macOS, Android, and web.
///  2. **Raster** (`beginJob`/`printPage`/`endJob`): Windows and Linux have no
///     native PDF-print API - that is exactly why the old `printing` plugin
///     bundled PDFium, which crashed on our broken-but-renderable inputs. There
///     we render each page with our own engine and stream it as a JPEG. The
///     runner reports `printPdf` unimplemented (a [MissingPluginException]),
///     which drops us onto this path.
///
/// [onProgress] is called `(rendered, total)` after each page in the raster
/// path (the vector path has nothing to render, so it never reports progress).
/// [channel] is a test seam.
Future<void> printDocumentPages(
  Uint8List pdfBytes, {
  required String name,
  MethodChannel channel = _channel,
  void Function(int rendered, int total)? onProgress,
}) async {
  // 1. Native vector printing. A MissingPluginException means this platform
  //    has no `printPdf` (Windows/Linux) - fall through to rasterising.
  try {
    await channel.invokeMethod<bool>('printPdf', <String, dynamic>{
      'name': name,
      'pdf': pdfBytes,
    });
    return; // printed as vector (or the user cancelled) - done
  } on MissingPluginException {
    // no native PDF printing here; rasterise below
  }

  // 2. Raster fallback. A MissingPluginException from beginJob means there is
  //    no native printer at all, and propagates to the caller.
  final document = PdfDocument.open(pdfBytes);
  final info = await channel.invokeMapMethod<String, dynamic>(
    'beginJob',
    <String, dynamic>{'name': name},
  );
  final dpi = _resolveDpi(info);
  try {
    for (var i = 0; i < document.pageCount; i++) {
      // Rendering and JPEG-encoding a page is heavy CPU on the UI isolate (the
      // encode is synchronous). Yield first so the engine can service input and
      // paint a frame between pages - otherwise a large document's print holds
      // the isolate long enough to make the app unresponsive.
      await Future<void>.delayed(Duration.zero);
      final jpeg = await PdfPageExport.exportPage(
        document.page(i),
        format: PdfRasterFormat.jpeg,
        dpi: dpi.toDouble(),
        jpegQuality: 85,
      );
      final ok = await channel.invokeMethod<bool>(
        'printPage',
        <String, dynamic>{'image': jpeg},
      );
      if (ok == false) {
        throw StateError('the printer rejected page ${i + 1}');
      }
      onProgress?.call(i + 1, document.pageCount);
    }
    // endJob returns false when the user cancels the print dialog - that is
    // handled, nothing more to do.
    await channel.invokeMethod<bool>('endJob');
  } catch (error) {
    // Tear down the half-accumulated job so the next print starts clean.
    try {
      await channel.invokeMethod<void>('cancelJob');
    } catch (_) {
      // best effort - the job is being discarded anyway
    }
    if (error is MissingPluginException || error is PlatformException) rethrow;
    throw PlatformException(
      code: 'native_print_failed',
      message: 'native printing failed: $error',
    );
  }
}

/// Target raster resolution from the runner's [info], clamped so an exotic
/// printer can't blow up memory. Defaults to 200 dpi when unspecified.
int _resolveDpi(Map<String, dynamic>? info) {
  final raw = (info?['dpi'] as num?)?.toInt() ?? 200;
  if (raw < 72) return 72;
  if (raw > 300) return 300;
  return raw;
}
