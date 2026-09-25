// Run with `dart tool/perf/nightly_test.dart` (CI does, next to the other
// tool tests). Checks perf-nightly's plumbing outside GitHub:
//   - tool/perf/nightly_ratio_check.sh against a stub perf_diff.sh in a
//     throwaway git repo (verdict mapping, iterations, the accepted-sha file);
//   - tool/perf/nightly_state.dart: the baseline rules (ratchet, re-check of
//     a red night, one carry past an errored night), the weekly backstop, and
//     a re-run reading and replacing its earlier attempt on a perf-data branch;
//   - .github/workflows/perf-nightly.yml's timeout budget, so a slow check
//     fails its own step instead of timing out the job and losing the append;
//   - tool/perf/report/build_report.mjs on history lines that are not objects.
// Plain asserts, no package imports - like the scripts. Needs bash + git;
// the dashboard check also needs node (skipped without it).
import 'dart:convert';
import 'dart:io';

import 'nightly_state.dart';

var _failures = 0;

void _check(bool ok, String label) {
  if (ok) {
    print('ok   $label');
  } else {
    _failures++;
    print('FAIL $label');
  }
}

final _perfDir = File.fromUri(Platform.script).parent;
final _repoRoot = _perfDir.parent.parent;

String _git(String dir, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
  return '${r.stdout}'.trim();
}

/// perf_diff.sh stand-in: logs its arguments, then behaves per scenario as
/// STUB_<scenario with - as _> says: ok, regressed, nodata (merge_runs found
/// no envelopes - exit 1 without a verdict), or crash (exit 2).
const _stubDiff = r'''#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
var="STUB_${2//-/_}"
case "${!var:-ok}" in
  ok) echo "VERDICT: OK"; exit 0 ;;
  regressed) echo "VERDICT: REGRESSED (median ratio > 1.15x)"; exit 1 ;;
  nodata) echo "ref.ndjson holds no envelopes" >&2; exit 1 ;;
  crash) echo "unknown flag" >&2; exit 2 ;;
esac
''';

class _Repo {
  _Repo() : dir = Directory.systemTemp.createTempSync('nightly_test').path {
    Directory('$dir/tool/perf').createSync(recursive: true);
    File('${_perfDir.path}/nightly_ratio_check.sh')
        .copySync('$dir/tool/perf/nightly_ratio_check.sh');
    File('$dir/tool/perf/perf_diff.sh').writeAsStringSync(_stubDiff);
    Process.runSync('chmod', [
      '+x',
      '$dir/tool/perf/perf_diff.sh',
      '$dir/tool/perf/nightly_ratio_check.sh'
    ]);
    _git(dir, ['init', '-q']);
    _git(dir, ['config', 'user.email', 'test@example.com']);
    _git(dir, ['config', 'user.name', 'test']);
    _git(dir, ['add', '-A']);
    _git(dir, ['-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'baseline']);
    baseline = _git(dir, ['rev-parse', 'HEAD']);
    File('$dir/change.txt').writeAsStringSync('tonight\n');
    _git(dir, ['add', '-A']);
    _git(dir, ['-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'tonight']);
    head = _git(dir, ['rev-parse', 'HEAD']);
  }

  final String dir;
  late final String baseline, head;

  void delete() => Directory(dir).deleteSync(recursive: true);
}

class _Run {
  _Run(this.exitCode, this.outputs, this.diffCalls, this.log);
  final int exitCode;
  final Map<String, String> outputs;
  final List<String> diffCalls;
  final String log;
}

_Run _ratioCheck(_Repo repo, List<String> args,
    {Map<String, String> stub = const {}}) {
  final out = File('${repo.dir}/github_output')..writeAsStringSync('');
  final calls = File('${repo.dir}/diff_calls')..writeAsStringSync('');
  final r =
      Process.runSync('bash', ['tool/perf/nightly_ratio_check.sh', ...args],
          workingDirectory: repo.dir,
          environment: {
            'GITHUB_OUTPUT': out.path,
            'STUB_LOG': calls.path,
            for (final e in stub.entries)
              'STUB_${e.key.replaceAll('-', '_')}': e.value,
          });
  final outputs = <String, String>{
    for (final line in out.readAsLinesSync())
      if (line.contains('='))
        line.substring(0, line.indexOf('=')):
            line.substring(line.indexOf('=') + 1),
  };
  return _Run(
      r.exitCode, outputs, calls.readAsLinesSync(), '${r.stdout}${r.stderr}');
}

void _testRatioCheck() {
  final repo = _Repo();
  try {
    final b = repo.baseline;

    var r = _ratioCheck(repo, ['nightly', b]);
    _check(r.exitCode == 0 && r.outputs['nightly'] == 'ok',
        'ratio check: both scenarios hold -> ok, exit 0 (got ${r.exitCode} ${r.outputs})');
    _check(
        r.diffCalls.length == 2 &&
            r.diffCalls[0] ==
                '$b save-incremental --iterations 2 --threshold 1.15 --clean' &&
            r.diffCalls[1] ==
                '$b ghent-suite-open --iterations 4 --threshold 1.15 --clean',
        'ratio check: save-incremental x2, ghent-suite-open x4, 1.15x '
        '(got ${r.diffCalls})');

    r = _ratioCheck(repo, ['nightly', b],
        stub: {'ghent-suite-open': 'regressed'});
    _check(r.exitCode == 1 && r.outputs['nightly'] == 'regressed',
        'ratio check: a REGRESSED verdict -> regressed, exit 1 (got ${r.outputs})');

    // The review finding: merge_runs.dart exits 1 when a side produced no
    // envelopes, and perf_diff.sh passes that 1 on.
    r = _ratioCheck(repo, ['nightly', b], stub: {'save-incremental': 'nodata'});
    _check(
        r.exitCode == 1 && r.outputs['nightly'] == 'error',
        'ratio check: exit 1 without a verdict line -> error, not regressed '
        '(got ${r.outputs})');
    _check(r.diffCalls.length == 2,
        'ratio check: an error on one scenario still runs the other');

    r = _ratioCheck(repo, ['nightly', b], stub: {'save-incremental': 'crash'});
    _check(r.exitCode == 1 && r.outputs['nightly'] == 'error',
        'ratio check: exit 2 -> error (got ${r.outputs})');

    r = _ratioCheck(repo, ['nightly', b],
        stub: {'save-incremental': 'nodata', 'ghent-suite-open': 'regressed'});
    _check(r.outputs['nightly'] == 'regressed',
        'ratio check: a regression outranks an error (got ${r.outputs})');

    for (final (sha, why) in [
      ('', 'no previous nightly'),
      (repo.head, 'baseline is HEAD'),
      ('0123456789abcdef0123456789abcdef01234567', 'unknown commit'),
    ]) {
      r = _ratioCheck(repo, ['nightly', sha]);
      _check(
          r.exitCode == 0 &&
              r.outputs['nightly'] == 'skipped' &&
              r.diffCalls.isEmpty,
          'ratio check: $why -> skipped, nothing measured (got ${r.outputs})');
    }

    // The accepted baseline comes from a reviewed file.
    File shaFile(String text) =>
        File('${repo.dir}/accepted.sha')..writeAsStringSync(text);
    shaFile('# accepted baseline\n#\n${b.substring(0, 12)}  # abbreviated\n\n');
    r = _ratioCheck(repo, ['accepted', '--sha-file', 'accepted.sha']);
    _check(
        r.exitCode == 0 &&
            r.outputs['accepted'] == 'ok' &&
            r.outputs['accepted_sha'] == b &&
            r.diffCalls.first.startsWith('$b '),
        'accepted: the file\'s one commit is resolved and checked '
        '(got ${r.outputs})');

    // The review finding: a typo'd or doubled file used to read "skipped"
    // and quietly switch the weekly check off.
    for (final (text, why) in [
      ('# comment\n${b.substring(0, 7)}x0000\n', 'a typo'),
      ('$b\n${repo.head}\n', 'two commits'),
      ('# nothing but comments\n', 'no commit'),
    ]) {
      shaFile(text);
      r = _ratioCheck(repo, ['accepted', '--sha-file', 'accepted.sha']);
      _check(
          r.exitCode == 1 &&
              r.outputs['accepted'] == 'error' &&
              !r.outputs.containsKey('accepted_sha') &&
              r.diffCalls.isEmpty,
          'accepted: $why in the sha file -> error, exit 1 (got ${r.outputs})');
    }
    r = _ratioCheck(repo, ['accepted', '--sha-file', 'missing.sha']);
    _check(r.exitCode == 1 && r.outputs['accepted'] == 'error',
        'accepted: a missing sha file -> error (got ${r.outputs})');

    r = _ratioCheck(repo, ['nightly']);
    _check(r.exitCode == 2 && r.outputs.isEmpty,
        'ratio check: bad usage exits 2 and records nothing');
  } finally {
    repo.delete();
  }
}

/// The workflow's steps as {key: value} maps of their top-level scalar keys
/// (a line scanner, enough for this file - no YAML package in tool/).
({int jobTimeout, List<Map<String, String>> steps}) _readWorkflow() {
  final lines = File('${_repoRoot.path}/.github/workflows/perf-nightly.yml')
      .readAsLinesSync();
  var jobTimeout = -1;
  final steps = <Map<String, String>>[];
  final jobKey = RegExp(r'^    timeout-minutes:\s*(\d+)\s*$');
  final stepStart = RegExp(r'^      - ([a-z-]+):\s*(.*)$');
  final stepKey = RegExp(r'^        ([a-z-]+):\s*(.*)$');
  for (final line in lines) {
    if (jobKey.firstMatch(line) case final m?) {
      jobTimeout = int.parse(m[1]!);
    } else if (stepStart.firstMatch(line) case final m?) {
      steps.add({m[1]!: m[2]!});
    } else if (stepKey.firstMatch(line) case final m? when steps.isNotEmpty) {
      steps.last[m[1]!] = m[2]!;
    }
  }
  return (jobTimeout: jobTimeout, steps: steps);
}

void _testWorkflowBudget() {
  const setupAllowance = 20; // checkout .. perf-data fetch: ~1 min measured
  final wf = _readWorkflow();
  final sweeps = wf.steps.indexWhere((s) => s['id'] == 'sweeps');
  final append = wf.steps
      .indexWhere((s) => (s['name'] ?? '').startsWith('Append history'));
  _check(sweeps >= 0 && append > sweeps,
      'workflow: found the sweeps and append steps');
  if (sweeps < 0 || append <= sweeps) return;
  final measured = wf.steps.sublist(sweeps, append + 1);
  final missing = [
    for (final s in measured)
      if (int.tryParse(s['timeout-minutes'] ?? '') == null) s['name'],
  ];
  _check(
      missing.isEmpty,
      'workflow: every step from the sweeps to the append has timeout-minutes '
      '(missing: $missing)');
  final sum = measured.fold<int>(
      0, (t, s) => t + (int.tryParse(s['timeout-minutes'] ?? '') ?? 0));
  _check(
      wf.jobTimeout >= sum + setupAllowance,
      'workflow: job timeout ${wf.jobTimeout} covers the step timeouts '
      '($sum) + $setupAllowance min of setup, so no check can time the job '
      'out before the append');
  _check(wf.jobTimeout <= 360, 'workflow: within the hosted-runner limit');
  final checks = [
    for (final s in measured)
      if (s['id'] == 'ratio' ||
          s['id'] == 'accepted' ||
          s['id'] == 'render_trend')
        s,
  ];
  _check(
      checks.length == 3 &&
          checks.every((s) => s['continue-on-error'] == 'true'),
      'workflow: the three checks continue on error, so a red or timed-out '
      'check still reaches the append');
  final appendIf = wf.steps[append]['if'] ?? '';
  _check(
      appendIf.contains('!cancelled()') &&
          appendIf.contains("steps.sweeps.outcome == 'success'"),
      'workflow: the append runs on red nights, never after a failed sweep');
  final upload = wf.steps.firstWhere(
      (s) => (s['uses'] ?? '').startsWith('actions/upload-artifact'),
      orElse: () => const {});
  final uploadText =
      File('${_repoRoot.path}/.github/workflows/perf-nightly.yml')
          .readAsStringSync();
  _check(
      upload.isNotEmpty &&
          RegExp(r'name: perf-history-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}')
              .hasMatch(uploadText),
      'workflow: the artifact name is unique per attempt (a re-run keeps '
      'the run id)');
  // A re-run finds its earlier append by the trailer nightly_state.dart
  // greps for, and every perf-data read goes through the prev step's base
  // (the tip, or the state before this run's first attempt).
  _check(uploadText.contains('-m "$nightTrailer: \$RUN_ID"'),
      'workflow: the append commit carries the trailer a re-run looks for');
  _check(
      uploadText.contains('git show "\$BASE:history/flutter-render.ndjson"') &&
          !uploadText.contains('git show perf-data:'),
      'workflow: the render trend reads the prev step\'s base, not the tip');
  final appendRun = uploadText.substring(
      uploadText.indexOf('- name: Append history'),
      uploadText.indexOf('- name: Fail on a red verdict'));
  _check(
      appendRun.contains('drop-run --commit "\$RUN_COMMIT"') &&
          appendRun.indexOf('drop-run') < appendRun.indexOf('cat "\$f" >>'),
      'workflow: a re-run drops its earlier attempt before appending');
}

void _testDashboardRobustness() {
  final node = Process.runSync('node', ['--version']);
  if (node.exitCode != 0) {
    print('skip dashboard checks: node not found');
    return;
  }
  final tmp = Directory.systemTemp.createTempSync('nightly_test_report');
  try {
    final history = Directory('${tmp.path}/history')..createSync();
    String envelope(String sha, int day) => jsonEncode({
          'schema': 1,
          'suite': 'vm-sweep',
          'scenario': 's',
          'rev': {'sha': sha, 'date': '2026-07-0${day}T00:00:00Z'},
          'ts': '2026-07-0${day}T01:00:00Z',
          'env': {'os': 'linux'},
          'metrics': {'p50OpenMs': 1.5 + day},
        });
    String verdict(String sha, String v) => jsonEncode({
          'date': '2026-07-01T04:00:00Z',
          'sha': sha,
          'verdict': v,
          'checks': {'nightly': v},
        });
    const junk = ['null', '[]', '7', '"text"', 'true', '{not json'];
    File('${history.path}/vm-sweep.ndjson').writeAsStringSync([
      envelope('abc12345', 1),
      ...junk,
      envelope('def67890', 2),
      envelope('0a1b2c3d', 3),
      '',
    ].join('\n'));
    File('${history.path}/nightly-verdicts.jsonl').writeAsStringSync([
      ...junk,
      verdict('abc12345', 'regressed'),
      verdict('def67890', 'error'),
      verdict('0a1b2c3d', 'regressed'),
      verdict('0a1b2c3d', 'ok'), // a re-check cleared it
      '',
    ].join('\n'));
    final out = '${tmp.path}/index.html';
    final r = Process.runSync('node', [
      '${_perfDir.path}/report/build_report.mjs',
      '--history', history.path, //
      '--targets', '${_perfDir.path}/targets.json', '--out', out,
    ]);
    _check(
        r.exitCode == 0,
        'dashboard: non-object history lines are skipped, not fatal '
        '(exit ${r.exitCode}: ${'${r.stderr}'.split('\n').first})');
    final html = r.exitCode == 0 ? File(out).readAsStringSync() : '';
    _check(
        html.contains('Nightly verdicts') &&
            html.contains('class="fail"') &&
            html.contains('3 runs on record'),
        'dashboard: the good records around them still render');
    // The review finding: `error` nights (a check broke) were ringed and
    // labelled like regressions.
    int count(String s) => s.allMatches(html).length;
    _check(
        count('<circle class="red"') == 1 &&
            count('<circle class="err"') == 1 &&
            html.contains('@abc12345  (nightly: regressed)') &&
            html.contains('@def67890  (nightly: error)') &&
            !html.contains('@0a1b2c3d  (nightly') &&
            !html.contains('(nightly: red)'),
        'dashboard: only regressed nights get the red ring, an error night a '
        'distinct one, and a later ok re-check clears a commit\'s ring');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// A verdict record as the workflow writes it.
NightRecord _record(String sha, String? prev, String nightly,
        {String accepted = 'not-run',
        String date = '2026-09-20T04:00:00Z',
        String runId = '1'}) =>
    {
      'date': date,
      'sha': sha,
      'prevSha': prev,
      'verdict': nightly == 'regressed' || nightly == 'error' ? nightly : 'ok',
      'checks': {
        'nightly': nightly,
        'accepted': accepted,
        'renderTrend': 'ok',
      },
      'runId': runId,
    };

void _testBaselineRules() {
  String? pick(List<NightRecord> records, String head,
          {bool haveVerdicts = true, String? vmTail}) =>
      resolveBaseline(
              records: records,
              haveVerdicts: haveVerdicts,
              head: head,
              vmSweepTail: vmTail)
          .sha;
  String rule(List<NightRecord> records, String head) =>
      resolveBaseline(records: records, haveVerdicts: true, head: head).rule;

  _check(
      pick(const [], 'c5', haveVerdicts: false, vmTail: 'c1') == 'c1' &&
          pick(const [], 'c5', haveVerdicts: false) == null,
      'baseline: before the verdict file exists, the vm-sweep tail (or none)');
  final nights = [_record('c1', 'c0', 'ok'), _record('c2', 'c1', 'ok')];
  _check(pick(nights, 'c3') == 'c2' && rule(nights, 'c3') == 'previous',
      'baseline: the last recorded night - the ratchet');

  // The review finding: a corrupt LAST line fell back to the vm-sweep tail,
  // which can be an old backfilled commit.
  final text = [
    ...nights.map(jsonEncode),
    '{"sha": "c9", "checks": {"nightly": "ok"',
    '[]',
    '{"date": "x"}',
  ].join('\n');
  final parsed = parseRecords(text);
  _check(
      parsed.length == 2 && pick(parsed, 'c3', vmTail: 'c0') == 'c2',
      'baseline: corrupt trailing lines are skipped, not a reason to fall '
      'back to the vm-sweep tail (got ${pick(parsed, 'c3', vmTail: 'c0')})');
  _check(
      pick(parseRecords('null\n{broken\n'), 'c3', vmTail: 'c0') == null,
      'baseline: a verdict file with no readable record is none, not an old '
      'vm-sweep sha');
  _check(
      lastEnvelopeSha('{"rev": {"sha": "c1"}}\n{"rev": {"sha": "c2"}}\n{bad\n'
              '[1]\n') ==
          'c2',
      'baseline: the vm-sweep fallback skips unreadable trailing lines too');

  // The review finding: a re-run or a dispatch on the same commit compared
  // HEAD with itself and read green while the regression was still there.
  for (final state in ['regressed', 'error']) {
    final red = [...nights, _record('c3', 'c2', state)];
    _check(
        pick(red, 'c3') == 'c2' && rule(red, 'c3') == 'recheck',
        'baseline: when the last night is HEAD and read $state, its own '
        'baseline is re-checked, not HEAD (got ${pick(red, 'c3')})');
  }
  final green = [...nights, _record('c3', 'c2', 'ok')];
  _check(pick(green, 'c3') == 'c3' && rule(green, 'c3') == 'unchanged',
      'baseline: a green night at HEAD leaves nothing to check');
  final renderRed = [
    ...nights,
    _record('c3', 'c2', 'ok')..['verdict'] = 'regressed',
  ];
  _check(pick(renderRed, 'c3') == 'c3',
      'baseline: only the nightly check\'s own red is re-checked');

  // The review finding: an errored night (a check that timed out) advanced
  // the baseline, so its range was never judged.
  final errored = [...nights, _record('c3', 'c2', 'error')];
  _check(
      pick(errored, 'c4') == 'c2' && rule(errored, 'c4') == 'carry',
      'baseline: an errored night\'s baseline is carried into the next '
      '(got ${pick(errored, 'c4')})');
  final carriedTwice = [...errored, _record('c4', 'c2', 'error')];
  _check(
      pick(carriedTwice, 'c5') == 'c4',
      'baseline: carried once only - a baseline that keeps failing cannot '
      'freeze the ratchet (got ${pick(carriedTwice, 'c5')})');
  final recheckedCarry = [...carriedTwice, _record('c4', 'c2', 'error')];
  _check(pick(recheckedCarry, 'c5') == 'c4',
      'baseline: a re-check of a carried night does not renew the carry');
  _check(pick([_record('c3', 'c1', 'error')], 'c4') == 'c1',
      'baseline: the first recorded night can carry too');
}

void _testAcceptedDue() {
  final now = DateTime.utc(2026, 9, 29, 4);
  NightRecord at(int daysAgo, String accepted) => _record('c', 'b', 'ok',
      accepted: accepted,
      date: now.subtract(Duration(days: daysAgo)).toIso8601String());
  _check(acceptedDue(const [], now).due,
      'accepted: due with no accepted check on record');
  _check(
      acceptedDue([at(8, 'ok'), at(1, 'not-run')], now).due,
      'accepted: due when the last one that ran is 8 days old (a dropped '
      'Sunday)');
  _check(!acceptedDue([at(8, 'ok'), at(2, 'regressed')], now).due,
      'accepted: not due two days after one ran');
  _check(!acceptedDue([at(1, 'error')], now).due,
      'accepted: an errored check counts as having run');
  _check(acceptedDue([at(3, 'skipped'), at(1, 'not-run')], now).due,
      'accepted: skipped / not-run nights are not a check');
}

void _testDropAppended() {
  var r = dropAppended('a\nb\nx\ny\nz\n', 'a\nb\n', 'a\nb\nx\ny\n');
  _check(r.text == 'a\nb\nz\n' && r.missing == 0,
      'drop: an attempt\'s lines go, a later night\'s stay (got ${jsonEncode(r.text)})');
  // Attempt 2 replaced attempt 1 (dropped x, appended w): dropping attempt 2
  // removes w only.
  r = dropAppended('a\nb\nw\nz\n', 'a\nb\nx\n', 'a\nb\nw\n');
  _check(r.text == 'a\nb\nz\n' && r.missing == 0,
      'drop: a replacing attempt\'s removals are not re-added');
  r = dropAppended('a\n', 'a\n', 'a\nq\n');
  _check(r.text == 'a\n' && r.missing == 1,
      'drop: a line already gone is counted, not fatal');
}

/// resolve + drop-run against a throwaway repo with a perf-data branch: a
/// first attempt, its re-run, a dispatch on the same commit, a third attempt,
/// and a re-run after a later night was recorded.
void _testStateCli() {
  final dir = Directory.systemTemp.createTempSync('nightly_state_test').path;
  final script = '${_perfDir.path}/nightly_state.dart';
  try {
    void git(List<String> args, [String? at]) => _git(at ?? dir, args);
    git(['init', '-q', '-b', 'main']);
    git(['config', 'user.email', 'test@example.com']);
    git(['config', 'user.name', 'test']);
    File('$dir/a.txt').writeAsStringSync('main\n');
    git(['add', '-A']);
    git(['-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'c1']);
    final prev = _git(dir, ['rev-parse', 'HEAD']);
    File('$dir/a.txt').writeAsStringSync('main 2\n');
    git(['-c', 'commit.gpgsign=false', 'commit', '-qam', 'c2']);
    final head = _git(dir, ['rev-parse', 'HEAD']);

    // perf-data: one recorded night (run 100 at `prev`), in a worktree.
    final pd = '$dir-pd';
    git(['worktree', 'add', '-q', '--detach', pd]);
    git(['checkout', '-q', '--orphan', 'perf-data'], pd);
    git(['rm', '-rfq', '.'], pd);
    Directory('$pd/history').createSync();
    String env(String sha, String tag) => jsonEncode({
          'suite': 'vm-sweep',
          'rev': {'sha': sha},
          'ts': tag
        });
    void append(String file, String line) => File('$pd/history/$file')
        .writeAsStringSync('$line\n', mode: FileMode.append);
    void commit(String runId) {
      git(['add', '-A'], pd);
      git([
        '-c', 'commit.gpgsign=false', 'commit', '-q', //
        '-m', 'perf-nightly: night (run $runId)',
        '-m', '$nightTrailer: $runId',
      ], pd);
    }

    append('vm-sweep.ndjson', env(prev, 'n0'));
    append('nightly-verdicts.jsonl',
        jsonEncode(_record(prev, null, 'skipped', runId: '100')));
    commit('100');
    final before = _git(pd, ['rev-parse', 'HEAD']);

    Map<String, String> resolve(String runId) {
      final r = Process.runSync(
          Platform.resolvedExecutable,
          [
            script, 'resolve', '--ref', 'perf-data', '--head', head, //
            '--run-id', runId, '--now', '2026-09-20T05:00:00Z',
          ],
          workingDirectory: dir);
      if (r.exitCode != 0) throw StateError('resolve: ${r.stderr}');
      return {
        for (final l in const LineSplitter().convert('${r.stdout}'))
          if (l.contains('='))
            l.substring(0, l.indexOf('=')): l.substring(l.indexOf('=') + 1),
      };
    }

    void dropRun(String commit) {
      final r = Process.runSync(Platform.resolvedExecutable,
          [script, 'drop-run', '--commit', commit, '--dir', pd]);
      if (r.exitCode != 0) throw StateError('drop-run: ${r.stderr}');
    }

    var o = resolve('200');
    _check(
        o['base'] == before &&
            o['sha'] == prev &&
            o['rule'] == 'previous' &&
            o['run_commit'] == '' &&
            o['superseded'] == 'false',
        'state: a first attempt reads the tip and compares against the last '
        'night (got $o)');

    // Attempt 1 of run 200: red, appended.
    append('vm-sweep.ndjson', env(head, 'attempt 1'));
    append('nightly-verdicts.jsonl',
        jsonEncode(_record(head, prev, 'regressed', runId: '200')));
    commit('200');
    final attempt1 = _git(pd, ['rev-parse', 'HEAD']);

    o = resolve('200');
    _check(
        o['base'] == before &&
            o['sha'] == prev &&
            o['run_commit'] == attempt1 &&
            o['superseded'] == 'false',
        'state: a re-run reads perf-data as it was before its first attempt '
        'and repeats that comparison (got $o)');
    o = resolve('300');
    _check(o['base'] == attempt1 && o['sha'] == prev && o['rule'] == 'recheck',
        'state: a new run on the same commit re-checks the red night (got $o)');

    // Attempt 2 replaces attempt 1's night.
    dropRun(attempt1);
    append('vm-sweep.ndjson', env(head, 'attempt 2'));
    append('nightly-verdicts.jsonl',
        jsonEncode(_record(head, prev, 'ok', runId: '200')));
    commit('200');
    final attempt2 = _git(pd, ['rev-parse', 'HEAD']);
    final vm = File('$pd/history/vm-sweep.ndjson').readAsStringSync();
    final verdicts = parseRecords(
        File('$pd/history/nightly-verdicts.jsonl').readAsStringSync());
    _check(
        !vm.contains('attempt 1') &&
            vm.contains('attempt 2') &&
            verdicts.length == 2 &&
            verdicts.last['checks'] is Map &&
            (verdicts.last['checks'] as Map)['nightly'] == 'ok',
        'state: the re-run replaces its earlier attempt\'s night instead of '
        'recording it twice');

    o = resolve('200');
    _check(o['base'] == before && o['run_commit'] == attempt2,
        'state: a third attempt still reads from before the first (got $o)');
    dropRun(attempt2);
    _check(
        File('$pd/history/vm-sweep.ndjson').readAsStringSync() ==
            '${env(prev, 'n0')}\n',
        'state: dropping the latest attempt leaves the history as before '
        'the run');
    git(['checkout', '-q', '--', '.'], pd);

    // A backfill commit (no trailer) is not a later night.
    append('vm-sweep.ndjson', env(prev, 'backfill'));
    git(['add', '-A'], pd);
    git(['-c', 'commit.gpgsign=false', 'commit', '-qm', 'perf-backfill'], pd);
    o = resolve('200');
    _check(o['superseded'] == 'false' && o['run_commit'] == attempt2,
        'state: a backfill appended since does not supersede a re-run (got $o)');

    // A later night is recorded, then run 200 is re-run again.
    append('nightly-verdicts.jsonl',
        jsonEncode(_record('later', head, 'ok', runId: '400')));
    commit('400');
    o = resolve('200');
    _check(o['superseded'] == 'true' && o['base'] == before,
        'state: a re-run after a later night leaves perf-data alone (got $o)');
  } finally {
    Process.runSync('git', ['worktree', 'remove', '--force', '$dir-pd'],
        workingDirectory: dir);
    Directory(dir).deleteSync(recursive: true);
    if (Directory('$dir-pd').existsSync()) {
      Directory('$dir-pd').deleteSync(recursive: true);
    }
  }
}

void main() {
  _testRatioCheck();
  _testBaselineRules();
  _testAcceptedDue();
  _testDropAppended();
  _testStateCli();
  _testWorkflowBudget();
  _testDashboardRobustness();
  if (_failures > 0) {
    print('$_failures check(s) failed');
    exit(1);
  }
  print('all perf-nightly checks passed');
}
