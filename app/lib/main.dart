import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'app_info.dart';

/// On Windows and Linux the OS launches the app with the opened file as a
/// command-line argument; the Flutter runner forwards it here.
Future<void> main(List<String> args) async {
  // PackageInfo (loaded below) needs the binding; ensure it before awaiting.
  WidgetsFlutterBinding.ensureInitialized();

  // On web, point the render worker at its compiled script so page
  // interpretation runs in a dedicated Web Worker (built by tool/build_web.sh;
  // see doc/render_worker_web.md). Ignored on native, where the background
  // isolate needs no script. With no compiled script present the worker simply
  // degrades to local rendering, so this is safe even before a worker build.
  if (kIsWeb) {
    pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';
  }

  // Resolve the About-box version from the build artifact so it tracks the
  // pubspec version automatically. Best-effort; never blocks startup on error.
  await AppInfo.load();

  runApp(DartPdfEditorApp(launchArgs: args));
}
