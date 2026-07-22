/// Device RAM in GB, when the platform reports it. Null everywhere but the
/// web - see performance_memory_io.dart for why.
double? get detectedPdfDeviceMemoryGb => null;

/// The process's current resident set size in bytes, for diagnostic logging.
/// Null where the platform does not expose it.
int? get currentProcessRssBytes => null;
