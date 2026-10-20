/// One best-effort reading of the memory constraints surrounding the app.
///
/// Every field is optional because browsers and native platforms expose
/// different subsets. The adaptive policy remains conservative when a runner
/// cannot provide the native snapshot channel.
class AppMemorySnapshot {
  const AppMemorySnapshot({
    this.physicalBytes,
    this.availableBytes,
    this.processRssBytes,
    this.processLimitBytes,
    this.lowMemory = false,
  });

  /// Installed physical RAM (or the browser's coarse device-memory value).
  final int? physicalBytes;

  /// Memory the OS currently considers available without heavy reclamation.
  final int? availableBytes;

  /// Resident bytes attributed to this process/tab, where observable.
  final int? processRssBytes;

  /// A platform-provided per-process or JS-heap limit, where one exists.
  final int? processLimitBytes;

  /// The platform is already inside its low-memory threshold.
  final bool lowMemory;
}
