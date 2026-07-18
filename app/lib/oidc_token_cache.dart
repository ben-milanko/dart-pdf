import 'dart:convert';

import 'devtools.dart';

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
  } catch (e) {
    AppDevTools.instance.addLog('cached OIDC token unreadable: $e');
    return null;
  }
}
