import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'oidc_pkce.dart';

/// Runs the Sigstore interactive OAuth flow (Authorization Code + PKCE with a
/// loopback redirect) and returns an OIDC `id_token`, or null if sign-in was
/// cancelled or failed.
///
/// It binds a throwaway loopback HTTP server, opens the system browser at
/// Sigstore's broker, waits for the browser to redirect back with the
/// authorization code, and exchanges it for tokens. [client] and [launch] are
/// injectable for tests; production uses a fresh [http.Client] and
/// `url_launcher`.
Future<String?> runSigstoreSignIn({
  http.Client? client,
  Future<bool> Function(Uri url)? launch,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final redirectUri = 'http://localhost:${server.port}/auth/callback';
    final session = PkceSession.generate();
    final authorizationUrl =
        buildAuthorizationUrl(redirectUri: redirectUri, session: session);

    final opened = await (launch ?? _defaultLaunch)(authorizationUrl);
    if (!opened) return null;

    final code = await _awaitAuthorizationCode(server, session.state);
    if (code == null) return null;

    final owned = client == null;
    final http.Client c = client ?? http.Client();
    try {
      final response = await c.post(
        Uri.parse(SigstoreOidc.tokenEndpoint),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: buildTokenRequestBody(
            code: code, redirectUri: redirectUri, session: session),
      );
      if (response.statusCode != 200) {
        throw http.ClientException(
            'token endpoint returned HTTP ${response.statusCode}',
            Uri.parse(SigstoreOidc.tokenEndpoint));
      }
      return idTokenFromResponse(response.body);
    } finally {
      if (owned) c.close();
    }
  } finally {
    await server.close(force: true);
  }
}

Future<bool> _defaultLaunch(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Waits for the browser to hit the loopback redirect and returns the
/// authorization `code` when its `state` matches [expectedState]. Answers each
/// request with a small HTML page, and returns null on an OAuth `error` or a
/// state mismatch (CSRF guard).
Future<String?> _awaitAuthorizationCode(
    HttpServer server, String expectedState) async {
  await for (final request in server) {
    final params = request.uri.queryParameters;
    // Ignore incidental hits (favicon, etc.) that carry no OAuth response.
    if (params['code'] == null && params['error'] == null) {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      continue;
    }
    final matched = params['error'] == null && params['state'] == expectedState;
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(matched ? _successPage : _failurePage);
    await request.response.close();
    return matched ? params['code'] : null;
  }
  return null;
}

const _successPage = '<!doctype html><meta charset="utf-8"><title>DartPDF</title>'
    '<body style="font-family:sans-serif;text-align:center;padding-top:3rem">'
    '<h2>Signed in</h2><p>You can close this tab and return to DartPDF.</p>';

const _failurePage = '<!doctype html><meta charset="utf-8"><title>DartPDF</title>'
    '<body style="font-family:sans-serif;text-align:center;padding-top:3rem">'
    '<h2>Sign-in failed</h2><p>Please return to DartPDF and try again.</p>';
