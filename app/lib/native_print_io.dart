import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';

/// The platform channel every native runner registers to print without a PDF
/// rasteriser (see `windows/runner/native_print.cpp`, the macOS/iOS Swift
/// handlers, the Android handler, and the Linux runner).
const MethodChannel _channel = MethodChannel('dev.milanko.dartpdf/native_print');

/// Prints [document] through the OS print system on a native platform, without
/// any bundled PDF engine.
///
/// The `printing` plugin used to spool by rendering the PDF through a bundled
/// PDFium, which crashes the process on some of the broken-but-renderable
/// files this engine opens. Here we render every page with our own engine,
/// hand each one to the runner as a JPEG, and let the platform's own print
/// system (GDI on Windows, `NSPrintOperation` on macOS,
/// `UIPrintInteractionController` on iOS, `PrintManager` on Android,
/// `GtkPrintOperation` on Linux) put it on paper. PDFium is gone.
///
/// The protocol is uniform: `beginJob` resets the job and returns a target
/// `dpi`; `printPage` streams one page's JPEG; `endJob` shows the platform's
/// print UI and prints the accumulated pages (returning false if the user
/// cancels). A [MissingPluginException] from `beginJob` means the runner has
/// no native printer; the caller surfaces that as a failure.
///
/// [channel] is a test seam.
Future<void> printDocumentPages(
  PdfDocument document, {
  required String name,
  MethodChannel channel = _channel,
}) async {
  // A MissingPluginException here propagates: the platform has no native
  // printer registered.
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
