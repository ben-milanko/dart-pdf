// Run with `dart tool/perf/nightly_test.dart` (CI does, next to the other
// tool tests). Checks perf-nightly's plumbing outside GitHub:
//   - tool/perf/nightly_ratio_check.sh against a stub perf_diff.sh in a
//     throwaway git repo (verdict mapping, iterations, the accepted-sha file);
//   - .github/workflows/perf-nightly.yml's timeout budget, so a slow check
//     fails its own step instead of timing out the job and losing the append;
//   - tool/perf/report/build_report.mjs on history lines that are not objects.
// Plain asserts, no package imports - like the scripts. Needs bash + git;
// the dashboard check also needs node (skipped without it).
import 'dart:convert';
import 'dart:io';

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
    final envelope = jsonEncode({
      'schema': 1,
      'suite': 'vm-sweep',
      'scenario': 's',
      'rev': {'sha': 'abc12345', 'date': '2026-07-01T00:00:00Z'},
      'ts': '2026-07-01T01:00:00Z',
      'env': {'os': 'linux'},
      'metrics': {'p50OpenMs': 1.5},
    });
    final verdict = jsonEncode({
      'date': '2026-07-01T04:00:00Z',
      'sha': 'abc12345',
      'verdict': 'regressed',
      'checks': {'nightly': 'regressed'},
    });
    const junk = ['null', '[]', '7', '"text"', 'true', '{not json'];
    File('${history.path}/vm-sweep.ndjson')
        .writeAsStringSync([envelope, ...junk, ''].join('\n'));
    File('${history.path}/nightly-verdicts.jsonl')
        .writeAsStringSync([...junk, verdict, ''].join('\n'));
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
            html.contains('class="red"') &&
            html.contains('1 runs on record'),
        'dashboard: the good records around them still render');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

void main() {
  _testRatioCheck();
  _testWorkflowBudget();
  _testDashboardRobustness();
  if (_failures > 0) {
    print('$_failures check(s) failed');
    exit(1);
  }
  print('all perf-nightly checks passed');
}
