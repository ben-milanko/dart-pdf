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
          {'id': 'PDF.js/stable.pdf page 0', 'route': 'flutter-gpu'},
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
          {'id': 'Ghent/fallback.pdf page 0', 'route': 'flutter-gpu'},
        ],
      },
      'PDF.js': {
        'accepted': 1,
        'rejected': 0,
        'pages': [
          {'id': 'PDF.js/stable.pdf page 0', 'route': 'flutter-gpu'},
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
