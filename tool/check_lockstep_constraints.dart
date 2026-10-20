// Enforces the workspace's lockstep versioning invariant.
//
// The core packages in this monorepo are released together at a single
// version. Independently versioned companion packages still depend on that
// exact current core floor. Because of that, whenever one workspace package
// depends on another, its
// dependency lower bound MUST equal that sibling's current version
// (`sibling: ^<sibling.version>`). A looser bound - e.g. `pdf_document: ^1.2.0`
// while the editor calls an API that pdf_document only grew in 1.2.3 - makes
// pub.dev's "compatible with dependency constraint lower bounds" downgrade
// analysis fail, because that check resolves each sibling to its *minimum*
// allowed version and then compiles. The code won't compile against the old
// API surface, so the package scores 0/20 on that metric.
//
// This script is the cheap, deterministic guard for that invariant. CI runs it
// on every push/PR (see .github/workflows/ci.yml), so a stale lower bound
// fails the build instead of silently shipping a 0/20 release.
//
// Usage (from the repo root): `dart run tool/check_lockstep_constraints.dart`

import 'dart:io';

void main() {
  final root = Directory.current;
  final rootPubspec = File('${root.path}/pubspec.yaml');
  if (!rootPubspec.existsSync()) {
    stderr.writeln('Run from the repo root (no ./pubspec.yaml found).');
    exit(2);
  }

  // Workspace member directories, read from the root `workspace:` list.
  final memberDirs = _workspaceMembers(rootPubspec.readAsStringSync());

  // name -> version for every workspace package that declares a version.
  final versions = <String, String>{};
  final pubspecs = <String, File>{};
  for (final dir in memberDirs) {
    final file = File('${root.path}/$dir/pubspec.yaml');
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    final name = _scalar(text, 'name');
    final version = _scalar(text, 'version');
    if (name == null) continue;
    pubspecs[name] = file;
    if (version != null) versions[name] = _baseVersion(version);
  }

  final violations = <String>[];

  for (final entry in pubspecs.entries) {
    final ownName = entry.key;
    final text = entry.value.readAsStringSync();
    for (final dep in _dependencyConstraints(text)) {
      // Only workspace-internal deps are governed by the lockstep rule.
      final expected = versions[dep.name];
      if (expected == null) continue;
      final lower = dep.lowerBound;
      if (lower == null) {
        violations.add(
          '$ownName: dependency `${dep.name}: ${dep.raw}` has no caret lower '
          'bound; expected `^$expected`.',
        );
        continue;
      }
      if (lower != expected) {
        violations.add(
          '$ownName: `${dep.name}: ${dep.raw}` pins lower bound $lower but '
          '${dep.name} is at $expected - use `^$expected`.',
        );
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln(
      'Lockstep constraint check failed. Workspace packages must depend on '
      'each other at the current release version (`^<version>`):\n',
    );
    for (final v in violations) {
      stderr.writeln('  - $v');
    }
    stderr.writeln(
      '\nFix the lower bounds above (or run `dart pub upgrade --tighten`) and '
      're-run. See dart.dev/go/downgrade-testing.',
    );
    exit(1);
  }

  stdout.writeln(
    'Lockstep constraints OK: ${pubspecs.length} workspace packages, all '
    'inter-package lower bounds match their current versions.',
  );
}

/// Directories listed under the root pubspec's `workspace:` block.
List<String> _workspaceMembers(String rootText) {
  final lines = rootText.split('\n');
  final members = <String>[];
  var inBlock = false;
  for (final line in lines) {
    if (RegExp(r'^workspace:\s*$').hasMatch(line)) {
      inBlock = true;
      continue;
    }
    if (inBlock) {
      final m = RegExp(r'^\s+-\s+(\S+)').firstMatch(line);
      if (m != null) {
        members.add(m.group(1)!);
        continue;
      }
      // A non-list, non-blank line ends the block.
      if (line.trim().isNotEmpty && !line.startsWith(' ')) break;
    }
  }
  return members;
}

/// Reads a top-level scalar key (`name`, `version`) from a pubspec.
String? _scalar(String text, String key) {
  final m =
      RegExp('^$key:\\s*(.+?)\\s*\$', multiLine: true).firstMatch(text);
  if (m == null) return null;
  return m.group(1)!.replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
}

/// Strips build/pre-release metadata: `1.2.3+6` -> `1.2.3`.
String _baseVersion(String v) => v.split(RegExp(r'[+-]')).first.trim();

class _Dep {
  _Dep(this.name, this.raw, this.lowerBound);
  final String name;
  final String raw;
  final String? lowerBound; // base version of the caret/range floor, or null.
}

/// Dependency lines of the form `  name: <version constraint>` inside the
/// runtime `dependencies:` block. `dev_dependencies:` are intentionally
/// excluded: they don't reach consumers and aren't part of pub.dev's
/// downgrade analysis (which only compiles `lib/`), and pinning them in
/// lockstep would create a publish-ordering cycle (e.g. pdf_cos dev-depends
/// on pdf_test_fixtures, which depends on pdf_cos). Path/git/sdk deps and
/// nested-map specs (no inline version) are skipped.
List<_Dep> _dependencyConstraints(String text) {
  final lines = text.split('\n');
  final deps = <_Dep>[];
  var inDeps = false;
  for (final line in lines) {
    if (RegExp(r'^dependencies:\s*$').hasMatch(line)) {
      inDeps = true;
      continue;
    }
    // Any other unindented key ends the current block.
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
      inDeps = false;
      continue;
    }
    if (!inDeps) continue;
    // Two-space indented `name: value` (deeper indent = nested map content).
    final m = RegExp(r'^  (\w[\w-]*):\s*(.*)$').firstMatch(line);
    if (m == null) continue;
    final name = m.group(1)!;
    final value = m.group(2)!.trim();
    if (value.isEmpty) continue; // nested map (path:/git:/sdk: on next lines)
    final floor = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(value);
    deps.add(_Dep(name, value, floor == null ? null : floor.group(1)));
  }
  return deps;
}
