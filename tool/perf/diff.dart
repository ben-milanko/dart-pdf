// Noise-aware comparison of two perf envelopes (tool/perf/SCHEMA.md).
// Standalone Dart - no package imports - so it runs from anywhere:
//
//   dart tool/perf/diff.dart baseline.json current.json [--threshold 1.10]
//       [--md] [--metric interpretMs,...] [--targets tool/perf/targets.json]
//
// Inputs may be envelope .json files or .ndjson history files (the last
// line wins; --scenario filters ndjson lines first). Results are paired by
// `file`; per metric the verdict uses the MEDIAN ratio (current/baseline)
// across files, with MAD-based outlier exclusion - a single noisy file is
// listed but cannot fail the run. Exit 1 on regression (median ratio worse
// than --threshold on any compared metric) so it can gate scripts/CI.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _defaultMetrics = [
  'openMs',
  'firstPageMs',
  'interpretMs',
  'extractMs',
  'saveMs',
  'peakRssBytes',
];

Map<String, Object?> _loadEnvelope(String path, String? scenario) {
  final text = File(path).readAsStringSync().trim();
  if (path.endsWith('.ndjson')) {
    final lines = text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => jsonDecode(l) as Map<String, Object?>)
        .where((e) => scenario == null || e['scenario'] == scenario)
        .toList();
    if (lines.isEmpty) {
      stderr.writeln('$path holds no envelopes'
          '${scenario == null ? '' : ' for scenario $scenario'}');
      exit(2);
    }
    return lines.last;
  }
  return jsonDecode(text) as Map<String, Object?>;
}

double _median(List<double> v) {
  final s = List<double>.of(v)..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

void main(List<String> argv) {
  final paths = <String>[];
  var threshold = 1.10;
  var md = false;
  String? targetsPath;
  String? scenario;
  var metrics = _defaultMetrics;
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    String next() => argv[++i];
    switch (arg) {
      case '--threshold':
        threshold = double.parse(next());
      case '--md':
        md = true;
      case '--targets':
        targetsPath = next();
      case '--scenario':
        scenario = next();
      case '--metric' || '--metrics':
        metrics = next().split(',');
      default:
        if (arg.startsWith('--')) {
          stderr.writeln('unknown flag $arg');
          exit(2);
        }
        paths.add(arg);
    }
  }
  if (paths.length != 2) {
    stderr.writeln('usage: diff.dart <baseline> <current> '
        '[--threshold R] [--md] [--scenario S] [--targets targets.json]');
    exit(2);
  }

  final base = _loadEnvelope(paths[0], scenario);
  final cur = _loadEnvelope(paths[1], scenario);
  final baseByFile = {
    for (final r in (base['results'] as List? ?? []))
      (r as Map)['file'] as String: r,
  };
  final curResults = (cur['results'] as List? ?? []).cast<Map>();

  final rows = <String>[];
  var regressed = false;
  final sb = StringBuffer();
  if (md) {
    sb.writeln('| metric | files | median ratio | verdict | outliers |');
    sb.writeln('|---|---|---|---|---|');
  }

  for (final metric in metrics) {
    final ratios = <String, double>{};
    for (final r in curResults) {
      final b = baseByFile[r['file']];
      if (b == null) continue;
      if (r['error'] != null || b['error'] != null) continue;
      final cv = r[metric], bv = b[metric];
      if (cv is! num || bv is! num || bv <= 0) continue;
      ratios[r['file'] as String] = cv / bv;
    }
    if (ratios.isEmpty) continue;

    final all = ratios.values.toList();
    final med = _median(all);
    final mad = _median([for (final v in all) (v - med).abs()]);
    // 3-MAD outliers are reported, never counted toward the verdict.
    final cut = 3 * math.max(mad, 0.01);
    final outliers = [
      for (final e in ratios.entries)
        if ((e.value - med).abs() > cut)
          '${e.key} (${e.value.toStringAsFixed(2)}x)',
    ];
    final inliers = [
      for (final v in all)
        if ((v - med).abs() <= cut) v,
    ];
    final verdictRatio = _median(inliers);
    final bad = verdictRatio > threshold;
    if (bad) regressed = true;
    final verdict = bad
        ? 'REGRESSED'
        : verdictRatio < 1 / threshold
            ? 'improved'
            : 'ok';
    if (md) {
      sb.writeln('| $metric | ${ratios.length} | '
          '${verdictRatio.toStringAsFixed(3)}x | $verdict | '
          '${outliers.isEmpty ? '-' : outliers.join('; ')} |');
    } else {
      rows.add('$metric: ${verdictRatio.toStringAsFixed(3)}x over '
          '${ratios.length} files -> $verdict'
          '${outliers.isEmpty ? '' : '  [outliers: ${outliers.join('; ')}]'}');
    }
  }

  if (md) {
    stdout.write(sb);
  } else {
    if (rows.isEmpty) {
      stderr.writeln('no comparable metrics between the two runs');
      exit(2);
    }
    rows.forEach(stdout.writeln);
  }

  // Aspirational targets: informational red/green, never affects exit code.
  if (targetsPath != null) {
    final targets =
        jsonDecode(File(targetsPath).readAsStringSync()) as Map<String, Object?>;
    final scenarioTargets = targets[cur['scenario']];
    if (scenarioTargets is Map) {
      final m = (cur['metrics'] as Map?) ?? {};
      stdout.writeln('targets (${cur['scenario']}):');
      scenarioTargets.forEach((key, budget) {
        final value = m[key];
        final max = (budget as Map)['max'] as num?;
        if (value is num && max != null) {
          final ok = value <= max;
          stdout.writeln('  ${ok ? 'PASS' : 'MISS'} $key: '
              '$value vs budget $max');
        }
      });
    }
  }

  stdout.writeln(regressed
      ? 'VERDICT: REGRESSED (median ratio > ${threshold.toStringAsFixed(2)}x)'
      : 'VERDICT: OK');
  exit(regressed ? 1 : 0);
}
