import 'package:pdf_document/pdf_document.dart';

/// Web (and any `dart:io`-less platform) fallback: a session-only store.
///
/// It still de-duplicates work within a run; for cross-session
/// persistence on the web, implement [PdfCacheStore] over IndexedDB and
/// return it here.
PdfCacheStore createPersistentCacheStore() => PdfMemoryCacheStore();
