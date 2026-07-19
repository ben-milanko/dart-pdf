// Writes the deterministic synthetic wide-strip CAD PDF (the "iPad janky pan"
// shape - one ~8504 x 842 pt page, ~850k paint commands in several /Contents
// streams) to a file, for the perf harness. The drawing itself lives in
// `buildSyntheticCadStrip` (package:pdf_test_fixtures), shared with the
// region-replay exercise test so the perf doc and the test doc are the same
// bytes.
//
//   fvm dart run packages/pdf_test_fixtures/tool/gen_cad_wide_pdf.dart \
//       <out.pdf> [ops] [streams] [seed]
//
// Defaults: ~850k primitives across 8 streams, matching the real file's
// ~850k-command transcript. FlateDecode-compressed, no timestamps -
// reproducible byte-for-byte across machines and weeks.
import 'dart:io';

import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'perf_cad_wide.pdf';
  final ops = args.length > 1 ? int.parse(args[1]) : 850000;
  final streams = args.length > 2 ? int.parse(args[2]) : 8;
  final seed = args.length > 3 ? int.parse(args[3]) : 20260718;

  final bytes = buildSyntheticCadStrip(ops: ops, streams: streams, seed: seed);
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  stderr.writeln('wrote $outPath: 1 page 8504x842pt, $ops primitives across '
      '$streams streams, ${(bytes.length / (1 << 20)).toStringAsFixed(1)} MB, '
      'seed $seed');
}
