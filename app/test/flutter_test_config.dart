import 'dart:async';

import 'package:dart_pdf_printing/dart_pdf_printing.dart';

/// Keeps the print preview's page renders on the test isolate: its background
/// render worker never completes under the widget-test binding's fake clock,
/// so the preview's progress mark would keep `pumpAndSettle` from settling.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PrintPreviewDialog.debugRenderWorkerEnabled = false;
  await testMain();
}
