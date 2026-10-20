import 'package:http/http.dart' as http;

import 'oidc_pkce.dart';

/// Web fallback: the interactive loopback OAuth flow needs a local HTTP server
/// to catch the redirect, which a browser tab can't provide, so keyless
/// sign-in is unavailable on the web. Returns null.
Future<OidcTokens?> runSigstoreSignIn({
  http.Client? client,
  Future<bool> Function(Uri url)? launch,
}) async =>
    null;

/// Web fallback: no keyless session, so nothing to refresh.
Future<OidcTokens?> refreshSigstoreTokens(
  String refreshToken, {
  http.Client? client,
}) async =>
    null;
