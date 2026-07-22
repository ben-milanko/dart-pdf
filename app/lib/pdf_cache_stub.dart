import 'dart:typed_data';

/// A target with neither `dart:io` nor JS interop can't snapshot opened bytes,
/// so Recent entries there still need a fresh pick to reopen.
bool get canCacheRecentPdfs => false;

Future<String?> cacheOpenedPdf(Uint8List bytes) async => null;

Future<Uint8List?> readCachedPdf(String cacheKey) async => null;

Future<void> pruneCachedPdfs(Set<String> keep) async {}
