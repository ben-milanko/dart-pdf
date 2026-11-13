import 'dart:async';

import 'package:dart_pdf_printing/dart_pdf_printing.dart';

/// Preview renders stay on the test isolate: a real render-worker isolate
/// never completes under the widget-test binding's fake clock.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PrintPreviewDialog.debugRenderWorkerEnabled = false;
  await testMain();
}
