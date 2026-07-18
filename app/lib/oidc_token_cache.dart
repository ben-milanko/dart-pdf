import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'keyless_signing.dart';

/// Reads the `exp` (expiry) claim of a JWT as a UTC [DateTime], or null when
/// the token is malformed or carries no numeric `exp`. This only decodes the
/// unsigned payload - it is not verification - and is used solely to decide
/// whether a cached Sigstore login can be reused without signing in again.
DateTime? oidcTokenExpiry(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight((payload.length + 3) & ~3, '=');
    final claims = json.decode(utf8.decode(base64.decode(payload)));
    if (claims is! Map) return null;
    final exp = claims['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000,
        isUtc: true);
  } catch (_) {
    return null;
  }
}

/// Wraps an [OidcTokenProvider] so a still-valid Sigstore login is reused
/// rather than launching the browser again every time the Digitally sign
/// dialog opens. The last `id_token` is kept in memory and returned as long as
/// its `exp` claim is still in the future (minus [leeway]); otherwise the inner
/// provider runs and its fresh token is cached.
///
/// The instance is callable, so it drops straight into
/// [EditorScreen.oidcTokenProvider]. [now] is injectable for tests.
class CachingOidcTokenProvider {
  CachingOidcTokenProvider(
    this._inner, {
    Duration leeway = const Duration(minutes: 1),
    DateTime Function()? now,
  })  : _leeway = leeway,
        _now = now ?? DateTime.now;

  final OidcTokenProvider _inner;
  final Duration _leeway;
  final DateTime Function() _now;

  String? _cached;

  /// Whether a still-valid login is cached (no browser sign-in needed).
  bool get hasValidToken => _cached != null && _isValid(_cached!);

  Future<String?> call(BuildContext context) async {
    final cached = _cached;
    if (cached != null && _isValid(cached)) return cached;
    final token = await _inner(context);
    _cached = (token != null && token.isNotEmpty) ? token : null;
    return _cached;
  }

  /// Forgets any cached login (e.g. on explicit sign-out).
  void clear() => _cached = null;

  bool _isValid(String token) {
    final exp = oidcTokenExpiry(token);
    return exp != null && exp.subtract(_leeway).isAfter(_now().toUtc());
  }
}
