// Shared helpers for the perf tooling: locate the repo root, and build the
// `rev` / `env` envelope sections (tool/perf/SCHEMA.md) that make a result
// comparable across machines and weeks. Tool-only code - dart:io is fine
// here (never under lib/).
import 'dart:io';

/// Walks up from [from] (defaults to the running script) to the workspace
/// root - the directory holding both `pubspec.yaml` and `.git`.
String findRepoRoot([String? from]) {
  var dir = Directory(from ?? File.fromUri(Platform.script).parent.path);
  while (true) {
    final hasPubspec = File('${dir.path}/pubspec.yaml').existsSync();
    final hasGit = FileSystemEntity.typeSync('${dir.path}/.git') !=
        FileSystemEntityType.notFound;
    if (hasPubspec && hasGit) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repo root not found above ${Platform.script}');
    }
    dir = parent;
  }
}

String _git(String repoRoot, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: repoRoot);
  return r.exitCode == 0 ? (r.stdout as String).trim() : '';
}

/// The `rev` envelope section: commit, branch, dirty flag, commit date.
Map<String, Object?> revInfo(String repoRoot) => {
      'sha': _git(repoRoot, ['rev-parse', 'HEAD']),
      'branch': _git(repoRoot, ['rev-parse', '--abbrev-ref', 'HEAD']),
      'dirty': _git(repoRoot, ['status', '--porcelain']).isNotEmpty,
      'date': _git(repoRoot, ['show', '-s', '--format=%cI', 'HEAD']),
    };

/// The `env` envelope section: platform, CPU count, Dart version, CI flag.
Map<String, Object?> envInfo() => {
      'os': '${Platform.operatingSystem}-${_arch()}',
      'osVersion': Platform.operatingSystemVersion,
      'cpus': Platform.numberOfProcessors,
      'dart': Platform.version.split(' ').first,
      'ci': Platform.environment['CI'] == 'true',
      'runner': Platform.environment['RUNNER_OS'] != null
          ? 'github-actions'
          : 'local',
    };

String _arch() {
  final r = Process.runSync('uname', ['-m']);
  return r.exitCode == 0 ? (r.stdout as String).trim() : 'unknown';
}

/// UTC timestamp for the `ts` envelope field.
String isoNow() => DateTime.now().toUtc().toIso8601String();

/// p-th percentile (0-100) of [values]; 0 when empty.
double percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.of(values)..sort();
  final rank = (p / 100) * (sorted.length - 1);
  final lo = rank.floor(), hi = rank.ceil();
  if (lo == hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - lo);
}
