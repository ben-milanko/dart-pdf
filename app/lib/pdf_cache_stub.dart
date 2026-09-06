import 'dart:typed_data';
import 'pdf_cache_policy.dart';

bool get canManageCachedPdfs => false;
Future<PdfCacheUsage?> cachedPdfUsage() async => null;
Future<bool> clearCachedPdfs() async => false;

/// A target with neither `dart:io` nor JS interop can't snapshot opened bytes,
/// so Recent entries there still need a fresh pick to reopen.
bool get canCacheRecentPdfs => false;

Future<String?> cacheOpenedPdf(Uint8List bytes) async => null;

Future<Uint8List?> readCachedPdf(String cacheKey) async => null;

Future<Set<String>?> pruneCachedPdfs(Set<String> keep) async => null;
