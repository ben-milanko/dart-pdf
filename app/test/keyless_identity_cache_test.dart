import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'package:dart_pdf_editor_app/keyless_identity_cache.dart';

void main() {
  // A short-lived identity like a Fulcio cert: valid from `from` for 10 min.
  PdfSigningIdentity shortLived(DateTime from) => PdfSigningIdentity.generate(
      name: 'dev@example.com',
      notBefore: from,
      validity: const Duration(minutes: 10));

  const ctx = _FakeContext();

  testWidgets('reuses the cached identity while its cert is fresh',
      (tester) async {
    final issued = DateTime.utc(2026, 1, 1, 12);
    var mints = 0;
    // "now" is 5 minutes into the 10-minute cert: comfortably fresh.
    final cache =
        KeylessIdentityCache(now: () => issued.add(const Duration(minutes: 5)));

    Future<PdfSigningIdentity?> mint(BuildContext _) async {
      mints++;
      return shortLived(issued);
    }

    final first = await cache.obtain(ctx, mint);
    final second = await cache.obtain(ctx, mint);
    expect(mints, 1); // minted once, reused the second time
    expect(identical(first, second), isTrue);
  });

  testWidgets('re-mints once the cached cert is near expiry', (tester) async {
    final issued = DateTime.utc(2026, 1, 1, 12);
    var mints = 0;
    // "now" is 9m30s into the cert's 10-minute life: inside the 2-min margin.
    final cache = KeylessIdentityCache(
        now: () => issued.add(const Duration(minutes: 9, seconds: 30)));

    Future<PdfSigningIdentity?> mint(BuildContext _) async {
      mints++;
      return shortLived(issued); // cert valid issued..issued+10min
    }

    await cache.obtain(ctx, mint);
    await cache.obtain(ctx, mint);
    expect(mints, 2); // cached cert is near expiry -> minted again
  });

  testWidgets('a mint that declines leaves no cache and yields null',
      (tester) async {
    final cache = KeylessIdentityCache();
    final result = await cache.obtain(ctx, (_) async => null);
    expect(result, isNull);
    expect(cache.cached, isNull);
  });
}

/// A stand-in BuildContext - the cache only forwards it to the mint callback.
class _FakeContext implements BuildContext {
  const _FakeContext();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
