import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dart_pdf_editor_app/oidc_pkce.dart';
import 'package:dart_pdf_editor_app/oidc_signin.dart';
import 'package:dart_pdf_editor_app/oidc_signin_io.dart';

/// An unsigned JWT (`header.payload.`) carrying [claims].
String _jwt(Map<String, Object?> claims) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(claims)}.';
}

String _token(DateTime exp) =>
    _jwt({'email': 'dev@example.com', 'exp': exp.millisecondsSinceEpoch ~/ 1000});

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
      // offline_access asks the broker for a refresh token
      expect(q['scope'], 'openid email offline_access');
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

    test('oidcTokensFromResponse reads the id_token and refresh_token', () {
      final tokens = oidcTokensFromResponse(
          '{"id_token":"a.b.c","refresh_token":"r3fr3sh"}');
      expect(tokens.idToken, 'a.b.c');
      expect(tokens.refreshToken, 'r3fr3sh');
      // absent refresh token -> null (broker didn't grant offline access)
      expect(oidcTokensFromResponse('{"id_token":"a.b.c"}').refreshToken, isNull);
    });

    test('buildRefreshTokenRequestBody carries the refresh grant', () {
      final parsed = Uri.splitQueryString(
          buildRefreshTokenRequestBody(refreshToken: 'r3fr3sh'));
      expect(parsed['grant_type'], 'refresh_token');
      expect(parsed['refresh_token'], 'r3fr3sh');
      expect(parsed['client_id'], 'sigstore');
    });
  });

  group('refreshSigstoreTokens', () {
    test('swaps a refresh token for a fresh id_token', () async {
      final client = MockClient((request) async {
        expect(Uri.splitQueryString(request.body)['grant_type'],
            'refresh_token');
        return http.Response('{"id_token":"new.id.tok"}', 200);
      });
      final tokens = await refreshSigstoreTokens('r3fr3sh', client: client);
      expect(tokens?.idToken, 'new.id.tok');
      // the old refresh token carries forward when none is returned
      expect(tokens?.refreshToken, 'r3fr3sh');
    });

    test('returns null when the broker rejects the refresh', () async {
      final client = MockClient(
          (request) async => http.Response('{"error":"invalid_grant"}', 400));
      expect(await refreshSigstoreTokens('stale', client: client), isNull);
    });
  });

  group('SigstoreSignInManager', () {
    test('reuses a valid id_token without signing in or refreshing', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      var signIns = 0, refreshes = 0;
      final manager = SigstoreSignInManager(
        now: () => now,
        signIn: () async {
          signIns++;
          return OidcTokens(
              idToken: _token(now.add(const Duration(minutes: 30))),
              refreshToken: 'r');
        },
        refresh: (_) async {
          refreshes++;
          return null;
        },
      );
      expect(await manager.call(), isNotNull);
      await manager.call();
      expect(signIns, 1);
      expect(refreshes, 0);
      expect(manager.hasValidToken, isTrue);
    });

    test('refreshes silently when the id_token has expired', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      var signIns = 0, refreshes = 0;
      final manager = SigstoreSignInManager(
        now: () => now,
        signIn: () async {
          signIns++;
          return OidcTokens(
              idToken: _token(now.subtract(const Duration(minutes: 1))),
              refreshToken: 'r');
        },
        refresh: (_) async {
          refreshes++;
          return OidcTokens(
              idToken: _token(now.add(const Duration(minutes: 30))),
              refreshToken: 'r2');
        },
      );
      await manager.call(); // browser sign-in, id_token already expired
      final token = await manager.call(); // silent refresh, no browser
      expect(signIns, 1);
      expect(refreshes, 1);
      expect(token, isNotNull);
    });

    test('falls back to the browser when the refresh fails', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      var signIns = 0;
      final manager = SigstoreSignInManager(
        now: () => now,
        signIn: () async {
          signIns++;
          return OidcTokens(
              idToken: _token(now.subtract(const Duration(minutes: 1))),
              refreshToken: 'r');
        },
        refresh: (_) async => null, // broker rejects the refresh
      );
      await manager.call(); // signIns = 1
      await manager.call(); // refresh fails -> browser again, signIns = 2
      expect(signIns, 2);
    });

    test('a cancelled sign-in yields no token', () async {
      final manager = SigstoreSignInManager(
        signIn: () async => null,
        refresh: (_) async => null,
      );
      expect(await manager.call(), isNull);
      expect(manager.hasValidToken, isFalse);
    });
  });

  group('interactive loopback flow (runSigstoreSignIn)', () {
    // Drives the real loopback server: the injected launch fires the browser
    // redirect back at the callback, and a mock token endpoint returns tokens.
    Future<OidcTokens?> run({
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
      expect((await run(returnedState: 'match'))?.idToken, 'header.payload.sig');
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
