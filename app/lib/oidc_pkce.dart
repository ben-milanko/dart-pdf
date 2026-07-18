import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Sigstore's public interactive OAuth broker (a Dex instance). It brokers
/// Google / GitHub / Microsoft sign-in and issues an OIDC `id_token` whose
/// issuer Fulcio's production CA trusts. It is a **public** client (`sigstore`,
/// no secret) that uses PKCE with a loopback redirect - exactly how cosign
/// signs - so DartPDF needs no OAuth client registration of its own.
abstract final class SigstoreOidc {
  static const issuer = 'https://oauth2.sigstore.dev/auth';
  static const authorizationEndpoint = 'https://oauth2.sigstore.dev/auth/auth';
  static const tokenEndpoint = 'https://oauth2.sigstore.dev/auth/token';
  static const clientId = 'sigstore';
  // offline_access asks the broker for a refresh token so a still-signed-in
  // user can mint a fresh id_token without opening the browser again. Brokers
  // that don't grant it simply omit the refresh token - the flow still works.
  static const scopes = 'openid email offline_access';
}

/// The tokens the broker returns: the [idToken] keyless signing consumes and,
/// when the broker grants one, a [refreshToken] to silently mint the next
/// [idToken] without a browser round-trip.
class OidcTokens {
  const OidcTokens({required this.idToken, this.refreshToken});

  final String idToken;
  final String? refreshToken;
}

/// A PKCE (RFC 7636) verifier + its S256 challenge, plus the CSRF `state` and
/// OIDC `nonce` a single authorization request needs. All are URL-safe,
/// unpadded base64 of fresh random bytes.
class PkceSession {
  PkceSession({required this.verifier, required this.state, required this.nonce})
      : challenge = _s256(verifier);

  /// Draws fresh random values from [random] (default [Random.secure]).
  factory PkceSession.generate({Random? random}) {
    final rng = random ?? Random.secure();
    return PkceSession(
      verifier: _randomUrlToken(32, rng),
      state: _randomUrlToken(16, rng),
      nonce: _randomUrlToken(16, rng),
    );
  }

  final String verifier;
  final String challenge;
  final String state;
  final String nonce;
}

/// The authorization-request URL to open in the browser: the Sigstore broker's
/// authorize endpoint with the OAuth 2.0 + PKCE query for [redirectUri] and
/// [session].
Uri buildAuthorizationUrl({
  required String redirectUri,
  required PkceSession session,
}) =>
    Uri.parse(SigstoreOidc.authorizationEndpoint).replace(queryParameters: {
      'response_type': 'code',
      'client_id': SigstoreOidc.clientId,
      'scope': SigstoreOidc.scopes,
      'redirect_uri': redirectUri,
      'state': session.state,
      'nonce': session.nonce,
      'code_challenge': session.challenge,
      'code_challenge_method': 'S256',
    });

/// The `application/x-www-form-urlencoded` body for the authorization-code
/// token exchange - swaps the [code] the browser returned for tokens, proving
/// possession of the PKCE verifier.
String buildTokenRequestBody({
  required String code,
  required String redirectUri,
  required PkceSession session,
}) =>
    Uri(queryParameters: {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': SigstoreOidc.clientId,
      'code_verifier': session.verifier,
    }).query;

/// The `application/x-www-form-urlencoded` body for the refresh-token grant -
/// swaps a [refreshToken] for a fresh `id_token` with no browser interaction.
String buildRefreshTokenRequestBody({required String refreshToken}) =>
    Uri(queryParameters: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': SigstoreOidc.clientId,
    }).query;

/// Extracts the `id_token` (the JWT keyless signing uses) and any
/// `refresh_token` from a token endpoint JSON response body. Throws a
/// [FormatException] when there is no `id_token`.
OidcTokens oidcTokensFromResponse(String responseBody) {
  final decoded = json.decode(responseBody);
  final token = decoded is Map ? decoded['id_token'] : null;
  if (token is! String || token.isEmpty) {
    final error = decoded is Map ? decoded['error'] : null;
    throw FormatException(
        'no id_token in the OAuth token response${error == null ? '' : ' ($error)'}');
  }
  final refresh = decoded is Map ? decoded['refresh_token'] : null;
  return OidcTokens(
    idToken: token,
    refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
  );
}

/// The `id_token` alone from a token response (throws if absent).
String idTokenFromResponse(String responseBody) =>
    oidcTokensFromResponse(responseBody).idToken;

String _s256(String verifier) =>
    _base64Url(crypto.sha256.convert(ascii.encode(verifier)).bytes);

String _randomUrlToken(int bytes, Random rng) =>
    _base64Url(Uint8List.fromList([for (var i = 0; i < bytes; i++) rng.nextInt(256)]));

/// URL-safe, unpadded base64 - the encoding PKCE and OAuth `state`/`nonce` use.
String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
