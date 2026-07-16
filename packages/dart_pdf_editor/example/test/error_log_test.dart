import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_viewer_example/error_log.dart';
import 'package:pdf_viewer_example/feedback.dart';

void main() {
  group('AppLog', () {
    test('records events oldest-first and notifies listeners', () {
      final log = AppLog();
      var notifications = 0;
      log.addListener(() => notifications++);

      log.info('one');
      log.warning('two');
      log.error('three');

      expect(log.entries.map((e) => e.message), ['one', 'two', 'three']);
      expect(log.entries.map((e) => e.level),
          [AppLogLevel.info, AppLogLevel.warning, AppLogLevel.error]);
      expect(notifications, 3);
    });

    test('caps at capacity, dropping the oldest events', () {
      final log = AppLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.info('event $i');
      }
      expect(log.entries.length, 3);
      expect(log.entries.map((e) => e.message),
          ['event 2', 'event 3', 'event 4']);
    });

    test('clear empties the buffer and notifies', () {
      final log = AppLog()..info('x');
      var notified = false;
      log.addListener(() => notified = true);
      log.clear();
      expect(log.isEmpty, isTrue);
      expect(notified, isTrue);
    });
  });

  group('buildDiagnosticsReport', () {
    test('includes a header and every entry', () {
      final now = DateTime.utc(2026, 7, 10, 12, 30, 0);
      final entries = [
        AppLogEntry(
          time: DateTime.utc(2026, 7, 10, 12, 0, 0),
          level: AppLogLevel.info,
          message: 'App started',
        ),
        AppLogEntry(
          time: DateTime.utc(2026, 7, 10, 12, 15, 0),
          level: AppLogLevel.error,
          message: 'Could not open sample.pdf',
          error: StateError('bad xref'),
          stackTrace: StackTrace.fromString('#0 frame one\n#1 frame two'),
        ),
      ];

      final report = buildDiagnosticsReport(
        entries: entries,
        environment: const DiagnosticsEnvironment(
          appVersion: '9.9.9',
          platform: 'Web',
          isWeb: true,
        ),
        now: now,
      );

      expect(report, contains('DartPDF app diagnostics'));
      expect(report, contains('App version: 9.9.9'));
      expect(report, contains('Platform: Web'));
      expect(report, contains('Log entries: 2'));
      expect(report, contains('App started'));
      expect(report, contains('ERROR'));
      expect(report, contains('Could not open sample.pdf'));
      expect(report, contains('Bad state: bad xref'));
      expect(report, contains('#0 frame one'));
    });

    test('describes an empty log', () {
      final report = buildDiagnosticsReport(entries: const []);
      expect(report, contains('Log entries: 0'));
      expect(report, contains('(no events recorded this session)'));
    });

    test('trims long stack traces', () {
      final frames =
          List.generate(40, (i) => '#$i frame').join('\n');
      final report = buildDiagnosticsReport(entries: [
        AppLogEntry(
          time: DateTime.utc(2026, 1, 1),
          level: AppLogLevel.error,
          message: 'boom',
          stackTrace: StackTrace.fromString(frames),
        ),
      ]);
      expect(report, contains('#0 frame'));
      expect(report, contains('#11 frame'));
      expect(report, isNot(contains('#12 frame')));
    });
  });

  group('buildFeedbackUri', () {
    final base = Uri.parse(
        'https://github.com/ben-milanko/dart-pdf/issues/new?template=app_feedback.yml');

    test('prefills version and preserves the template param', () {
      final uri = buildFeedbackUri(base, version: '1.2.3');
      expect(uri.queryParameters['template'], 'app_feedback.yml');
      expect(uri.queryParameters['version'], '1.2.3');
      expect(uri.queryParameters.containsKey('diagnostics'), isFalse);
    });

    test('attaches a short report verbatim', () {
      final uri =
          buildFeedbackUri(base, version: '1.2.3', report: 'short report');
      expect(uri.queryParameters['diagnostics'], 'short report');
    });

    test('truncates a long report to keep the URL under the budget', () {
      final report = List.generate(2000, (i) => 'line $i').join('\n');
      final uri = buildFeedbackUri(base, report: report, maxUrlLength: 2000);
      expect(uri.toString().length, lessThanOrEqualTo(2000));
      final attached = uri.queryParameters['diagnostics']!;
      expect(attached, contains('older entries truncated'));
      // Keeps the tail (most recent events), not the head.
      expect(attached, contains('line 1999'));
      expect(attached, isNot(contains('line 0\n')));
    });
  });
}
