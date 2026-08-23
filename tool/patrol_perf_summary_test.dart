import 'patrol_perf_summary.dart' as summary;

void main() {
  final trace = summary.PatrolPerfTrace.parse(const [
    '[perf 0] build commit=test',
    '[perf 10] scenario name=heavy-document phase=start',
    '[perf 20] JANK build=1ms raster=2ms total=3ms',
    '[perf 25] scenario name=web-worker phase=start',
    '[perf 30] webworker startRenderWorker generation=1 '
        'url=pdf_render_worker.dart.js',
    '[perf 35] webworker ready generation=1',
    '[perf 36] webworker phase worker=0 kind=record page=0 '
        'outcome=presented queue=1.0ms worker=8.0ms parse=0.5ms '
        'interpret=1.0ms stream=2.0ms decode=4.0ms serialize=0.5ms '
        'bin=0.0ms transfer=2.0ms deserialize=1.0ms total=12.0ms '
        'transcript=miss imageDecode=codec=2 '
        'cache=2h/3m/4e/8388608B '
        'cacheDelta=2h/3m/4e/8388608B',
    '[perf 37] webworker phase worker=0 kind=detail page=0 '
        'outcome=presented queue=0.5ms worker=7.0ms parse=0.0ms '
        'interpret=0.0ms stream=0.0ms decode=0.0ms serialize=2.0ms '
        'bin=1.0ms transfer=1.0ms deserialize=0.5ms total=9.0ms '
        'transcript=hit imageDecode=none '
        'cache=2h/3m/4e/8388608B cacheDelta=0h/0m/0e/0B',
    '[perf 38] tile replay page=0 region=256x256pt ratio=2.83 '
        'selected=40/100 replay=2.0ms raster=5.0ms img=725x725',
    '[perf 39] tile slice page=0 rung=3 class=prefetch tiles=4 '
        'elapsed=3.0ms retained=8388608 entries=8',
    '[perf 40] tile stats platform=android budget=67108864 '
        'retained=8388608 entries=8 scheduled=12 landed=10 discarded=2 '
        'staticRescheduled=0',
    '[perf 41] raster page=0 ms=12.5',
    '[perf 45] webworker result kind=record page=0 commands=1 → worker',
    '[perf 47] webworker result kind=record page=1 declined (null) → local',
    '[perf 55] scenario name=web-worker phase=validated',
    '[perf 60] page-reconcile mode=incremental elapsed=1.5ms',
    '[perf 90] scenario name=heavy-document phase=validated',
  ]);
  final json = trace.toJson();
  _expectEqual(json['schema'], 8, 'schema');

  final workerPhases = _map(_map(json, 'webWorker'), 'phases');
  _expectEqual(workerPhases['count'], 2, 'worker phase count');
  _expectEqual(
    _map(workerPhases, 'totalMs')['p95'],
    12.0,
    'worker total phase',
  );
  _expectEqual(
    _map(workerPhases, 'decodeMs')['p95'],
    4.0,
    'worker decode phase',
  );
  _expectEqual(
    _map(workerPhases, 'imageCacheBytes')['max'],
    8388608,
    'worker image cache peak',
  );
  _expectEqual(
    _map(workerPhases, 'imageCacheActivity'),
    const {
      'samples': 2,
      'hits': 2,
      'misses': 3,
      'requestsWithHits': 1,
      'missOnlyRequests': 0,
      'noLookupRequests': 1,
      'netEntries': 4,
      'netBytes': 8388608,
    },
    'worker image cache activity',
  );

  final tiles = _map(json, 'tiles');
  _expectEqual(tiles['replayRequests'], 1, 'tile replay requests');
  _expectEqual(tiles['sliceBatches'], 1, 'tile slice batches');
  _expectEqual(tiles['slicedTiles'], 4, 'sliced tiles');
  _expectEqual(
    _map(tiles, 'sliceBatchesByClass'),
    const {'prefetch': 1},
    'tile slice classes',
  );
  _expectEqual(
    _map(tiles, 'sliceBatchesByRungClass'),
    const {'rung-3/prefetch': 1},
    'tile rung classes',
  );
  _expectEqual(
    _map(tiles, 'retainedBytes')['max'],
    8388608,
    'tile retained bytes',
  );
  final tilePolicy = _map(tiles, 'policy');
  _expectEqual(tilePolicy['samples'], 1, 'tile policy samples');
  _expectEqual(
    _map(tilePolicy, 'budgetBytes')['max'],
    67108864,
    'tile policy budget',
  );
  _expectEqual(tilePolicy['scheduled'], 12, 'tile policy scheduled');
  _expectEqual(tilePolicy['landed'], 10, 'tile policy landed');
  _expectEqual(tilePolicy['discarded'], 2, 'tile policy discarded');
  _expectEqual(
    tilePolicy['staticRescheduled'],
    0,
    'tile policy static reschedules',
  );

  final scenarios = _map(json, 'scenarioMetrics');
  final heavy = _map(scenarios, 'heavy-document');
  _expectEqual(heavy['runs'], 1, 'heavy runs');
  _expectEqual(_map(heavy, 'elapsedMs')['p95'], 80.0, 'heavy elapsed');
  _expectEqual(
    _map(_map(heavy, 'jank'), 'totalMs')['p95'],
    3.0,
    'heavy jank',
  );
  _expectEqual(
    _map(_map(heavy, 'reconciliation'), 'elapsedMs')['p95'],
    1.5,
    'heavy reconcile',
  );
  _expectEqual(
    _map(_map(heavy, 'rasters'), 'elapsedMs')['p95'],
    12.5,
    'heavy raster',
  );
  _expectEqual(
    _map(heavy, 'webWorkerOutcomes'),
    const {
      'ready': 1,
      'result-local': 1,
      'result-worker': 1,
      'start-configured': 1,
    },
    'heavy worker outcomes',
  );
  _expectEqual(
    _map(_map(heavy, 'workerPhases'), 'totalMs')['p95'],
    12.0,
    'heavy worker total phase',
  );

  final worker = _map(scenarios, 'web-worker');
  _expectEqual(worker['runs'], 1, 'worker runs');
  _expectEqual(_map(worker, 'elapsedMs')['p95'], 30.0, 'worker elapsed');
  _expectEqual(_map(worker, 'jank')['count'], 0, 'worker jank count');
  _expectEqual(
    _map(worker, 'reconciliation')['count'],
    0,
    'worker reconcile count',
  );

  final markdown = trace.toMarkdown();
  _expectContains(markdown, '### Scenario breakdown', 'scenario heading');
  _expectContains(
    markdown,
    '| `heavy-document` | 1 | 80.0 ms / 80.0 ms / 80.0 ms |',
    'heavy scenario row',
  );
  _expectContains(markdown, '| Worker image-cache peak | 8.0 MiB |',
      'worker cache summary');
  _expectContains(
    markdown,
    '| Worker image-cache lookups | 2 hit / 3 miss (40.0% hit) |',
    'worker cache lookups',
  );
  _expectContains(
    markdown,
    '| Worker image-cache request paths | 1 reuse / 0 miss-only / 1 no-lookup |',
    'worker cache request paths',
  );
  _expectContains(
    markdown,
    '| Worker image-cache net growth | 4 entries / +8.0 MiB |',
    'worker cache growth',
  );
  _expectContains(
    markdown,
    '| Tile slice classes | `prefetch` 1 batch / 4 tiles |',
    'tile class summary',
  );
  _expectContains(
    markdown,
    '| Tile retained peak | 8.0 MiB / 8 entries |',
    'tile retained summary',
  );
  _expectContains(
    markdown,
    '| Tile budget peak | 64.0 MiB |',
    'tile budget summary',
  );
  _expectContains(
    markdown,
    '| Tile discard rate | 16.7% |',
    'tile discard summary',
  );
  _expectContains(
    trace.toMarkdown(label: 'Android'),
    '## Patrol Android performance',
    'platform heading',
  );
  final headline = trace.toHeadlineMarkdown(label: 'Android');
  _expectContains(headline, '### Android headline', 'headline heading');
  _expectContains(
    headline,
    '| Jank total p95 | 3.0 ms |',
    'headline jank',
  );
  _expectContains(
    headline,
    '| Scenario `heavy-document` elapsed p50 (1 run) | 80.0 ms |',
    'headline scenario',
  );

  final comparison = summary.PatrolPerfComparison(
    baseline: {
      'build': 'commit=main',
      'scenarios': json['scenarios'],
      'tiles': {
        'replayRequests': 2,
        'sliceBatchesByClass': {'prefetch': 2},
        'slicedTilesByClass': {'prefetch': 8},
        'replayMs': {'p95': 4.0},
        'rasterMs': {'p95': 10.0},
      },
      'scenarioMetrics': {
        'heavy-document': {
          'runs': 1,
          'elapsedMs': {'p50': 100.0, 'p95': 100.0},
          'jank': {
            'totalMs': {'p95': 4.0},
          },
          'rasters': {
            'elapsedMs': {'p95': 10.0},
          },
        },
      },
    },
    current: json,
  ).toMarkdown();
  _expectContains(
    comparison,
    '| Scenario heavy-document elapsed p50 | 100.0 ms | 80.0 ms | -20.0% |',
    'scenario median comparison',
  );
  _expectContains(
    comparison,
    '| Scenario heavy-document elapsed p95 | 100.0 ms | 80.0 ms | -20.0% |',
    'scenario tail comparison',
  );
  _expectContains(
    comparison,
    '| Web-worker fatal fallbacks | n/a | 0 | n/a |',
    'missing current fallback is zero',
  );
  _expectContains(
    comparison,
    '| Scenario heavy-document worker total p95 | n/a | 12.0 ms | n/a |',
    'scenario worker comparison',
  );
  _expectContains(
    comparison,
    '| Tile prefetch batches | 2 | 1 | -1 |',
    'tile prefetch comparison',
  );
  final comparisonHeadline = summary.PatrolPerfComparison(
    baseline: {
      'scenarios': json['scenarios'],
      'jank': {
        'count': 2,
        'totalMs': {'p95': 4.0},
      },
      'scenarioMetrics': {
        'heavy-document': {
          'runs': 1,
          'elapsedMs': {'p50': 100.0, 'p95': 100.0},
        },
      },
    },
    current: json,
  ).toHeadlineMarkdown();
  _expectContains(
    comparisonHeadline,
    '### Headline comparison with `main`',
    'comparison headline heading',
  );
  final androidComparison = summary.PatrolPerfComparison(
    baseline: {'scenarios': json['scenarios']},
    current: json,
  );
  _expectContains(
    androidComparison.toHeadlineMarkdown(label: 'Android'),
    '### Android comparison with `main`',
    'platform comparison headline',
  );
  _expectContains(
    androidComparison.toMarkdown(label: 'Android'),
    'newest usable Android artifact',
    'platform baseline description',
  );
  _expectContains(
    comparisonHeadline,
    '| Jank total p95 | 4.0 ms | 3.0 ms | -25.0% |',
    'comparison headline jank',
  );
  _expectContains(
    comparisonHeadline,
    '| Scenario `heavy-document` elapsed p50 | 100.0 ms | 80.0 ms | -20.0% |',
    'comparison headline scenario',
  );
  _expectContains(
    comparisonHeadline,
    'fewer than three samples',
    'sparse comparison warning',
  );
  final sparseHeadline = summary.PatrolPerfComparison(
    baseline: const {'scenarios': <String, Object?>{}},
    current: const {'scenarios': <String, Object?>{}},
  ).toHeadlineMarkdown();
  _expectNotContains(
    sparseHeadline,
    'Worker phase total p95',
    'missing headline metrics',
  );

  final resetTrace = summary.PatrolPerfTrace.parse(const [
    '[perf 0] scenario name=orphan phase=start',
    '[perf 5] JANK build=1ms raster=1ms total=2ms',
    '[perf 0] build commit=next-process',
    '[perf 10] scenario name=orphan phase=validated',
  ]).toJson();
  final orphan = _map(_map(resetTrace, 'scenarioMetrics'), 'orphan');
  _expectEqual(orphan['runs'], 0, 'cross-process scenario is incomplete');
  _expectEqual(orphan['elapsedMs'], null, 'cross-process elapsed is absent');

  final repeatedTrace = summary.PatrolPerfTrace.parse(const [
    '[perf 0] build commit=repeated',
    '[perf 10] scenario name=repeatable phase=start',
    '[perf 110] scenario name=repeatable phase=validated',
    '[perf 0] build commit=repeated',
    '[perf 10] scenario name=repeatable phase=start',
    '[perf 310] scenario name=repeatable phase=validated',
    '[perf 0] build commit=repeated',
    '[perf 10] scenario name=repeatable phase=start',
    '[perf 210] scenario name=repeatable phase=validated',
  ]);
  final repeatedJson = repeatedTrace.toJson();
  final repeatedScenario =
      _map(_map(repeatedJson, 'scenarioMetrics'), 'repeatable');
  _expectEqual(repeatedScenario['runs'], 3, 'repeated scenario runs');
  _expectEqual(
    _map(repeatedScenario, 'elapsedMs'),
    const {'p50': 200.0, 'p95': 300.0, 'max': 300.0},
    'repeated scenario distribution',
  );
  _expectContains(
    repeatedTrace.toHeadlineMarkdown(),
    '| Scenario `repeatable` elapsed p50 (3 runs) | 200.0 ms |',
    'repeated headline median',
  );
  final repeatedComparison = summary.PatrolPerfComparison(
    baseline: repeatedJson,
    current: repeatedJson,
  ).toHeadlineMarkdown();
  _expectContains(
    repeatedComparison,
    'Samples (main / PR): `repeatable` 3 / 3.',
    'repeated comparison sample counts',
  );
  _expectNotContains(
    repeatedComparison,
    'fewer than three samples',
    'repeated comparison is not sparse',
  );

  print('Patrol performance summarizer tests passed');
}

Map<String, Object?> _map(Object? parent, String key) {
  if (parent is! Map || parent[key] is! Map) {
    throw StateError('$key is not a map: $parent');
  }
  return Map<String, Object?>.from(parent[key] as Map);
}

void _expectEqual(Object? actual, Object? expected, String label) {
  if (actual is Map && expected is Map) {
    if (actual.length == expected.length &&
        actual.entries.every((entry) => expected[entry.key] == entry.value)) {
      return;
    }
  } else if (actual == expected) {
    return;
  }
  throw StateError('$label: expected $expected, got $actual');
}

void _expectContains(String actual, String expected, String label) {
  if (!actual.contains(expected)) {
    throw StateError('$label: missing "$expected" in:\n$actual');
  }
}

void _expectNotContains(String actual, String unexpected, String label) {
  if (actual.contains(unexpected)) {
    throw StateError(
        '$label: unexpectedly contained "$unexpected" in:\n$actual');
  }
}
