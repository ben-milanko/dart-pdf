import 'gpu_corpus_summary.dart' as summary;

void main() {
  final baseline = summary.GpuCorpusReport.parse({
    'schema': 1,
    'suites': {
      'Ghent': {
        'accepted': 1,
        'rejected': 1,
        'pages': [
          {'id': 'Ghent/accepted.pdf page 0', 'route': 'flutter-gpu'},
          {
            'id': 'Ghent/fallback.pdf page 0',
            'route': 'canvas-fallback',
            'reason': 'unsupported blend',
          },
        ],
      },
      'PDF.js': {
        'accepted': 1,
        'rejected': 0,
        'pages': [
          {
            'id': 'PDF.js/stable.pdf page 0',
            'route': 'flutter-gpu',
            'meanDifference': 0.5,
            'stats': {
              'drawCalls': 10,
              'directSolidDrawCalls': 2,
              'stencilFanDrawCalls': 3,
              'stencilCoverDrawCalls': 2,
              'stencilClearDrawCalls': 1,
              'textureDrawCalls': 1,
              'glyphDrawCalls': 1,
              'blendDrawCalls': 0,
              'softMaskDrawCalls': 0,
              'selectedCommands': 5,
              'drawCallsSaved': 2,
              'directRectangleDraws': 0,
              'geometryVertices': 100,
              'issueMicros': 4000,
              'compileMicros': 2000,
            },
          },
        ],
      },
    },
  });
  final current = summary.GpuCorpusReport.parse({
    'schema': 1,
    'suites': {
      'Ghent': {
        'accepted': 1,
        'rejected': 1,
        'pages': [
          {
            'id': 'Ghent/accepted.pdf page 0',
            'route': 'canvas-fallback',
            'reason': 'new rejection',
          },
          {
            'id': 'Ghent/fallback.pdf page 0',
            'route': 'flutter-gpu',
            'meanDifference': 0.25,
            'stats': {
              'drawCalls': 20,
              'directSolidDrawCalls': 4,
              'stencilFanDrawCalls': 6,
              'stencilCoverDrawCalls': 4,
              'stencilClearDrawCalls': 2,
              'textureDrawCalls': 1,
              'glyphDrawCalls': 1,
              'blendDrawCalls': 1,
              'softMaskDrawCalls': 1,
              'selectedCommands': 12,
              'drawCallsSaved': 4,
              'directRectangleDraws': 3,
              'directTriangleDraws': 3,
              'geometryVertices': 240,
              'issueMicros': 6000,
              'compileMicros': 3000,
            },
          },
        ],
      },
      'PDF.js': {
        'accepted': 1,
        'rejected': 0,
        'pages': [
          {
            'id': 'PDF.js/stable.pdf page 0',
            'route': 'flutter-gpu',
            'meanDifference': 0.4,
            'stats': {
              'drawCalls': 8,
              'directSolidDrawCalls': 2,
              'stencilFanDrawCalls': 2,
              'stencilCoverDrawCalls': 1,
              'stencilClearDrawCalls': 1,
              'textureDrawCalls': 1,
              'glyphDrawCalls': 1,
              'blendDrawCalls': 0,
              'softMaskDrawCalls': 0,
              'selectedCommands': 5,
              'drawCallsSaved': 4,
              'directRectangleDraws': 2,
              'directTriangleDraws': 2,
              'geometryVertices': 90,
              'issueMicros': 3500,
              'compileMicros': 1800,
            },
          },
        ],
      },
    },
  });
  final comparison = summary.GpuCorpusComparison(
    baseline: baseline,
    current: current,
  );

  _expect(comparison.hasRegressions, 'route regression is detected');
  _expectEqual(
    comparison.regressions.single.id,
    'Ghent/accepted.pdf page 0',
    'regressed page',
  );
  _expectEqual(
    comparison.improvements.single.id,
    'Ghent/fallback.pdf page 0',
    'new coverage page',
  );
  final headline = comparison.toHeadlineMarkdown();
  _expectContains(
    headline,
    '| Ghent | 1 / 1 | 1 / 1 | 0 accepted |',
    'headline totals',
  );
  _expectContains(
    headline,
    '**New GPU coverage:** `Ghent/fallback.pdf page 0`.',
    'headline improvement',
  );
  _expectContains(
    headline,
    '**New Canvas fallbacks:** `Ghent/accepted.pdf page 0`.',
    'headline regression',
  );
  _expectContains(
    comparison.toMarkdown(),
    '| `Ghent/accepted.pdf page 0` | new rejection |',
    'fallback detail',
  );
  _expectContains(
    comparison.toMarkdown(),
    '| Native draw calls | 10 | 8 | -20.0% |',
    'structural draw comparison',
  );
  _expectContains(
    comparison.toMarkdown(),
    '| Stencil fan draws | 3 | 2 | -33.3% |',
    'structural draw-kind comparison',
  );
  _expectContains(
    comparison.toMarkdown(),
    '| Direct triangle draws | 0 | 2 | new |',
    'direct-triangle comparison',
  );
  _expectContains(
    comparison.toMarkdown(),
    '| `Ghent/fallback.pdf page 0` | 20 | 12 | 4 | 3 | '
        '3 | 4/6/4/2/1/1/1/1 | 6.000 ms | 3.000 ms | 0.250 |',
    'ranked draw hotspot',
  );

  final safe = summary.GpuCorpusComparison(
    baseline: current,
    current: current,
  );
  _expect(!safe.hasRegressions, 'stable routes are safe');
  _expectContains(
    safe.toHeadlineMarkdown(),
    '**New Canvas fallbacks:** none.',
    'safe headline',
  );

  _expectThrows(
    () => summary.GpuCorpusReport.parse({
      'schema': 1,
      'suites': {
        'Ghent': {
          'accepted': 2,
          'rejected': 0,
          'pages': [
            {'id': 'Ghent/one.pdf page 0', 'route': 'flutter-gpu'},
          ],
        },
      },
    }),
    'mismatched route totals',
  );

  print('Flutter GPU corpus summarizer tests passed');
}

void _expect(bool value, String label) {
  if (!value) throw StateError(label);
}

void _expectEqual(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    throw StateError('$label: expected $expected, got $actual');
  }
}

void _expectContains(String actual, String expected, String label) {
  if (!actual.contains(expected)) {
    throw StateError('$label: expected to find $expected in:\n$actual');
  }
}

void _expectThrows(void Function() callback, String label) {
  try {
    callback();
  } on FormatException {
    return;
  }
  throw StateError('$label: expected a FormatException');
}
