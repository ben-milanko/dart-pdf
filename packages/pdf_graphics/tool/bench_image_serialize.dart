// #451: where does a render-record serialize actually spend its time?
//
// The device traces showed a 5.3 MB record serialising in 1817 ms while a
// 39 MB one took 329 ms in the same worker - so the cost is not the payload.
// This reproduces that on the VM by running the record path's exact call
// (`serializeCommands(cos:, decodeImages: true, maxImagePixelRatio: 2.0)`)
// over a corpus and reporting, per page, the serialize time split into the
// image half and the command-encode half.
//
//   fvm dart tool/bench_image_serialize.dart [dir-or-file ...]
//
// Defaults to the checked-in test corpora. `--json` emits machine-readable
// rows so an A/B can diff two revisions; `--runs=N` takes the best of N.
import 'dart:convert';
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _ratio = 2.0;

void main(List<String> args) {
  final json = args.contains('--json');
  final runs = int.tryParse(
          args.firstWhere((a) => a.startsWith('--runs='), orElse: () => '')
              .replaceFirst('--runs=', '')) ??
      1;
  final paths = args.where((a) => !a.startsWith('--')).toList();
  final files = _collect(paths.isEmpty
      ? const ['../../test_corpora/ghent', '../../test_corpora/pdfjs']
      : paths);
  if (files.isEmpty) {
    stderr.writeln('no PDFs found');
    exit(1);
  }

  final rows = <Map<String, Object?>>[];
  for (final file in files) {
    final PdfDocument doc;
    final int pageCount;
    try {
      doc = PdfDocument.open(file.readAsBytesSync());
      pageCount = doc.pageCount;
    } catch (_) {
      continue;
    }
    for (var i = 0; i < pageCount; i++) {
      try {
        final row = _measurePage(file.path, doc, i, runs);
        if (row != null) rows.add(row);
      } catch (_) {
        // A page that cannot be interpreted is not this benchmark's concern.
      }
    }
  }

  rows.sort((a, b) => (b['imageMs'] as num).compareTo(a['imageMs'] as num));
  if (json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(rows));
    return;
  }

  stdout.writeln('Image cost inside serialize at ratio $_ratio '
      '(${rows.length} pages, best of $runs)\n');
  stdout.writeln('  imageMs  encodeMs   cmds   imgs     outMB   srcMpx  page');
  for (final r in rows.take(25)) {
    stdout.writeln('  ${_pad(r['imageMs'], 7)}  ${_pad(r['encodeMs'], 8)}  '
        '${_pad(r['commands'], 5)}  ${_pad(r['images'], 4)}  '
        '${_pad(r['outMB'], 8)}  ${_pad(r['sourceMpx'], 7)}  ${r['page']}');
  }
  final totalImage = rows.fold<double>(0, (s, r) => s + (r['imageMs'] as num));
  final totalEncode = rows.fold<double>(0, (s, r) => s + (r['encodeMs'] as num));
  final withImages = rows.where((r) => (r['images'] as int) > 0).length;
  stdout.writeln('\n$withImages/${rows.length} pages draw images; '
      'total image=${totalImage.toStringAsFixed(0)}ms '
      'encode=${totalEncode.toStringAsFixed(0)}ms');
}

Map<String, Object?>? _measurePage(
    String path, PdfDocument doc, int index, int runs) {
  final page = doc.page(index);
  final cos = doc.cos;
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: cos, device: recorder)
    ..drawPage(page)
    ..drawAnnotations(page);
  final commands = recorder.commands;

  // Warm whatever the real worker would already have warm (fonts, parsed ICC
  // profiles, the stream cache) so the first page of a file is not charged for
  // it, and confirm the page serializes at all.
  if (serializeCommands(commands,
          cos: cos, decodeImages: true, maxImagePixelRatio: _ratio) ==
      null) {
    return null;
  }

  var encodeUs = -1, totalUs = -1;
  var bytes = 0;
  for (var run = 0; run < runs; run++) {
    final encodeSw = Stopwatch()..start();
    serializeCommands(commands, cos: cos, decodeImages: false);
    encodeSw.stop();

    final sw = Stopwatch()..start();
    final buf = serializeCommands(commands,
        cos: cos, decodeImages: true, maxImagePixelRatio: _ratio);
    sw.stop();
    if (buf == null) return null;
    bytes = buf.length;
    if (encodeUs < 0 || encodeSw.elapsedMicroseconds < encodeUs) {
      encodeUs = encodeSw.elapsedMicroseconds;
    }
    if (totalUs < 0 || sw.elapsedMicroseconds < totalUs) {
      totalUs = sw.elapsedMicroseconds;
    }
  }

  return <String, Object?>{
    'page': '${path.split('/').last} p$index',
    'imageMs': _round((totalUs - encodeUs) / 1000),
    'encodeMs': _round(encodeUs / 1000),
    'commands': commands.length,
    'images': recorder.imageRequests.length,
    'outMB': _round(bytes / (1 << 20)),
    'sourceMpx': _round(_sourceMpx(recorder.imageRequests, cos)),
  };
}

/// Total declared source pixels of every image the page draws - the quantity
/// the heavy colour-conversion path scales with (as opposed to output bytes).
double _sourceMpx(List<PdfImageRequest> requests, CosDocument cos) {
  var pixels = 0.0;
  for (final request in requests) {
    final dict = request.stream.dictionary;
    final w = cos.resolve(dict['Width']);
    final h = cos.resolve(dict['Height']);
    if (w is CosInteger && h is CosInteger) pixels += w.value * h.value;
  }
  return pixels / 1e6;
}

List<File> _collect(List<String> paths) {
  final out = <File>[];
  for (final p in paths) {
    final dir = Directory(p);
    if (dir.existsSync()) {
      out.addAll(dir.listSync(recursive: true).whereType<File>().where((f) =>
          f.path.toLowerCase().endsWith('.pdf') && !f.path.contains('/_')));
      continue;
    }
    final file = File(p);
    if (file.existsSync()) out.add(file);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

double _round(double v) => double.parse(v.toStringAsFixed(2));

String _pad(Object? v, int width) => v.toString().padLeft(width);
