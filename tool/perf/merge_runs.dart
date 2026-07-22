// Merges an NDJSON of same-scenario envelopes into one envelope whose
// per-file timings are the best (minimum) across all runs - the ABAB
// aggregation step of tool/perf/perf_diff.sh. Standalone Dart (no package
// imports). Reads the file named in argv[0], writes the merged envelope to
// stdout.
import 'dart:convert';
import 'dart:io';

void main(List<String> argv) {
  if (argv.length != 1) {
    stderr.writeln('usage: merge_runs.dart <history.ndjson>');
    exit(2);
  }
  final envelopes = File(argv[0])
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, Object?>)
      .toList();
  if (envelopes.isEmpty) {
    stderr.writeln('${argv[0]} holds no envelopes');
    exit(1);
  }

  const timeKeys = [
    'openMs',
    'firstPageMs',
    'interpretMs',
    'renderMs',
    'extractMs',
    'saveMs',
    'peakRssBytes',
  ];
  final merged = <String, Map<String, Object?>>{};
  for (final envelope in envelopes) {
    for (final r in (envelope['results'] as List? ?? []).cast<Map>()) {
      final file = r['file'] as String;
      final prev = merged[file];
      if (prev == null) {
        merged[file] = Map<String, Object?>.from(r);
        continue;
      }
      // An errored run never overrides a clean one.
      if (r['error'] != null) continue;
      if (prev['error'] != null) {
        merged[file] = Map<String, Object?>.from(r);
        continue;
      }
      for (final key in timeKeys) {
        final a = prev[key], b = r[key];
        if (a is num && b is num && b < a) prev[key] = b;
      }
    }
  }

  final out = Map<String, Object?>.from(envelopes.last);
  out['results'] = merged.values.toList();
  out['params'] = {
    ...?(out['params'] as Map?)?.cast<String, Object?>(),
    'mergedRuns': envelopes.length,
  };
  stdout.writeln(jsonEncode(out));
}
