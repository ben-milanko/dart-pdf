// Enforces 100% key coverage across every localization bundle's ARB files.
//
// gen-l10n is lenient: a translation ARB that is *missing* keys still
// generates - the lookups just fall back to the template (English) at runtime.
// That silence is exactly what we don't want, because a half-translated locale
// ships looking finished while random strings render in English. This gate is
// the deterministic guard: for each bundle it compares every `<prefix>_<loc>.arb`
// against its `<prefix>_en.arb` template and fails the build when a locale is
// missing keys, carries keys the template doesn't have, mislabels its
// `@@locale`, or uses an interpolation placeholder the template never declared
// (a common translator typo like `{cont}` for `{count}`).
//
// Placeholder note: only bare `{name}` interpolations are compared. The ICU
// selector forms (`{count, plural, ...}` / `{x, select, ...}`) are validated
// structurally by gen-l10n itself, so we don't re-check them here - we only
// make sure a translation doesn't introduce a stray/misspelled interpolation.
//
// CI runs it on every push/PR (see .github/workflows/ci.yml).
//
// Usage (from the repo root): `dart run tool/check_arb_coverage.dart`

import 'dart:convert';
import 'dart:io';

/// The localization bundles: each is a directory holding `<prefix>_<locale>.arb`
/// files with `<prefix>_en.arb` as the template.
const _bundles = <({String dir, String prefix})>[
  (dir: 'packages/dart_pdf_editor/lib/l10n', prefix: 'dart_pdf_editor'),
  (dir: 'app/lib/l10n', prefix: 'app'),
  (dir: 'packages/dart_pdf_editor/example/lib/l10n', prefix: 'app'),
];

void main() {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run from the repo root (no ./pubspec.yaml found).');
    exit(2);
  }

  final problems = <String>[];
  var localesChecked = 0;

  for (final bundle in _bundles) {
    final dir = Directory(bundle.dir);
    if (!dir.existsSync()) {
      problems.add('${bundle.dir}: directory not found');
      continue;
    }
    final templateFile = File('${bundle.dir}/${bundle.prefix}_en.arb');
    if (!templateFile.existsSync()) {
      problems.add('${bundle.dir}: template ${bundle.prefix}_en.arb not found');
      continue;
    }

    final template = _readArb(templateFile, problems);
    if (template == null) continue;
    final templateKeys = _messageKeys(template);
    // Placeholders the template legitimately uses, per key - the allowed set
    // for the translation of that key.
    final templatePlaceholders = {
      for (final key in templateKeys)
        key: _placeholders(template[key] as String)
          ..addAll(_declaredPlaceholders(template, key)),
    };

    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match =
          RegExp('^${bundle.prefix}_(.+)\\.arb\$').firstMatch(name);
      if (match == null) continue;
      final locale = match.group(1)!;
      if (locale == 'en') continue; // the template itself
      localesChecked++;

      final arb = _readArb(entity, problems);
      if (arb == null) continue;
      final where = '${bundle.dir}/$name';

      final declaredLocale = arb['@@locale'];
      if (declaredLocale != locale) {
        problems.add('$where: @@locale is "$declaredLocale", '
            'expected "$locale" (from the filename)');
      }

      final keys = _messageKeys(arb);
      final missing = templateKeys.difference(keys).toList()..sort();
      final extra = keys.difference(templateKeys).toList()..sort();
      if (missing.isNotEmpty) {
        problems.add('$where: missing ${missing.length} key(s): '
            '${_preview(missing)}');
      }
      if (extra.isNotEmpty) {
        problems.add('$where: ${extra.length} key(s) not in the template: '
            '${_preview(extra)}');
      }

      for (final key in keys.intersection(templateKeys)) {
        final used = _placeholders(arb[key] as String);
        final allowed = templatePlaceholders[key]!;
        final stray = used.difference(allowed).toList()..sort();
        if (stray.isNotEmpty) {
          problems.add('$where: key "$key" uses undeclared '
              'placeholder(s): ${stray.map((p) => '{$p}').join(', ')}');
        }
      }
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('ARB coverage check failed:\n');
    for (final problem in problems) {
      stderr.writeln('  - $problem');
    }
    stderr.writeln('\nEvery non-English ARB must have the exact same keys as '
        'its _en.arb template.');
    exit(1);
  }

  stdout.writeln('ARB coverage OK: $localesChecked locale file(s) across '
      '${_bundles.length} bundles match their templates.');
}

/// Parses [file] as a JSON ARB map, recording a problem and returning null on
/// malformed JSON.
Map<String, dynamic>? _readArb(File file, List<String> problems) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      problems.add('${file.path}: not a JSON object');
      return null;
    }
    return decoded;
  } on FormatException catch (e) {
    problems.add('${file.path}: invalid JSON ($e)');
    return null;
  }
}

/// The translatable message keys in [arb] - everything that isn't `@`-prefixed
/// metadata (`@@locale`, `@keyName`).
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    {for (final key in arb.keys) if (!key.startsWith('@')) key};

/// The bare `{name}` interpolation placeholders used in [value] (not the ICU
/// `{x, plural/select, ...}` selectors, whose `{x,` shape doesn't match).
Set<String> _placeholders(String value) => RegExp(r'\{(\w+)\}')
    .allMatches(value)
    .map((m) => m.group(1)!)
    .toSet();

/// Placeholder names the template's `@key` metadata declares for [key].
Set<String> _declaredPlaceholders(Map<String, dynamic> template, String key) {
  final meta = template['@$key'];
  if (meta is! Map) return const {};
  final placeholders = meta['placeholders'];
  if (placeholders is! Map) return const {};
  return {for (final name in placeholders.keys) name.toString()};
}

String _preview(List<String> keys) {
  const limit = 8;
  if (keys.length <= limit) return keys.join(', ');
  return '${keys.take(limit).join(', ')}, … (+${keys.length - limit} more)';
}
