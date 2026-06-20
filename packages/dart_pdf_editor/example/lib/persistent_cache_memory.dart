import 'package:pdf_document/pdf_document.dart';

/// Ultimate fallback for a platform with neither `dart:io` nor JS interop:
/// a session-only store.
///
/// Native platforms use the filesystem store and the web uses the
/// IndexedDB store (see persistent_cache.dart); this one only de-duplicates
/// work within a single run.
PdfCacheStore createPersistentCacheStore() => PdfMemoryCacheStore();
