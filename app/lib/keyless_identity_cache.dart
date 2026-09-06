import 'package:flutter/widgets.dart';
import 'package:pdf_cos/pdf_cos.dart' show X509Certificate;
import 'package:pdf_document/pdf_document.dart' show PdfSigningIdentity;

import 'devtools.dart';

/// Mints a keyless (Sigstore/Fulcio) identity - an OIDC sign-in followed by a
/// Fulcio certificate. Returns null when it can't: a silent attempt with no
/// reusable login, or a cancelled interactive sign-in.
typedef KeylessMint = Future<PdfSigningIdentity?> Function(BuildContext context);

/// Reuses a minted keyless [PdfSigningIdentity] across signatures while its
/// short-lived Fulcio certificate stays valid, so most signatures need no
/// fresh OIDC sign-in. A new identity is minted (via the supplied [KeylessMint])
/// only when there's no cached one or its certificate is within [margin] of
/// expiry.
class KeylessIdentityCache {
  KeylessIdentityCache({
    this.margin = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Headroom kept before the cached certificate expires - enough to finish
  /// the dialog and sign before it lapses.
  final Duration margin;
  final DateTime Function() _now;

  PdfSigningIdentity? _cached;

  /// The cached identity, whether or not it is still fresh (for inspection).
  PdfSigningIdentity? get cached => _cached;

  /// Returns the cached identity while its certificate is comfortably valid,
  /// otherwise mints a fresh one with [mint] and caches it. A [mint] that
  /// returns null (silent decline / cancel) leaves any cache untouched and
  /// yields null.
  Future<PdfSigningIdentity?> obtain(
      BuildContext context, KeylessMint mint) async {
    final cached = _cached;
    if (cached != null && _fresh(cached)) return cached;
    final minted = await mint(context);
    if (minted != null) _cached = minted;
    return minted;
  }

  /// Forgets the cached identity.
  void clear() => _cached = null;

  bool _fresh(PdfSigningIdentity identity) {
    try {
      final notAfter = X509Certificate.parse(identity.certificate).notAfter;
      return notAfter.toUtc().isAfter(_now().toUtc().add(margin));
    } catch (e) {
      AppDevTools.instance
          .addLog('keyless identity certificate unreadable: $e');
      return false;
    }
  }
}
