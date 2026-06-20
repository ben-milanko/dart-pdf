/// Web-only entry for the Web Worker render backend.
///
/// A consuming web app's worker script imports this library and calls
/// [runPdfRenderWorker] from its `main()`. Do NOT import this from the main
/// app — it pulls in `dart:js_interop` / `package:web` and is meant to be
/// compiled as a standalone worker script. The main app only needs to set
/// `pdfRenderWorkerScriptUrl` (from the normal `dart_pdf_editor.dart` export).
///
/// See `doc/render_worker_web.md` for the build wiring.
library;

export 'src/render_worker_web_entry.dart' show runPdfRenderWorker;
