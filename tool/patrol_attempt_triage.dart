import 'dart:io';

/// Decides whether a failed iOS `patrol test` attempt may be retried.
///
/// Usage: `dart tool/patrol_attempt_triage.dart <patrol-verbose-log>`
///
/// Exits 0 and prints the reason when every failure in the attempt is the
/// simulator refusing to launch or terminate an app - XCTest's app lifecycle,
/// before a Dart test body got to run. Exits 1 (with the reason on stderr)
/// for anything else, including any sign that a Dart test failed.
///
/// Only the xcodebuild lines are trusted to be complete: Patrol forwards them
/// straight from the xcodebuild process. The `flutter:` lines come through a
/// separate device-log stream that lags, and is cut off when xcodebuild exits,
/// so their absence proves nothing - only their presence counts, and any Dart
/// failure they show makes the attempt a real failure.
void main(List<String> arguments) {
  if (arguments.length != 1 || arguments.first == '--help') {
    stdout.writeln(
      'Usage: dart tool/patrol_attempt_triage.dart <patrol-verbose-log>',
    );
    exit(arguments.length == 1 ? 0 : 64);
  }
  final log = File(arguments.first);
  if (!log.existsSync()) {
    stderr.writeln('Patrol log does not exist: ${arguments.first}');
    exit(66);
  }
  final verdict = triagePatrolAttempt(log.readAsLinesSync());
  if (verdict.retryable) {
    stdout.writeln(verdict.reason);
    exit(0);
  }
  stderr.writeln(verdict.reason);
  exit(1);
}

final _ansiEscape = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');

/// An XCTest failure recorded against one generated native test case, e.g.
/// `.../RunnerUITests.m:5: error: -[RunnerUITests name] : <message>`.
final _nativeTestFailure = RegExp(r'error: -\[\w+ ([^\]]+)\] : (.*)$');

/// The simulator app-lifecycle faults seen on the hosted macOS runners. Each
/// one happens while XCTest (re)launches or tears down an app, before Patrol
/// has asked the Dart side to run anything, so it carries no information
/// about the code under test.
final _lifecycleFaults = <RegExp>[
  // XCUIApplication.launch terminates the previous instance first; on a
  // loaded runner that sometimes times out after 60s.
  RegExp(r'Failed to terminate [\w.]+:\d+'),
  // The app or the test runner could not be launched at all, e.g. FrontBoard
  // not yet knowing about an app that was just (re)installed.
  RegExp(r'Failed to launch app with identifier'),
  RegExp(r'Simulator device failed to launch [\w.]+'),
  RegExp(r'is unknown to FrontBoard'),
  RegExp(r'Failed to install or launch the test runner'),
];

/// Evidence, in whatever part of the Dart log did arrive, that a Dart test
/// failed. Any of these makes the attempt a hard failure.
final _dartFailures = <RegExp>[
  RegExp(r'PatrolBinding: tearDown\(\): test .*, passed: false'),
  RegExp(r'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK'),
  RegExp(r'Some tests failed\.'),
  RegExp(r'runDartTest\(.*\): call finished, test result: (FAILED|CRASHED)'),
];

class PatrolAttemptVerdict {
  const PatrolAttemptVerdict.retry(this.reason) : retryable = true;
  const PatrolAttemptVerdict.fail(this.reason) : retryable = false;

  final bool retryable;
  final String reason;
}

PatrolAttemptVerdict triagePatrolAttempt(Iterable<String> sourceLines) {
  final faults = <String>{};
  final otherNativeFailures = <String>[];
  for (final raw in sourceLines) {
    final line = raw.replaceAll(_ansiEscape, '');
    for (final pattern in _dartFailures) {
      if (pattern.hasMatch(line)) {
        return PatrolAttemptVerdict.fail(
          'a Dart test failed: ${line.trim()}',
        );
      }
    }
    String? fault;
    for (final pattern in _lifecycleFaults) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        fault = match.group(0);
        break;
      }
    }
    if (fault != null) faults.add(fault);
    final nativeFailure = _nativeTestFailure.firstMatch(line);
    if (nativeFailure != null && fault == null) {
      otherNativeFailures.add(
        '${nativeFailure.group(1)}: ${nativeFailure.group(2)}',
      );
    }
  }
  if (otherNativeFailures.isNotEmpty) {
    return PatrolAttemptVerdict.fail(
      'native test failure(s) other than a simulator app-lifecycle fault: '
      '${otherNativeFailures.join('; ')}',
    );
  }
  if (faults.isEmpty) {
    return const PatrolAttemptVerdict.fail(
      'no simulator app-lifecycle fault explains the failure',
    );
  }
  return PatrolAttemptVerdict.retry(
    'simulator app-lifecycle fault: ${faults.join('; ')}',
  );
}
