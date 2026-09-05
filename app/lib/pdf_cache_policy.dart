/// Limits apply to disposable opened-document snapshots, never crash recovery.
const pdfCacheMaxBytes = 256 * 1024 * 1024;
const pdfCacheMaxFileBytes = 64 * 1024 * 1024;

/// PDF payload bytes only; browser bookkeeping is included in its quota estimate.
class PdfCacheUsage {
  const PdfCacheUsage(this.bytes, this.documents);

  final int bytes;
  final int documents;
}

/// Leave 10% of the origin quota free for preferences, recovery and overhead.
/// An unavailable estimate still permits caching within our own byte budget.
bool pdfCacheFitsQuota(int addedBytes, {num? usage, num? quota}) {
  if (usage == null || quota == null || !usage.isFinite || !quota.isFinite) {
    return true;
  }
  return usage >= 0 && quota > 0 && usage + addedBytes <= quota * 0.9;
}
