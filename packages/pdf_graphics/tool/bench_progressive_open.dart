// Measures the progressive-open win (#328/#359): how many BYTES the reader must
// pull to paint the first page when it opens through the ranged PdfByteSource
// (PdfDocument.openSource) versus reading the whole file first. On a large doc
// over a slow/remote source, first paint is bounded by the header + xref +
// page-0 objects, not the full download.
//
//   cd packages/pdf_graphics
//   fvm dart run tool/bench_progressive_open.dart <doc.pdf> [repeat]
//
// PdfByteSource / openSource are 2.0.0-era APIs, so this is a HEAD/2.0.0+
// benchmark (no backfill). Emits one `progressive-open` envelope; the metrics
// are the progressive vs full bytes-to-first-page and the fraction.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'perf_run_context.dart';

/// Swallows device calls; the interpreter still loads + parses page 0's content
/// and resources, which is what forces the progressive source to fetch the
/// bytes a first paint needs.
class _NullDevice implements PdfDevice {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Counts the bytes pulled through the ranged API.
class _CountingSource implements PdfByteSource {
  _CountingSource(this._bytes);
  final Uint8List _bytes;
  int bytesRead = 0;
  int reads = 0;

  @override
  Future<int?> get length async => _bytes.length;

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    final s = start < 0 ? 0 : (start > _bytes.length ? _bytes.length : start);
    final e = endExclusive < s
        ? s
        : (endExclusive > _bytes.length ? _bytes.length : endExclusive);
    bytesRead += e - s;
    reads++;
    return Uint8List.sublistView(_bytes, s, e);
  }

  @override
  Future<void> close() async {}
}

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? args[0]
      : '../../tool/perf/cache/cad-138-6000-20260718.pdf';
  final repeat = args.length > 1 ? int.parse(args[1]) : 3;
  final scenario = Platform.environment['PDF_PROGRESSIVE_SCENARIO'];
  final appendPath = Platform.environment['PDF_PROGRESSIVE_APPEND_HISTORY'];
  final outPath = Platform.environment['PDF_PROGRESSIVE_OUT'];

  final bytes = File(path).readAsBytesSync();

  var bestProgMs = double.infinity, bestFullMs = double.infinity;
  var progBytes = 0;
  for (var r = 0; r < repeat; r++) {
    // Progressive first-paint: open through the ranged source loading only the
    // first page's objects (firstPaintPages: 1), then rasterize-interpret page
    // 0 off the bytes that pulled in. bytesRead is the I/O a remote reader
    // needs to show page 1 - the #328/#359 win.
    final src = _CountingSource(bytes);
    final sw = Stopwatch()..start();
    final doc = await PdfDocument.openSource(
      src,
      options: const PdfSourceLoadOptions(firstPaintPages: 1),
    );
    PdfInterpreter(cos: doc.cos, device: _NullDevice()).drawPage(doc.page(0));
    final progMs = sw.elapsedMicroseconds / 1000;
    progBytes = src.bytesRead;

    // The pre-progressive path: the whole file must be in hand before page 0.
    final fullSrc = _CountingSource(bytes);
    final sw2 = Stopwatch()..start();
    final doc2 = await PdfDocument.openSource(fullSrc); // default = full fetch
    PdfInterpreter(cos: doc2.cos, device: _NullDevice()).drawPage(doc2.page(0));
    final fullMs = sw2.elapsedMicroseconds / 1000;

    if (progMs < bestProgMs) bestProgMs = progMs;
    if (fullMs < bestFullMs) bestFullMs = fullMs;
  }

  double round(double v) => double.parse(v.toStringAsFixed(3));
  final fraction = bytes.isEmpty ? 0.0 : progBytes / bytes.length * 100;
  final metrics = {
    'firstPageBytesProgressive': progBytes,
    'firstPageBytesFull': bytes.length,
    'firstPageBytesFractionPct': round(fraction),
    'p50FirstPageMsProgressive': round(bestProgMs),
    'p50FirstPageMsFull': round(bestFullMs),
  };
  final payload = {
    'schema': 1,
    'suite': 'progressive-open',
    'scenario': scenario,
    'metrics': metrics,
    'rev': revInfo(Directory.current.parent.parent.path),
    'env': envInfo(),
    'ts': DateTime.now().toUtc().toIso8601String(),
    'tool': 'dart-pdf-progressive',
    'engine': 'PdfDocument.openSource vs open',
    'results': [
      {'file': path.split('/').last, ...metrics},
    ],
  };
  final text = const JsonEncoder.withIndent('  ').convert(payload);
  if (outPath != null) {
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    stdout.writeln('wrote $outPath');
  } else {
    stdout.writeln(text);
  }
  if (appendPath != null) {
    File(appendPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('${jsonEncode(payload)}\n', mode: FileMode.append);
    stdout.writeln('appended to $appendPath');
  }
  stdout.writeln('first-page bytes: progressive=$progBytes / '
      'full=${bytes.length} (${round(fraction)}%)');
}
