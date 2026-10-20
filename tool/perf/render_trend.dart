// Night-over-night trend rule for the nightly flutter-render envelopes
// (tool/perf/SCHEMA.md). A same-runner A/B is too slow for the render suites,
// but consecutive nights on the hosted runner are comparable, so tonight is
// judged against the nights before it. Standalone Dart - no package imports:
//
//   dart tool/perf/render_trend.dart --history prior.ndjson \
//       --current tonight.ndjson [--nights 5] [--threshold 1.4]
//       [--metric renderMs] [--summary <markdown-file>]
//   dart tool/perf/render_trend.dart --replay history.ndjson [--nights 5] ...
//
// Per scenario, each file's baseline is the MEDIAN of its metric over the
// prior N nights, and the verdict is the median of the per-file ratios
// (tonight / baseline): REGRESSED at >= --threshold. In a multi-file suite
// (ghent-render) that damps one noisy file - the worst files are listed, not
// counted - but image-render, devicen-render and jbig2-scanned-render render
// one file each, so that one file's ratio is the verdict (single-file noise
// reached 1.27x in the replay below, against the 1.4x threshold).
//
// A history night at tonight's commit is an earlier measurement of the same
// code - a re-run, a dispatch on the same commit, a night with no new
// commits - so it is left out: tonight is judged against the nights before
// that commit, repeating the comparison instead of reading ~1.0x against
// itself. So a flagged commit stays red on every night until a new commit
// lands, like the nightly ratio check's `recheck`
// (tool/perf/nightly_state.dart), and an ok one takes another sample of the
// same comparison.
//
// A night the rule flags starts a new level: later nights never reach back
// past it. So a step is red on the night it lands and is the baseline from
// then on - the same one-alert-per-step ratchet as the VM ratio check - and
// a long gap in the history costs one red night, not N. Nights are ordered by
// commit date (rev.date, then ts), like the dashboard, so backfilled points
// land where they belong instead of posing as last night.
//
// The price of the reset: the night after a flag is judged against that one
// night alone. If the flag was a noise spike, a real step no bigger than the
// spike that lands in the next night or two reads ~1.0x and is absorbed
// without a flag of its own (a spike that simply recedes is harmless: it
// reads "improved" and drops out of the median as nights accumulate). Nights
// that each look like a step cannot tell a spike-then-step from a step that
// held, and without the reset every real step flags three nights running (the
// lagging median), so the reset stays. Across the 277 night x scenario
// verdicts replayed when this was written the only flags were real steps and
// the noisiest unflagged night read 1.27x (a single-file suite, on a second
// night at an unchanged commit), so a 1.4x spike has not happened yet. Treat
// a flagged night that looks like noise as a reason to re-run the night, or
// to watch the dashboard for the next two nights.
//
// Exit 1 when any scenario regressed tonight, 2 on bad input. --replay judges
// every night in the history instead, each as the workflow would have after
// the nights before it, and prints the verdicts (exit 0).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// One scenario's envelope from one run: [values] maps each file that
/// rendered cleanly to its metric.
class TrendNight {
  TrendNight({
    required this.scenario,
    required this.sha,
    required this.ts,
    required this.values,
    this.revDate,
  });

  final String scenario;
  final String sha;
  final String ts;
  final DateTime? revDate;
  final Map<String, double> values;

  /// Reads [envelope]'s per-file [metric]; null for an envelope without a
  /// scenario or a `results` list (a line of the wrong shape is skipped like
  /// a corrupt one: a throw here would read `error` every night until someone
  /// hand-edited perf-data). Rows with an error or a non-positive value are
  /// skipped.
  static TrendNight? fromEnvelope(Map<String, Object?> envelope,
      {String metric = 'renderMs'}) {
    final scenario = envelope['scenario'];
    if (scenario is! String || scenario.isEmpty) return null;
    final results = envelope['results'];
    if (results is! List) return null;
    final rev = envelope['rev'] is Map ? envelope['rev'] as Map : const {};
    final values = <String, double>{};
    for (final r in results) {
      if (r is! Map || r['error'] != null) continue;
      final file = r['file'], v = r[metric];
      if (file is String && v is num && v > 0) values[file] = v.toDouble();
    }
    final revDate = rev['date'];
    return TrendNight(
      scenario: scenario,
      sha: rev['sha'] is String ? rev['sha'] as String : '',
      ts: envelope['ts'] is String ? envelope['ts'] as String : '',
      revDate: revDate is String ? DateTime.tryParse(revDate) : null,
      values: values,
    );
  }

  DateTime? get _when => revDate ?? DateTime.tryParse(ts);
}

/// Orders [nights] by commit date, then run timestamp (stable otherwise).
List<TrendNight> orderNights(Iterable<TrendNight> nights) {
  final indexed = nights.toList();
  final order = List<int>.generate(indexed.length, (i) => i);
  order.sort((a, b) {
    final wa = indexed[a]._when, wb = indexed[b]._when;
    if (wa != null && wb != null && wa != wb) return wa.compareTo(wb);
    final byTs = indexed[a].ts.compareTo(indexed[b].ts);
    return byTs != 0 ? byTs : a.compareTo(b);
  });
  return [for (final i in order) indexed[i]];
}

/// The rule's reading of one night.
class TrendVerdict {
  TrendVerdict({
    required this.night,
    required this.window,
    required this.ratio,
    required this.files,
    required this.worst,
    required this.regressed,
  });

  final TrendNight night;

  /// Earlier nights the baseline was drawn from (0: nothing to compare).
  final int window;

  /// Median per-file ratio vs the window; null when nothing was comparable.
  final double? ratio;
  final int files;

  /// The slowest files by ratio, worst first (informational only).
  final List<MapEntry<String, double>> worst;
  final bool regressed;

  String label(double threshold) => ratio == null
      ? 'skipped'
      : regressed
          ? 'REGRESSED'
          : ratio! <= 1 / threshold
              ? 'improved'
              : 'ok';
}

double _median(List<double> v) {
  final s = List<double>.of(v)..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// Judges [night] against the [window] of earlier nights.
TrendVerdict judgeNight(TrendNight night, List<TrendNight> window,
    {double threshold = 1.4, int worstCount = 3}) {
  final ratios = <String, double>{};
  night.values.forEach((file, value) {
    final samples = [
      for (final w in window)
        if (w.values[file] case final v?) v,
    ];
    if (samples.isNotEmpty) ratios[file] = value / _median(samples);
  });
  if (ratios.isEmpty) {
    return TrendVerdict(
        night: night,
        window: window.length,
        ratio: null,
        files: 0,
        worst: const [],
        regressed: false);
  }
  final ratio = _median(ratios.values.toList());
  final worst = ratios.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return TrendVerdict(
    night: night,
    window: window.length,
    ratio: ratio,
    files: ratios.length,
    worst: worst.take(worstCount).toList(),
    regressed: ratio >= threshold,
  );
}

/// Walks one scenario's [ordered] nights and judges each against up to
/// [nights] earlier ones, never reaching back past the last flagged night.
List<TrendVerdict> walkScenario(List<TrendNight> ordered,
    {int nights = 5, double threshold = 1.4}) {
  final verdicts = <TrendVerdict>[];
  var levelStart = 0;
  for (var i = 0; i < ordered.length; i++) {
    final from = math.max(levelStart, i - nights);
    final verdict =
        judgeNight(ordered[i], ordered.sublist(from, i), threshold: threshold);
    verdicts.add(verdict);
    if (verdict.regressed) levelStart = i;
  }
  return verdicts;
}

/// [night]'s verdict after the [history] nights of its scenario (in commit
/// order, [night] last), leaving out the nights at [night]'s own commit.
TrendVerdict judgeAfter(List<TrendNight> history, TrendNight night,
        {int nights = 5, double threshold = 1.4}) =>
    walkScenario([
      ...orderNights(history.where((h) =>
          h.scenario == night.scenario &&
          (night.sha.isEmpty || h.sha != night.sha))),
      night,
    ], nights: nights, threshold: threshold)
        .last;

/// Tonight's verdict per scenario in [current]: each is judged after the
/// [history] nights of the same scenario (current envelopes always last).
List<TrendVerdict> judgeTonight(
    List<TrendNight> history, List<TrendNight> current,
    {int nights = 5, double threshold = 1.4}) {
  final tonight = <String, TrendNight>{};
  for (final n in current) {
    tonight[n.scenario] = n; // the last envelope of a scenario wins
  }
  return [
    for (final n in tonight.values)
      judgeAfter(history, n, nights: nights, threshold: threshold),
  ];
}

String _fmt(double v) => '${v.toStringAsFixed(3)}x';

String _describe(TrendVerdict v, double threshold) {
  final base = v.ratio == null
      ? '${v.night.scenario}: no comparable earlier night -> skipped'
      : '${v.night.scenario}: ${_fmt(v.ratio!)} vs median of ${v.window} '
          'prior night(s) over ${v.files} file(s) -> ${v.label(threshold)}';
  if (v.ratio == null || v.files < 2) return base;
  return '$base  [worst: '
      '${v.worst.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}x').join('; ')}]';
}

List<TrendNight> _readNights(String path, String metric) {
  final nights = <TrendNight>[];
  for (final line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      stderr.writeln('$path: skipping a corrupt line');
      continue;
    }
    if (decoded is! Map<String, Object?>) continue;
    final night = TrendNight.fromEnvelope(decoded, metric: metric);
    if (night != null) nights.add(night);
  }
  return nights;
}

void main(List<String> argv) {
  String? historyPath, currentPath, summaryPath;
  var replay = false;
  var nights = 5;
  var threshold = 1.4;
  var metric = 'renderMs';
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    String next() {
      if (i + 1 >= argv.length) {
        stderr.writeln('$arg needs a value');
        exit(2);
      }
      return argv[++i];
    }

    switch (arg) {
      case '--history':
        historyPath = next();
      case '--current':
        currentPath = next();
      case '--replay':
        replay = true;
        historyPath = next();
      case '--nights':
        nights = int.parse(next());
      case '--threshold':
        threshold = double.parse(next());
      case '--metric':
        metric = next();
      case '--summary':
        summaryPath = next();
      default:
        stderr.writeln('unknown argument $arg');
        exit(2);
    }
  }
  if (historyPath == null || (!replay && currentPath == null)) {
    stderr.writeln('usage: render_trend.dart --history <prior.ndjson> '
        '--current <tonight.ndjson> [--nights N] [--threshold R] '
        '[--metric renderMs] [--summary <md>]\n'
        '       render_trend.dart --replay <history.ndjson> [...]');
    exit(2);
  }
  final history = File(historyPath).existsSync()
      ? _readNights(historyPath, metric)
      : <TrendNight>[];

  if (replay) {
    // Each night as the workflow would have judged it: after the nights
    // before it, in commit order.
    final scenarios = {for (final n in history) n.scenario};
    final all = <TrendVerdict>[];
    for (final s in scenarios) {
      final ordered = orderNights(history.where((n) => n.scenario == s));
      for (var i = 0; i < ordered.length; i++) {
        all.add(judgeAfter(ordered.sublist(0, i), ordered[i],
            nights: nights, threshold: threshold));
      }
    }
    all.sort((a, b) => a.night.ts.compareTo(b.night.ts));
    for (final v in all) {
      final day = v.night.ts.length >= 10 ? v.night.ts.substring(0, 10) : '?';
      final sha =
          v.night.sha.length > 8 ? v.night.sha.substring(0, 8) : v.night.sha;
      stdout.writeln('$day $sha ${_describe(v, threshold)}');
    }
    final flagged = all.where((v) => v.regressed).toList();
    stdout.writeln('flagged ${flagged.length} of ${all.length} night-scenario '
        'verdicts (--nights $nights, --threshold $threshold)');
    return;
  }

  final current = File(currentPath!).existsSync()
      ? _readNights(currentPath, metric)
      : <TrendNight>[];
  if (current.isEmpty) {
    stderr.writeln('$currentPath holds no scenario envelopes');
    exit(2);
  }
  final verdicts =
      judgeTonight(history, current, nights: nights, threshold: threshold);
  for (final v in verdicts) {
    stdout.writeln(_describe(v, threshold));
  }
  final regressed = verdicts.any((v) => v.regressed);
  if (summaryPath != null) {
    final md = StringBuffer()
      ..writeln('### Render trend ($metric vs the median of up to $nights '
          'prior nights, fail at ${threshold.toStringAsFixed(2)}x)')
      ..writeln()
      ..writeln('| scenario | files | nights | ratio | verdict | worst |')
      ..writeln('|---|---|---|---|---|---|');
    for (final v in verdicts) {
      md.writeln('| ${v.night.scenario} | ${v.files} | ${v.window} | '
          '${v.ratio == null ? '-' : _fmt(v.ratio!)} | '
          '${v.label(threshold)} | '
          '${v.files < 2 ? '-' : v.worst.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}x').join('; ')} |');
    }
    File(summaryPath).writeAsStringSync('$md\n', mode: FileMode.append);
  }
  stdout.writeln(regressed
      ? 'VERDICT: REGRESSED (suite median ratio >= '
          '${threshold.toStringAsFixed(2)}x)'
      : 'VERDICT: OK');
  exit(regressed ? 1 : 0);
}
