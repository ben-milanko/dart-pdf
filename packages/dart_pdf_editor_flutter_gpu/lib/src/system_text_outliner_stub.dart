import 'package:pdf_graphics/pdf_graphics.dart';

import 'text_outliner.dart';

/// Web stub for the native system-font outline adapter.
class FlutterGpuSystemTextOutliner implements FlutterGpuTextOutliner {
  FlutterGpuSystemTextOutliner._();

  static FlutterGpuSystemTextOutliner? tryCreate() => null;

  @override
  PdfTextRun? outline(PdfTextRun run) => null;
}
