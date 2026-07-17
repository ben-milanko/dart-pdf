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
///  2. **Vector page** (`beginJob` reporting `vector: true`, then
///     `printPageVector` per page): Windows and Linux have no native PDF-print
///     API - that is exactly why the old `printing` plugin bundled PDFium,
///     which crashed on our broken-but-renderable inputs. Instead of handing
///     the OS a whole PDF it can't print, we lower each page with our own
///     engine to a compact vector op stream ([encodePageForVectorPrinting])
///     that the runner replays onto its printer DC (GDI) / Cairo context.
///     Text stays selectable (substituted fonts) or crisply outlined (embedded
///     fonts) and graphics stay vector - no full-page bitmaps.
///  3. **Raster** (`beginJob`/`printPage`/`endJob`): the fallback for a runner
///     that has no vector support (an older build that omits `vector: true`).
///     Each page is rendered by our engine and streamed as a JPEG.
///
/// The Windows/Linux path chooses vector vs raster from what `beginJob`
/// reports, so one print-dialog / job covers both and an old runner that never
/// sets `vector` keeps rasterising unchanged.
///
/// [onProgress] is called `(rendered, total)` after each page on both the
/// vector-page and raster desktop paths (the whole-PDF `printPdf` path has
/// nothing to render, so it never reports progress). [channel] is a test seam.
Future<void> printDocumentPages(
  Uint8List pdfBytes, {
  required String name,
  MethodChannel channel = _channel,
  void Function(int rendered, int total)? onProgress,
}) async {
  // 1. Native vector printing. A MissingPluginException means this platform
  //    has no `printPdf` (Windows/Linux) - fall through to the desktop path.
  try {
    await channel.invokeMethod<bool>('printPdf', <String, dynamic>{
      'name': name,
      'pdf': pdfBytes,
    });
    return; // printed as vector (or the user cancelled) - done
  } on MissingPluginException {
    // no native PDF printing here; drive the OS print system per page below
  }

  // 2/3. Desktop path. A MissingPluginException from beginJob means there is
  //      no native printer at all, and propagates to the caller. The runner
  //      reports whether it can replay our vector op stream; when it can we
  //      print vector, otherwise we rasterise. One job either way.
  final document = PdfDocument.open(pdfBytes);
  final info = await channel.invokeMapMethod<String, dynamic>(
    'beginJob',
    <String, dynamic>{'name': name},
  );
  final vector = info?['vector'] == true;
  final dpi = _resolveDpi(info);
  try {
    for (var i = 0; i < document.pageCount; i++) {
      // Lowering (or JPEG-encoding) a page is heavy CPU on the UI isolate.
      // Yield first so the engine can service input and paint a frame between
      // pages - otherwise a large document's print holds the isolate long
      // enough to make the app unresponsive.
      await Future<void>.delayed(Duration.zero);
      final bool? ok;
      if (vector) {
        final stream = await encodePageForVectorPrinting(document.page(i));
        ok = await channel.invokeMethod<bool>(
          'printPageVector',
          <String, dynamic>{'page': stream},
        );
      } else {
        final jpeg = await PdfPageExport.exportPage(
          document.page(i),
          format: PdfRasterFormat.jpeg,
          dpi: dpi.toDouble(),
          jpegQuality: 85,
        );
        ok = await channel.invokeMethod<bool>(
          'printPage',
          <String, dynamic>{'image': jpeg},
        );
      }
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
