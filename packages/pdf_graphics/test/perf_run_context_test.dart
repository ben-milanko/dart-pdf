// The optional toolchain keys of the perf envelope's `env` section
// (tool/perf_run_context.dart, tool/perf/SCHEMA.md).
@TestOn('vm')
library;

import 'package:test/test.dart';

import '../tool/perf_run_context.dart';

void main() {
  test('records the Flutter SDK and the hosted runner image when set', () {
    expect(
        toolchainEnv({
          'PDF_PERF_FLUTTER_VERSION': '3.47.4',
          'ImageOS': 'ubuntu24',
          'ImageVersion': '20260920.314.1',
        }),
        {'flutter': '3.47.4', 'runnerImage': 'ubuntu24/20260920.314.1'});
  });

  test('leaves the keys out when the variables are unset', () {
    expect(toolchainEnv({}), isEmpty);
  });

  test('an empty variable is unset, not half a value', () {
    expect(
        toolchainEnv({
          'PDF_PERF_FLUTTER_VERSION': '',
          'ImageOS': 'ubuntu24',
          'ImageVersion': '',
        }),
        isEmpty);
    expect(toolchainEnv({'ImageOS': '', 'ImageVersion': '20260920.314.1'}),
        isEmpty);
    expect(toolchainEnv({'ImageOS': 'ubuntu24'}), isEmpty);
  });
}
