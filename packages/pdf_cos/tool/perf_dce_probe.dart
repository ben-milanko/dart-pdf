// Minimal entrypoint for tool/check_perf_dce.sh: builds a document with the
// from-scratch writer and re-opens it, touching the instrumented open/save
// paths the way a regular API user would (including a runtime enable, which
// must be a no-op when the facade is compiled out). The probe deliberately
// never calls PdfPerf.snapshot()/format() - a normal app doesn't, and the
// check asserts the whole recording machinery is tree-shaken with
// -DPDF_PERF=false.
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';

void main() {
  // Attach a sink so the compiled-in build provably retains the marker line
  // (dart2js whole-program analysis would otherwise see a never-assigned
  // sink and eliminate it); with -DPDF_PERF=false the guarded setter body -
  // marker included - must vanish anyway.
  PdfPerf.sink = print;
  PdfPerf.enabled = true;
  final builder = CosDocumentBuilder();
  final pagesRef = builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([]),
    'Count': const CosInteger(0),
  }));
  final rootRef = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
  }));
  final doc = CosDocument.open(builder.build(root: rootRef));
  print('opened PDF ${doc.version}');
}
