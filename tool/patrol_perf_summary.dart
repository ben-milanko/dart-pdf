import 'dart:convert';
import 'dart:io';

final _ansiEscape = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
final _perfLine = RegExp(r'\[perf\s+(\d+)\]\s+(.+)$');
final _field = RegExp(r'([A-Za-z][A-Za-z0-9_-]*)=([^\s]+)');

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.contains('--help')) {
    stdout.writeln(
      'Usage: dart tool/patrol_perf_summary.dart <patrol-log> '
      '--output <directory> [--markdown <file>]',
    );
    exit(arguments.contains('--help') ? 0 : 64);
  }

  final input = arguments.first;
  String? output;
  String? markdownOutput;
  for (var i = 1; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--output':
        output = _nextArgument(arguments, ++i, '--output');
      case '--markdown':
        markdownOutput = _nextArgument(arguments, ++i, '--markdown');
      default:
        stderr.writeln('Unknown argument: ${arguments[i]}');
        exit(64);
    }
  }
  if (output == null) {
    stderr.writeln('--output is required');
    exit(64);
  }

  final source = File(input);
  if (!source.existsSync()) {
    stderr.writeln('Patrol log does not exist: $input');
    exit(66);
  }

  final trace = PatrolPerfTrace.parse(source.readAsLinesSync());
  final directory = Directory(output)..createSync(recursive: true);
  File('${directory.path}/patrol-perf.log').writeAsStringSync(
    trace.lines.isEmpty ? '' : '${trace.lines.join('\n')}\n',
  );
  File('${directory.path}/patrol-perf.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(trace.toJson())}\n',
  );
  final markdown = trace.toMarkdown();
  File('${directory.path}/patrol-perf.md').writeAsStringSync(markdown);
  if (markdownOutput != null) {
    File(markdownOutput).writeAsStringSync(markdown, mode: FileMode.append);
  }

  stdout.writeln(
    'Collected ${trace.lines.length} Patrol perf events in ${directory.path}',
  );
}

String _nextArgument(List<String> arguments, int index, String option) {
  if (index >= arguments.length) {
    stderr.writeln('$option requires a value');
    exit(64);
  }
  return arguments[index];
}

class PatrolPerfTrace {
  PatrolPerfTrace._({
    required this.lines,
    required this.timestampsMs,
    required this.buildTag,
    required this.eventCounts,
    required this.jankBuildMs,
    required this.jankRasterMs,
    required this.jankTotalMs,
    required this.reconcileElapsedMs,
    required this.reconcileModes,
    required this.reconcileFallbackReasons,
    required this.thumbnailPaths,
    required this.pageRasterOutcomes,
    required this.rasterElapsedMs,
  });

  factory PatrolPerfTrace.parse(Iterable<String> sourceLines) {
    final lines = <String>[];
    final timestamps = <int>[];
    String? buildTag;
    final eventCounts = <String, int>{};
    final jankBuild = <double>[];
    final jankRaster = <double>[];
    final jankTotal = <double>[];
    final reconcileElapsed = <double>[];
    final reconcileModes = <String, int>{};
    final fallbackReasons = <String, int>{};
    final thumbnailPaths = <String, int>{};
    final pageRasterOutcomes = <String, int>{};
    final rasterElapsed = <double>[];

    for (final sourceLine in sourceLines) {
      final clean = sourceLine.replaceAll(_ansiEscape, '');
      final match = _perfLine.firstMatch(clean);
      if (match == null) continue;
      final timestamp = int.parse(match.group(1)!);
      final message = match.group(2)!.trim();
      final normalized = '[perf $timestamp] $message';
      lines.add(normalized);
      timestamps.add(timestamp);

      final event = message.split(RegExp(r'\s+')).first;
      _increment(eventCounts, event);
      final fields = <String, String>{
        for (final field in _field.allMatches(message))
          field.group(1)!: field.group(2)!,
      };

      if (event == 'build') {
        buildTag = message.substring('build'.length).trim();
      } else if (event == 'JANK') {
        _addMilliseconds(jankBuild, fields['build']);
        _addMilliseconds(jankRaster, fields['raster']);
        _addMilliseconds(jankTotal, fields['total']);
      } else if (event == 'page-reconcile') {
        _increment(reconcileModes, fields['mode'] ?? 'unknown');
        _addMilliseconds(reconcileElapsed, fields['elapsed']);
        final reason = fields['reason'];
        if (reason != null) _increment(fallbackReasons, reason);
      } else if (event == 'thumbnail') {
        if (fields.containsKey('page') && fields.containsKey('px')) {
          _increment(thumbnailPaths, _thumbnailPath(message));
        }
      } else if (event == 'page-raster') {
        _increment(pageRasterOutcomes, _secondWord(message));
      } else if (event == 'raster') {
        _addMilliseconds(rasterElapsed, fields['ms']);
      }
    }

    return PatrolPerfTrace._(
      lines: lines,
      timestampsMs: timestamps,
      buildTag: buildTag,
      eventCounts: eventCounts,
      jankBuildMs: jankBuild,
      jankRasterMs: jankRaster,
      jankTotalMs: jankTotal,
      reconcileElapsedMs: reconcileElapsed,
      reconcileModes: reconcileModes,
      reconcileFallbackReasons: fallbackReasons,
      thumbnailPaths: thumbnailPaths,
      pageRasterOutcomes: pageRasterOutcomes,
      rasterElapsedMs: rasterElapsed,
    );
  }

  final List<String> lines;
  final List<int> timestampsMs;
  final String? buildTag;
  final Map<String, int> eventCounts;
  final List<double> jankBuildMs;
  final List<double> jankRasterMs;
  final List<double> jankTotalMs;
  final List<double> reconcileElapsedMs;
  final Map<String, int> reconcileModes;
  final Map<String, int> reconcileFallbackReasons;
  final Map<String, int> thumbnailPaths;
  final Map<String, int> pageRasterOutcomes;
  final List<double> rasterElapsedMs;

  int get durationMs =>
      timestampsMs.length < 2 ? 0 : timestampsMs.last - timestampsMs.first;

  Map<String, Object?> toJson() => {
        'schema': 1,
        'build': buildTag,
        'events': lines.length,
        'durationMs': durationMs,
        'eventCounts': _sortedMap(eventCounts),
        'jank': {
          'count': jankTotalMs.length,
          'buildMs': _distribution(jankBuildMs),
          'rasterMs': _distribution(jankRasterMs),
          'totalMs': _distribution(jankTotalMs),
        },
        'reconciliation': {
          'count': reconcileElapsedMs.length,
          'modes': _sortedMap(reconcileModes),
          'fallbackReasons': _sortedMap(reconcileFallbackReasons),
          'elapsedMs': _distribution(reconcileElapsedMs),
        },
        'thumbnails': {
          'events': eventCounts['thumbnail'] ?? 0,
          'renders': _sum(thumbnailPaths.values),
          'paths': _sortedMap(thumbnailPaths),
        },
        'pageRasters': {
          'events': eventCounts['page-raster'] ?? 0,
          'outcomes': _sortedMap(pageRasterOutcomes),
        },
        'rasters': {
          'count': eventCounts['raster'] ?? 0,
          'elapsedMs': _distribution(rasterElapsedMs),
        },
      };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('## Patrol web performance')
      ..writeln()
      ..writeln(
        lines.isEmpty
            ? 'No `PdfPerfLog` events were captured. The Patrol result '
                'artifact still contains the empty trace for diagnosis.'
            : 'Observational trace from the real Patrol browser journey. '
                'Use it for PR comparisons; wall-clock values are not a CI gate.',
      )
      ..writeln()
      ..writeln('| Signal | Result |')
      ..writeln('| --- | ---: |')
      ..writeln('| Build | ${_code(buildTag ?? 'unstamped')} |')
      ..writeln('| Perf events | ${lines.length} |')
      ..writeln('| Trace span | ${_formatMs(durationMs.toDouble())} |')
      ..writeln('| Jank frames | ${jankTotalMs.length} |')
      ..writeln(
        '| Jank total p50 / p95 / max | ${_distributionText(jankTotalMs)} |',
      )
      ..writeln(
        '| Reconcile p50 / p95 / max | '
        '${_distributionText(reconcileElapsedMs)} |',
      )
      ..writeln('| Reconcile modes | ${_mapText(reconcileModes)} |')
      ..writeln(
          '| Reconcile fallbacks | ${_mapText(reconcileFallbackReasons)} |')
      ..writeln('| Thumbnail paths | ${_mapText(thumbnailPaths)} |')
      ..writeln('| Page-raster outcomes | ${_mapText(pageRasterOutcomes)} |')
      ..writeln('| Raster p50 / p95 / max | '
          '${_distributionText(rasterElapsedMs)} |')
      ..writeln()
      ..writeln(
        'Artifacts: `patrol-perf.log` (normalized raw trace), '
        '`patrol-perf.json` (machine comparison), and this Markdown summary.',
      )
      ..writeln();
    return buffer.toString();
  }
}

String _thumbnailPath(String message) {
  if (message.contains('disk-hit')) return 'disk-hit';
  if (message.contains('preview-hit')) return 'preview-hit';
  if (message.contains('retained')) return 'retained';
  if (message.contains('defer')) return 'deferred';
  if (message.contains('skip')) return 'skipped';
  if (message.contains('worker')) return 'worker';
  if (message.contains('local')) return 'local';
  return 'other';
}

String _secondWord(String message) {
  final words = message.split(RegExp(r'\s+'));
  if (words.length < 2) return 'unknown';
  final separator = words[1].indexOf('=');
  return separator < 0 ? words[1] : words[1].substring(0, separator);
}

void _increment(Map<String, int> values, String key) {
  values[key] = (values[key] ?? 0) + 1;
}

void _addMilliseconds(List<double> values, String? raw) {
  if (raw == null) return;
  final parsed = double.tryParse(raw.replaceFirst(RegExp(r'ms$'), ''));
  if (parsed != null) values.add(parsed);
}

Map<String, int> _sortedMap(Map<String, int> values) => {
      for (final key in values.keys.toList()..sort()) key: values[key]!,
    };

int _sum(Iterable<int> values) =>
    values.fold(0, (total, value) => total + value);

Map<String, double>? _distribution(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = List<double>.of(values)..sort();
  return {
    'p50': _percentile(sorted, 0.50),
    'p95': _percentile(sorted, 0.95),
    'max': sorted.last,
  };
}

double _percentile(List<double> sorted, double fraction) {
  final index = ((sorted.length - 1) * fraction).round();
  return sorted[index];
}

String _distributionText(List<double> values) {
  final distribution = _distribution(values);
  if (distribution == null) return 'n/a';
  return '${_formatMs(distribution['p50']!)} / '
      '${_formatMs(distribution['p95']!)} / '
      '${_formatMs(distribution['max']!)}';
}

String _mapText(Map<String, int> values) {
  if (values.isEmpty) return 'none';
  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map((entry) => '${_code(entry.key)} ${entry.value}')
      .join(', ');
}

String _formatMs(double value) => '${value.toStringAsFixed(1)} ms';

String _code(String value) => '`$value`';
