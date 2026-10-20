// Regenerates the reading-view reflow evaluation corpus into
// test_corpora/reflow/: one PDF per document class plus the ground truth the
// generator recorded while drawing it.
//
// The committed bytes are the measurement contract, exactly like
// test_corpora/dartpdf - everything is deterministic (fixed prose, fixed
// layout arithmetic, no timestamps), so regenerating without a deliberate
// corpus change produces no diff. Regenerate on purpose and review the diff
// like a baseline update; then re-run tool/reflow_eval.dart --update-baseline,
// because new truth means new scores.
//
//   cd packages/pdf_graphics
//   fvm dart run tool/gen_reflow_corpus.dart
//   fvm dart run tool/gen_reflow_corpus.dart --out ../../test_corpora/reflow
import 'dart:convert';
import 'dart:io';

import 'reflow/corpus.dart';

void main(List<String> argv) {
  var out = '../../test_corpora/reflow';
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] == '--out' && i + 1 < argv.length) out = argv[i + 1];
  }
  final directory = Directory(out)..createSync(recursive: true);

  final encoder = const JsonEncoder.withIndent('  ');
  final index = <Map<String, Object?>>[];
  for (final doc in buildReflowCorpus()) {
    File('${directory.path}/${doc.name}.pdf').writeAsBytesSync(doc.bytes);
    File('${directory.path}/${doc.name}.truth.json')
        .writeAsStringSync('${encoder.convert(doc.truth.toJson())}\n');
    final truth = doc.truth;
    index.add({
      'name': doc.name,
      'description': truth.description,
      'pages': truth.pageCount,
      'readableBlocks': truth.readableBlocks.length,
      'artifacts': truth.artifacts.length,
      'figures': truth.figures.length,
      'bytes': doc.bytes.length,
    });
    stdout.writeln('${doc.name.padRight(22)} '
        '${truth.pageCount} pages, '
        '${truth.readableBlocks.length} blocks, '
        '${truth.artifacts.length} artifacts, '
        '${truth.figures.length} figures, '
        '${doc.bytes.length} bytes');
  }
  File('${directory.path}/index.json')
      .writeAsStringSync('${encoder.convert(index)}\n');
  stdout.writeln('\nwrote ${index.length} documents to ${directory.path}');
}
