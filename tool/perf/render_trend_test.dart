// Run with `dart tool/perf/render_trend_test.dart` (CI does, next to the
// other tool tests). Plain asserts, no package imports - like the script.
import 'dart:convert';
import 'dart:io';

import 'render_trend.dart';

var _failures = 0;

void _check(bool ok, String label) {
  if (ok) {
    print('ok   $label');
  } else {
    _failures++;
    print('FAIL $label');
  }
}

/// A flutter-render envelope for [scenario] on [day] (July 2026, one commit
/// per day) with renderMs per file.
Map<String, Object?> _envelope(String scenario, int day, Map<String, num> ms,
    {int? commitDay, Map<String, String> errors = const {}}) {
  final d = (commitDay ?? day).toString().padLeft(2, '0');
  final t = day.toString().padLeft(2, '0');
  return {
    'schema': 1,
    'suite': 'flutter-render',
    'scenario': scenario,
    'rev': {'sha': 'sha$d', 'date': '2026-07-${d}T12:00:00+10:00'},
    'ts': '2026-07-${t}T03:30:00.000Z',
    'results': [
      for (final e in ms.entries)
        {'file': e.key, 'renderMs': e.value, 'error': null},
      for (final e in errors.entries)
        {'file': e.key, 'renderMs': 0.0, 'error': e.value},
    ],
  };
}

TrendNight _night(String scenario, int day, Map<String, num> ms,
        {int? commitDay, Map<String, String> errors = const {}}) =>
    TrendNight.fromEnvelope(
        _envelope(scenario, day, ms, commitDay: commitDay, errors: errors))!;

/// Five files around [base] ms with a little night-to-night jitter.
Map<String, num> _suite(int day, double base) => {
      for (var f = 0; f < 5; f++)
        'f$f.pdf': base * (1 + 0.08 * ((day * 7 + f * 3) % 5 - 2) / 2),
    };

void main() {
  // A flat, jittery series never flags.
  final flat = [for (var d = 1; d <= 20; d++) _night('s', d, _suite(d, 100))];
  final flatVerdicts = walkScenario(flat);
  _check(
      flatVerdicts.every((v) => !v.regressed), 'flat series: no night flagged');
  _check(flatVerdicts.first.ratio == null && flatVerdicts.first.window == 0,
      'first night of a scenario is skipped, not judged');

  // A 2x step on night 10 flags that night only: the nights after it compare
  // against the new level instead of re-flagging while the median catches up.
  final step = [
    for (var d = 1; d <= 20; d++)
      _night('s', d, _suite(d, d >= 10 ? 200 : 100)),
  ];
  final stepVerdicts = walkScenario(step);
  final flagged = [
    for (var i = 0; i < stepVerdicts.length; i++)
      if (stepVerdicts[i].regressed) i + 1,
  ];
  _check(flagged.length == 1 && flagged.single == 10,
      'a step flags exactly its own night (got $flagged)');
  _check((stepVerdicts[9].ratio! - 2).abs() < 0.1,
      'the step night reads ~2x (${stepVerdicts[9].ratio})');
  _check(stepVerdicts[10].window == 1 && stepVerdicts[11].window == 2,
      'nights after a flag draw only from the new level');
  _check(stepVerdicts[16].window == 5, 'the window regrows to --nights');

  // A second step while the window is still short is still caught.
  final twoSteps = [
    for (var d = 1; d <= 14; d++)
      _night(
          's',
          d,
          _suite(
              d,
              d >= 11
                  ? 400
                  : d >= 9
                      ? 200
                      : 100)),
  ];
  final twoFlagged = [
    for (final (i, v) in walkScenario(twoSteps).indexed)
      if (v.regressed) i + 1,
  ];
  _check(twoFlagged.join(',') == '9,11',
      'back-to-back steps each flag once (got $twoFlagged)');

  // One file 10x slower in a five-file suite is listed, never decisive.
  final spike = [
    for (var d = 1; d <= 6; d++)
      _night('s', d, {..._suite(d, 100), if (d == 6) 'f2.pdf': 1000}),
  ];
  final spikeVerdict = walkScenario(spike).last;
  _check(!spikeVerdict.regressed, 'a single slow file does not fail the suite');
  _check(spikeVerdict.worst.first.key == 'f2.pdf',
      'the slow file heads the worst list');

  // A single-file suite is judged on that file alone.
  final single = [
    for (var d = 1; d <= 6; d++)
      _night('j', d, {'scan.pdf': d == 6 ? 185 : 100}),
  ];
  _check(walkScenario(single).last.regressed,
      'single-file suite: 1.85x on its only file flags');

  // The threshold is inclusive.
  final edge = [
    _night('e', 1, {'a.pdf': 100}),
    _night('e', 2, {'a.pdf': 140}),
  ];
  _check(walkScenario(edge, threshold: 1.4).last.regressed,
      'a ratio equal to the threshold flags');

  // Errored rows and files missing from the window are skipped.
  final withErrors = TrendNight.fromEnvelope(_envelope(
      's', 3, {'a.pdf': 100, 'new.pdf': 900},
      errors: {'b.pdf': 'page 0: boom'}))!;
  _check(!withErrors.values.containsKey('b.pdf'),
      'an errored row carries no value');
  final partial = judgeNight(withErrors, [
    _night('s', 1, {'a.pdf': 100, 'b.pdf': 100}),
  ]);
  _check(partial.files == 1 && !partial.regressed,
      'only files present on both sides are compared');

  // A backfilled point (an old commit measured today, appended last) is
  // ordered by its commit date, so it never poses as last night.
  final history = [
    for (var d = 1; d <= 6; d++) _night('s', d, _suite(d, 100)),
    _night('s', 9, _suite(9, 300), commitDay: 1), // backfill of an old sha
  ];
  final ordered = orderNights(history);
  _check(ordered.first.sha == 'sha01' && ordered.last.sha == 'sha06',
      'history orders by commit date, then run time');
  final tonight = judgeTonight(history, [_night('s', 10, _suite(10, 100))]);
  _check(tonight.single.window == 5 && !tonight.single.regressed,
      'tonight is judged after the whole history, ignoring append order');

  // The frozen-history case: months of gap, one red night, then a new level.
  final gap = [
    for (var d = 1; d <= 5; d++) _night('g', d, _suite(d, 10)),
  ];
  final first = judgeTonight(gap, [_night('g', 25, _suite(25, 90))]).single;
  final second = judgeTonight([...gap, _night('g', 25, _suite(25, 90))],
      [_night('g', 26, _suite(26, 95))]).single;
  _check(first.regressed && !second.regressed,
      'a long gap costs one red night, then the new level holds');

  // The CLI: exit 1 on a regression (with a summary table), 0 when clean,
  // 2 without tonight's envelopes.
  final tmp = Directory.systemTemp.createTempSync('render_trend_test');
  try {
    File('${tmp.path}/prior.ndjson').writeAsStringSync([
      for (var d = 1; d <= 5; d++)
        jsonEncode(_envelope('s', d, _suite(d, 100))),
    ].join('\n'));
    File('${tmp.path}/slow.ndjson')
        .writeAsStringSync(jsonEncode(_envelope('s', 6, _suite(6, 160))));
    File('${tmp.path}/ok.ndjson')
        .writeAsStringSync(jsonEncode(_envelope('s', 6, _suite(6, 104))));
    final script = Platform.script.resolve('render_trend.dart').toFilePath();
    ProcessResult run(List<String> args) =>
        Process.runSync(Platform.resolvedExecutable, [script, ...args]);
    final summary = '${tmp.path}/summary.md';
    final slow = run([
      '--history', '${tmp.path}/prior.ndjson', //
      '--current', '${tmp.path}/slow.ndjson', '--summary', summary,
    ]);
    _check(slow.exitCode == 1 && '${slow.stdout}'.contains('REGRESSED'),
        'CLI exits 1 on a regression (got ${slow.exitCode})');
    _check(File(summary).readAsStringSync().contains('| s | 5 | 5 |'),
        'CLI appends a markdown summary row');
    final ok = run([
      '--history', '${tmp.path}/prior.ndjson', //
      '--current', '${tmp.path}/ok.ndjson',
    ]);
    _check(ok.exitCode == 0 && '${ok.stdout}'.contains('VERDICT: OK'),
        'CLI exits 0 when tonight holds (got ${ok.exitCode})');
    final missing = run([
      '--history', '${tmp.path}/prior.ndjson', //
      '--current', '${tmp.path}/none.ndjson',
    ]);
    _check(
        missing.exitCode != 0 && missing.exitCode != 1,
        'CLI fails as bad input, not as a regression, without tonight '
        '(got ${missing.exitCode})');
    final noHistory = run([
      '--history', '${tmp.path}/absent.ndjson', //
      '--current', '${tmp.path}/slow.ndjson',
    ]);
    _check(noHistory.exitCode == 0,
        'CLI with no history yet skips instead of failing');
  } finally {
    tmp.deleteSync(recursive: true);
  }

  if (_failures > 0) {
    print('$_failures check(s) failed');
    exit(1);
  }
  print('all render trend checks passed');
}
