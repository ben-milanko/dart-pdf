/// Web-only entry for the Web Worker render backend.
///
/// dart_pdf_editor already ships a prebuilt worker as a Flutter package asset.
/// Import this only when compiling a custom self-hosted worker script whose
/// `main()` calls [runPdfRenderWorker]. Do NOT import this from the main app -
/// it pulls in `dart:js_interop` / `package:web` and is meant to be compiled as
/// a standalone worker script. Set `pdfRenderWorkerScriptUrl` (from the normal
/// `dart_pdf_editor.dart` export) only when overriding the bundled asset URL.
///
/// See `doc/render_worker_web.md` for the build wiring.
library;

export 'src/render_worker_web_entry.dart' show runPdfRenderWorker;
