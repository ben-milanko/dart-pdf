import 'package:flutter/widgets.dart';

import 'render_worker.dart';

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
    SizedBox.shrink(key: key);
