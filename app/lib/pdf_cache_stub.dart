import 'dart:typed_data';

/// Web (and any other `dart:io`-less target) can't snapshot opened bytes to a
/// private file, so Recent entries there still need a fresh pick to reopen.
bool get canCacheRecentPdfs => false;

Future<String?> cacheOpenedPdf(Uint8List bytes) async => null;

Future<void> pruneCachedPdfs(Set<String> keep) async {}
