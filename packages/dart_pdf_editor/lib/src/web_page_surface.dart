import 'package:flutter/widgets.dart';

import 'render_worker.dart';
import 'web_page_surface_stub.dart'
    if (dart.library.js_interop) 'web_page_surface_web.dart' as implementation;

/// Builds the experimental web-only DOM canvas painted directly by a render
/// worker, outside Flutter's SkWasm surface.
///
/// The caller gates this behind [PdfPageView.webDomRasterPresentation]. The
/// stub is deliberately empty on non-web platforms, so enabling the benchmark
/// switch can never alter native rendering.
Widget pdfWebPageSurface({
  required Key key,
  required PdfRenderWorker worker,
  required int pageIndex,
  required bool annotations,
  required int width,
  required int height,
  required int pageColor,
  PdfPageSurfaceRegion? region,
  required int? rotation,
  required int priority,
  required VoidCallback onReady,
  required VoidCallback onDeclined,
}) =>
    implementation.pdfWebPageSurface(
      key: key,
      worker: worker,
      pageIndex: pageIndex,
      annotations: annotations,
      width: width,
      height: height,
      pageColor: pageColor,
      region: region,
      rotation: rotation,
      priority: priority,
      onReady: onReady,
      onDeclined: onDeclined,
    );
