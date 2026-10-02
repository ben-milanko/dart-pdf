// Keeps the editor's design-system coupling from growing and keeps the
// headless core separable from it (see the material_ui plan: 6.0 moved the
// libraries from package:flutter/material.dart to material_ui, and the
// editor runs under material_ui, legacy Material, Cupertino and plain widgets
// hosts). "Design library" below means any of package:material_ui,
// package:cupertino_ui, package:flutter/material.dart and
// package:flutter/cupertino.dart. Three ratchets, all may only shrink, and
// one hard rule:
//
// (a) Design-library importers. Every file under the scanned packages' lib/
//     that imports or exports a design library is listed in the baseline. A
//     file that starts importing one fails; a listed file that stopped
//     importing it fails too, with a hint to tighten the baseline.
//
// (b) Headless closures. The transitive import closure of the editing
//     controller and of PdfPageView must reach no design library, so a host
//     without Material can drive the editor and draw pages. The walk follows
//     relative and package: imports/exports (all conditional-import branches)
//     through the workspace packages and their pub dependencies. It stops at
//     the Flutter SDK's own libraries (package:flutter/widgets.dart importing
//     cupertino internals is the SDK's business) and allows exactly one known
//     edge: the generated localizations under lib/l10n/ importing
//     package:flutter_localizations, which pulls in flutter/material.
//
// (c) Raw component counters, over the editor's and the printing package's
//     lib/ (outside the editor's lib/src/design/ and lib/src/legacy/): uses
//     of showMenu, showModalBottomSheet, ScaffoldMessenger and
//     DropdownButton(FormField), and text fields (TextField, TextFormField,
//     SelectableText) without the shared context menu, per file. These are
//     the calls a non-Material host cannot survive; they go through
//     library-owned seams instead (the presenter, PdfDropdown,
//     pdfTextContextMenu). Comments do not count.
//
// (d) Legacy imports. Only files under the editor's lib/src/legacy/ (the
//     legacy-host bridge) may import package:flutter/material.dart or
//     package:flutter/cupertino.dart, and only they and the generated
//     lib/l10n/ may import package:flutter_localizations. Not a ratchet:
//     anything else fails outright.
//
// (e) Cupertino separation. The Cupertino presenter (lib/src/cupertino/) is
//     reachable only through package:dart_pdf_editor/cupertino.dart: the
//     import closure of lib/dart_pdf_editor.dart must not reach it, so a
//     Material host never compiles it. Not a ratchet.
//
// The baseline is tool/design_imports_baseline.json. After removing a
// Material import or a raw use, run with --update-baseline to tighten it; it
// refuses to record growth (edit the JSON by hand, in review, if a new
// Material importer is genuinely needed).
//
// CI runs it after `flutter pub get` (the dependency walk reads
// .dart_tool/package_config.json). Tests: tool/check_design_imports_test.dart.
//
// Usage (from the repo root): dart run tool/check_design_imports.dart
//                              [--update-baseline]

import 'dart:convert';
import 'dart:io';

const baselinePath = 'tool/design_imports_baseline.json';

/// Package lib/ trees whose design-library importers are allowlisted (a)
/// and whose legacy imports are policed (d).
const scannedLibs = [
  'packages/dart_pdf_editor/lib',
  'packages/dart_pdf_printing/lib',
  'packages/dart_pdf_editor_flutter_gpu/lib',
];

/// The one subtree allowed to import the legacy design libraries (d).
const legacyBridgeDir = 'packages/dart_pdf_editor/lib/src/legacy/';

/// Entry points whose import closure must stay Material-free (b).
const headlessRoots = [
  'packages/dart_pdf_editor/lib/src/editing/editing_controller.dart',
  'packages/dart_pdf_editor/lib/src/pdf_page_view.dart',
];

/// The subtree only lib/cupertino.dart may reach (e), and the libraries
/// whose closures must not reach it.
const cupertinoOnlyDir = 'packages/dart_pdf_editor/lib/src/cupertino/';
const cupertinoFreeRoots = [
  'packages/dart_pdf_editor/lib/dart_pdf_editor.dart'
];

/// Where counters (c) look, and the subtrees they skip (the seams
/// themselves: the shared chrome and the legacy-host bridge).
const counterLibs = [
  'packages/dart_pdf_editor/lib',
  'packages/dart_pdf_printing/lib',
];
const counterExempt = [
  'packages/dart_pdf_editor/lib/src/design/',
  legacyBridgeDir,
];

/// The raw component uses counted by (c), each over comment-stripped code.
final counters = <String, int Function(String code)>{
  'showMenu': _matches(RegExp(r'\bshowMenu\s*[<(]')),
  'showModalBottomSheet': _matches(RegExp(r'\bshowModalBottomSheet\s*[<(]')),
  'ScaffoldMessenger': _matches(RegExp(r'\bScaffoldMessenger\b')),
  'DropdownButton': _matches(RegExp(r'\bDropdownButton(FormField)?\b')),
  'TextFieldWithoutMenu': textFieldsWithoutSharedMenu,
};

int Function(String) _matches(RegExp pattern) =>
    (code) => pattern.allMatches(code).length;

/// The context-menu builders that re-inject what a non-Material host lacks
/// (lib/src/design/material_host.dart).
const sharedTextMenus = ['pdfTextContextMenu', 'pdfStockTextContextMenu'];

/// `TextField`, `TextFormField` and `SelectableText` constructions in [code]
/// whose arguments do not pass one of the [sharedTextMenus] as their
/// `contextMenuBuilder`. Their stock menu builds in the root overlay, where a
/// non-Material host has no MaterialLocalizations.
int textFieldsWithoutSharedMenu(String code) {
  var count = 0;
  final call =
      RegExp(r'\b(TextField|TextFormField|SelectableText)(\.rich)?\s*\(');
  for (final m in call.allMatches(code)) {
    final args = _argumentsAt(code, m.end - 1);
    final menu = args.indexOf('contextMenuBuilder:');
    if (menu < 0 ||
        !sharedTextMenus.any((name) => args.indexOf(name, menu) >= 0)) {
      count++;
    }
  }
  return count;
}

/// The text between the `(` at [open] and its matching `)` (quotes are
/// skipped; [code] is comment-stripped).
String _argumentsAt(String code, int open) {
  var depth = 0;
  String? quote;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (code.startsWith(quote, i)) {
        i += quote.length - 1;
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = code.startsWith(c * 3, i) ? c * 3 : c;
      i += quote.length - 1;
    } else if (c == '(') {
      depth++;
    } else if (c == ')' && --depth == 0) {
      return code.substring(open + 1, i);
    }
  }
  return code.substring(open + 1);
}

/// The legacy design libraries (d).
const legacyUris = {
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
};

/// Whether [uri] is a design library: legacy Material/Cupertino, or any
/// library of the material_ui / cupertino_ui packages.
bool isDesignUri(String uri) =>
    legacyUris.contains(uri) ||
    uri.startsWith('package:material_ui/') ||
    uri.startsWith('package:cupertino_ui/');

void main(List<String> args) {
  final update = args.contains('--update-baseline');
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run from the repo root (no ./pubspec.yaml found).');
    exit(2);
  }
  final resolver = PackageResolver.load(Directory.current.path);
  final current = scan(Directory.current.path, resolver);
  final baselineFile = File(baselinePath);
  final baseline = baselineFile.existsSync()
      ? DesignBaseline.fromJson(
          jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>)
      : DesignBaseline.empty();

  final problems = <String>[...current.problems];
  final ratchet = compare(baseline, current.baseline);
  if (update) {
    // A missing baseline is being created, not grown.
    if (baselineFile.existsSync() && ratchet.growth.isNotEmpty) {
      stderr.writeln('Refusing to record growth in $baselinePath:');
      ratchet.growth.forEach((p) => stderr.writeln('  - $p'));
      exit(1);
    }
    baselineFile.writeAsStringSync(current.baseline.encode());
    print('Wrote $baselinePath.');
  } else {
    problems.addAll(ratchet.growth);
    problems.addAll(ratchet.stale.map((s) =>
        '$s - tighten the baseline: dart run tool/check_design_imports.dart '
        '--update-baseline'));
  }

  if (problems.isNotEmpty) {
    stderr.writeln('Design import check failed:');
    for (final p in problems) {
      stderr.writeln('  - $p');
    }
    exit(1);
  }
  final c = current.baseline;
  print('Design import check passed: ${c.materialImporters.length} '
      'allowlisted design-library importers, legacy imports only under '
      '$legacyBridgeDir, ${headlessRoots.length} headless closures clean, '
      '$cupertinoOnlyDir unreachable from the main library, '
      'counters ${{
    for (final e in c.counters.entries)
      e.key: e.value.values.fold<int>(0, (a, b) => a + b)
  }}.');
}

/// The checked-in state: allowlisted importers + per-file counters.
class DesignBaseline {
  DesignBaseline(this.materialImporters, this.counters);
  DesignBaseline.empty() : this(<String>{}, <String, Map<String, int>>{});

  factory DesignBaseline.fromJson(Map<String, dynamic> json) => DesignBaseline({
        for (final f in (json['materialImporters'] as List? ?? const []))
          f as String
      }, {
        for (final e in ((json['counters'] as Map?) ?? const {}).entries)
          e.key as String: {
            for (final f in (e.value as Map).entries)
              f.key as String: f.value as int
          }
      });

  final Set<String> materialImporters;
  final Map<String, Map<String, int>> counters;

  String encode() {
    final sortedCounters = {
      for (final name in counters.keys.toList()..sort())
        name: {
          for (final f in counters[name]!.keys.toList()..sort())
            f: counters[name]![f]
        }
    };
    return '${const JsonEncoder.withIndent('  ').convert({
          'materialImporters': materialImporters.toList()..sort(),
          'counters': sortedCounters,
        })}\n';
  }
}

class ScanResult {
  ScanResult(this.baseline, this.problems);
  final DesignBaseline baseline;
  final List<String> problems;
}

class Ratchet {
  Ratchet(this.growth, this.stale);
  final List<String> growth;
  final List<String> stale;
}

/// Scans [root] (the repo root) for all three checks.
ScanResult scan(String root, PackageResolver resolver) {
  final importers = <String>{};
  final problems = <String>[];
  for (final lib in scannedLibs) {
    final dir = Directory('$root/$lib');
    if (!dir.existsSync()) continue;
    for (final file in _dartFiles(dir)) {
      final rel = _relative(root, file.path);
      final uris = directiveUris(file.readAsStringSync());
      if (uris.any(isDesignUri)) importers.add(rel);
      problems.addAll(checkLegacyImports(rel, uris));
    }
  }

  final counts = <String, Map<String, int>>{
    for (final name in counters.keys) name: <String, int>{}
  };
  for (final lib in counterLibs) {
    final counterDir = Directory('$root/$lib');
    if (!counterDir.existsSync()) continue;
    for (final file in _dartFiles(counterDir)) {
      final rel = _relative(root, file.path);
      if (counterExempt.any(rel.startsWith)) continue;
      final code = stripComments(file.readAsStringSync());
      counters.forEach((name, count) {
        final n = count(code);
        if (n > 0) counts[name]![rel] = n;
      });
    }
  }

  for (final entry in headlessRoots) {
    problems.addAll(checkClosure(root, entry, resolver));
  }
  for (final entry in cupertinoFreeRoots) {
    problems.addAll(checkNotReached(root, entry, cupertinoOnlyDir, resolver));
  }
  return ScanResult(DesignBaseline(importers, counts), problems);
}

/// Rule (d) for one scanned file at repo-relative [rel] with directive
/// [uris]: legacy design libraries only under [legacyBridgeDir],
/// flutter_localizations only there and in the generated lib/l10n/.
List<String> checkLegacyImports(String rel, List<String> uris) {
  if (rel.startsWith(legacyBridgeDir)) return const [];
  return [
    for (final uri in uris)
      if (legacyUris.contains(uri))
        '$rel imports $uri: only $legacyBridgeDir may use the legacy design '
            'libraries (the library is built on material_ui/cupertino_ui)'
      else if (uri.startsWith('package:flutter_localizations/') &&
          !_isGeneratedL10n(rel))
        '$rel imports $uri: its delegates are the legacy ones; use '
            "material_ui's GlobalMaterialLocalizations (only the generated "
            'lib/l10n/ and $legacyBridgeDir may import it)',
  ];
}

/// Every way [current] is worse than [baseline] (growth) or better (stale).
Ratchet compare(DesignBaseline baseline, DesignBaseline current) {
  final growth = <String>[];
  final stale = <String>[];
  for (final f
      in current.materialImporters.difference(baseline.materialImporters)) {
    growth.add('$f imports a design library (material_ui, cupertino_ui, '
        'flutter/material or flutter/cupertino) and is not in the allowlist. '
        'New code belongs on the widgets layer (lib/src/design/ for shared '
        'chrome).');
  }
  for (final f
      in baseline.materialImporters.difference(current.materialImporters)) {
    stale.add('$f no longer imports a design library (or no longer exists)');
  }
  final names = {...baseline.counters.keys, ...current.counters.keys};
  for (final name in names) {
    final was = baseline.counters[name] ?? const <String, int>{};
    final now = current.counters[name] ?? const <String, int>{};
    for (final f in {...was.keys, ...now.keys}) {
      final a = was[f] ?? 0;
      final b = now[f] ?? 0;
      if (b > a) {
        growth.add('$f: $b raw $name use(s), baseline allows $a. Route it '
            'through a library-owned seam instead.');
      } else if (b < a) {
        stale.add('$f: $b raw $name use(s), baseline still records $a');
      }
    }
  }
  growth.sort();
  stale.sort();
  return Ratchet(growth, stale);
}

/// Walks the import closure of [entry] (repo-relative) and reports every
/// Material importer reached, with the chain that reaches it.
List<String> checkClosure(String root, String entry, PackageResolver resolver) {
  final start = File('$root/$entry').absolute.path;
  if (!File(start).existsSync()) return ['$entry: headless root not found'];
  final parent = <String, String?>{start: null};
  final queue = [start];
  final problems = <String>[];

  List<String> chain(String path) {
    final out = <String>[];
    String? at = path;
    while (at != null) {
      out.add(_display(root, at));
      at = parent[at];
    }
    return out.reversed.toList();
  }

  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final (:uri, :show) in directives(file.readAsStringSync())) {
      if (isDesignUri(uri)) {
        problems.add('$entry must stay Material-free, but '
            '${chain(path).join(' -> ')} imports $uri'
            '${show == null ? '' : ' show ${show.join(', ')}'}');
        continue;
      }
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:flutter_localizations/')) {
        if (_isGeneratedL10n(path)) continue;
        problems.add('$entry must stay Material-free, but '
            '${chain(path).join(' -> ')} imports $uri (only the generated '
            'localizations under lib/l10n/ may)');
        continue;
      }
      // The Flutter SDK's own libraries are terminal: what widgets.dart pulls
      // in internally is not ours to police.
      if (uri.startsWith('package:flutter/') ||
          uri.startsWith('package:sky_engine/')) {
        continue;
      }
      final target = uri.startsWith('package:')
          ? resolver.resolve(uri)
          : File.fromUri(file.uri.resolve(uri)).path;
      if (target == null) continue;
      final normalized = File(target).absolute.path;
      if (parent.containsKey(normalized)) continue;
      parent[normalized] = path;
      queue.add(normalized);
    }
  }
  return problems;
}

/// Rule (e): walks [entry]'s closure through relative and
/// `package:dart_pdf_editor/` imports (nothing else can lead back into the
/// editor's lib/) and reports every file under [dir] it reaches. A missing
/// [entry] reports nothing (the scan's fixtures may not have one).
List<String> checkNotReached(
    String root, String entry, String dir, PackageResolver resolver) {
  final start = File('$root/$entry').absolute.path;
  if (!File(start).existsSync()) return const [];
  final banned = Directory('$root/$dir').absolute.path;
  final parent = <String, String?>{start: null};
  final queue = [start];
  final problems = <String>[];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final (:uri, show: _) in directives(file.readAsStringSync())) {
      final String? target;
      if (uri.startsWith('package:dart_pdf_editor/')) {
        target = resolver.resolve(uri);
      } else if (!uri.contains(':')) {
        target = File.fromUri(file.uri.resolve(uri)).path;
      } else {
        continue;
      }
      if (target == null) continue;
      final normalized = File(target).absolute.path;
      if (parent.containsKey(normalized)) continue;
      parent[normalized] = path;
      if (normalized.startsWith(banned)) {
        final chain = <String>[];
        String? at = normalized;
        while (at != null) {
          chain.add(_display(root, at));
          at = parent[at];
        }
        problems.add('$entry must not reach $dir (a Material host would '
            'compile the Cupertino presenter; only lib/cupertino.dart may '
            'import it), but ${chain.reversed.join(' -> ')} does');
        continue;
      }
      queue.add(normalized);
    }
  }
  return problems;
}

bool _isGeneratedL10n(String path) =>
    path.replaceAll(r'\', '/').contains('/lib/l10n/');

/// Every URI named by an import/export/part directive in [source], including
/// each branch of a conditional import. `part of` is skipped.
List<String> directiveUris(String source) =>
    [for (final d in directives(source)) d.uri];

/// Like [directiveUris], with the directive's `show` names (null when it
/// has no `show` combinator).
List<({String uri, Set<String>? show})> directives(String source) {
  final code = stripComments(source);
  final out = <({String uri, Set<String>? show})>[];
  final directive =
      RegExp(r'^\s*(import|export|part)\b(?!\s+of\b)([^;]*);', multiLine: true);
  final quoted = RegExp(r'''['"]([^'"]+)['"]''');
  final showClause = RegExp(r'\bshow\b([\w\s,]*?)(?=\bhide\b|\bshow\b|$)');
  for (final m in directive.allMatches(code)) {
    final body = m.group(2)!;
    final shows = showClause.allMatches(body).toList();
    final show = shows.isEmpty
        ? null
        : {
            for (final s in shows)
              for (final name in s.group(1)!.split(','))
                if (name.trim().isNotEmpty) name.trim()
          };
    for (final q in quoted.allMatches(body)) {
      final uri = q.group(1)!;
      if (uri.endsWith('.dart')) out.add((uri: uri, show: show));
    }
  }
  return out;
}

/// [source] with `//` and `/* */` comments blanked (string-aware enough for
/// Dart sources: quotes are tracked so `'//'` inside a string survives).
String stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  var raw = false;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (quote != null) {
      out.write(c);
      if (!raw && c == r'\' && i + 1 < source.length) {
        out.write(next);
        i += 2;
        continue;
      }
      if (source.startsWith(quote, i)) {
        out.write(quote.substring(1));
        i += quote.length;
        quote = null;
        continue;
      }
      i++;
      continue;
    }
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      out.write(' ');
      continue;
    }
    if (c == "'" || c == '"') {
      quote = source.startsWith(c * 3, i) ? c * 3 : c;
      raw = i > 0 && source[i - 1] == 'r';
      out.write(quote);
      i += quote.length;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Resolves package: URIs through .dart_tool/package_config.json.
class PackageResolver {
  PackageResolver(this._roots);

  factory PackageResolver.load(String root) {
    final config = File('$root/.dart_tool/package_config.json');
    if (!config.existsSync()) {
      stderr.writeln('No .dart_tool/package_config.json: run '
          '`flutter pub get` at the repo root first.');
      exit(2);
    }
    final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    final roots = <String, Uri>{};
    for (final p in (json['packages'] as List).cast<Map<String, dynamic>>()) {
      final rootUri = config.uri.resolve(p['rootUri'] as String);
      final dir = rootUri.path.endsWith('/') ? rootUri : Uri.parse('$rootUri/');
      roots[p['name'] as String] =
          dir.resolve(p['packageUri'] as String? ?? '');
    }
    return PackageResolver(roots);
  }

  final Map<String, Uri> _roots;

  String? resolve(String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.pathSegments.isEmpty) return null;
    final lib = _roots[parsed.pathSegments.first];
    if (lib == null) return null;
    return File.fromUri(lib.resolve(parsed.pathSegments.skip(1).join('/')))
        .path;
  }
}

Iterable<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

String _relative(String root, String path) {
  final r = Directory(root).absolute.path;
  final p = File(path).absolute.path;
  final prefix = r.endsWith('/') ? r : '$r/';
  return (p.startsWith(prefix) ? p.substring(prefix.length) : p)
      .replaceAll(r'\', '/');
}

String _display(String root, String path) {
  final rel = _relative(root, path);
  if (!rel.startsWith('/')) return rel;
  // A pub-cache dependency: show it as package-relative.
  final m = RegExp(r'/([^/]+)/lib/(.*)$').firstMatch(rel);
  return m == null ? rel : '${m.group(1)}:${m.group(2)}';
}
