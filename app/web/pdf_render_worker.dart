// Dedicated Web Worker entry that backs the off-thread page render worker.
//
// This is NOT compiled by Flutter — `web/` Dart files are not auto-built.
// Compile it to a standalone worker bundle with:
//
//   dart compile js web/pdf_render_worker.dart -o web/pdf_render_worker.dart.js -O2
//
// (see tool/build_web.sh), and the app sets
// `pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js'` before opening a
// viewer. See doc/render_worker_web.md.
import 'package:dart_pdf_editor/render_worker_web.dart';

void main() => runPdfRenderWorker();
