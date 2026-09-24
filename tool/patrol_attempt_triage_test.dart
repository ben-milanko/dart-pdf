import 'patrol_attempt_triage.dart';

// Excerpts from real hosted-runner logs (paths shortened).
const _terminateFault = [
  '\t    t =     0.38s         Terminate dev.milanko.pdfViewerExample:37785',
  '\t/runner/example/ios/RunnerUITests/RunnerUITests.m:5: error: '
      '-[RunnerUITests native_perf_e2e_test+fills+and+settles+the+native+'
      'mobile+tile+budget] : Failed to terminate '
      'dev.milanko.pdfViewerExample:37785: Failed to terminate '
      'dev.milanko.pdfViewerExample:0',
  "\tTest Case '-[RunnerUITests native_perf_e2e_test+fills+and+settles+the+"
      "native+mobile+tile+budget]' failed (62.263 seconds).",
  '\t2026-09-24 11:07:52.585594+0000 RunnerUITests-Runner[37204:110046] '
      'runDartTest("native_perf_e2e_test warms and rasterizes a real native '
      'flutter_gpu scene"): call finished, test result: PASSED',
  'flutter: PatrolBinding: tearDown(): test "warms and rasterizes a real '
      'native flutter_gpu scene" in group "native_perf_e2e_test warms and '
      'rasterizes a real native flutter_gpu scene", passed: true',
  '\t** TEST EXECUTE FAILED **',
];

const _frontBoardFault = [
  '\t2026-09-24 10:24:17.017 xcodebuild[82560:228465]  iOSSimulator: '
      'DC4CD8B3: Failed to launch app with identifier: '
      'dev.milanko.pdfViewerExample.RunnerUITests.xctrunner and options: {',
  '\tFailure Reason: The request was denied by service delegate '
      '(SBMainWorkspace) for reason: NotFound ("Application '
      '"dev.milanko.pdfViewerExample.RunnerUITests.xctrunner" is unknown to '
      'FrontBoard").',
  '\tTesting failed:',
  '\t\tSimulator device failed to launch '
      'dev.milanko.pdfViewerExample.RunnerUITests.xctrunner.',
  '\t** TEST EXECUTE FAILED **',
  'Error: xcodebuild exited with code 65',
];

void main() {
  var failures = 0;
  void check(String name, PatrolAttemptVerdict verdict, bool retryable) {
    if (verdict.retryable != retryable) {
      failures++;
      print('FAIL $name: expected retryable=$retryable, got '
          '${verdict.retryable} (${verdict.reason})');
    } else {
      print('ok   $name: ${verdict.reason}');
    }
  }

  check('terminate timeout before the Dart test ran',
      triagePatrolAttempt(_terminateFault), true);
  check('test runner unknown to FrontBoard',
      triagePatrolAttempt(_frontBoardFault), true);

  check(
    'a Dart failure next to a lifecycle fault is never retried',
    triagePatrolAttempt([
      ..._terminateFault,
      'flutter: PatrolBinding: tearDown(): test "warms" in group "warms", '
          'passed: false',
    ]),
    false,
  );
  check(
    'a framework exception is a Dart failure',
    triagePatrolAttempt([
      ..._frontBoardFault,
      'flutter: ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════',
    ]),
    false,
  );
  check(
    'the native runner reporting a Dart FAILED result',
    triagePatrolAttempt([
      ..._terminateFault,
      '\t2026-09-24 RunnerUITests-Runner[1:2] runDartTest("x"): call '
          'finished, test result: FAILED',
    ]),
    false,
  );
  check(
    'an assertion from runDartTest is a real failure even when the Dart '
    'log was cut off',
    triagePatrolAttempt([
      ..._terminateFault,
      '\t/runner/RunnerUITests.m:5: error: -[RunnerUITests warms+scene] : '
          '((passed) is true) failed - Expected: true',
    ]),
    false,
  );
  check(
    'a failure without any lifecycle fault',
    triagePatrolAttempt([
      '\t** TEST EXECUTE FAILED **',
      'Error: xcodebuild exited with code 65',
    ]),
    false,
  );
  check(
    'ANSI colour codes do not hide a Dart failure',
    triagePatrolAttempt([
      ..._frontBoardFault,
      '\x1B[31mflutter: 00:06 +1 -1: Some tests failed.\x1B[0m',
    ]),
    false,
  );

  if (failures > 0) {
    throw StateError('$failures patrol_attempt_triage check(s) failed');
  }
}
