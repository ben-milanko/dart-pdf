// perf-nightly's reading of its own state on the perf-data branch
// (.github/workflows/perf-nightly.yml). Standalone Dart - no package imports:
//
//   dart tool/perf/nightly_state.dart resolve --head <sha> --run-id <id>
//       [--ref perf-data] [--now <iso8601>]
//   dart tool/perf/nightly_state.dart drop-run --commit <sha> [--dir <tree>]
//
// `resolve` prints KEY=VALUE lines for $GITHUB_OUTPUT (and says why on
// stderr):
//   base=         the perf-data commit tonight's checks read. The tip, except
//                 on a re-run: then the parent of this run's first append, so
//                 attempt 2 sees exactly what attempt 1 saw.
//   sha= rule=    the nightly ratio check's baseline and the rule that chose
//                 it (resolveBaseline below).
//   accepted_due= whether the weekly accepted check is overdue (acceptedDue).
//   run_commit=   this run's latest append on perf-data, when an earlier
//                 attempt made one: the append replaces it (drop-run) rather
//                 than recording the night twice.
//   superseded=   true when a later night is already recorded after this
//                 run's: the re-run then leaves perf-data alone.
//
// `drop-run` removes the history lines <commit> appended from the working
// tree at --dir (a perf-data worktree), so the append that follows replaces
// that attempt's night.
import 'dart:convert';
import 'dart:io';

typedef NightRecord = Map<String, Object?>;

/// The trailer perf-nightly puts on each night's perf-data commit
/// (`Perf-Nightly-Run: <github.run_id>`), so a re-run can find its night.
const nightTrailer = 'Perf-Nightly-Run';

/// The verdict records in [text] (history/nightly-verdicts.jsonl), oldest
/// first. A line that is not a JSON object with a non-empty string `sha` is
/// skipped, so one bad line never decides the baseline.
List<NightRecord> parseRecords(String text) {
  final records = <NightRecord>[];
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is Map<String, Object?> && _str(decoded['sha']) != null) {
      records.add(decoded);
    }
  }
  return records;
}

/// The commit of the last readable envelope in [text] (a vm-sweep history).
String? lastEnvelopeSha(String text) {
  final lines = const LineSplitter().convert(text);
  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trim().isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(lines[i]);
    } on FormatException {
      continue;
    }
    if (decoded is Map && decoded['rev'] is Map) {
      final sha = _str((decoded['rev'] as Map)['sha']);
      if (sha != null) return sha;
    }
  }
  return null;
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

String? _check(NightRecord r, String name) {
  final checks = r['checks'];
  return checks is Map ? _str(checks[name]) : null;
}

String _short(String? sha) =>
    sha == null ? '-' : (sha.length > 8 ? sha.substring(0, 8) : sha);

/// The nightly ratio check's baseline for tonight.
class Baseline {
  const Baseline(this.sha, this.rule, this.why);

  /// Null when there is nothing to compare against (the check skips).
  final String? sha;

  /// previous | recheck | carry | unchanged | vm-sweep-tail | none
  final String rule;
  final String why;
}

/// Picks the nightly baseline from the verdict [records] (oldest first).
///
/// - `previous`: the last recorded night's commit - the ratchet.
/// - `recheck`: the last night is at [head] too (a re-run, a dispatch on the
///   same commit, or a night with no new commits) and its nightly check read
///   `regressed` or `error`: repeat that night's comparison. Comparing HEAD
///   with itself would read green while the regression is still there.
/// - `unchanged`: the last night is at [head] and read ok (or skipped):
///   nothing new to measure, the check skips.
/// - `carry`: the last night's nightly check read `error` - it judged
///   nothing, e.g. it ran out of time - so its range is carried into
///   tonight's instead of being absorbed. Once: a night whose own baseline was
///   already carried (or re-checked past the previous night) is not carried
///   again, so a baseline that keeps failing cannot freeze the ratchet.
/// - `vm-sweep-tail`: no verdict file yet ([haveVerdicts] false) - the last
///   vm-sweep envelope, as before the verdict file existed.
/// - `none`: nothing usable (the check skips).
Baseline resolveBaseline({
  required List<NightRecord> records,
  required bool haveVerdicts,
  required String head,
  String? vmSweepTail,
}) {
  if (!haveVerdicts) {
    return vmSweepTail == null
        ? const Baseline(null, 'none', 'no nightly on record yet')
        : Baseline(vmSweepTail, 'vm-sweep-tail',
            'no verdict file yet: the last vm-sweep envelope');
  }
  if (records.isEmpty) {
    return const Baseline(
        null, 'none', 'nightly-verdicts.jsonl holds no readable record');
  }
  final tail = records.last;
  final tailSha = tail['sha']! as String;
  final nightly = _check(tail, 'nightly');
  final prev = _str(tail['prevSha']);
  if (tailSha == head) {
    if ((nightly == 'regressed' || nightly == 'error') &&
        prev != null &&
        prev != head) {
      return Baseline(
          prev,
          'recheck',
          'the last night at this commit read $nightly vs ${_short(prev)}: '
              'repeating that comparison');
    }
    return Baseline(head, 'unchanged',
        'the last night was this commit and read ${nightly ?? '?'}');
  }
  if (nightly == 'error' && prev != null && prev != head) {
    // The night before the tail's commit was first measured: the tail's
    // baseline was the plain previous night only if it is that night's sha.
    String? before;
    for (var i = records.length - 1; i >= 0; i--) {
      if (records[i]['sha'] != tailSha) {
        before = records[i]['sha']! as String;
        break;
      }
    }
    if (before == null || before == prev) {
      return Baseline(
          prev,
          'carry',
          'the last night (${_short(tailSha)}) errored without judging its '
              'range: carrying its baseline ${_short(prev)} once');
    }
  }
  return Baseline(tailSha, 'previous', 'the last nightly');
}

/// Whether the weekly accepted check is overdue: no night on record ran it,
/// or the last one that did (ok, regressed or error) is [every] old. The
/// workflow also runs it every Sunday; this catches a Sunday run that GitHub
/// dropped or that failed before its checks.
({bool due, String why}) acceptedDue(List<NightRecord> records, DateTime now,
    {Duration every = const Duration(days: 7)}) {
  for (final r in records.reversed) {
    final state = _check(r, 'accepted');
    if (state != 'ok' && state != 'regressed' && state != 'error') continue;
    final date =
        r['date'] is String ? DateTime.tryParse(r['date']! as String) : null;
    if (date == null) continue;
    final age = now.difference(date);
    return (
      due: age >= every,
      why: 'the last accepted check ran ${age.inHours} h ago',
    );
  }
  return (due: true, why: 'no accepted check on record');
}

/// [tip] without the lines that [after] added to [before] (a history file at
/// an append commit and its parent). Each added line is removed once, from
/// the end, so lines appended since - a later night, a backfill - stay put.
/// Returns the new text and how many added lines were not found in [tip].
({String text, int missing}) dropAppended(
    String tip, String before, String after) {
  final pending = <String, int>{};
  for (final line in const LineSplitter().convert(after)) {
    pending[line] = (pending[line] ?? 0) + 1;
  }
  for (final line in const LineSplitter().convert(before)) {
    final n = pending[line];
    if (n != null) pending[line] = n - 1;
  }
  pending.removeWhere((_, n) => n <= 0);
  final lines = const LineSplitter().convert(tip);
  final kept = <String>[];
  for (var i = lines.length - 1; i >= 0; i--) {
    final n = pending[lines[i]];
    if (n != null && n > 0) {
      pending[lines[i]] = n - 1;
      continue;
    }
    kept.add(lines[i]);
  }
  final text = kept.reversed.map((l) => '$l\n').join();
  return (text: text, missing: pending.values.fold(0, (a, b) => a + b));
}

ProcessResult _git(List<String> args, {String? dir}) =>
    Process.runSync('git', args,
        workingDirectory: dir, stdoutEncoding: utf8, stderrEncoding: utf8);

/// `git show <rev>:<path>`, or null when it does not exist.
String? _show(String rev, String path, {String? dir}) {
  final r = _git(['show', '$rev:$path'], dir: dir);
  return r.exitCode == 0 ? r.stdout as String : null;
}

String? _commit(String rev, {String? dir}) {
  final r = _git(['rev-parse', '-q', '--verify', '$rev^{commit}'], dir: dir);
  return r.exitCode == 0 ? (r.stdout as String).trim() : null;
}

/// perf-data commits in [range] that a nightly appended (their
/// [nightTrailer]), newest first: [runId]'s only, or any run's.
List<String> _nightCommits(String range, {String? runId}) {
  if (runId != null && !RegExp(r'^[0-9]+$').hasMatch(runId)) return const [];
  final r = _git([
    'log', '--format=%H', //
    '--grep=^$nightTrailer: ${runId ?? '[0-9][0-9]*'}\$', range,
  ]);
  if (r.exitCode != 0) return const [];
  return [
    for (final l in const LineSplitter().convert(r.stdout as String))
      if (l.trim().isNotEmpty) l.trim(),
  ];
}

void _resolve(Map<String, String> args) {
  final head = args['head'] ?? '';
  final runId = args['run-id'] ?? '';
  final now =
      args['now'] != null ? DateTime.parse(args['now']!) : DateTime.now();
  final tip = _commit(args['ref'] ?? 'perf-data');
  final out = <String, String>{};
  void why(String text) => stderr.writeln(text);

  var base = tip;
  var runCommit = '';
  var superseded = false;
  if (tip != null) {
    final mine = _nightCommits(tip, runId: runId);
    if (mine.isNotEmpty) {
      // A re-run: an earlier attempt of this run already appended. Read the
      // history as it stood before that attempt, and replace its night -
      // unless another night has been appended since, which must stay the
      // last one (it is the next night's baseline).
      runCommit = mine.first;
      base = _commit('${mine.last}^');
      superseded = _nightCommits('${mine.first}..$tip').isNotEmpty;
      why('re-run of run $runId: reading perf-data at ${_short(base)}, before '
          'its first append ${_short(mine.last)}');
      if (superseded) {
        why('a later night is already recorded after this run\'s: perf-data '
            'keeps the earlier attempt');
      }
    }
  }
  final verdictsText =
      base == null ? null : _show(base, 'history/nightly-verdicts.jsonl');
  final records = parseRecords(verdictsText ?? '');
  final baseline = resolveBaseline(
    records: records,
    haveVerdicts: verdictsText != null,
    head: head,
    vmSweepTail: verdictsText == null && base != null
        ? lastEnvelopeSha(_show(base, 'history/vm-sweep.ndjson') ?? '')
        : null,
  );
  final due = acceptedDue(records, now);
  why('previous nightly: ${baseline.sha ?? 'none'} (${baseline.rule}: '
      '${baseline.why})');
  why('accepted check ${due.due ? 'due' : 'not due'}: ${due.why}');
  out['base'] = base ?? '';
  out['sha'] = baseline.sha ?? '';
  out['rule'] = baseline.rule;
  out['accepted_due'] = '${due.due}';
  out['accepted_why'] = due.why;
  out['run_commit'] = runCommit;
  out['superseded'] = '$superseded';
  out.forEach((k, v) => stdout.writeln('$k=$v'));
}

void _dropRun(Map<String, String> args) {
  final commit = args['commit'];
  final dir = args['dir'] ?? '.';
  if (commit == null || commit.isEmpty) _usage();
  final files = _git([
    'diff-tree', '--no-commit-id', '--name-only', '-r', '--root', //
    commit, '--', 'history',
  ], dir: dir);
  if (files.exitCode != 0) {
    stderr.writeln('drop-run: ${files.stderr}');
    exit(1);
  }
  final hasParent = _commit('$commit^', dir: dir) != null;
  for (final path in const LineSplitter().convert(files.stdout as String)) {
    if (path.trim().isEmpty) continue;
    final file = File('$dir/$path');
    if (!file.existsSync()) continue;
    final before = hasParent ? _show('$commit^', path, dir: dir) ?? '' : '';
    final after = _show(commit, path, dir: dir) ?? '';
    final dropped = dropAppended(file.readAsStringSync(), before, after);
    file.writeAsStringSync(dropped.text);
    stderr.writeln('drop-run: $path without ${_short(commit)}\'s lines'
        '${dropped.missing > 0 ? ' (${dropped.missing} already gone)' : ''}');
  }
}

Never _usage() {
  stderr.writeln('usage: nightly_state.dart resolve --head <sha> '
      '--run-id <id> [--ref perf-data] [--now <iso8601>]\n'
      '       nightly_state.dart drop-run --commit <sha> [--dir <tree>]');
  exit(2);
}

void main(List<String> argv) {
  if (argv.isEmpty) _usage();
  final args = <String, String>{};
  for (var i = 1; i < argv.length; i++) {
    if (!argv[i].startsWith('--') || i + 1 >= argv.length) _usage();
    args[argv[i].substring(2)] = argv[++i];
  }
  switch (argv.first) {
    case 'resolve':
      _resolve(args);
    case 'drop-run':
      _dropRun(args);
    default:
      _usage();
  }
}
