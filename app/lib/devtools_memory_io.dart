import 'dart:io';

/// Resident set size of the process right now.
int? currentRssBytes() => ProcessInfo.currentRss;

/// High-water mark of the resident set size.
int? maxRssBytes() => ProcessInfo.maxRss;

/// True under `flutter test`, whose binding asserts that foundation globals
/// like [debugPrint] are never replaced.
bool inFlutterTest() => Platform.environment.containsKey('FLUTTER_TEST');
