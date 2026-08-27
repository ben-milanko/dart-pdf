import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart tool/gpu_corpus_summary.dart '
      '<main.json> <pr.json> [--output <directory>] '
      '[--markdown <file>]',
    );
    exitCode = 64;
    return;
  }

  final baselinePath = arguments[0];
  final currentPath = arguments[1];
  String? outputDirectory;
  String? markdownPath;
  for (var index = 2; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--output':
        outputDirectory = _nextValue(arguments, ++index, '--output');
      case '--markdown':
        markdownPath = _nextValue(arguments, ++index, '--markdown');
      default:
        throw FormatException('Unknown argument: ${arguments[index]}');
    }
  }

  final comparison = GpuCorpusComparison(
    baseline: GpuCorpusReport.parse(
      jsonDecode(File(baselinePath).readAsStringSync()),
    ),
    current: GpuCorpusReport.parse(
      jsonDecode(File(currentPath).readAsStringSync()),
    ),
  );
  final headline = comparison.toHeadlineMarkdown();
  final report = comparison.toMarkdown();
  stdout.writeln(headline);

  if (outputDirectory != null) {
    final directory = Directory(outputDirectory)..createSync(recursive: true);
    File('${directory.path}/gpu-corpus-headline.md')
        .writeAsStringSync('$headline\n');
    File('${directory.path}/gpu-corpus.md').writeAsStringSync('$report\n');
  }
  if (markdownPath != null) {
    final file = File(markdownPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$report\n', mode: FileMode.append);
  }

  if (comparison.hasRegressions) {
    stderr.writeln(
      'Flutter GPU corpus regression: ${comparison.regressions.length} '
      'previously accepted page(s) now require Canvas fallback.',
    );
    exitCode = 1;
  }
}

String _nextValue(List<String> arguments, int index, String flag) {
  if (index >= arguments.length) {
    throw FormatException('$flag requires a value');
  }
  return arguments[index];
}

class GpuCorpusReport {
  GpuCorpusReport(this.suites);

  factory GpuCorpusReport.parse(Object? value) {
    if (value is! Map || value['schema'] != 1 || value['suites'] is! Map) {
      throw const FormatException('Unsupported Flutter GPU corpus report');
    }
    final suites = <String, GpuCorpusSuite>{};
    for (final entry in (value['suites'] as Map).entries) {
      if (entry.key is! String) {
        throw const FormatException('GPU corpus suite name is not a string');
      }
      suites[entry.key as String] = GpuCorpusSuite.parse(entry.value);
    }
    return GpuCorpusReport(suites);
  }

  final Map<String, GpuCorpusSuite> suites;
}

class GpuCorpusSuite {
  GpuCorpusSuite(this.pages);

  factory GpuCorpusSuite.parse(Object? value) {
    if (value is! Map || value['pages'] is! List) {
      throw const FormatException('Invalid Flutter GPU corpus suite');
    }
    final pages = <String, GpuCorpusPage>{};
    for (final rawPage in value['pages'] as List) {
      final page = GpuCorpusPage.parse(rawPage);
      if (pages[page.id] != null) {
        throw FormatException('Duplicate Flutter GPU corpus page: ${page.id}');
      }
      pages[page.id] = page;
    }
    final suite = GpuCorpusSuite(pages);
    if (value['accepted'] != suite.accepted ||
        value['rejected'] != suite.rejected) {
      throw const FormatException(
        'Flutter GPU corpus route totals do not match the page records',
      );
    }
    return suite;
  }

  final Map<String, GpuCorpusPage> pages;

  int get accepted => pages.values.where((page) => page.accepted).length;
  int get rejected => pages.length - accepted;
}

class GpuCorpusPage {
  const GpuCorpusPage({
    required this.id,
    required this.route,
    this.reason,
    this.meanDifference,
    this.stats = const {},
  });

  factory GpuCorpusPage.parse(Object? value) {
    if (value is! Map || value['id'] is! String || value['route'] is! String) {
      throw const FormatException('Invalid Flutter GPU corpus page');
    }
    final route = value['route'] as String;
    if (route != 'flutter-gpu' && route != 'canvas-fallback') {
      throw FormatException('Unknown Flutter GPU corpus route: $route');
    }
    return GpuCorpusPage(
      id: value['id'] as String,
      route: route,
      reason: value['reason'] as String?,
      meanDifference: (value['meanDifference'] as num?)?.toDouble(),
      stats: _stringKeyedMap(value['stats']),
    );
  }

  final String id;
  final String route;
  final String? reason;
  final double? meanDifference;
  final Map<String, Object?> stats;

  bool get accepted => route == 'flutter-gpu';

  num? stat(String name) => stats[name] as num?;
}

class GpuCorpusComparison {
  GpuCorpusComparison({required this.baseline, required this.current});

  final GpuCorpusReport baseline;
  final GpuCorpusReport current;

  List<GpuCorpusPage> get regressions => _routeChanges(
        baselineAccepted: true,
        currentAccepted: false,
      );

  List<GpuCorpusPage> get improvements => _routeChanges(
        baselineAccepted: false,
        currentAccepted: true,
      );

  bool get hasRegressions => regressions.isNotEmpty;

  String toHeadlineMarkdown() {
    final buffer = StringBuffer()
      ..writeln('### Flutter GPU corpus comparison with `main`')
      ..writeln()
      ..writeln(
          '| Suite | Main accepted / fallback | PR accepted / fallback | Change |')
      ..writeln('| --- | ---: | ---: | ---: |');
    for (final name in _suiteNames) {
      final main = baseline.suites[name];
      final pullRequest = current.suites[name];
      final mainAccepted = main?.accepted ?? 0;
      final currentAccepted = pullRequest?.accepted ?? 0;
      final delta = currentAccepted - mainAccepted;
      buffer.writeln(
        '| ${_escape(name)} | ${main?.accepted ?? 0} / '
        '${main?.rejected ?? 0} | ${pullRequest?.accepted ?? 0} / '
        '${pullRequest?.rejected ?? 0} | ${_signed(delta)} accepted |',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        '**New GPU coverage:** ${_inlinePages(improvements, empty: 'none')}.',
      )
      ..writeln(
        '**New Canvas fallbacks:** '
        '${_inlinePages(regressions, empty: 'none')}.',
      );
    return buffer.toString().trimRight();
  }

  String toMarkdown() {
    final buffer = StringBuffer(toHeadlineMarkdown());
    _writeStructuralComparison(buffer);
    _writeHotspots(buffer);
    _writeChanges(buffer, 'New GPU coverage', improvements);
    _writeChanges(buffer, 'New Canvas fallbacks', regressions);

    final fallbacks = <GpuCorpusPage>[
      for (final suite in current.suites.values)
        for (final page in suite.pages.values)
          if (!page.accepted) page,
    ]..sort((a, b) => a.id.compareTo(b.id));
    buffer
      ..writeln()
      ..writeln()
      ..writeln('#### Current conservative Canvas fallbacks')
      ..writeln();
    if (fallbacks.isEmpty) {
      buffer.writeln('None.');
    } else {
      buffer
        ..writeln('| Page | Reason |')
        ..writeln('| --- | --- |');
      for (final page in fallbacks) {
        buffer.writeln(
          '| `${_escape(page.id)}` | ${_escape(page.reason ?? 'unspecified')} |',
        );
      }
    }
    return buffer.toString().trimRight();
  }

  void _writeStructuralComparison(StringBuffer buffer) {
    final samples = <(GpuCorpusPage, GpuCorpusPage)>[];
    for (final suiteName in _suiteNames) {
      final mainPages = baseline.suites[suiteName]?.pages;
      final currentPages = current.suites[suiteName]?.pages;
      if (mainPages == null || currentPages == null) continue;
      for (final entry in mainPages.entries) {
        final pullRequest = currentPages[entry.key];
        if (entry.value.accepted &&
            pullRequest?.accepted == true &&
            entry.value.stats.isNotEmpty &&
            pullRequest!.stats.isNotEmpty) {
          samples.add((entry.value, pullRequest));
        }
      }
    }
    buffer
      ..writeln()
      ..writeln()
      ..writeln('#### GPU corpus structural comparison')
      ..writeln();
    if (samples.isEmpty) {
      buffer.writeln(
        'Per-page backend statistics are unavailable for one side of this '
        'comparison.',
      );
      return;
    }
    buffer
      ..writeln('Common accelerated pages: ${samples.length}.')
      ..writeln()
      ..writeln('| Metric | Main | PR | Change |')
      ..writeln('| --- | ---: | ---: | ---: |');
    for (final metric in const [
      ('Native draw calls', 'drawCalls'),
      ('Direct solid draws', 'directSolidDrawCalls'),
      ('Stencil fan draws', 'stencilFanDrawCalls'),
      ('Stencil cover draws', 'stencilCoverDrawCalls'),
      ('Stencil clear draws', 'stencilClearDrawCalls'),
      ('Texture draws', 'textureDrawCalls'),
      ('Glyph draws', 'glyphDrawCalls'),
      ('Advanced blend draws', 'blendDrawCalls'),
      ('Soft-mask draws', 'softMaskDrawCalls'),
      ('Selected commands', 'selectedCommands'),
      ('Draw calls saved', 'drawCallsSaved'),
      ('Direct rectangle draws', 'directRectangleDraws'),
      ('Geometry vertices', 'geometryVertices'),
    ]) {
      if (!samples.every((sample) =>
          sample.$1.stat(metric.$2) != null &&
          sample.$2.stat(metric.$2) != null)) {
        continue;
      }
      final main = _sumStats(samples.map((sample) => sample.$1), metric.$2);
      final pullRequest =
          _sumStats(samples.map((sample) => sample.$2), metric.$2);
      buffer.writeln(
        '| ${metric.$1} | $main | $pullRequest | '
        '${_deltaPercent(main, pullRequest)} |',
      );
    }
  }

  void _writeHotspots(StringBuffer buffer) {
    final pages = <GpuCorpusPage>[
      for (final suite in current.suites.values)
        for (final page in suite.pages.values)
          if (page.accepted && page.stat('drawCalls') != null) page,
    ]..sort((a, b) {
        final draws =
            (b.stat('drawCalls') ?? 0).compareTo(a.stat('drawCalls') ?? 0);
        return draws != 0 ? draws : a.id.compareTo(b.id);
      });
    buffer
      ..writeln()
      ..writeln()
      ..writeln('#### Current GPU corpus draw hotspots')
      ..writeln();
    if (pages.isEmpty) {
      buffer.writeln('Per-page backend statistics were not recorded.');
      return;
    }
    buffer
      ..writeln('Draw mix is direct solid / stencil fan / stencil cover / '
          'stencil clear / texture / glyph / advanced blend / soft mask.')
      ..writeln()
      ..writeln('| Page | Draws | Commands | Saved | Direct rectangles | '
          'Draw mix | Issue | Compile | Canvas mean delta |')
      ..writeln(
          '| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |');
    for (final page in pages.take(15)) {
      buffer.writeln(
        '| `${_escape(page.id)}` | ${_integerStat(page, 'drawCalls')} | '
        '${_integerStat(page, 'selectedCommands')} | '
        '${_integerStat(page, 'drawCallsSaved')} | '
        '${_integerStat(page, 'directRectangleDraws')} | '
        '${_drawMix(page)} | '
        '${_millisecondsStat(page, 'issueMicros')} | '
        '${_millisecondsStat(page, 'compileMicros')} | '
        '${page.meanDifference?.toStringAsFixed(3) ?? '—'} |',
      );
    }
  }

  List<String> get _suiteNames => {
        ...baseline.suites.keys,
        ...current.suites.keys,
      }.toList()
        ..sort();

  List<GpuCorpusPage> _routeChanges({
    required bool baselineAccepted,
    required bool currentAccepted,
  }) {
    final result = <GpuCorpusPage>[];
    for (final suiteName in _suiteNames) {
      final mainPages = baseline.suites[suiteName]?.pages;
      final currentPages = current.suites[suiteName]?.pages;
      if (mainPages == null || currentPages == null) continue;
      for (final entry in mainPages.entries) {
        final pullRequest = currentPages[entry.key];
        if (pullRequest != null &&
            entry.value.accepted == baselineAccepted &&
            pullRequest.accepted == currentAccepted) {
          result.add(pullRequest);
        }
      }
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }
}

void _writeChanges(
  StringBuffer buffer,
  String heading,
  List<GpuCorpusPage> pages,
) {
  buffer
    ..writeln()
    ..writeln()
    ..writeln('#### $heading')
    ..writeln();
  if (pages.isEmpty) {
    buffer.writeln('None.');
    return;
  }
  for (final page in pages) {
    buffer.writeln(
      '- `${page.id}`${page.reason == null ? '' : ' — ${page.reason}'}',
    );
  }
}

String _inlinePages(
  List<GpuCorpusPage> pages, {
  required String empty,
  int limit = 4,
}) {
  if (pages.isEmpty) return empty;
  final visible = pages.take(limit).map((page) => '`${page.id}`').join(', ');
  final remaining = pages.length - limit;
  return remaining > 0 ? '$visible, and $remaining more' : visible;
}

String _signed(int value) => value > 0 ? '+$value' : '$value';

String _escape(String value) => value.replaceAll('|', r'\|');

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value == null) return const {};
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid Flutter GPU page statistics');
  }
  return {for (final entry in value.entries) entry.key as String: entry.value};
}

int _sumStats(Iterable<GpuCorpusPage> pages, String name) => pages.fold(
      0,
      (total, page) => total + (page.stat(name)?.toInt() ?? 0),
    );

String _deltaPercent(int baseline, int current) {
  if (baseline == 0) return current == 0 ? '0.0%' : 'new';
  final percent = (current - baseline) * 100 / baseline;
  return '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)}%';
}

String _integerStat(GpuCorpusPage page, String name) =>
    page.stat(name)?.toInt().toString() ?? '—';

String _drawMix(GpuCorpusPage page) {
  const names = [
    'directSolidDrawCalls',
    'stencilFanDrawCalls',
    'stencilCoverDrawCalls',
    'stencilClearDrawCalls',
    'textureDrawCalls',
    'glyphDrawCalls',
    'blendDrawCalls',
    'softMaskDrawCalls',
  ];
  if (names.any((name) => page.stat(name) == null)) return '—';
  return names.map((name) => page.stat(name)!.toInt()).join('/');
}

String _millisecondsStat(GpuCorpusPage page, String name) {
  final micros = page.stat(name);
  return micros == null ? '—' : '${(micros / 1000).toStringAsFixed(3)} ms';
}
