import 'dart:io';

/// Device RAM in GB - unavailable on the Dart VM.
///
/// `dart:io` exposes the process's own footprint ([ProcessInfo.currentRss],
/// [ProcessInfo.maxRss]) but no total-physical-memory API, and reading one out
/// of `sysctl`/`/proc` would mean spawning a process during cache setup on
/// platforms that each spell it differently. Native callers fall back to the
/// platform tier instead (a phone and a desktop want different budgets far
/// more than two desktops do).
double? get detectedPdfDeviceMemoryGb => null;

/// The process's current resident set size in bytes ([ProcessInfo.currentRss]),
/// for diagnostic logging - the number that climbs toward the OS's per-process
/// high-water limit. Null where `dart:io` is unavailable (web).
int? get currentProcessRssBytes => ProcessInfo.currentRss;
