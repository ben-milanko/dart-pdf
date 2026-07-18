import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dart_pdf_editor_app/oidc_pkce.dart';
import 'package:dart_pdf_editor_app/oidc_signin_io.dart';

void main() {
  group('PKCE session', () {
    test('challenge is the unpadded base64url S256 of the verifier', () {
      final session = PkceSession.generate();
      final expected = base64Url
          .encode(crypto.sha256.convert(ascii.encode(session.verifier)).bytes)
          .replaceAll('=', '');
      expect(session.challenge, expected);
      expect(session.challenge, isNot(contains('=')));
      expect(session.verifier, isNot(contains('=')));
      // fresh sessions differ
      expect(PkceSession.generate().verifier, isNot(session.verifier));
    });
  });

  group('authorization URL', () {
    test('carries the OAuth 2.0 + PKCE query for the Sigstore broker', () {
      final session =
          PkceSession(verifier: 'v', state: 'st4te', nonce: 'n0nce');
      final url = buildAuthorizationUrl(
          redirectUri: 'http://localhost:1234/auth/callback',
          session: session);
      expect(url.origin + url.path, SigstoreOidc.authorizationEndpoint);
      final q = url.queryParameters;
      expect(q['response_type'], 'code');
      expect(q['client_id'], 'sigstore');
      expect(q['scope'], 'openid email');
      expect(q['redirect_uri'], 'http://localhost:1234/auth/callback');
      expect(q['state'], 'st4te');
      expect(q['nonce'], 'n0nce');
      expect(q['code_challenge'], session.challenge);
      expect(q['code_challenge_method'], 'S256');
    });
  });

  group('token request/response', () {
    test('body carries the code + PKCE verifier', () {
      final body = buildTokenRequestBody(
        code: 'the-code',
        redirectUri: 'http://localhost:1/auth/callback',
        session: PkceSession(verifier: 'verify', state: 's', nonce: 'n'),
      );
      final parsed = Uri.splitQueryString(body);
      expect(parsed['grant_type'], 'authorization_code');
      expect(parsed['code'], 'the-code');
      expect(parsed['client_id'], 'sigstore');
      expect(parsed['code_verifier'], 'verify');
    });

    test('idTokenFromResponse reads the id_token, else throws', () {
      expect(idTokenFromResponse('{"id_token":"abc.def.ghi"}'), 'abc.def.ghi');
      expect(() => idTokenFromResponse('{"error":"access_denied"}'),
          throwsFormatException);
    });
  });

  group('interactive loopback flow (runSigstoreSignIn)', () {
    // Drives the real loopback server: the injected launch fires the browser
    // redirect back at the callback, and a mock token endpoint returns tokens.
    Future<String?> run({
      required String returnedState, // 'match' to echo the real state
      String? oauthError,
      bool launchOpens = true,
      http.Response Function(http.Request)? token,
    }) {
      final client = MockClient((request) async =>
          token?.call(request) ??
          http.Response('{"id_token":"header.payload.sig"}', 200));
      return runSigstoreSignIn(
        client: client,
        launch: (authUrl) async {
          if (!launchOpens) return false;
          final redirect = Uri.parse(authUrl.queryParameters['redirect_uri']!);
          final state = returnedState == 'match'
              ? authUrl.queryParameters['state']!
              : returnedState;
          // Fire the redirect without awaiting: the server answers it only
          // after launch returns, so awaiting here would deadlock.
          unawaited(http.get(redirect.replace(queryParameters: {
            if (oauthError != null) 'error': oauthError,
            if (oauthError == null) 'code': 'auth-code',
            'state': state,
          })));
          return true;
        },
      );
    }

    test('exchanges the code for an id_token', () async {
      expect(await run(returnedState: 'match'), 'header.payload.sig');
    });

    test('returns null when the user does not complete sign-in', () async {
      expect(await run(returnedState: 'match', launchOpens: false), isNull);
    });

    test('rejects a state mismatch (CSRF guard)', () async {
      expect(await run(returnedState: 'attacker'), isNull);
    });

    test('returns null on an OAuth error redirect', () async {
      expect(await run(returnedState: 'match', oauthError: 'access_denied'),
          isNull);
    });
  });
}
