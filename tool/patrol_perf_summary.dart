import 'dart:convert';
import 'dart:io';

final _ansiEscape = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
final _perfLine = RegExp(r'\[perf\s+(\d+)\]\s+(.+)$');
final _field = RegExp(r'([A-Za-z][A-Za-z0-9_-]*)=([^\s]+)');
final _workerImageCache = RegExp(r'^(\d+)h/(\d+)m/(\d+)e/(\d+)B$');
final _workerImageCacheDelta = RegExp(r'^(\d+)h/(\d+)m/(-?\d+)e/(-?\d+)B$');

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.contains('--help')) {
    stdout.writeln(
      'Usage: dart tool/patrol_perf_summary.dart <patrol-log> '
      '--output <directory> [--markdown <file>] [--baseline <json>] '
      '[--label <platform>] [--require-scenario-runs <name>=<count>]',
    );
    exit(arguments.contains('--help') ? 0 : 64);
  }

  final input = arguments.first;
  String? output;
  String? markdownOutput;
  String? baselineInput;
  var label = 'web';
  final requiredScenarioRuns = <String, int>{};
  for (var i = 1; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--output':
        output = _nextArgument(arguments, ++i, '--output');
      case '--markdown':
        markdownOutput = _nextArgument(arguments, ++i, '--markdown');
      case '--baseline':
        baselineInput = _nextArgument(arguments, ++i, '--baseline');
      case '--label':
        label = _nextArgument(arguments, ++i, '--label');
      case '--require-scenario-runs':
        final raw = _nextArgument(arguments, ++i, '--require-scenario-runs');
        final separator = raw.lastIndexOf('=');
        final name = separator < 0 ? '' : raw.substring(0, separator);
        final count =
            separator < 0 ? null : int.tryParse(raw.substring(separator + 1));
        if (name.isEmpty || count == null || count < 1) {
          stderr.writeln(
            '--require-scenario-runs expects <name>=<positive-count>: $raw',
          );
          exit(64);
        }
        requiredScenarioRuns[name] = count;
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
  final current = trace.toJson();
  File('${directory.path}/patrol-perf.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(current)}\n',
  );
  var headline = trace.toHeadlineMarkdown(label: label);
  var markdown = trace.toMarkdown(label: label);
  if (baselineInput != null) {
    final baselineFile = File(baselineInput);
    if (!baselineFile.existsSync()) {
      stderr.writeln('Patrol baseline does not exist: $baselineInput');
      exit(66);
    }
    final decoded = jsonDecode(baselineFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('Patrol baseline is not a JSON object: $baselineInput');
      exit(65);
    }
    final comparison = PatrolPerfComparison(
      baseline: decoded,
      current: current,
    );
    headline = comparison.toHeadlineMarkdown(label: label);
    markdown += comparison.toMarkdown(label: label);
  }
  File('${directory.path}/patrol-perf-headline.md').writeAsStringSync(headline);
  File('${directory.path}/patrol-perf.md').writeAsStringSync(markdown);
  if (markdownOutput != null) {
    File(markdownOutput).writeAsStringSync(markdown, mode: FileMode.append);
  }

  final shortfalls = patrolPerfScenarioRunShortfalls(
    current,
    requiredScenarioRuns,
  );
  if (shortfalls.isNotEmpty) {
    for (final entry in shortfalls.entries) {
      stderr.writeln(
        'Scenario ${entry.key} produced ${entry.value} complete run(s); '
        'required ${requiredScenarioRuns[entry.key]}.',
      );
    }
    exit(65);
  }

  stdout.writeln(
    'Collected ${trace.lines.length} Patrol perf events in ${directory.path}',
  );
}

/// Returns the observed run count for every required scenario that did not
/// produce enough complete start/end pairs.
///
/// CI uses this after writing the report artifacts: a flaky Patrol invocation
/// remains diagnosable, but cannot silently reduce a repeated comparison to a
/// sparse result.
Map<String, int> patrolPerfScenarioRunShortfalls(
  Map<String, Object?> trace,
  Map<String, int> required,
) {
  final shortfalls = <String, int>{};
  for (final entry in required.entries) {
    final actual = _jsonNumber(
          trace,
          ['scenarioMetrics', entry.key, 'runs'],
        )?.round() ??
        0;
    if (actual < entry.value) shortfalls[entry.key] = actual;
  }
  return shortfalls;
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
    required this.durationMs,
    required this.journeys,
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
    required this.webWorkerOutcomes,
    required this.workerPhases,
    required this.rasterElapsedMs,
    required this.tiles,
    required this.scenarioPhases,
    required Map<String, _ScenarioMetrics> scenarioMetrics,
  }) : _scenarioMetrics = scenarioMetrics;

  factory PatrolPerfTrace.parse(Iterable<String> sourceLines) {
    final lines = <String>[];
    final timestamps = <int>[];
    var durationMs = 0;
    var journeys = 0;
    int? previousTimestamp;
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
    final webWorkerOutcomes = <String, int>{};
    final workerPhases = _WorkerPhaseMetrics();
    final rasterElapsed = <double>[];
    final tiles = _TileMetrics();
    final scenarioPhases = <String, int>{};
    final scenarioMetrics = <String, _ScenarioMetrics>{};
    final activeScenarios = <String, _ActiveScenario>{};

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

      // Separate Patrol targets (and app restarts within one target) reset the
      // perf stopwatch. A `build` stamp is an explicit segment boundary; a
      // decreasing timestamp is the fallback for unstamped traces. Summing
      // monotonic segments avoids a negative or invented cross-process span.
      final startsSegment = event == 'build' ||
          previousTimestamp == null ||
          timestamp < previousTimestamp;
      if (startsSegment) {
        journeys++;
        // A Patrol app restart resets the stopwatch. Never pair an unfinished
        // scenario in the old process with a completion marker in the next.
        activeScenarios.clear();
      } else {
        durationMs += timestamp - previousTimestamp;
      }
      previousTimestamp = timestamp;

      String? scenarioName;
      String? scenarioPhase;
      if (event == 'scenario') {
        scenarioName = fields['name'] ?? 'unknown';
        scenarioPhase = fields['phase'] ?? 'event';
        _increment(scenarioPhases, '$scenarioName:$scenarioPhase');
        if (scenarioPhase == 'start') {
          final metrics = scenarioMetrics.putIfAbsent(
            scenarioName,
            _ScenarioMetrics.new,
          );
          activeScenarios[scenarioName] = _ActiveScenario(timestamp, metrics);
        }
      }

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
      } else if (event == 'webworker') {
        final outcome = _webWorkerOutcome(message);
        if (outcome != null) _increment(webWorkerOutcomes, outcome);
        if (message.startsWith('webworker phase ')) {
          workerPhases.record(fields);
        }
      } else if (event == 'raster') {
        _addMilliseconds(rasterElapsed, fields['ms']);
      } else if (event == 'tile') {
        tiles.record(message, fields);
      }

      for (final scenario in activeScenarios.values) {
        scenario.metrics.record(event, message, fields);
      }
      if (scenarioName != null &&
          scenarioPhase != null &&
          _completesScenario(scenarioPhase)) {
        final scenario = activeScenarios.remove(scenarioName);
        if (scenario != null) {
          scenario.metrics.elapsedMs.add(
            (timestamp - scenario.startedAtMs).toDouble(),
          );
        }
      }
    }

    return PatrolPerfTrace._(
      lines: lines,
      timestampsMs: timestamps,
      durationMs: durationMs,
      journeys: journeys,
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
      webWorkerOutcomes: webWorkerOutcomes,
      workerPhases: workerPhases,
      rasterElapsedMs: rasterElapsed,
      tiles: tiles,
      scenarioPhases: scenarioPhases,
      scenarioMetrics: scenarioMetrics,
    );
  }

  final List<String> lines;
  final List<int> timestampsMs;
  final int durationMs;
  final int journeys;
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
  final Map<String, int> webWorkerOutcomes;
  final _WorkerPhaseMetrics workerPhases;
  final List<double> rasterElapsedMs;
  final _TileMetrics tiles;
  final Map<String, int> scenarioPhases;
  final Map<String, _ScenarioMetrics> _scenarioMetrics;

  Map<String, Object?> toJson() => {
        'schema': 9,
        'build': buildTag,
        'events': lines.length,
        'journeys': journeys,
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
        'webWorker': {
          'events': eventCounts['webworker'] ?? 0,
          'outcomes': _sortedMap(webWorkerOutcomes),
          'phases': workerPhases.toJson(),
        },
        'rasters': {
          'count': eventCounts['raster'] ?? 0,
          'elapsedMs': _distribution(rasterElapsedMs),
        },
        'tiles': tiles.toJson(),
        'scenarios': _sortedMap(scenarioPhases),
        'scenarioMetrics': {
          for (final name in _scenarioMetrics.keys.toList()..sort())
            name: _scenarioMetrics[name]!.toJson(),
        },
      };

  String toHeadlineMarkdown({String label = 'web'}) {
    final heading =
        label.toLowerCase() == 'web' ? '### Headline' : '### $label headline';
    final speedup = _gpuTileSpeedupHeadline(toJson());
    final buffer = StringBuffer()..writeln(heading);
    if (speedup != null) {
      buffer
        ..writeln()
        ..writeln(speedup);
    }
    buffer
      ..writeln()
      ..writeln(
        lines.isEmpty
            ? 'No `PdfPerfLog` events were captured.'
            : 'Current Patrol $label trace. Lower timing is better.',
      );
    if (lines.isEmpty) return '${buffer.toString()}\n';
    if (_scenarioMetrics.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'Scenario elapsed uses p50 across repeated runs; phase and tail '
          'signals remain p95.',
        );
    }
    buffer
      ..writeln()
      ..writeln('| Signal | Result |')
      ..writeln('| --- | ---: |');
    for (final name in _scenarioMetrics.keys.toList()..sort()) {
      final elapsed = _scenarioMetrics[name]!.elapsedMs;
      buffer.writeln('| Scenario ${_code(name)} elapsed p50 '
          '(${elapsed.length} ${elapsed.length == 1 ? 'run' : 'runs'}) | '
          '${_p50Text(elapsed)} |');
    }
    buffer
      ..writeln('| Jank frames | ${jankTotalMs.length} |')
      ..writeln('| Jank total p95 | ${_p95Text(jankTotalMs)} |')
      ..writeln('| Reconcile p95 | ${_p95Text(reconcileElapsedMs)} |')
      ..writeln('| Raster p95 | ${_p95Text(rasterElapsedMs)} |');
    if (workerPhases.totalMs.isNotEmpty) {
      buffer.writeln('| Worker phase total p95 | '
          '${_p95Text(workerPhases.totalMs)} |');
    }
    if (tiles.replayMs.isNotEmpty) {
      buffer.writeln('| Tile replay p95 | ${_p95Text(tiles.replayMs)} |');
    }
    buffer
      ..writeln('| Reconcile fallbacks | '
          '${_sum(reconcileFallbackReasons.values)} |')
      ..writeln('| Page-raster rejects | '
          '${pageRasterOutcomes['reject'] ?? 0} |')
      ..writeln('| Web-worker fatal fallbacks | '
          '${webWorkerOutcomes['fallback'] ?? 0} |');
    buffer.writeln();
    return buffer.toString();
  }

  String toMarkdown({String label = 'web'}) {
    final journeyKind = label.toLowerCase() == 'web' ? 'browser' : 'device';
    final buffer = StringBuffer()
      ..writeln('## Patrol $label performance')
      ..writeln()
      ..writeln(
        lines.isEmpty
            ? 'No `PdfPerfLog` events were captured. The Patrol result '
                'artifact still contains the empty trace for diagnosis.'
            : 'Observational trace from the real Patrol $journeyKind journey. '
                'Use it for PR comparisons; wall-clock values are not a CI gate.',
      )
      ..writeln()
      ..writeln('| Signal | Result |')
      ..writeln('| --- | ---: |')
      ..writeln('| Build | ${_code(buildTag ?? 'unstamped')} |')
      ..writeln('| Journey segments | $journeys |')
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
      ..writeln('| Web-worker outcomes | ${_mapText(webWorkerOutcomes)} |')
      ..writeln('| Worker phase requests | ${workerPhases.totalMs.length} |')
      ..writeln('| Worker total p50 / p95 / max | '
          '${_distributionText(workerPhases.totalMs)} |')
      ..writeln('| Worker decode p50 / p95 / max | '
          '${_distributionText(workerPhases.decodeMs)} |')
      ..writeln('| Worker image-cache peak | '
          '${_formatBytes(workerPhases.peakImageCacheBytes)} |')
      ..writeln('| Worker image-cache lookups | '
          '${workerPhases.cacheLookupText} |')
      ..writeln('| Worker image-cache request paths | '
          '${workerPhases.cacheRequestPathText} |')
      ..writeln('| Worker image-cache net growth | '
          '${workerPhases.netImageCacheEntries} entries / '
          '${_formatSignedBytes(workerPhases.netImageCacheBytes)} |')
      ..writeln('| Scenarios | ${_mapText(scenarioPhases)} |')
      ..writeln('| Raster p50 / p95 / max | '
          '${_distributionText(rasterElapsedMs)} |')
      ..writeln('| Tile replay requests | ${tiles.replayRequests} |')
      ..writeln('| Tile replay p50 / p95 / max | '
          '${_distributionText(tiles.replayMs)} |')
      ..writeln('| Tile replay raster p50 / p95 / max | '
          '${_distributionText(tiles.rasterMs)} |')
      ..writeln('| Tile slice classes | ${tiles.sliceClassText} |')
      ..writeln('| Tile rung/class batches | '
          '${_mapText(tiles.sliceBatchesByRungClass)} |')
      ..writeln('| Tile retained peak | ${tiles.retainedPeakText} |');
    if (tiles.policySamples > 0) {
      buffer
        ..writeln('| Tile policy snapshots | ${tiles.policySamples} |')
        ..writeln(
            '| Tile budget peak | ${_formatBytes(tiles.peakBudgetBytes)} |')
        ..writeln('| Tile scheduled / landed / discarded | '
            '${tiles.scheduled} / ${tiles.landed} / ${tiles.discarded} |')
        ..writeln('| Tile discard rate | ${tiles.discardRateText} |')
        ..writeln('| Static-view reschedules | ${tiles.staticRescheduled} |');
    }
    buffer.writeln();
    if (_scenarioMetrics.isNotEmpty) {
      buffer
        ..writeln('### Scenario breakdown')
        ..writeln()
        ..writeln(
          '| Scenario | Runs | Elapsed p50 / p95 / max | Jank p95 | '
          'Reconcile p95 | Raster p95 | Worker total p95 | '
          'Decode p95 | Tile replay / prefetch batches | Tile retained peak | '
          'Cache lookups | Image cache peak | Worker outcomes |',
        )
        ..writeln(
          '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | '
          '---: | ---: | ---: | ---: | --- |',
        );
      for (final name in _scenarioMetrics.keys.toList()..sort()) {
        final metrics = _scenarioMetrics[name]!;
        buffer.writeln(
          '| ${_code(name)} | ${metrics.elapsedMs.length} | '
          '${_distributionText(metrics.elapsedMs)} | '
          '${_p95Text(metrics.jankTotalMs)} | '
          '${_p95Text(metrics.reconcileElapsedMs)} | '
          '${_p95Text(metrics.rasterElapsedMs)} | '
          '${_p95Text(metrics.workerPhases.totalMs)} | '
          '${_p95Text(metrics.workerPhases.decodeMs)} | '
          '${metrics.tiles.replayRequests} / '
          '${metrics.tiles.prefetchBatches} | '
          '${metrics.tiles.retainedPeakText} | '
          '${metrics.workerPhases.cacheLookupText} | '
          '${_formatBytes(metrics.workerPhases.peakImageCacheBytes)} | '
          '${_mapText(metrics.webWorkerOutcomes)} |',
        );
      }
      buffer.writeln();
    }
    buffer
      ..writeln(
        'Artifacts: `patrol-perf.log` (normalized raw trace), '
        '`patrol-perf.json` (machine comparison), '
        '`patrol-perf-headline.md` (visible PR headline), and this full '
        'Markdown summary.',
      )
      ..writeln();
    return buffer.toString();
  }
}

/// Advisory comparison with the most recent successful `main` web artifact.
///
/// Browser timings are intentionally never a pass/fail gate: shared runners,
/// CanvasKit startup, and headless Chrome all add noise. Structural paths and
/// outcomes sit beside the timings so a reviewer can distinguish a genuinely
/// different render/reconcile route from ordinary wall-clock variance.
class PatrolPerfComparison {
  const PatrolPerfComparison({required this.baseline, required this.current});

  final Map<String, dynamic> baseline;
  final Map<String, Object?> current;

  String toHeadlineMarkdown({String? label}) {
    final baselineScenarios = _jsonCountMap(baseline, const ['scenarios']);
    final currentScenarios = _jsonCountMap(current, const ['scenarios']);
    final sameCoverage = _sameMapKeys(baselineScenarios, currentScenarios);
    final measuredScenarios = <String>{
      ..._jsonMapKeys(baseline, const ['scenarioMetrics']),
      ..._jsonMapKeys(current, const ['scenarioMetrics']),
    }.toList()
      ..sort();
    final heading = label == null || label.toLowerCase() == 'web'
        ? '### Headline comparison with `main`'
        : '### $label comparison with `main`';
    final speedup = _gpuTileSpeedupHeadline(current, baseline: baseline);
    final buffer = StringBuffer()..writeln(heading);
    if (speedup != null) {
      buffer
        ..writeln()
        ..writeln(speedup);
    }
    buffer
      ..writeln()
      ..writeln(
        'Lower timing is better. Structural counts should stay stable unless '
        'the PR intentionally changes the exercised path.',
      );
    if (measuredScenarios.isNotEmpty) {
      final samples = measuredScenarios.map((scenario) {
        final before = _jsonNumber(
          baseline,
          ['scenarioMetrics', scenario, 'runs'],
        );
        final after = _jsonNumber(
          current,
          ['scenarioMetrics', scenario, 'runs'],
        );
        return '${_code(scenario)} ${_numberText(before)} / '
            '${_numberText(after)}';
      }).join(', ');
      final sparseSamples = measuredScenarios.any((scenario) {
        final before = _jsonNumber(
          baseline,
          ['scenarioMetrics', scenario, 'runs'],
        );
        final after = _jsonNumber(
          current,
          ['scenarioMetrics', scenario, 'runs'],
        );
        return before == null || after == null || before < 3 || after < 3;
      });
      buffer
        ..writeln()
        ..writeln(
          'Scenario elapsed uses p50 across repeated runs; phase and tail '
          'signals remain p95. Samples (main / PR): $samples.',
        )
        ..writeln()
        ..writeln(
          'When both cohorts have at least four samples, overlapping '
          'interquartile ranges are labelled `within run spread` instead '
          'of showing a misleading percentage.',
        );
      if (sparseSamples) {
        buffer
          ..writeln()
          ..writeln(
            '⚠️ At least one scenario has fewer than three samples; treat '
            'its timing delta as provisional.',
          );
      }
    }
    if (!sameCoverage) {
      buffer
        ..writeln()
        ..writeln(
          '⚠️ Scenario coverage differs from `main`; timing deltas are not '
          'like-for-like.',
        );
    }
    buffer
      ..writeln()
      ..writeln('| Signal | Main | PR | Change |')
      ..writeln('| --- | ---: | ---: | ---: |');

    void countRow(
      String label,
      List<String> path, {
      bool absentIsZero = false,
    }) {
      final before = _jsonNumber(baseline, path, absentIsZero: absentIsZero);
      final after = _jsonNumber(current, path, absentIsZero: absentIsZero);
      buffer.writeln('| $label | ${_numberText(before)} | '
          '${_numberText(after)} | ${_countDelta(before, after)} |');
    }

    void timingRow(String label, List<String> path) {
      final before = _jsonNumber(baseline, path);
      final after = _jsonNumber(current, path);
      if (before == null && after == null) return;
      buffer.writeln('| $label | ${_timingText(before)} | '
          '${_timingText(after)} | ${_percentDelta(before, after)} |');
    }

    for (final scenario in measuredScenarios) {
      final path = ['scenarioMetrics', scenario, 'elapsedMs', 'p50'];
      final before = _jsonNumber(baseline, path);
      final after = _jsonNumber(current, path);
      if (before == null && after == null) continue;
      buffer.writeln('| Scenario ${_code(scenario)} elapsed p50 | '
          '${_timingText(before)} | ${_timingText(after)} | '
          '${_scenarioElapsedDelta(baseline, current, scenario)} |');
    }
    timingRow('Jank total p95', const ['jank', 'totalMs', 'p95']);
    timingRow('Reconcile p95', const ['reconciliation', 'elapsedMs', 'p95']);
    timingRow('Raster p95', const ['rasters', 'elapsedMs', 'p95']);
    timingRow(
      'Worker phase total p95',
      const ['webWorker', 'phases', 'totalMs', 'p95'],
    );
    timingRow('Tile replay p95', const ['tiles', 'replayMs', 'p95']);
    countRow('Jank frames', const ['jank', 'count']);
    countRow(
      'Reconcile fallbacks',
      const ['reconciliation', 'fallbackReasons', '*'],
      absentIsZero: true,
    );
    countRow(
      'Page-raster rejects',
      const ['pageRasters', 'outcomes', 'reject'],
      absentIsZero: true,
    );
    countRow(
      'Web-worker fatal fallbacks',
      const ['webWorker', 'outcomes', 'fallback'],
      absentIsZero: true,
    );
    buffer.writeln();
    return buffer.toString();
  }

  String toMarkdown({String? label}) {
    final baselineScenarios = _jsonCountMap(baseline, const ['scenarios']);
    final currentScenarios = _jsonCountMap(current, const ['scenarios']);
    final sameCoverage = _sameMapKeys(baselineScenarios, currentScenarios);
    final measuredScenarios = <String>{
      ..._jsonMapKeys(baseline, const ['scenarioMetrics']),
      ..._jsonMapKeys(current, const ['scenarioMetrics']),
    }.toList()
      ..sort();
    final platform =
        label == null || label.toLowerCase() == 'web' ? '' : ' $label';
    final artifactKind = label == null ? 'web' : label;
    final buffer = StringBuffer()
      ..writeln('## Patrol$platform comparison with `main`')
      ..writeln()
      ..writeln(
        'Advisory only: timing changes do not fail CI. The baseline is the '
        'newest usable $artifactKind artifact from `Patrol E2E` on `main`.',
      )
      ..writeln()
      ..writeln(
        'Scenario elapsed p50 changes are labelled `within run spread` when '
        'both cohorts have at least four samples and their interquartile '
        'ranges overlap.',
      )
      ..write(
        sameCoverage
            ? ''
            : '\nCoverage differs between the artifacts; timing deltas are '
                'not like-for-like until `main` contains the same scenarios.\n',
      )
      ..writeln()
      ..writeln('| Signal | Main | PR | Change |')
      ..writeln('| --- | ---: | ---: | ---: |');

    void countRow(
      String label,
      List<String> path, {
      bool absentIsZero = false,
    }) {
      final before = _jsonNumber(baseline, path, absentIsZero: absentIsZero);
      final after = _jsonNumber(current, path, absentIsZero: absentIsZero);
      buffer.writeln('| $label | ${_numberText(before)} | '
          '${_numberText(after)} | ${_countDelta(before, after)} |');
    }

    void timingRow(
      String label,
      List<String> path, {
      String? change,
    }) {
      final before = _jsonNumber(baseline, path);
      final after = _jsonNumber(current, path);
      buffer.writeln('| $label | ${_timingText(before)} | '
          '${_timingText(after)} | '
          '${change ?? _percentDelta(before, after)} |');
    }

    countRow('Journey segments', const ['journeys']);
    countRow('Perf events', const ['events']);
    countRow('Jank frames', const ['jank', 'count']);
    timingRow('Jank total p95', const ['jank', 'totalMs', 'p95']);
    timingRow('Reconcile p95', const ['reconciliation', 'elapsedMs', 'p95']);
    countRow(
        'Reconcile fallbacks', const ['reconciliation', 'fallbackReasons', '*'],
        absentIsZero: true);
    countRow(
      'Thumbnail preview hits',
      const ['thumbnails', 'paths', 'preview-hit'],
      absentIsZero: true,
    );
    countRow(
      'Page-raster rejects',
      const ['pageRasters', 'outcomes', 'reject'],
      absentIsZero: true,
    );
    countRow(
      'Web-worker ready',
      const ['webWorker', 'outcomes', 'ready'],
    );
    countRow(
      'Web-worker null starts',
      const ['webWorker', 'outcomes', 'start-null'],
      absentIsZero: true,
    );
    countRow(
      'Web-worker fatal fallbacks',
      const ['webWorker', 'outcomes', 'fallback'],
      absentIsZero: true,
    );
    countRow('Worker phase requests', const ['webWorker', 'phases', 'count']);
    timingRow(
      'Worker phase total p95',
      const ['webWorker', 'phases', 'totalMs', 'p95'],
    );
    timingRow(
      'Worker decode p95',
      const ['webWorker', 'phases', 'decodeMs', 'p95'],
    );
    timingRow('Raster p95', const ['rasters', 'elapsedMs', 'p95']);
    countRow('Tile replay requests', const ['tiles', 'replayRequests']);
    countRow(
      'Tile prefetch batches',
      const ['tiles', 'sliceBatchesByClass', 'prefetch'],
    );
    countRow(
      'Tile prefetch tiles',
      const ['tiles', 'slicedTilesByClass', 'prefetch'],
    );
    timingRow('Tile replay p95', const ['tiles', 'replayMs', 'p95']);
    timingRow('Tile replay raster p95', const ['tiles', 'rasterMs', 'p95']);
    for (final scenario in measuredScenarios) {
      countRow(
        'Scenario $scenario runs',
        ['scenarioMetrics', scenario, 'runs'],
      );
      timingRow(
        'Scenario $scenario elapsed p50',
        ['scenarioMetrics', scenario, 'elapsedMs', 'p50'],
        change: _scenarioElapsedDelta(baseline, current, scenario),
      );
      timingRow(
        'Scenario $scenario elapsed p95',
        ['scenarioMetrics', scenario, 'elapsedMs', 'p95'],
      );
      timingRow(
        'Scenario $scenario jank p95',
        ['scenarioMetrics', scenario, 'jank', 'totalMs', 'p95'],
      );
      timingRow(
        'Scenario $scenario reconcile p95',
        [
          'scenarioMetrics',
          scenario,
          'reconciliation',
          'elapsedMs',
          'p95',
        ],
      );
      timingRow(
        'Scenario $scenario raster p95',
        ['scenarioMetrics', scenario, 'rasters', 'elapsedMs', 'p95'],
      );
      timingRow(
        'Scenario $scenario worker total p95',
        ['scenarioMetrics', scenario, 'workerPhases', 'totalMs', 'p95'],
      );
      timingRow(
        'Scenario $scenario decode p95',
        ['scenarioMetrics', scenario, 'workerPhases', 'decodeMs', 'p95'],
      );
      countRow(
        'Scenario $scenario tile replay requests',
        ['scenarioMetrics', scenario, 'tiles', 'replayRequests'],
      );
      countRow(
        'Scenario $scenario tile prefetch batches',
        [
          'scenarioMetrics',
          scenario,
          'tiles',
          'sliceBatchesByClass',
          'prefetch',
        ],
      );
    }

    buffer
      ..writeln()
      ..writeln('| Structural signal | Main | PR |')
      ..writeln('| --- | --- | --- |')
      ..writeln(_mapComparisonRow(
          'Scenarios', const ['scenarios'], baseline, current))
      ..writeln(_mapComparisonRow('Reconcile modes',
          const ['reconciliation', 'modes'], baseline, current))
      ..writeln(_mapComparisonRow('Fallback reasons',
          const ['reconciliation', 'fallbackReasons'], baseline, current))
      ..writeln(_mapComparisonRow(
          'Thumbnail paths', const ['thumbnails', 'paths'], baseline, current))
      ..writeln(_mapComparisonRow('Page-raster outcomes',
          const ['pageRasters', 'outcomes'], baseline, current))
      ..writeln(_mapComparisonRow('Web-worker outcomes',
          const ['webWorker', 'outcomes'], baseline, current))
      ..writeln(_mapComparisonRow('Worker request kinds',
          const ['webWorker', 'phases', 'kinds'], baseline, current))
      ..writeln(_mapComparisonRow('Worker phase outcomes',
          const ['webWorker', 'phases', 'outcomes'], baseline, current))
      ..writeln(_mapComparisonRow('Worker transcript paths',
          const ['webWorker', 'phases', 'transcripts'], baseline, current))
      ..writeln(_mapComparisonRow('Tile slice classes',
          const ['tiles', 'sliceBatchesByClass'], baseline, current))
      ..writeln(_mapComparisonRow('Tile rung/class batches',
          const ['tiles', 'sliceBatchesByRungClass'], baseline, current))
      ..writeAll(
        measuredScenarios.map(
          (scenario) => _mapComparisonRow(
            'Scenario $scenario worker outcomes',
            ['scenarioMetrics', scenario, 'webWorkerOutcomes'],
            baseline,
            current,
          ),
        ),
        '\n',
      )
      ..writeln()
      ..writeln(
          'Baseline build: ${_code('${baseline['build'] ?? 'unstamped'}')}.')
      ..writeln();
    return buffer.toString();
  }
}

class _ActiveScenario {
  const _ActiveScenario(this.startedAtMs, this.metrics);

  final int startedAtMs;
  final _ScenarioMetrics metrics;
}

class _ScenarioMetrics {
  final elapsedMs = <double>[];
  final jankTotalMs = <double>[];
  final reconcileElapsedMs = <double>[];
  final rasterElapsedMs = <double>[];
  final webWorkerOutcomes = <String, int>{};
  final workerPhases = _WorkerPhaseMetrics();
  final tiles = _TileMetrics();

  void record(
    String event,
    String message,
    Map<String, String> fields,
  ) {
    if (event == 'JANK') {
      _addMilliseconds(jankTotalMs, fields['total']);
    } else if (event == 'page-reconcile') {
      _addMilliseconds(reconcileElapsedMs, fields['elapsed']);
    } else if (event == 'raster') {
      _addMilliseconds(rasterElapsedMs, fields['ms']);
    } else if (event == 'webworker') {
      final outcome = _webWorkerOutcome(message);
      if (outcome != null) _increment(webWorkerOutcomes, outcome);
      if (message.startsWith('webworker phase ')) {
        workerPhases.record(fields);
      }
    } else if (event == 'tile') {
      tiles.record(message, fields);
    }
  }

  Map<String, Object?> toJson() => {
        'runs': elapsedMs.length,
        'elapsedMs': _distribution(elapsedMs),
        // Retain the small per-scenario sample set so PR comparisons can
        // distinguish a shifted distribution from overlapping runner noise.
        'elapsedSamplesMs': List<double>.unmodifiable(elapsedMs),
        'jank': {
          'count': jankTotalMs.length,
          'totalMs': _distribution(jankTotalMs),
        },
        'reconciliation': {
          'count': reconcileElapsedMs.length,
          'elapsedMs': _distribution(reconcileElapsedMs),
        },
        'rasters': {
          'count': rasterElapsedMs.length,
          'elapsedMs': _distribution(rasterElapsedMs),
        },
        'workerPhases': workerPhases.toJson(),
        'tiles': tiles.toJson(),
        'webWorkerOutcomes': _sortedMap(webWorkerOutcomes),
      };
}

class _WorkerPhaseMetrics {
  final queueMs = <double>[];
  final workerMs = <double>[];
  final decodeMs = <double>[];
  final transferMs = <double>[];
  final deserializeMs = <double>[];
  final totalMs = <double>[];
  final kinds = <String, int>{};
  final outcomes = <String, int>{};
  final transcripts = <String, int>{};
  final imageCacheBytes = <int>[];
  var imageCacheDeltaSamples = 0;
  var imageCacheHits = 0;
  var imageCacheMisses = 0;
  var imageCacheRequestsWithHits = 0;
  var imageCacheMissOnlyRequests = 0;
  var imageCacheNoLookupRequests = 0;
  var netImageCacheEntries = 0;
  var netImageCacheBytes = 0;

  int get peakImageCacheBytes => imageCacheBytes.isEmpty
      ? 0
      : imageCacheBytes.reduce((a, b) => a > b ? a : b);

  String get cacheLookupText {
    final lookups = imageCacheHits + imageCacheMisses;
    final rate = lookups == 0
        ? 'n/a'
        : '${(imageCacheHits * 100 / lookups).toStringAsFixed(1)}% hit';
    return '$imageCacheHits hit / $imageCacheMisses miss ($rate)';
  }

  String get cacheRequestPathText => '$imageCacheRequestsWithHits reuse / '
      '$imageCacheMissOnlyRequests miss-only / '
      '$imageCacheNoLookupRequests no-lookup';

  void record(Map<String, String> fields) {
    _addMilliseconds(queueMs, fields['queue']);
    _addMilliseconds(workerMs, fields['worker']);
    _addMilliseconds(decodeMs, fields['decode']);
    _addMilliseconds(transferMs, fields['transfer']);
    _addMilliseconds(deserializeMs, fields['deserialize']);
    _addMilliseconds(totalMs, fields['total']);
    _increment(kinds, fields['kind'] ?? 'unknown');
    _increment(outcomes, fields['outcome'] ?? 'unknown');
    _increment(transcripts, fields['transcript'] ?? 'unknown');
    final cache = fields['cache'];
    final match = cache == null ? null : _workerImageCache.firstMatch(cache);
    if (match != null) imageCacheBytes.add(int.parse(match.group(4)!));
    final delta = fields['cacheDelta'];
    final deltaMatch =
        delta == null ? null : _workerImageCacheDelta.firstMatch(delta);
    if (deltaMatch != null) {
      imageCacheDeltaSamples++;
      final hits = int.parse(deltaMatch.group(1)!);
      final misses = int.parse(deltaMatch.group(2)!);
      imageCacheHits += hits;
      imageCacheMisses += misses;
      netImageCacheEntries += int.parse(deltaMatch.group(3)!);
      netImageCacheBytes += int.parse(deltaMatch.group(4)!);
      if (hits > 0) {
        imageCacheRequestsWithHits++;
      } else if (misses > 0) {
        imageCacheMissOnlyRequests++;
      } else {
        imageCacheNoLookupRequests++;
      }
    }
  }

  Map<String, Object?> toJson() => {
        'count': totalMs.length,
        'queueMs': _distribution(queueMs),
        'workerMs': _distribution(workerMs),
        'decodeMs': _distribution(decodeMs),
        'transferMs': _distribution(transferMs),
        'deserializeMs': _distribution(deserializeMs),
        'totalMs': _distribution(totalMs),
        'kinds': _sortedMap(kinds),
        'outcomes': _sortedMap(outcomes),
        'transcripts': _sortedMap(transcripts),
        'imageCacheBytes': {
          'samples': imageCacheBytes.length,
          'max': peakImageCacheBytes,
        },
        'imageCacheActivity': {
          'samples': imageCacheDeltaSamples,
          'hits': imageCacheHits,
          'misses': imageCacheMisses,
          'requestsWithHits': imageCacheRequestsWithHits,
          'missOnlyRequests': imageCacheMissOnlyRequests,
          'noLookupRequests': imageCacheNoLookupRequests,
          'netEntries': netImageCacheEntries,
          'netBytes': netImageCacheBytes,
        },
      };
}

class _TileMetrics {
  var replayRequests = 0;
  var sliceBatches = 0;
  var slicedTiles = 0;
  final replayMs = <double>[];
  final rasterMs = <double>[];
  final sliceElapsedMs = <double>[];
  final sliceBatchesByClass = <String, int>{};
  final slicedTilesByClass = <String, int>{};
  final sliceBatchesByRungClass = <String, int>{};
  final retainedBytes = <int>[];
  final retainedEntries = <int>[];
  final budgetBytes = <int>[];
  var policySamples = 0;
  var scheduled = 0;
  var landed = 0;
  var discarded = 0;
  var staticRescheduled = 0;

  int get prefetchBatches => sliceBatchesByClass['prefetch'] ?? 0;

  int get peakRetainedBytes =>
      retainedBytes.isEmpty ? 0 : retainedBytes.reduce((a, b) => a > b ? a : b);

  int get peakRetainedEntries => retainedEntries.isEmpty
      ? 0
      : retainedEntries.reduce((a, b) => a > b ? a : b);

  int get peakBudgetBytes =>
      budgetBytes.isEmpty ? 0 : budgetBytes.reduce((a, b) => a > b ? a : b);

  String get discardRateText => scheduled == 0
      ? 'n/a'
      : '${(discarded * 100 / scheduled).toStringAsFixed(1)}%';

  String get sliceClassText {
    if (sliceBatchesByClass.isEmpty) return 'none';
    final classes = sliceBatchesByClass.keys.toList()..sort();
    return classes.map((name) {
      final batches = sliceBatchesByClass[name]!;
      final tiles = slicedTilesByClass[name] ?? 0;
      return '${_code(name)} $batches '
          '${batches == 1 ? 'batch' : 'batches'} / $tiles '
          '${tiles == 1 ? 'tile' : 'tiles'}';
    }).join(', ');
  }

  String get retainedPeakText {
    if (retainedBytes.isEmpty && retainedEntries.isEmpty) return 'n/a';
    return '${_formatBytes(peakRetainedBytes)} / $peakRetainedEntries entries';
  }

  void record(String message, Map<String, String> fields) {
    if (message.startsWith('tile replay ')) {
      replayRequests++;
      _addMilliseconds(replayMs, fields['replay']);
      _addMilliseconds(rasterMs, fields['raster']);
      return;
    }
    if (message.startsWith('tile stats ')) {
      policySamples++;
      final budget = int.tryParse(fields['budget'] ?? '');
      if (budget != null) budgetBytes.add(budget);
      scheduled += int.tryParse(fields['scheduled'] ?? '') ?? 0;
      landed += int.tryParse(fields['landed'] ?? '') ?? 0;
      discarded += int.tryParse(fields['discarded'] ?? '') ?? 0;
      staticRescheduled += int.tryParse(fields['staticRescheduled'] ?? '') ?? 0;
      final retained = int.tryParse(fields['retained'] ?? '');
      if (retained != null) retainedBytes.add(retained);
      final entries = int.tryParse(fields['entries'] ?? '');
      if (entries != null) retainedEntries.add(entries);
      return;
    }
    if (!message.startsWith('tile slice ')) return;

    sliceBatches++;
    final tileCount = int.tryParse(fields['tiles'] ?? '') ?? 0;
    slicedTiles += tileCount;
    final tileClass = fields['class'] ?? 'unknown';
    sliceBatchesByClass[tileClass] = (sliceBatchesByClass[tileClass] ?? 0) + 1;
    slicedTilesByClass[tileClass] =
        (slicedTilesByClass[tileClass] ?? 0) + tileCount;
    final rung = fields['rung'] ?? 'unknown';
    final rungClass = 'rung-$rung/$tileClass';
    sliceBatchesByRungClass[rungClass] =
        (sliceBatchesByRungClass[rungClass] ?? 0) + 1;
    _addMilliseconds(sliceElapsedMs, fields['elapsed']);
    final retained = int.tryParse(fields['retained'] ?? '');
    if (retained != null) retainedBytes.add(retained);
    final entries = int.tryParse(fields['entries'] ?? '');
    if (entries != null) retainedEntries.add(entries);
  }

  Map<String, Object?> toJson() => {
        'replayRequests': replayRequests,
        'replayMs': _distribution(replayMs),
        'rasterMs': _distribution(rasterMs),
        'sliceBatches': sliceBatches,
        'slicedTiles': slicedTiles,
        'sliceElapsedMs': _distribution(sliceElapsedMs),
        'sliceBatchesByClass': _sortedMap(sliceBatchesByClass),
        'slicedTilesByClass': _sortedMap(slicedTilesByClass),
        'sliceBatchesByRungClass': _sortedMap(sliceBatchesByRungClass),
        'retainedBytes': {
          'samples': retainedBytes.length,
          'max': peakRetainedBytes,
        },
        'retainedEntries': {
          'samples': retainedEntries.length,
          'max': peakRetainedEntries,
        },
        'policy': {
          'samples': policySamples,
          'budgetBytes': {
            'samples': budgetBytes.length,
            'max': peakBudgetBytes,
          },
          'scheduled': scheduled,
          'landed': landed,
          'discarded': discarded,
          'staticRescheduled': staticRescheduled,
        },
      };
}

bool _completesScenario(String phase) =>
    phase == 'validated' ||
    phase == 'complete' ||
    phase == 'completed' ||
    phase == 'end';

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

String? _webWorkerOutcome(String message) {
  if (message.startsWith('webworker startRenderWorker')) {
    return message.contains('url=null') ? 'start-null' : 'start-configured';
  }
  if (message.startsWith('webworker ready ')) return 'ready';
  if (message.startsWith('webworker result ')) {
    if (message.contains('→ worker')) return 'result-worker';
    // Some individual pages deliberately decline when their image mix cannot
    // travel through the worker. Keep that ordinary per-record local path
    // distinct from a dead worker falling back for the whole session.
    if (message.contains('→ local')) return 'result-local';
  }
  if (message.contains('falling back to local') ||
      message.contains('watchdog fired')) {
    return 'fallback';
  }
  return null;
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

String _p95Text(List<double> values) {
  final distribution = _distribution(values);
  return distribution == null ? 'n/a' : _formatMs(distribution['p95']!);
}

String _p50Text(List<double> values) {
  final distribution = _distribution(values);
  return distribution == null ? 'n/a' : _formatMs(distribution['p50']!);
}

String _mapText(Map<String, int> values) {
  if (values.isEmpty) return 'none';
  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map((entry) => '${_code(entry.key)} ${entry.value}')
      .join(', ');
}

num? _jsonNumber(
  Object? root,
  List<String> path, {
  bool absentIsZero = false,
}) {
  Object? value = root;
  for (var i = 0; i < path.length; i++) {
    final part = path[i];
    if (part == '*') {
      if (value is! Map) return null;
      var total = 0.0;
      for (final item in value.values) {
        if (item is num) {
          total += item;
        }
      }
      return total;
    }
    if (value is! Map) return null;
    if (!value.containsKey(part)) {
      return absentIsZero && i == path.length - 1 ? 0 : null;
    }
    value = value[part];
  }
  return value is num ? value : null;
}

Map<String, int> _jsonCountMap(Object? root, List<String> path) {
  Object? value = root;
  for (final part in path) {
    if (value is! Map || !value.containsKey(part)) return const {};
    value = value[part];
  }
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.value is num) '${entry.key}': (entry.value as num).round(),
  };
}

Set<String> _jsonMapKeys(Object? root, List<String> path) {
  Object? value = root;
  for (final part in path) {
    if (value is! Map || !value.containsKey(part)) return const {};
    value = value[part];
  }
  return value is Map
      ? value.keys.map((key) => key.toString()).toSet()
      : const {};
}

List<double> _jsonNumberList(Object? root, List<String> path) {
  Object? value = root;
  for (final part in path) {
    if (value is! Map || !value.containsKey(part)) return const [];
    value = value[part];
  }
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is num) item.toDouble(),
  ];
}

String _scenarioElapsedDelta(
  Object? baseline,
  Object? current,
  String scenario,
) {
  final before = _jsonNumber(
    baseline,
    ['scenarioMetrics', scenario, 'elapsedMs', 'p50'],
  );
  final after = _jsonNumber(
    current,
    ['scenarioMetrics', scenario, 'elapsedMs', 'p50'],
  );
  final beforeSamples = _jsonNumberList(
    baseline,
    ['scenarioMetrics', scenario, 'elapsedSamplesMs'],
  );
  final afterSamples = _jsonNumberList(
    current,
    ['scenarioMetrics', scenario, 'elapsedSamplesMs'],
  );
  if (_interquartileRangesOverlap(beforeSamples, afterSamples)) {
    return 'within run spread';
  }
  return _percentDelta(before, after);
}

bool _interquartileRangesOverlap(List<double> a, List<double> b) {
  if (a.length < 4 || b.length < 4) return false;
  final sortedA = List<double>.of(a)..sort();
  final sortedB = List<double>.of(b)..sort();
  final aLow = _percentile(sortedA, 0.25);
  final aHigh = _percentile(sortedA, 0.75);
  final bLow = _percentile(sortedB, 0.25);
  final bHigh = _percentile(sortedB, 0.75);
  return aLow <= bHigh && bLow <= aHigh;
}

typedef _GpuTileSpeedup = ({
  double firstTileMs,
  double canvasTileMs,
  double? pairedSpeedup,
});

Map<String, _GpuTileSpeedup> _gpuTileSpeedups(Object? trace) {
  const suffix = '-first-tile';
  final result = <String, _GpuTileSpeedup>{};
  final scenarios = _jsonMapKeys(trace, const ['scenarioMetrics']).toList()
    ..sort();
  for (final scenario in scenarios) {
    if (!scenario.startsWith('gpu-') || !scenario.endsWith(suffix)) continue;
    final prefix = scenario.substring(0, scenario.length - suffix.length);
    final firstTile = _jsonNumber(
      trace,
      ['scenarioMetrics', scenario, 'elapsedMs', 'p50'],
    );
    final canvasTile = _jsonNumber(
      trace,
      ['scenarioMetrics', '$prefix-canvas-tile', 'elapsedMs', 'p50'],
    );
    if (firstTile == null || canvasTile == null || firstTile <= 0) continue;
    final firstTileSamples = _jsonNumberList(
      trace,
      ['scenarioMetrics', scenario, 'elapsedSamplesMs'],
    );
    final canvasTileSamples = _jsonNumberList(
      trace,
      ['scenarioMetrics', '$prefix-canvas-tile', 'elapsedSamplesMs'],
    );
    final pairedRatios = <double>[];
    if (firstTileSamples.length == canvasTileSamples.length) {
      for (var i = 0; i < firstTileSamples.length; i++) {
        final first = firstTileSamples[i];
        if (first > 0) pairedRatios.add(canvasTileSamples[i] / first);
      }
    }
    final sortedRatios = List<double>.of(pairedRatios)..sort();
    result[prefix.substring('gpu-'.length).replaceAll('-', ' ')] = (
      firstTileMs: firstTile.toDouble(),
      canvasTileMs: canvasTile.toDouble(),
      pairedSpeedup:
          sortedRatios.isEmpty ? null : _percentile(sortedRatios, 0.50),
    );
  }
  return result;
}

String? _gpuTileSpeedupHeadline(
  Object? current, {
  Object? baseline,
}) {
  final before = baseline == null
      ? const <String, _GpuTileSpeedup>{}
      : _gpuTileSpeedups(baseline);
  final after = _gpuTileSpeedups(current);
  final workloads = <String>{...before.keys, ...after.keys}.toList()..sort();
  if (workloads.isEmpty) return null;

  String speedup(_GpuTileSpeedup? value) => value == null
      ? 'n/a'
      : '${_ratioText(value.pairedSpeedup ?? value.canvasTileMs / value.firstTileMs)}×';

  if (baseline != null) {
    final values = workloads.map(
        (workload) => '${_code(workload)} **${speedup(before[workload])} → '
            '${speedup(after[workload])}**');
    return '**First tile vs Canvas (p50, main → PR):** '
        '${values.join('; ')}.';
  }

  final values = workloads.map((workload) {
    final value = after[workload]!;
    return '${_code(workload)} **${speedup(value)}** '
        '(${_formatMs(value.firstTileMs)} vs '
        '${_formatMs(value.canvasTileMs)})';
  });
  return '**First tile vs Canvas (p50):** ${values.join('; ')}.';
}

String _ratioText(double value) =>
    value < 1 ? value.toStringAsFixed(2) : value.toStringAsFixed(1);

bool _sameMapKeys(Map<String, int> a, Map<String, int> b) =>
    a.length == b.length && a.keys.every(b.containsKey);

String _mapComparisonRow(
  String label,
  List<String> path,
  Object? baseline,
  Object? current,
) =>
    '| $label | ${_mapText(_jsonCountMap(baseline, path))} | '
    '${_mapText(_jsonCountMap(current, path))} |';

String _numberText(num? value) {
  if (value == null) return 'n/a';
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

String _timingText(num? value) =>
    value == null ? 'n/a' : _formatMs(value.toDouble());

String _countDelta(num? before, num? after) {
  if (before == null || after == null) return 'n/a';
  final delta = after - before;
  if (delta == 0) return '—';
  return '${delta > 0 ? '+' : ''}${_numberText(delta)}';
}

String _percentDelta(num? before, num? after) {
  if (before == null || after == null || before == 0) return 'n/a';
  final percent = (after / before - 1) * 100;
  if (percent.abs() < 0.05) return '—';
  return '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1)}%';
}

String _formatMs(double value) => '${value.toStringAsFixed(1)} ms';

String _formatBytes(int value) {
  if (value <= 0) return 'n/a';
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  return '$value B';
}

String _formatSignedBytes(int value) {
  if (value == 0) return '0 B';
  final sign = value > 0 ? '+' : '-';
  final magnitude = value.abs();
  if (magnitude >= 1024 * 1024) {
    return '$sign${(magnitude / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (magnitude >= 1024) {
    return '$sign${(magnitude / 1024).toStringAsFixed(1)} KiB';
  }
  return '$sign$magnitude B';
}

String _code(String value) => '`$value`';
