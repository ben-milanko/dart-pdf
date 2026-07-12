import 'dart:collection';

import 'package:flutter/foundation.dart';

/// The app version reported in diagnostics. Keep in sync with the `version`
/// field in `pubspec.yaml`; it is surfaced to feedback reviewers so a report
/// can be matched to a build.
const String kAppVersion = '1.4.1';

/// Severity of a captured [AppLogEntry].
enum AppLogLevel {
  info,
  warning,
  error;

  String get label => switch (this) {
        AppLogLevel.info => 'INFO',
        AppLogLevel.warning => 'WARN',
        AppLogLevel.error => 'ERROR',
      };
}

/// A single line in the in-app diagnostics log: a timestamp, a severity, a
/// human-readable message, and - for failures - the originating error object
/// and its stack trace.
@immutable
class AppLogEntry {
  const AppLogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime time;
  final AppLogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  /// Renders the entry as plain text for the diagnostics report. Stack traces
  /// are trimmed to [stackFrames] frames so a report stays scannable and the
  /// prefilled feedback URL stays within a browser's length budget.
  String format({int stackFrames = 12}) {
    final buffer = StringBuffer()
      ..write(_formatTimestamp(time))
      ..write('  ')
      ..write(level.label.padRight(5))
      ..write('  ')
      ..write(message);
    if (error != null) {
      buffer
        ..write('\n        ')
        ..write(_collapseWhitespace(error.toString()));
    }
    final stack = stackTrace;
    if (stack != null) {
      final frames = stack
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(stackFrames);
      for (final frame in frames) {
        buffer
          ..write('\n          ')
          ..write(frame.trim());
      }
    }
    return buffer.toString();
  }
}

/// A capped, in-memory ring buffer of diagnostic events for the running app.
///
/// Nothing is written to disk or sent anywhere on its own: the log lives only
/// for the session and is surfaced to the user on demand, so they can review
/// it and choose to attach it to a GitHub feedback issue. Installing it hooks
/// Flutter's error reporters so uncaught framework and platform errors land
/// here automatically; the app can also record its own breadcrumbs through
/// [info]/[warning]/[error].
class AppLog extends ChangeNotifier {
  AppLog({this.capacity = 300});

  /// The shared instance the app and the feedback flow read from.
  static final AppLog instance = AppLog();

  /// The most events retained. Older events fall off the front once the
  /// buffer is full - recent context is what a bug report needs.
  final int capacity;

  final Queue<AppLogEntry> _entries = Queue<AppLogEntry>();

  bool _installed = false;

  /// A snapshot of the retained events, oldest first.
  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  /// Records an event. [error]/[stackTrace] are optional and only meaningful
  /// for warnings and errors. Notifies listeners so an open diagnostics view
  /// refreshes live.
  void record(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _entries.add(AppLogEntry(
      time: DateTime.now(),
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
    ));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  void info(String message) => record(AppLogLevel.info, message);

  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      record(AppLogLevel.warning, message,
          error: error, stackTrace: stackTrace);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      record(AppLogLevel.error, message,
          error: error, stackTrace: stackTrace);

  /// Clears the buffer (offered from the diagnostics view so a user can start
  /// a clean capture before reproducing a problem).
  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Installs framework error hooks so uncaught errors are captured without
  /// each call site having to remember to log. Chains the previous handlers
  /// so the default console reporting still runs. Idempotent.
  ///
  /// Returns a zone error handler suitable for `runZonedGuarded`, capturing
  /// asynchronous errors that escape the framework's own reporting.
  void Function(Object, StackTrace) install() {
    if (!_installed) {
      _installed = true;
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        record(
          AppLogLevel.error,
          _describeFlutterError(details),
          error: details.exception,
          stackTrace: details.stack,
        );
        previousOnError?.call(details);
      };

      final previousPlatformOnError = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        record(AppLogLevel.error, 'Uncaught platform error',
            error: error, stackTrace: stack);
        return previousPlatformOnError?.call(error, stack) ?? false;
      };
    }
    return (Object error, StackTrace stack) {
      record(AppLogLevel.error, 'Uncaught error',
          error: error, stackTrace: stack);
    };
  }

  /// Builds the plain-text diagnostics report a user attaches to feedback.
  /// [now] and [environment] are injectable so the output is deterministic in
  /// tests.
  String buildReport({
    DiagnosticsEnvironment environment = const DiagnosticsEnvironment(),
    DateTime? now,
  }) =>
      buildDiagnosticsReport(
        entries: entries,
        environment: environment,
        now: now,
      );
}

/// Runtime facts included at the head of a diagnostics report. Kept as a
/// value object (rather than read from globals) so reports are reproducible in
/// tests and the platform label can be overridden.
@immutable
class DiagnosticsEnvironment {
  const DiagnosticsEnvironment({
    this.appVersion = kAppVersion,
    this.platform,
    this.isWeb,
  });

  /// Captures the current platform/version from Flutter's constants.
  factory DiagnosticsEnvironment.current() => DiagnosticsEnvironment(
        platform: kIsWeb ? 'Web' : _platformName(defaultTargetPlatform),
        isWeb: kIsWeb,
      );

  final String appVersion;
  final String? platform;
  final bool? isWeb;

  String get platformLabel => platform ?? 'unknown';
}

/// Renders [entries] and [environment] into the report body. Free function so
/// it can be unit-tested without a Flutter binding.
String buildDiagnosticsReport({
  required List<AppLogEntry> entries,
  DiagnosticsEnvironment environment = const DiagnosticsEnvironment(),
  DateTime? now,
}) {
  final buffer = StringBuffer()
    ..writeln('DartPDF app diagnostics')
    ..writeln('App version: ${environment.appVersion}')
    ..writeln('Platform: ${environment.platformLabel}');
  if (now != null) {
    buffer.writeln('Captured: ${_formatTimestamp(now)}');
  }
  buffer
    ..writeln('Log entries: ${entries.length}')
    ..writeln();
  if (entries.isEmpty) {
    buffer.writeln('(no events recorded this session)');
  } else {
    for (final entry in entries) {
      buffer.writeln(entry.format());
    }
  }
  return buffer.toString().trimRight();
}

String _describeFlutterError(FlutterErrorDetails details) {
  final context = details.context?.toString();
  final library = details.library;
  if (context != null && context.isNotEmpty) {
    return 'Flutter error ($context)';
  }
  if (library != null && library.isNotEmpty) {
    return 'Flutter error in $library';
  }
  return 'Flutter error';
}

String _platformName(TargetPlatform platform) => switch (platform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };

String _formatTimestamp(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
}

String _collapseWhitespace(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();
