// Flag handling of `dart run dart_pdf_editor:build_web_worker`. Every deploy,
// preview, release and publish workflow builds the web render worker through
// this tool with no -O flag of its own, so its default level is the level
// every web user's worker ships at. These pin that default (-O3, not the old
// -O2 and not -O4) without spawning dart2js.
import 'package:flutter_test/flutter_test.dart';

import '../bin/build_web_worker.dart';

void main() {
  test('defaults to -O3 and no source maps', () {
    final options = WorkerBuildOptions.parse(const []);
    expect(defaultWorkerOptimizationLevel, 3);
    expect(options.optimizationLevel, 3);
    expect(options.out, 'web/pdf_render_worker.dart.js');
    expect(options.compilerFlags, ['-O3', '--no-source-maps']);
  });

  test('the level can be pinned in every spelling', () {
    for (final args in [
      ['--optimization-level', '2'],
      ['--optimization-level=2'],
      ['-O2'],
    ]) {
      expect(
        WorkerBuildOptions.parse(args).compilerFlags,
        ['-O2', '--no-source-maps'],
        reason: '$args',
      );
    }
    expect(WorkerBuildOptions.parse(const ['-O4']).optimizationLevel, 4);
  });

  test('--no-optimize passes no -O flag; the last level flag wins', () {
    expect(WorkerBuildOptions.parse(const ['--no-optimize']).compilerFlags, [
      '--no-source-maps',
    ]);
    expect(
      WorkerBuildOptions.parse(const ['--no-optimize', '-O2']).compilerFlags,
      ['-O2', '--no-source-maps'],
    );
    expect(
      WorkerBuildOptions.parse(const ['-O2', '--no-optimize']).compilerFlags,
      ['--no-source-maps'],
    );
  });

  test('out path and source maps parse as before', () {
    final options = WorkerBuildOptions.parse(const [
      '--out',
      'a/worker.js',
      '--source-maps',
    ]);
    expect(options.out, 'a/worker.js');
    expect(options.compilerFlags, ['-O3']);
    expect(WorkerBuildOptions.parse(const ['-o', 'b.js']).out, 'b.js');
    expect(WorkerBuildOptions.parse(const ['--out=c.js']).out, 'c.js');
  });

  test('rejects levels outside 1-4 and unknown arguments', () {
    for (final args in [
      ['-O0'],
      ['-O5'],
      ['-O'],
      ['--optimization-level=x'],
      ['--optimization-level'],
      ['--out'],
      ['--fast'],
    ]) {
      expect(
        () => WorkerBuildOptions.parse(args),
        throwsFormatException,
        reason: '$args',
      );
    }
  });
}
