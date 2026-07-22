/// Render-path diagnostic trace for the viewer.
///
/// UNSTABLE diagnostics surface with **no semver guarantee** - deliberately
/// not exported from `package:dart_pdf_editor/dart_pdf_editor.dart`, mirroring
/// `package:pdf_cos/perf.dart`.
///
/// Kept a separate entry point so a host can flip the trace on (and install a
/// [PdfPerfLog.sink]) from code that must stay out of the editor's own loading
/// unit - the app's `main.dart` runs before its deferred `app.dart` split, and
/// importing the package entry there would pull the whole editor stack into
/// the initial web download.
library;

export 'src/perf_log.dart';
