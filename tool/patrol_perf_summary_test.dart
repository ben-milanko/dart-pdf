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
    '[perf 40] raster page=0 ms=12.5',
    '[perf 45] webworker result kind=record page=0 commands=1 → worker',
    '[perf 47] webworker result kind=record page=1 declined (null) → local',
    '[perf 55] scenario name=web-worker phase=validated',
    '[perf 60] page-reconcile mode=incremental elapsed=1.5ms',
    '[perf 90] scenario name=heavy-document phase=validated',
  ]);
  final json = trace.toJson();
  _expectEqual(json['schema'], 4, 'schema');

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

  final comparison = summary.PatrolPerfComparison(
    baseline: {
      'build': 'commit=main',
      'scenarios': json['scenarios'],
      'scenarioMetrics': {
        'heavy-document': {
          'runs': 1,
          'elapsedMs': {'p95': 100.0},
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
    '| Scenario heavy-document elapsed p95 | 100.0 ms | 80.0 ms | -20.0% |',
    'scenario comparison',
  );
  _expectContains(
    comparison,
    '| Web-worker fatal fallbacks | n/a | 0 | n/a |',
    'missing current fallback is zero',
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
